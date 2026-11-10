// Written by Jürgen Moßgraber - mossgrabers.de
// (c) 2017-2026
// Licensed under LGPLv3 - http://www.gnu.org/licenses/lgpl-3.0.txt

package de.mossgrabers.framework.daw.constants;

/**
 * Operations to edit the device chains (insert slots) of tracks.
 *
 * @author Jürgen Moßgraber
 */
public enum DeviceChainOperation
{
    /**
     * Insert a copy of the source device before the destination device (or at the end of the
     * destination chain).
     */
    COPY,
    /** Replace the destination device with a copy of the source device. */
    REPLACE,
    /** Move the source device before the destination device (or to the end of the chain). */
    MOVE,
    /** Swap the positions of the source and the destination device. */
    SWAP
}
