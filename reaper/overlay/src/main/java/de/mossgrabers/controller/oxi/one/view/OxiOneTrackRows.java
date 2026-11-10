// Written by Jürgen Moßgraber - mossgrabers.de
// (c) 2017-2026
// Licensed under LGPLv3 - http://www.gnu.org/licenses/lgpl-3.0.txt

package de.mossgrabers.controller.oxi.one.view;

import java.util.ArrayList;
import java.util.List;

import de.mossgrabers.controller.oxi.one.OxiOneConfiguration;
import de.mossgrabers.controller.oxi.one.OxiOneConfiguration.TrackButtons;
import de.mossgrabers.controller.oxi.one.controller.OxiOneColorManager;
import de.mossgrabers.controller.oxi.one.controller.OxiOneControlSurface;
import de.mossgrabers.framework.controller.ButtonID;
import de.mossgrabers.framework.controller.color.ColorManager;
import de.mossgrabers.framework.controller.grid.IPadGrid;
import de.mossgrabers.framework.daw.DAWColor;
import de.mossgrabers.framework.daw.data.ITrack;


/**
 * Helper for drawing and handling the track state rows (select, mute, solo, record arm) which are
 * shared by the different mixer views of the OXI One.
 *
 * @author Jürgen Moßgraber
 */
public final class OxiOneTrackRows
{
    /** The different types of track state rows. */
    public enum RowType
    {
        /** Select the track. */
        SELECT,
        /** Toggle mute. */
        MUTE,
        /** Toggle solo. */
        SOLO,
        /** Toggle record arm. */
        REC_ARM
    }


    /**
     * Private due to helper class.
     */
    private OxiOneTrackRows ()
    {
        // Intentionally empty
    }


    /**
     * Remembers the type of the row which a pad had when it was pressed. The row types can change
     * while a pad is held (Shift shows the other state row), the release of the pad must still
     * trigger the action of the row which was visible when the pad was pressed.
     */
    public static final class PressedRows
    {
        private final RowType [] rowTypes = new RowType [128];


        /**
         * Remember the row type of a pressed pad.
         *
         * @param note The note of the pad
         * @param rowType The row type
         */
        public void press (final int note, final RowType rowType)
        {
            if (note >= 0 && note < this.rowTypes.length)
                this.rowTypes[note] = rowType;
        }


        /**
         * Get (and forget) the row type which was remembered when the pad was pressed.
         *
         * @param note The note of the pad
         * @param fallback The row type to return if nothing was remembered
         * @return The row type
         */
        public RowType release (final int note, final RowType fallback)
        {
            if (note < 0 || note >= this.rowTypes.length)
                return fallback;
            final RowType rowType = this.rowTypes[note];
            this.rowTypes[note] = null;
            return rowType == null ? fallback : rowType;
        }
    }


    /**
     * Get the rows to display in the track mixer and plugin mixer view, depending on the
     * configuration. If only mute or only solo is configured, holding Shift displays the other
     * one.
     *
     * @param configuration The configuration
     * @param isShifted True if Shift is pressed
     * @return The rows from top to bottom, the first is always the select row
     */
    public static List<RowType> getMixerRows (final OxiOneConfiguration configuration, final boolean isShifted)
    {
        final List<RowType> rows = new ArrayList<> (4);
        rows.add (RowType.SELECT);
        final TrackButtons trackButtons = configuration.getTrackButtons ();
        if (trackButtons == TrackButtons.MUTE_AND_SOLO)
        {
            rows.add (RowType.MUTE);
            rows.add (RowType.SOLO);
        }
        else if (trackButtons == TrackButtons.MUTE_ONLY)
            rows.add (isShifted ? RowType.SOLO : RowType.MUTE);
        else
            rows.add (isShifted ? RowType.MUTE : RowType.SOLO);
        if (configuration.isShowRecArm ())
            rows.add (RowType.REC_ARM);
        return rows;
    }


    /**
     * Get the state row (mute or solo) of the Mix 64 view, which only has one state row. Holding Shift
     * displays the other one.
     *
     * @param configuration The configuration
     * @param isShifted True if Shift is pressed
     * @return The row type
     */
    public static RowType getMix64StateRow (final OxiOneConfiguration configuration, final boolean isShifted)
    {
        return configuration.isMix64ShowsSolo () != isShifted ? RowType.SOLO : RowType.MUTE;
    }


    /**
     * Draw one pad of a track state row.
     *
     * @param surface The surface
     * @param colorManager The color manager
     * @param x The x position on the grid (0 is left)
     * @param y The y position on the grid (0 is top)
     * @param track The track
     * @param rowType The type of the row
     */
    public static void drawTrackPad (final OxiOneControlSurface surface, final ColorManager colorManager, final int x, final int y, final ITrack track, final RowType rowType)
    {
        final IPadGrid padGrid = surface.getPadGrid ();
        if (!track.doesExist ())
        {
            padGrid.lightEx (x, y, OxiOneColorManager.OXI_ONE_COLOR_BLACK);
            return;
        }

        final OxiOneConfiguration configuration = surface.getConfiguration ();
        final boolean colorTrackStates = configuration.isColorTrackStates ();
        switch (rowType)
        {
            case SELECT:
                final int colorIndex = colorManager.getColorIndex (DAWColor.getColorID (track.getColor ()));
                if (track.isSelected ())
                    padGrid.lightEx (x, y, colorIndex, OxiOneColorManager.OXI_ONE_COLOR_WHITE, false);
                else
                    padGrid.lightEx (x, y, colorIndex);
                break;

            case MUTE:
                padGrid.lightEx (x, y, getStateColor (track.isMute (), colorTrackStates, configuration.getMuteColor (true), configuration.getMuteColor (false)));
                break;

            case SOLO:
                padGrid.lightEx (x, y, getStateColor (track.isSolo (), colorTrackStates, configuration.getSoloColor (true), configuration.getSoloColor (false)));
                break;

            case REC_ARM:
                padGrid.lightEx (x, y, getStateColor (track.isRecArm (), colorTrackStates, OxiOneColorManager.OXI_ONE_COLOR_RED, OxiOneColorManager.OXI_ONE_COLOR_DARKER_RED));
                break;
        }
    }


    /**
     * Handle the press of a pad in a track state row. Holding PASTE removes the track, holding COPY
     * duplicates it. This is executed on the press, so that it does not matter in which order the
     * buttons are released.
     *
     * @param surface The surface
     * @param track The track
     * @param rowType The type of the row
     * @return True if the press was consumed, the release of the pad must then be ignored
     */
    public static boolean handleTrackPadPress (final OxiOneControlSurface surface, final ITrack track, final RowType rowType)
    {
        if (rowType != RowType.SELECT || !track.doesExist ())
            return false;

        if (surface.isPressed (ButtonID.DELETE))
        {
            surface.setTriggerConsumed (ButtonID.DELETE);
            surface.getDisplay ().notify ("Removed: " + track.getName ());
            track.remove ();
            return true;
        }

        if (surface.isPressed (ButtonID.DUPLICATE))
        {
            surface.setTriggerConsumed (ButtonID.DUPLICATE);
            surface.getDisplay ().notify ("Duplicated: " + track.getName ());
            track.duplicate ();
            return true;
        }

        return false;
    }


    /**
     * Handle the release of a pad in a track state row.
     *
     * @param surface The surface
     * @param track The track
     * @param rowType The type of the row
     */
    public static void handleTrackPad (final OxiOneControlSurface surface, final ITrack track, final RowType rowType)
    {
        if (!track.doesExist ())
            return;

        switch (rowType)
        {
            case SELECT:
                final OxiOneConfiguration configuration = surface.getConfiguration ();
                if (configuration.isDeleteModeActive ())
                {
                    configuration.toggleDeleteModeActive ();
                    track.remove ();
                }
                else if (configuration.isDuplicateModeActive ())
                {
                    configuration.toggleDuplicateModeActive ();
                    track.duplicate ();
                }
                else if (surface.isShiftPressed ())
                    track.stop (false);
                else
                    track.selectOrExpandGroup ();
                break;

            case MUTE:
                track.toggleMute ();
                break;

            case SOLO:
                track.toggleSolo ();
                break;

            case REC_ARM:
                track.toggleRecArm ();
                break;
        }
    }


    private static int getStateColor (final boolean state, final boolean colorTrackStates, final int activeColor, final int inActiveColor)
    {
        if (state)
            return activeColor;
        return colorTrackStates ? inActiveColor : OxiOneColorManager.OXI_ONE_COLOR_BLACK;
    }
}
