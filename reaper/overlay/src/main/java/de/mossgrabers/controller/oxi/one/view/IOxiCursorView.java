// Written by Jürgen Moßgraber - mossgrabers.de
// (c) 2017-2026
// Licensed under LGPLv3 - http://www.gnu.org/licenses/lgpl-3.0.txt

package de.mossgrabers.controller.oxi.one.view;

import de.mossgrabers.framework.command.trigger.Direction;


/**
 * Interface for views which want to handle (some of) the cursor buttons themselves.
 *
 * @author Jürgen Moßgraber
 */
public interface IOxiCursorView
{
    /**
     * Does the view handle the given cursor direction itself?
     *
     * @param direction The direction
     * @return True if the view handles it
     */
    boolean handlesCursor (Direction direction);


    /**
     * Execute the cursor action. Only called if handlesCursor returned true.
     *
     * @param direction The direction
     * @param isShifted True if Shift is pressed
     */
    void onCursor (Direction direction, boolean isShifted);


    /**
     * Can the view scroll in the given direction? Only called if handlesCursor returned true.
     *
     * @param direction The direction
     * @param isShifted True if Shift is pressed
     * @return True if possible
     */
    boolean canCursor (Direction direction, boolean isShifted);
}
