// Written by Jürgen Moßgraber - mossgrabers.de
// (c) 2017-2026
// Licensed under LGPLv3 - http://www.gnu.org/licenses/lgpl-3.0.txt

package de.mossgrabers.controller.oxi.one.view;

import de.mossgrabers.controller.oxi.one.OxiOneConfiguration;
import de.mossgrabers.controller.oxi.one.controller.OxiOneColorManager;
import de.mossgrabers.controller.oxi.one.controller.OxiOneControlSurface;
import de.mossgrabers.controller.oxi.one.mode.OxiOneSendsMode;
import de.mossgrabers.controller.oxi.one.view.OxiOneTrackRows.RowType;
import de.mossgrabers.framework.command.trigger.Direction;
import de.mossgrabers.framework.controller.grid.IPadGrid;
import de.mossgrabers.framework.daw.DAWColor;
import de.mossgrabers.framework.daw.IModel;
import de.mossgrabers.framework.daw.data.ISend;
import de.mossgrabers.framework.daw.data.ITrack;
import de.mossgrabers.framework.daw.data.bank.ISendBank;
import de.mossgrabers.framework.daw.data.bank.ITrackBank;
import de.mossgrabers.framework.featuregroup.AbstractView;
import de.mossgrabers.framework.featuregroup.ModeManager;
import de.mossgrabers.framework.mode.Modes;


/**
 * Base class of the send matrix views. The tracks are arranged in blocks of 16 tracks (one track
 * per column, like the Mix 32 view). The first row of a block selects the track (track color), the
 * other rows show the sends of the track: color of the send channel, the brightness shows the
 * level, red = send off, pale = pre-fader.
 * <ul>
 * <li>Pad on a send: select the track, the encoders switch to the group of this send</li>
 * <li>Shift + pad: send on/off, 2x pad: pre/post fader</li>
 * <li>Up/Down: next/previous group of 4 sends (encoders and rows), with Shift the rows move by
 * one send</li>
 * <li>Left/Right: scroll the tracks by a page, with Shift by 16 tracks</li>
 * </ul>
 * While the view is active the encoders edit 4 sends of the selected track (sends mode).
 *
 * @author seren.a / Claude (based on the wide mixer views)
 */
public abstract class AbstractOxiOneSendView extends AbstractView<OxiOneControlSurface, OxiOneConfiguration> implements IOxiCursorView
{
    private static final int  COLUMNS         = 16;
    private static final long DOUBLE_PRESS_MS = 350;

    private final int         numBlocks;
    private final int         rowsPerBlock;
    private final int         numTracks;
    private final OxiOneTrackRows.PressedRows pressedRows = new OxiOneTrackRows.PressedRows ();
    private int               consumedNote    = -1;
    private int               sendOffset      = 0;
    private int               lastNote        = -1;
    private long              lastNoteTime    = 0;


    /**
     * Constructor.
     *
     * @param name The name of the view
     * @param surface The surface
     * @param model The model
     * @param numBlocks The number of blocks of 16 tracks
     */
    protected AbstractOxiOneSendView (final String name, final OxiOneControlSurface surface, final IModel model, final int numBlocks)
    {
        super (name, surface, model);

        this.numBlocks = numBlocks;
        this.rowsPerBlock = 8 / numBlocks;
        this.numTracks = numBlocks * COLUMNS;

        // Only monitor the bank (with all its sends) while the view is active
        OxiOneObservers.setEnabled (this.model.getAdditionalTrackBank (this.numTracks, OxiOneSendsMode.NUM_SENDS), false);
    }


    private int getSendRows ()
    {
        return this.rowsPerBlock - 1;
    }


    private OxiOneSendsMode getSendsMode ()
    {
        return (OxiOneSendsMode) this.surface.getModeManager ().get (Modes.SEND);
    }


    /** {@inheritDoc} */
    @Override
    public void onActivate ()
    {
        super.onActivate ();

        final ITrackBank bank = this.model.getAdditionalTrackBank (this.numTracks, OxiOneSendsMode.NUM_SENDS);
        if (bank != null)
        {
            OxiOneObservers.setEnabled (bank, true);
            final int mainPosition = Math.max (0, this.model.getTrackBank ().getScrollPosition ());
            bank.scrollTo (mainPosition / this.numTracks * this.numTracks);
        }

        final ModeManager modeManager = this.surface.getModeManager ();
        if (modeManager.get (Modes.SEND) != null)
        {
            modeManager.setActive (Modes.SEND);
            this.followGroup ();
        }
    }


    /** {@inheritDoc} */
    @Override
    public void onDeactivate ()
    {
        OxiOneObservers.setEnabled (this.model.getAdditionalTrackBank (this.numTracks, OxiOneSendsMode.NUM_SENDS), false);

        final ModeManager modeManager = this.surface.getModeManager ();
        if (modeManager.isActive (Modes.SEND))
            modeManager.setActive (Modes.TRACK);

        super.onDeactivate ();
    }


    /** Make the rows show the group of sends which the encoders edit. */
    private void followGroup ()
    {
        final OxiOneSendsMode mode = this.getSendsMode ();
        if (mode == null)
            return;
        final int first = mode.getGroup () * OxiOneSendsMode.GROUP_SIZE;
        final int last = first + OxiOneSendsMode.GROUP_SIZE - 1;
        if (first < this.sendOffset || last >= this.sendOffset + this.getSendRows ())
            this.sendOffset = Math.max (0, Math.min (OxiOneSendsMode.NUM_SENDS - this.getSendRows (), first));
    }


    /** {@inheritDoc} */
    @Override
    public void drawGrid ()
    {
        final IPadGrid padGrid = this.surface.getPadGrid ();
        final ITrackBank bank = this.getBank ();
        final OxiOneSendsMode mode = this.getSendsMode ();
        final int group = mode == null ? -1 : mode.getGroup ();

        for (int block = 0; block < this.numBlocks; block++)
        {
            for (int x = 0; x < COLUMNS; x++)
            {
                final int trackIndex = block * COLUMNS + x;
                final ITrack track = trackIndex < bank.getPageSize () ? bank.getItem (trackIndex) : null;
                for (int r = 0; r < this.rowsPerBlock; r++)
                {
                    final int y = block * this.rowsPerBlock + r;
                    if (track == null || !track.doesExist ())
                        padGrid.lightEx (x, y, OxiOneColorManager.OXI_ONE_COLOR_BLACK);
                    else if (r == 0)
                        OxiOneTrackRows.drawTrackPad (this.surface, this.colorManager, x, y, track, RowType.SELECT);
                    else
                    {
                        final int sendIndex = this.sendOffset + r - 1;
                        final boolean highlight = track.isSelected () && sendIndex / OxiOneSendsMode.GROUP_SIZE == group;
                        padGrid.lightEx (x, y, this.getSendColor (track, sendIndex, highlight));
                    }
                }
            }
        }
    }


    private int getSendColor (final ITrack track, final int sendIndex, final boolean highlight)
    {
        final ISend send = getSend (track, sendIndex);
        if (send == null)
            return highlight ? OxiOneColorManager.OXI_ONE_COLOR_GRAY : OxiOneColorManager.OXI_ONE_COLOR_BLACK;
        if (!send.isEnabled ())
            return highlight ? OxiOneColorManager.OXI_ONE_COLOR_RED : OxiOneColorManager.OXI_ONE_COLOR_DARKER_RED;

        final int color = this.colorManager.getColorIndex (DAWColor.getColorID (send.getColor ()));
        if (send.isPreFader ())
            return OxiOneColorManager.getSendColorVariant (color, OxiOneColorManager.SEND_PALE_OFFSET);

        final double level = send.getValue () / (double) this.model.getValueChanger ().getUpperBound ();
        if (level >= 0.6)
            return color;
        if (level >= 0.3 || highlight)
            return OxiOneColorManager.getSendColorVariant (color, OxiOneColorManager.SEND_DIM_OFFSET);
        return level > 0 ? OxiOneColorManager.getSendColorVariant (color, OxiOneColorManager.SEND_DIMMER_OFFSET) : OxiOneColorManager.OXI_ONE_COLOR_GRAY;
    }


    private static ISend getSend (final ITrack track, final int sendIndex)
    {
        final ISendBank sendBank = track.getSendBank ();
        if (sendBank == null || sendIndex < 0 || sendIndex >= sendBank.getPageSize ())
            return null;
        final ISend send = sendBank.getItem (sendIndex);
        return send.doesExist () ? send : null;
    }


    /** {@inheritDoc} */
    @Override
    public void onGridNote (final int note, final int velocity)
    {
        // Note rows are counted from the bottom (0) to the top (7)
        final int y = 7 - note / 16;
        final int x = note % 16;
        final int block = y / this.rowsPerBlock;
        final int r = y % this.rowsPerBlock;
        final int trackIndex = block * COLUMNS + x;
        final ITrackBank bank = this.getBank ();
        final ITrack track = trackIndex < bank.getPageSize () ? bank.getItem (trackIndex) : null;
        if (track == null || !track.doesExist ())
            return;

        if (r == 0)
        {
            // The select row behaves like the one of the mixer views
            if (velocity > 0)
            {
                this.pressedRows.press (note, RowType.SELECT);
                if (OxiOneTrackRows.handleTrackPadPress (this.surface, track, RowType.SELECT))
                    this.consumedNote = note;
                return;
            }
            if (this.consumedNote == note)
            {
                this.consumedNote = -1;
                this.pressedRows.release (note, null);
                return;
            }
            OxiOneTrackRows.handleTrackPad (this.surface, track, this.pressedRows.release (note, RowType.SELECT));
            return;
        }

        if (velocity == 0)
            return;

        final int sendIndex = this.sendOffset + r - 1;
        final ISend send = getSend (track, sendIndex);
        final long now = System.currentTimeMillis ();
        final boolean isDouble = note == this.lastNote && now - this.lastNoteTime < DOUBLE_PRESS_MS;
        this.lastNote = isDouble ? -1 : note;
        this.lastNoteTime = now;

        if (this.surface.isShiftPressed ())
        {
            if (send != null)
                OxiOneSendsMode.toggleMute (this.surface, send);
            return;
        }

        if (!track.isSelected ())
            track.select ();
        final OxiOneSendsMode mode = this.getSendsMode ();
        if (mode != null)
            mode.setGroup (sendIndex / OxiOneSendsMode.GROUP_SIZE);

        if (send == null)
            return;
        if (isDouble)
            OxiOneSendsMode.togglePreFader (this.surface, send);
        else
            this.surface.getDisplay ().notify (send.getName (8) + ": " + send.getDisplayedValue (8));
    }


    /** {@inheritDoc} */
    @Override
    public boolean handlesCursor (final Direction direction)
    {
        return true;
    }


    /** {@inheritDoc} */
    @Override
    public void onCursor (final Direction direction, final boolean isShifted)
    {
        if (direction == Direction.UP || direction == Direction.DOWN)
        {
            final int delta = direction == Direction.DOWN ? 1 : -1;
            if (isShifted)
            {
                // Move the rows by one send, the encoders stay
                this.sendOffset = Math.max (0, Math.min (OxiOneSendsMode.NUM_SENDS - this.getSendRows (), this.sendOffset + delta));
                return;
            }
            final OxiOneSendsMode mode = this.getSendsMode ();
            if (mode != null)
            {
                mode.setGroup (mode.getGroup () + delta);
                this.followGroup ();
            }
            return;
        }

        final ITrackBank bank = this.getBank ();
        final int step = isShifted ? COLUMNS : this.numTracks;
        final int position = Math.max (0, bank.getScrollPosition ());
        if (direction == Direction.LEFT)
            bank.scrollTo (Math.max (0, position - step));
        else if (position + step < bank.getItemCount ())
            bank.scrollTo (position + step);
    }


    /** {@inheritDoc} */
    @Override
    public boolean canCursor (final Direction direction, final boolean isShifted)
    {
        if (direction == Direction.UP || direction == Direction.DOWN)
        {
            if (isShifted)
                return direction == Direction.UP ? this.sendOffset > 0 : this.sendOffset < OxiOneSendsMode.NUM_SENDS - this.getSendRows ();
            final OxiOneSendsMode mode = this.getSendsMode ();
            if (mode == null)
                return false;
            return direction == Direction.UP ? mode.getGroup () > 0 : mode.getGroup () < OxiOneSendsMode.NUM_SENDS / OxiOneSendsMode.GROUP_SIZE - 1;
        }
        final ITrackBank bank = this.getBank ();
        final int position = Math.max (0, bank.getScrollPosition ());
        if (direction == Direction.LEFT)
            return position > 0;
        return position + (isShifted ? COLUMNS : this.numTracks) < bank.getItemCount ();
    }


    /**
     * Get the track bank with sends. Falls back to the current track bank if the DAW does not
     * support additional track banks.
     *
     * @return The bank
     */
    protected ITrackBank getBank ()
    {
        final ITrackBank bank = this.model.getAdditionalTrackBank (this.numTracks, OxiOneSendsMode.NUM_SENDS);
        return bank == null ? this.model.getCurrentTrackBank () : bank;
    }
}
