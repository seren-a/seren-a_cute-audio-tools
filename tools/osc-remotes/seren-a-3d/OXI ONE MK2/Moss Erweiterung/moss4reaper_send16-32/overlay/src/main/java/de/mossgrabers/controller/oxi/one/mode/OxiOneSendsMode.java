// Written by Jürgen Moßgraber - mossgrabers.de
// (c) 2017-2026
// Licensed under LGPLv3 - http://www.gnu.org/licenses/lgpl-3.0.txt

package de.mossgrabers.controller.oxi.one.mode;

import de.mossgrabers.controller.oxi.one.OxiOneConfiguration;
import de.mossgrabers.controller.oxi.one.controller.OxiOneControlSurface;
import de.mossgrabers.framework.controller.ContinuousID;
import de.mossgrabers.framework.controller.display.IGraphicDisplay;
import de.mossgrabers.framework.daw.IModel;
import de.mossgrabers.framework.daw.data.ICursorTrack;
import de.mossgrabers.framework.daw.data.ISend;
import de.mossgrabers.framework.daw.data.bank.ISendBank;
import de.mossgrabers.framework.featuregroup.AbstractParameterMode;
import de.mossgrabers.framework.graphics.canvas.component.simple.TitleValueMenuComponent;
import de.mossgrabers.framework.daw.data.IItem;


/**
 * The 4 encoders edit 4 sends of the selected track: sends 1-4, 5-8, 9-12 or 13-16 (the group is
 * changed by the send views). Turning changes the level, a press toggles the send (mute) and a
 * double press switches between pre- and post-fader (configurable, see 'Send views: encoder
 * press'). A long press resets the level.
 *
 * @author seren.a / Claude (based on the OXI One modes by Jürgen Moßgraber)
 */
public class OxiOneSendsMode extends AbstractParameterMode<OxiOneControlSurface, OxiOneConfiguration, IItem> implements IOxiModeReset
{
    /** The number of sends which can be reached with the encoders. */
    public static final int NUM_SENDS       = 16;
    /** The number of sends edited at the same time (one per encoder). */
    public static final int GROUP_SIZE      = 4;

    private static final long DOUBLE_PRESS_MS = 350;

    private int               group         = 0;
    private int               selectedIndex = 0;
    private final int []      taps          = new int [GROUP_SIZE];
    private final int []      generation    = new int [GROUP_SIZE];
    private final boolean []  wasLong       = new boolean [GROUP_SIZE];


    /**
     * Constructor.
     *
     * @param surface The control surface
     * @param model The model
     */
    public OxiOneSendsMode (final OxiOneControlSurface surface, final IModel model)
    {
        super ("Sends", surface, model, false);

        this.setControls (ContinuousID.createSequentialList (ContinuousID.KNOB1, GROUP_SIZE));
    }


    /**
     * Get the current group of sends.
     *
     * @return 0 = sends 1-4, 1 = 5-8, ...
     */
    public int getGroup ()
    {
        return this.group;
    }


    /**
     * Set the group of sends which is edited by the encoders.
     *
     * @param group 0 = sends 1-4, 1 = 5-8, ...
     */
    public void setGroup (final int group)
    {
        final int g = Math.max (0, Math.min (NUM_SENDS / GROUP_SIZE - 1, group));
        if (g == this.group)
            return;
        this.group = g;
        this.surface.getDisplay ().notify ("Sends " + (g * GROUP_SIZE + 1) + "-" + (g * GROUP_SIZE + GROUP_SIZE));
    }


    /**
     * Get a send of the selected track.
     *
     * @param sendIndex The index of the send (0-15)
     * @return The send or null if it does not exist
     */
    public ISend getSend (final int sendIndex)
    {
        final ICursorTrack cursorTrack = this.model.getCursorTrack ();
        if (!cursorTrack.doesExist ())
            return null;
        final ISendBank sendBank = cursorTrack.getSendBank ();
        if (sendIndex >= sendBank.getPageSize ())
            return null;
        final ISend send = sendBank.getItem (sendIndex);
        return send.doesExist () ? send : null;
    }


    private ISend getKnobSend (final int index)
    {
        return this.getSend (this.group * GROUP_SIZE + index);
    }


    /** {@inheritDoc} */
    @Override
    public void onKnobValue (final int index, final int value)
    {
        this.selectedIndex = index;
        final ISend send = this.getKnobSend (index);
        if (send != null)
            send.changeValue (value);
    }


    /** {@inheritDoc} */
    @Override
    public int getKnobValue (final int index)
    {
        final ISend send = this.getKnobSend (index);
        return send == null ? 0 : send.getValue ();
    }


    /** {@inheritDoc} */
    @Override
    public void onKnobTouch (final int index, final boolean isTouched)
    {
        // Also called when a knob is turned, therefore only used for the display
        if (index < 0 || index >= GROUP_SIZE)
            return;
        this.selectedIndex = index;
        this.setTouchedKnob (index, isTouched);
    }


    /**
     * A real press or release of an encoder (not the emulated touch of turning).
     *
     * @param index The index of the encoder
     * @param isPressed True if pressed, false if released
     */
    public void onEncoderPress (final int index, final boolean isPressed)
    {
        if (index < 0 || index >= GROUP_SIZE)
            return;
        this.selectedIndex = index;
        this.setTouchedKnob (index, isPressed);

        if (isPressed)
        {
            this.wasLong[index] = false;
            return;
        }
        if (this.wasLong[index])
            return;

        // DAW without pre/post (Reaper): mute immediately, no waiting for a double press
        final ISend direct = this.getKnobSend (index);
        if (direct != null && !direct.canChangePreFader ())
        {
            this.taps[index] = 0;
            toggleMute (this.surface, direct);
            return;
        }

        // Count the presses, the action is executed when no further press follows
        this.taps[index]++;
        final int gen = ++this.generation[index];
        if (this.taps[index] >= 2)
        {
            this.taps[index] = 0;
            this.execute (index, true);
            return;
        }
        this.surface.scheduleTask ( () -> {
            if (gen != this.generation[index] || this.taps[index] == 0)
                return;
            this.taps[index] = 0;
            this.execute (index, false);
        }, DOUBLE_PRESS_MS);
    }


    /** {@inheritDoc} */
    @Override
    public void resetValue (final int index)
    {
        if (index < 0 || index >= GROUP_SIZE)
            return;
        this.wasLong[index] = true;
        this.taps[index] = 0;
        final ISend send = this.getKnobSend (index);
        if (send != null)
            send.resetValue ();
    }


    private void execute (final int index, final boolean isDouble)
    {
        final ISend send = this.getKnobSend (index);
        if (send == null)
            return;
        final boolean muteOnSingle = this.surface.getConfiguration ().isSendPressMutes ();
        if (isDouble == muteOnSingle)
            togglePreFader (this.surface, send);
        else
            toggleMute (this.surface, send);
    }


    /**
     * Toggle the send on/off and show the result.
     *
     * @param surface The surface
     * @param send The send
     */
    public static void toggleMute (final OxiOneControlSurface surface, final ISend send)
    {
        final boolean wasEnabled = send.isEnabled ();
        send.toggleEnabled ();
        surface.getDisplay ().notify (send.getName (8) + (wasEnabled ? ": muted" : ": on"));
    }


    /**
     * Toggle the send between pre- and post-fader and show the result.
     *
     * @param surface The surface
     * @param send The send
     */
    public static void togglePreFader (final OxiOneControlSurface surface, final ISend send)
    {
        if (!send.canChangePreFader ())
        {
            surface.getDisplay ().notify ("Pre/Post: E16");
            return;
        }
        final boolean wasPre = send.isPreFader ();
        send.togglePreFader ();
        surface.getDisplay ().notify (send.getName (8) + (wasPre ? ": Post" : ": Pre"));
    }


    /** {@inheritDoc} */
    @Override
    public void updateDisplay ()
    {
        final IGraphicDisplay display = this.surface.getGraphicsDisplay ();
        final ICursorTrack cursorTrack = this.model.getCursorTrack ();

        final String [] menu = new String [GROUP_SIZE];
        for (int i = 0; i < GROUP_SIZE; i++)
        {
            final ISend send = this.getKnobSend (i);
            menu[i] = send == null ? "S" + (this.group * GROUP_SIZE + i + 1) : send.getName (4);
        }

        String desc = "Select a track";
        String label = "Sends " + (this.group * GROUP_SIZE + 1) + "-" + (this.group * GROUP_SIZE + GROUP_SIZE);
        int value = -1;
        if (cursorTrack.doesExist ())
        {
            desc = cursorTrack.getPosition () + 1 + ": " + cursorTrack.getName (9);
            final ISend send = this.getKnobSend (this.selectedIndex);
            if (send != null)
            {
                label = send.getName (8) + ": " + (send.isEnabled () ? send.getDisplayedValue (8) : "Muted") + (send.isPreFader () ? " Pre" : "");
                value = send.getValue ();
            }
        }

        display.addElement (new TitleValueMenuComponent (desc, label, menu, value, -1, -1, false));
        display.send ();
    }
}
