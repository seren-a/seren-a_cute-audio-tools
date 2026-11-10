// Written by Jürgen Moßgraber - mossgrabers.de
// (c) 2017-2026
// Licensed under LGPLv3 - http://www.gnu.org/licenses/lgpl-3.0.txt

package de.mossgrabers.controller.oxi.one.view;

import de.mossgrabers.controller.oxi.one.OxiOneConfiguration;
import de.mossgrabers.controller.oxi.one.controller.OxiOneColorManager;
import de.mossgrabers.framework.controller.grid.LightInfo;


/**
 * The clip colors of the session views, which can be configured.
 *
 * @author Jürgen Moßgraber
 */
public final class OxiOneClipColors
{
    /** Index of the color for a recording clip. */
    public static final int  IS_RECORDING        = 0;
    /** Index of the color for a clip which is queued for recording. */
    public static final int  IS_RECORDING_QUEUED = 1;
    /** Index of the color for a playing clip. */
    public static final int  IS_PLAYING          = 2;
    /** Index of the color for a clip which is queued for playback. */
    public static final int  IS_PLAYING_QUEUED   = 3;
    /** Index of the color for a clip which is queued for stopping. */
    public static final int  IS_STOP_QUEUED      = 4;
    /** Index of the color for a clip with content. */
    public static final int  HAS_CONTENT         = 5;
    /** Index of the color for an empty slot. */
    public static final int  NO_CONTENT          = 6;
    /** Index of the color for an empty slot of a record armed track. */
    public static final int  REC_ARMED           = 7;
    /** Index of the color for a muted clip. */
    public static final int  IS_MUTED            = 8;

    private static final int DEFAULT_CONTENT     = OxiOneColorManager.OXI_ONE_COLOR_ORANGE;


    /**
     * Private due to helper class.
     */
    private OxiOneClipColors ()
    {
        // Intentionally empty
    }


    /**
     * Should the clip colors of the DAW be used?
     *
     * @param configuration The configuration
     * @return True if the DAW clip colors should be used
     */
    public static boolean useClipColor (final OxiOneConfiguration configuration)
    {
        return configuration.getClipColor () < 0;
    }


    /**
     * Create the colors for the session view.
     *
     * @param configuration The configuration
     * @return The colors, see the index constants
     */
    public static LightInfo [] createColors (final OxiOneConfiguration configuration)
    {
        final int black = OxiOneColorManager.OXI_ONE_COLOR_BLACK;
        final int white = OxiOneColorManager.OXI_ONE_COLOR_WHITE;
        final int recording = configuration.getClipRecordingColor ();
        final int playing = configuration.getClipPlayingColor ();
        final int clipColor = configuration.getClipColor ();
        final int content = clipColor < 0 ? DEFAULT_CONTENT : clipColor;

        return new LightInfo []
        {
            new LightInfo (recording, -1, false),
            new LightInfo (recording, black, true),
            new LightInfo (playing, -1, false),
            new LightInfo (playing, playing, true),
            new LightInfo (playing, playing, true),
            new LightInfo (content, white, false),
            new LightInfo (black, -1, false),
            new LightInfo (OxiOneColorManager.OXI_ONE_COLOR_DARKER_RED, -1, false),
            new LightInfo (OxiOneColorManager.OXI_ONE_COLOR_GRAY, -1, false)
        };
    }
}
