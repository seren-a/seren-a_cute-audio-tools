// Written by Jürgen Moßgraber - mossgrabers.de
// (c) 2017-2026
// Licensed under LGPLv3 - http://www.gnu.org/licenses/lgpl-3.0.txt

package de.mossgrabers.framework.daw.data;

import de.mossgrabers.framework.controller.color.ColorEx;
import de.mossgrabers.framework.parameter.IParameter;


/**
 * Interface to a send.
 *
 * @author Jürgen Moßgraber
 */
public interface ISend extends IParameter
{
    /**
     * Get the color of the send channel.
     *
     * @return The color in RGB
     */
    ColorEx getColor ();


    /**
     * Returns true if the send is enabled.
     *
     * @return True if enabled
     */
    boolean isEnabled ();


    /**
     * Toggle the enabled state of the send.
     */
    void toggleEnabled ();


    /**
     * Can the send be switched between pre- and post-fader?
     *
     * @return True if supported by the DAW implementation
     */
    default boolean canChangePreFader ()
    {
        return false;
    }


    /**
     * Returns true if the send is taken before the fader.
     *
     * @return True if pre-fader
     */
    default boolean isPreFader ()
    {
        return false;
    }


    /**
     * Switch the send between pre- and post-fader (if supported).
     */
    default void togglePreFader ()
    {
        // Not supported by default
    }
}