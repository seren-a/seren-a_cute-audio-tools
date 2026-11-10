// Written by Jürgen Moßgraber - mossgrabers.de
// (c) 2017-2026
// Licensed under LGPLv3 - http://www.gnu.org/licenses/lgpl-3.0.txt

package de.mossgrabers.controller.oxi.one.view;

import java.util.List;

import de.mossgrabers.controller.oxi.one.OxiOneConfiguration;
import de.mossgrabers.controller.oxi.one.OxiOneConfiguration.PluginWindowBehaviour;
import de.mossgrabers.controller.oxi.one.controller.OxiOneColorManager;
import de.mossgrabers.controller.oxi.one.controller.OxiOneControlSurface;
import de.mossgrabers.controller.oxi.one.view.OxiOneTrackRows.RowType;
import de.mossgrabers.framework.command.trigger.Direction;
import de.mossgrabers.framework.controller.ButtonID;
import de.mossgrabers.framework.controller.display.IDisplay;
import de.mossgrabers.framework.controller.grid.IPadGrid;
import de.mossgrabers.framework.daw.DAWColor;
import de.mossgrabers.framework.daw.IModel;
import de.mossgrabers.framework.daw.constants.DeviceChainOperation;
import de.mossgrabers.framework.daw.data.ICursorDevice;
import de.mossgrabers.framework.daw.data.IDevice;
import de.mossgrabers.framework.daw.data.ITrack;
import de.mossgrabers.framework.daw.data.bank.IDeviceBank;
import de.mossgrabers.framework.daw.data.bank.ITrackBank;
import de.mossgrabers.framework.featuregroup.AbstractView;
import de.mossgrabers.framework.view.Views;


/**
 * A mixer view which shows the devices (insert plugins) of each track below the track state rows
 * instead of clips. Pressing a device pad selects the device (and optionally opens its plugin
 * window), Shift + pad toggles the bypass of the device (or removes it, see configuration). Up/Down
 * scroll the devices of all tracks.
 *
 * @author Jürgen Moßgraber
 */
public class OxiOnePluginMixerView extends AbstractView<OxiOneControlSurface, OxiOneConfiguration> implements IOxiCursorView
{
    /** The maximum number of device rows (if only select and one state row are visible). */
    public static final int MAX_DEVICE_ROWS = 6;

    /** The source device of a copy or move/swap gesture. */
    private static final class Source
    {
        private final int     trackIndex;
        private final int     trackPosition;
        private int           position;
        private final String  name;
        private final boolean isMove;


        Source (final int trackIndex, final ITrack track, final IDevice device, final boolean isMove)
        {
            this.trackIndex = trackIndex;
            this.trackPosition = track.getPosition ();
            this.position = device.getPosition ();
            this.name = device.getName ();
            this.isMove = isMove;
        }
    }

    private final OxiOneTrackRows.PressedRows pressedRows  = new OxiOneTrackRows.PressedRows ();
    private int                               numTrackRows = 4;
    private Source                            source       = null;
    private int                               consumedNote = -1;


    /**
     * Constructor.
     *
     * @param surface The surface
     * @param model The model
     */
    public OxiOnePluginMixerView (final OxiOneControlSurface surface, final IModel model)
    {
        super (Views.NAME_PLUGIN_MIXER, surface, model);

        // Only monitor the devices of all tracks while the view is active
        this.enableDeviceObservers (false);
    }


    /** {@inheritDoc} */
    @Override
    public void onActivate ()
    {
        super.onActivate ();
        this.enableDeviceObservers (true);
    }


    /** {@inheritDoc} */
    @Override
    public void onDeactivate ()
    {
        this.cancelGesture ();
        this.enableDeviceObservers (false);
        super.onDeactivate ();
    }


    private void enableDeviceObservers (final boolean enable)
    {
        final int pageSize = this.model.getTrackBank ().getPageSize ();
        for (int i = 0; i < pageSize; i++)
        {
            OxiOneObservers.setEnabled (this.model.getTrackDeviceBank (i), enable);
        }
    }


    /** {@inheritDoc} */
    @Override
    public void drawGrid ()
    {
        this.checkGestureEnd ();

        final List<RowType> trackRows = this.updateLayout ();
        final IPadGrid padGrid = this.surface.getPadGrid ();
        final ICursorDevice cursorDevice = this.model.getCursorDevice ();

        final ITrackBank tb = this.model.getCurrentTrackBank ();
        final boolean isMainBank = tb == this.model.getTrackBank ();
        final int pageSize = tb.getPageSize ();
        for (int x = 0; x < 16; x++)
        {
            if (x >= pageSize)
            {
                for (int y = 0; y < 8; y++)
                    padGrid.lightEx (x, y, OxiOneColorManager.OXI_ONE_COLOR_BLACK);
                continue;
            }

            final ITrack track = tb.getItem (x);
            for (int y = 0; y < trackRows.size (); y++)
                OxiOneTrackRows.drawTrackPad (this.surface, this.colorManager, x, y, track, trackRows.get (y));

            final IDeviceBank deviceBank = this.getDeviceBank (x, track, isMainBank);
            for (int y = this.numTrackRows; y < 8; y++)
            {
                final int deviceIndex = y - this.numTrackRows;
                if (deviceBank == null || !track.doesExist () || deviceIndex >= deviceBank.getPageSize ())
                {
                    padGrid.lightEx (x, y, OxiOneColorManager.OXI_ONE_COLOR_BLACK);
                    continue;
                }
                this.drawDevicePad (padGrid, x, y, track, deviceBank.getItem (deviceIndex), cursorDevice);
            }
        }
    }


    private void drawDevicePad (final IPadGrid padGrid, final int x, final int y, final ITrack track, final IDevice device, final ICursorDevice cursorDevice)
    {
        if (!device.doesExist ())
        {
            padGrid.lightEx (x, y, OxiOneColorManager.OXI_ONE_COLOR_BLACK);
            return;
        }

        final OxiOneConfiguration configuration = this.surface.getConfiguration ();
        final int color;
        if (device.isOffline ())
            color = configuration.getPluginOfflineColor ();
        else if (!device.isEnabled ())
            color = configuration.getPluginBypassColor ();
        else if (device.isWindowOpen ())
            color = configuration.getPluginWindowColor ();
        else
        {
            final int pluginColor = configuration.getPluginColor ();
            color = pluginColor < 0 ? this.colorManager.getColorIndex (DAWColor.getColorID (track.getColor ())) : pluginColor;
        }

        // The source of a copy/move operation blinks fast, the selected device slowly
        final int blinkColor = color == OxiOneColorManager.OXI_ONE_COLOR_WHITE ? OxiOneColorManager.OXI_ONE_COLOR_BLACK : OxiOneColorManager.OXI_ONE_COLOR_WHITE;
        if (this.source != null && this.source.trackIndex == x && this.source.position == device.getPosition ())
            padGrid.lightEx (x, y, color, blinkColor, true);
        else if (isCursorDevice (track, device, cursorDevice))
            padGrid.lightEx (x, y, color, blinkColor, false);
        else
            padGrid.lightEx (x, y, color);
    }


    /** {@inheritDoc} */
    @Override
    public void onGridNote (final int note, final int velocity)
    {
        final List<RowType> trackRows = this.updateLayout ();

        // Note rows are counted from the bottom (0) to the top (7)
        final int y = 7 - note / 16;
        final int x = note % 16;
        final ITrackBank tb = this.model.getCurrentTrackBank ();
        if (x >= tb.getPageSize ())
            return;
        final ITrack track = tb.getItem (x);

        if (y < trackRows.size ())
        {
            if (velocity > 0)
            {
                // Using any other pad ends a gesture
                this.cancelGesture ();
                this.pressedRows.press (note, trackRows.get (y));
                if (OxiOneTrackRows.handleTrackPadPress (this.surface, track, trackRows.get (y)))
                    this.consumedNote = note;
            }
            else if (this.consumedNote == note)
            {
                this.consumedNote = -1;
                this.pressedRows.release (note, null);
            }
            else
                OxiOneTrackRows.handleTrackPad (this.surface, track, this.pressedRows.release (note, trackRows.get (y)));
        }
        else if (velocity > 0)
        {
            final boolean isMainBank = tb == this.model.getTrackBank ();
            final IDeviceBank deviceBank = this.getDeviceBank (x, track, isMainBank);
            final int deviceIndex = y - this.numTrackRows;
            if (deviceBank != null && track.doesExist () && deviceIndex < deviceBank.getPageSize ())
            {
                final IDevice device = deviceBank.getItem (deviceIndex);
                if (!isMainBank || !this.handleEditGestures (x, track, device))
                    this.handleDevicePad (track, device);
            }
        }

        // Revert to last view of the selected track
        if (velocity == 0 && this.surface.isPressed (ButtonID.SESSION))
        {
            this.surface.setTriggerConsumed (ButtonID.SESSION);
            this.surface.recallPreferredView (this.model.getCursorTrack ());
        }
    }


    /**
     * Handle the gestures for copying, moving and deleting devices (on the main track bank):
     * <ul>
     * <li>Hold COPY, press a device (source), press another slot: Inserts a copy before the device
     * on that slot or at the end of the chain if the slot is empty. Additionally hold Shift to
     * replace the device on that slot.
     * <li>Hold Shift, press a device (source), press another slot: Swaps the 2 devices or moves the
     * source device to the end of the chain if the slot is empty. If Shift is released without
     * selecting a 2nd slot, the configured Shift action (bypass, offline, remove) is executed.
     * <li>Hold PASTE, press a device: Removes it.
     * </ul>
     *
     * @param trackIndex The index of the track in the page
     * @param track The track
     * @param device The device on the pressed slot, might not exist
     * @return True if the pad press was consumed by a gesture
     */
    private boolean handleEditGestures (final int trackIndex, final ITrack track, final IDevice device)
    {
        final IDisplay display = this.surface.getDisplay ();
        final boolean isShift = this.surface.isShiftPressed ();

        // Copy / Replace
        if (this.surface.isPressed (ButtonID.DUPLICATE))
        {
            this.surface.setTriggerConsumed (ButtonID.DUPLICATE);
            if (this.source == null || this.source.isMove)
            {
                this.source = null;
                if (device.doesExist ())
                {
                    this.source = new Source (trackIndex, track, device, false);
                    display.notify ("Copy to? (+Shift: replace)");
                }
                return true;
            }

            final Source copySource = this.source;
            if (this.findSourceDevice (copySource) == null)
            {
                this.source = null;
                display.notify ("Cancelled");
                return true;
            }

            final boolean isReplace = isShift && device.doesExist ();
            final int destinationPosition = getDestinationPosition (device);
            // Replacing the source with itself does nothing
            if (isReplace && copySource.trackIndex == trackIndex && copySource.position == destinationPosition)
                return true;
            final DeviceChainOperation operation = isReplace ? DeviceChainOperation.REPLACE : DeviceChainOperation.COPY;
            if (this.model.editDeviceChain (operation, copySource.trackIndex, copySource.position, trackIndex, destinationPosition))
            {
                display.notify ((isReplace ? "Replaced with " : "Copied ") + copySource.name);
                // A copy inserted before the source on the same track moves the source down
                if (!isReplace && copySource.trackIndex == trackIndex && destinationPosition >= 0 && destinationPosition <= copySource.position)
                    copySource.position++;
            }
            else
                display.notify ("Not possible");
            return true;
        }

        // Delete
        if (this.surface.isPressed (ButtonID.DELETE))
        {
            this.surface.setTriggerConsumed (ButtonID.DELETE);
            this.source = null;
            if (device.doesExist ())
            {
                display.notify ("Removed: " + device.getName ());
                device.remove ();
            }
            return true;
        }

        // Classic: Execute the Shift action immediately
        if (isShift && !this.surface.getConfiguration ().isShiftMoveSwap ())
        {
            this.source = null;
            if (device.doesExist ())
                this.executeShiftAction (device);
            return true;
        }

        // Move / Swap (and the configured Shift action on Shift release)
        if (isShift)
        {
            if (this.source == null || !this.source.isMove)
            {
                this.source = null;
                if (device.doesExist ())
                {
                    this.source = new Source (trackIndex, track, device, true);
                    display.notify ("Move/Swap?");
                }
                return true;
            }

            final Source moveSource = this.source;
            this.source = null;
            if (this.findSourceDevice (moveSource) == null)
            {
                display.notify ("Cancelled");
                return true;
            }
            final int destinationPosition = getDestinationPosition (device);
            if (moveSource.trackIndex == trackIndex && moveSource.position == destinationPosition)
                return true;
            final boolean isSwap = device.doesExist ();
            final DeviceChainOperation operation = isSwap ? DeviceChainOperation.SWAP : DeviceChainOperation.MOVE;
            if (this.model.editDeviceChain (operation, moveSource.trackIndex, moveSource.position, trackIndex, destinationPosition))
                display.notify ((isSwap ? "Swapped " : "Moved ") + moveSource.name);
            else
                display.notify ("Not possible");
            return true;
        }

        return false;
    }


    /**
     * Ends a gesture if the related button was released. If Shift was released and only one device
     * was selected, the configured Shift action is executed on it.
     */
    private void checkGestureEnd ()
    {
        if (this.source == null)
            return;

        if (!this.source.isMove)
        {
            if (!this.surface.isPressed (ButtonID.DUPLICATE))
                this.source = null;
            return;
        }

        if (this.surface.isShiftPressed ())
            return;

        final IDevice device = this.findSourceDevice (this.source);
        this.source = null;
        if (device != null)
            this.executeShiftAction (device);
    }


    /**
     * Cancel a running gesture, e.g. if something else was done while Shift was held.
     */
    private void cancelGesture ()
    {
        this.source = null;
    }


    /**
     * Get the device of a gesture source. Checks that it is still the same track and device (it
     * might have changed since the banks were scrolled or the chain was edited).
     *
     * @param src The source
     * @return The device or null if it is no longer available
     */
    private IDevice findSourceDevice (final Source src)
    {
        final ITrackBank tb = this.model.getCurrentTrackBank ();
        if (tb != this.model.getTrackBank () || src.trackIndex >= tb.getPageSize ())
            return null;
        final ITrack track = tb.getItem (src.trackIndex);
        if (!track.doesExist () || track.getPosition () != src.trackPosition)
            return null;
        final IDeviceBank deviceBank = this.model.getTrackDeviceBank (src.trackIndex);
        if (deviceBank == null)
            return null;
        for (int i = 0; i < deviceBank.getPageSize (); i++)
        {
            final IDevice device = deviceBank.getItem (i);
            if (device.doesExist () && device.getPosition () == src.position)
                return src.name.equals (device.getName ()) ? device : null;
        }
        return null;
    }


    /**
     * Execute the configured Shift action: bypass, offline or remove. The states are updated
     * asynchronously, therefore the state before toggling is used for the notification.
     *
     * @param device The device
     */
    private void executeShiftAction (final IDevice device)
    {
        final IDisplay display = this.surface.getDisplay ();
        switch (this.surface.getConfiguration ().getPluginShiftAction ())
        {
            case REMOVE:
                display.notify ("Removed: " + device.getName ());
                device.remove ();
                break;

            case OFFLINE:
                final boolean wasOffline = device.isOffline ();
                device.toggleOffline ();
                display.notify ((wasOffline ? "Online: " : "Offline: ") + device.getName ());
                break;

            default:
                final boolean wasEnabled = device.isEnabled ();
                device.toggleEnabledState ();
                display.notify ((wasEnabled ? "Bypass: " : "Active: ") + device.getName ());
                break;
        }
    }


    private static int getDestinationPosition (final IDevice device)
    {
        return device.doesExist () ? device.getPosition () : -1;
    }


    private void handleDevicePad (final ITrack track, final IDevice device)
    {
        if (!device.doesExist ())
            return;

        final OxiOneConfiguration configuration = this.surface.getConfiguration ();

        // Fallback if no gestures are possible (effect tracks or devices of the cursor track)
        if (this.surface.isShiftPressed ())
        {
            this.executeShiftAction (device);
            return;
        }

        final boolean wasSelected = isCursorDevice (track, device, this.model.getCursorDevice ());
        if (!track.isSelected ())
            track.select ();
        device.select ();
        this.surface.getDisplay ().notify (device.getName ());

        final PluginWindowBehaviour behaviour = configuration.getPluginWindowBehaviour ();
        if (behaviour == PluginWindowBehaviour.FIRST_PRESS || behaviour == PluginWindowBehaviour.SECOND_PRESS && wasSelected || device.isWindowOpen ())
            device.toggleWindowOpen ();
    }


    /** {@inheritDoc} */
    @Override
    public boolean handlesCursor (final Direction direction)
    {
        // Only possible with device banks per track of the main track bank
        if (direction != Direction.UP && direction != Direction.DOWN)
            return false;
        return this.model.getCurrentTrackBank () == this.model.getTrackBank () && this.model.getTrackDeviceBank (0) != null;
    }


    /** {@inheritDoc} */
    @Override
    public void onCursor (final Direction direction, final boolean isShifted)
    {
        this.cancelGesture ();
        final int visibleRows = 8 - this.updateLayout ().size ();
        final int pageSize = this.model.getTrackBank ().getPageSize ();
        for (int i = 0; i < pageSize; i++)
        {
            final IDeviceBank deviceBank = this.model.getTrackDeviceBank (i);
            if (deviceBank == null)
                continue;
            final int position = Math.max (0, deviceBank.getScrollPosition ());
            if (direction == Direction.UP)
            {
                if (position > 0)
                    deviceBank.scrollTo (isShifted ? 0 : position - 1);
            }
            else if (position + visibleRows < deviceBank.getItemCount ())
                deviceBank.scrollTo (position + 1);
        }
    }


    /** {@inheritDoc} */
    @Override
    public boolean canCursor (final Direction direction, final boolean isShifted)
    {
        final int visibleRows = 8 - this.updateLayout ().size ();
        final int pageSize = this.model.getTrackBank ().getPageSize ();
        for (int i = 0; i < pageSize; i++)
        {
            final IDeviceBank deviceBank = this.model.getTrackDeviceBank (i);
            if (deviceBank == null)
                continue;
            final int position = Math.max (0, deviceBank.getScrollPosition ());
            if (direction == Direction.UP ? position > 0 : position + visibleRows < deviceBank.getItemCount ())
                return true;
        }
        return false;
    }


    /**
     * Get the device bank to display for a track. If the DAW does not support device banks per
     * track (or the effect track bank is active) only the devices of the selected track are shown
     * (from the cursor device bank).
     *
     * @param index The index of the track in the page
     * @param track The track
     * @param isMainBank True if the main track bank is active
     * @return The device bank or null
     */
    private IDeviceBank getDeviceBank (final int index, final ITrack track, final boolean isMainBank)
    {
        if (isMainBank)
        {
            final IDeviceBank deviceBank = this.model.getTrackDeviceBank (index);
            if (deviceBank != null)
                return deviceBank;
        }
        return track.isSelected () ? this.model.getCursorDevice ().getDeviceBank () : null;
    }


    private static boolean isCursorDevice (final ITrack track, final IDevice device, final ICursorDevice cursorDevice)
    {
        // A nested device (in a container or layer) is never on the top level of the track
        return track.isSelected () && cursorDevice.doesExist () && !cursorDevice.isNested () && cursorDevice.getPosition () == device.getPosition ();
    }


    private List<RowType> updateLayout ()
    {
        final List<RowType> trackRows = OxiOneTrackRows.getMixerRows (this.surface.getConfiguration (), this.surface.isShiftPressed ());
        this.numTrackRows = trackRows.size ();
        return trackRows;
    }
}
