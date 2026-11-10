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
import de.mossgrabers.framework.view.Views;


/**
 * Mixer for 32 tracks: 2 blocks of 16 tracks with 4 rows each. The first rows of a block are the
 * track state rows as configured for the track mixer (select, mute, solo, record arm). The rows
 * which are not used by the state rows show the devices (insert plugins) of each track, like in the
 * plugin mixer. At least one row of each block is reserved for the devices, if all 4 state rows are
 * configured the record arm and then the solo row are not displayed.
 * <p>
 * Pressing a device pad selects the device (and optionally opens its plugin window). Up/Down scroll
 * the devices of all visible tracks. The gestures for copying, moving, swapping and deleting
 * devices work like in the plugin mixer (also across the 32 visible tracks).
 *
 * @author Jürgen Moßgraber
 */
public class OxiOnePlugin32View extends AbstractOxiOneWideMixerView
{
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

    private Source source = null;


    /**
     * Constructor.
     *
     * @param surface The surface
     * @param model The model
     */
    public OxiOnePlugin32View (final OxiOneControlSurface surface, final IModel model)
    {
        super (Views.NAME_PLUGIN32, surface, model, 2);

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
        // The devices of the visible tracks
        final ITrackBank bank = this.getBank ();
        boolean hasDeviceBanks = false;
        for (int i = 0; i < this.getNumTracks (); i++)
        {
            final ITrack track = this.getTrack (bank, i);
            final IDeviceBank deviceBank = track == null ? null : this.model.getTrackDeviceBank (track);
            if (deviceBank == null)
                continue;
            OxiOneObservers.setEnabled (deviceBank, enable);
            hasDeviceBanks = true;
        }
        if (hasDeviceBanks)
            return;

        // Fallback to the device banks of the main track bank
        final int pageSize = this.model.getTrackBank ().getPageSize ();
        for (int i = 0; i < pageSize; i++)
        {
            OxiOneObservers.setEnabled (this.model.getTrackDeviceBank (i), enable);
        }
    }


    /** {@inheritDoc} */
    @Override
    protected List<RowType> getBlockRows (final OxiOneConfiguration configuration)
    {
        final List<RowType> rows = OxiOneTrackRows.getMixerRows (configuration, this.surface.isShiftPressed ());
        // Keep at least one row for the devices
        final int maxRows = this.getRowsPerBlock () - 1;
        return rows.size () > maxRows ? rows.subList (0, maxRows) : rows;
    }


    /**
     * Get the number of rows per block which display devices.
     *
     * @return The number of rows
     */
    private int getNumDeviceRows ()
    {
        return this.getRowsPerBlock () - this.getBlockRows (this.surface.getConfiguration ()).size ();
    }


    /** {@inheritDoc} */
    @Override
    public void drawGrid ()
    {
        this.checkGestureEnd ();
        super.drawGrid ();
    }


    /** {@inheritDoc} */
    @Override
    protected void drawExtraPad (final int x, final int y, final int trackIndex, final ITrack track, final int extraRow)
    {
        final IPadGrid padGrid = this.surface.getPadGrid ();
        final IDeviceBank deviceBank = track.doesExist () ? this.model.getTrackDeviceBank (track) : null;
        if (deviceBank == null || extraRow >= deviceBank.getPageSize ())
        {
            padGrid.lightEx (x, y, OxiOneColorManager.OXI_ONE_COLOR_BLACK);
            return;
        }

        final IDevice device = deviceBank.getItem (extraRow);
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
        if (this.source != null && this.source.trackIndex == trackIndex && this.source.position == device.getPosition ())
            padGrid.lightEx (x, y, color, blinkColor, true);
        else if (isCursorDevice (track, device, this.model.getCursorDevice ()))
            padGrid.lightEx (x, y, color, blinkColor, false);
        else
            padGrid.lightEx (x, y, color);
    }


    /** {@inheritDoc} */
    @Override
    protected void onTrackRowPressed ()
    {
        // Using any other pad ends a gesture
        this.cancelGesture ();
    }


    /** {@inheritDoc} */
    @Override
    protected void onExtraPadPressed (final int trackIndex, final ITrack track, final int extraRow)
    {
        final IDeviceBank deviceBank = track.doesExist () ? this.model.getTrackDeviceBank (track) : null;
        if (deviceBank == null || extraRow >= deviceBank.getPageSize ())
            return;

        final IDevice device = deviceBank.getItem (extraRow);
        if (!this.handleEditGestures (trackIndex, track, device))
            this.handleDevicePad (track, device);
    }


    /**
     * Handle the gestures for copying, moving and deleting devices:
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
     * @param trackIndex The index of the track in the view
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
            final ITrack copySourceTrack = this.findSourceTrack (copySource);
            if (copySourceTrack == null || this.findSourceDevice (copySource) == null)
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
            if (this.model.editDeviceChain (operation, copySourceTrack, copySource.position, track, destinationPosition))
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
            final ITrack moveSourceTrack = this.findSourceTrack (moveSource);
            if (moveSourceTrack == null || this.findSourceDevice (moveSource) == null)
            {
                display.notify ("Cancelled");
                return true;
            }
            final int destinationPosition = getDestinationPosition (device);
            if (moveSource.trackIndex == trackIndex && moveSource.position == destinationPosition)
                return true;
            final boolean isSwap = device.doesExist ();
            final DeviceChainOperation operation = isSwap ? DeviceChainOperation.SWAP : DeviceChainOperation.MOVE;
            if (this.model.editDeviceChain (operation, moveSourceTrack, moveSource.position, track, destinationPosition))
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
     * Get the track of a gesture source. Checks that it is still the same track (the tracks might
     * have changed since the bank was scrolled).
     *
     * @param src The source
     * @return The track or null if it is no longer available
     */
    private ITrack findSourceTrack (final Source src)
    {
        if (src.trackIndex >= this.getNumTracks ())
            return null;
        final ITrack track = this.getTrack (this.getBank (), src.trackIndex);
        if (track == null || !track.doesExist () || track.getPosition () != src.trackPosition)
            return null;
        return track;
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
        final ITrack track = this.findSourceTrack (src);
        if (track == null)
            return null;
        final IDeviceBank deviceBank = this.model.getTrackDeviceBank (track);
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

        final boolean wasSelected = isCursorDevice (track, device, this.model.getCursorDevice ());
        if (!track.isSelected ())
            track.select ();
        device.select ();
        this.surface.getDisplay ().notify (device.getName ());

        final PluginWindowBehaviour behaviour = this.surface.getConfiguration ().getPluginWindowBehaviour ();
        if (behaviour == PluginWindowBehaviour.FIRST_PRESS || behaviour == PluginWindowBehaviour.SECOND_PRESS && wasSelected || device.isWindowOpen ())
            device.toggleWindowOpen ();
    }


    /** {@inheritDoc} */
    @Override
    public boolean handlesCursor (final Direction direction)
    {
        // Scrolling the devices is only possible with device banks per track
        if (direction == Direction.UP || direction == Direction.DOWN)
            return this.model.getTrackDeviceBank (0) != null;
        return super.handlesCursor (direction);
    }


    /** {@inheritDoc} */
    @Override
    public void onCursor (final Direction direction, final boolean isShifted)
    {
        if (direction != Direction.UP && direction != Direction.DOWN)
        {
            this.cancelGesture ();
            super.onCursor (direction, isShifted);
            return;
        }

        this.cancelGesture ();
        final int visibleRows = this.getNumDeviceRows ();
        final ITrackBank bank = this.getBank ();
        for (int i = 0; i < this.getNumTracks (); i++)
        {
            final ITrack track = this.getTrack (bank, i);
            final IDeviceBank deviceBank = track != null && track.doesExist () ? this.model.getTrackDeviceBank (track) : null;
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
        if (direction != Direction.UP && direction != Direction.DOWN)
            return super.canCursor (direction, isShifted);

        final int visibleRows = this.getNumDeviceRows ();
        final ITrackBank bank = this.getBank ();
        for (int i = 0; i < this.getNumTracks (); i++)
        {
            final ITrack track = this.getTrack (bank, i);
            final IDeviceBank deviceBank = track != null && track.doesExist () ? this.model.getTrackDeviceBank (track) : null;
            if (deviceBank == null)
                continue;
            final int position = Math.max (0, deviceBank.getScrollPosition ());
            if (direction == Direction.UP ? position > 0 : position + visibleRows < deviceBank.getItemCount ())
                return true;
        }
        return false;
    }


    private static boolean isCursorDevice (final ITrack track, final IDevice device, final ICursorDevice cursorDevice)
    {
        // A nested device (in a container or layer) is never on the top level of the track
        return track.isSelected () && cursorDevice.doesExist () && !cursorDevice.isNested () && cursorDevice.getPosition () == device.getPosition ();
    }
}
