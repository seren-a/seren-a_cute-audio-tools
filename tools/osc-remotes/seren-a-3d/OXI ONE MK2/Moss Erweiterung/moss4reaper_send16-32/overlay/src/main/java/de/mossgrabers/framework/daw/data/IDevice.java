// Written by Jürgen Moßgraber - mossgrabers.de
// (c) 2017-2026
// Licensed under LGPLv3 - http://www.gnu.org/licenses/lgpl-3.0.txt

package de.mossgrabers.framework.daw.data;

/**
 * Interface to a device.
 *
 * @author Jürgen Moßgraber
 */
public interface IDevice extends IItem
{
    /**
     * Returns true if the device is enabled.
     *
     * @return True if the device is enabled
     */
    boolean isEnabled ();


    /**
     * Toggle the device on/off.
     */
    void toggleEnabledState ();


    /**
     * Delete the device.
     */
    void remove ();


    /**
     * Duplicate the device.
     */
    void duplicate ();


    /**
     * Is the device offline (Reaper)? Default implementation returns false.
     *
     * @return True if offline
     */
    default boolean isOffline ()
    {
        return false;
    }


    /**
     * Toggle the offline state of the device (Reaper). Default implementation toggles the enabled
     * (bypass) state since offline is not supported.
     */
    default void toggleOffline ()
    {
        this.toggleEnabledState ();
    }


    /**
     * Is the plugin window of the device open? Default implementation returns false.
     *
     * @return True if open
     */
    default boolean isWindowOpen ()
    {
        return false;
    }


    /**
     * Open/close the plugin window of the device. Default implementation does nothing.
     */
    default void toggleWindowOpen ()
    {
        // Not supported by default
    }
}