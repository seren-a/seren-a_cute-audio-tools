// Written by Jürgen Moßgraber - mossgrabers.de
// (c) 2017-2026
// Licensed under LGPLv3 - http://www.gnu.org/licenses/lgpl-3.0.txt

package de.mossgrabers.controller.oxi.one.view;

import java.util.List;

import de.mossgrabers.controller.oxi.one.OxiOneConfiguration;
import de.mossgrabers.controller.oxi.one.controller.OxiOneColorManager;
import de.mossgrabers.controller.oxi.one.controller.OxiOneControlSurface;
import de.mossgrabers.controller.oxi.one.view.OxiOneTrackRows.RowType;
import de.mossgrabers.framework.controller.ButtonID;
import de.mossgrabers.framework.controller.grid.LightInfo;
import de.mossgrabers.framework.daw.IModel;
import de.mossgrabers.framework.daw.data.ISlot;
import de.mossgrabers.framework.daw.data.ITrack;
import de.mossgrabers.framework.daw.data.bank.ITrackBank;
import de.mossgrabers.framework.view.AbstractSessionView;


/**
 * A view for mixing with track select, mute, solo, record arm, stop clip, volume and panning as
 * well as 4 rows of clips. Mute, solo and record arm rows can be hidden in the configuration, which
 * gives up to 2 more rows of clips.
 *
 * @author Jürgen Moßgraber
 */
public class OxiOneMixAndSessionView extends AbstractSessionView<OxiOneControlSurface, OxiOneConfiguration>
{
    private final OxiOneTrackRows.PressedRows pressedRows  = new OxiOneTrackRows.PressedRows ();
    private int                               consumedNote = -1;


    /**
     * Constructor.
     *
     * @param surface The surface
     * @param model The model
     */
    public OxiOneMixAndSessionView (final OxiOneControlSurface surface, final IModel model)
    {
        super ("Track Mixer", surface, model, 4, 16, true);

        final int redLo = OxiOneColorManager.OXI_ONE_COLOR_DARKER_RED;
        final int redHi = OxiOneColorManager.OXI_ONE_COLOR_RED;
        final int black = OxiOneColorManager.OXI_ONE_COLOR_BLACK;
        final int white = OxiOneColorManager.OXI_ONE_COLOR_WHITE;
        final int green = OxiOneColorManager.OXI_ONE_COLOR_GREEN;
        final int amber = OxiOneColorManager.OXI_ONE_COLOR_ORANGE;
        final int gray = OxiOneColorManager.OXI_ONE_COLOR_GRAY;
        final LightInfo isRecording = new LightInfo (redHi, -1, false);
        final LightInfo isRecordingQueued = new LightInfo (redHi, black, true);
        final LightInfo isPlaying = new LightInfo (green, -1, false);
        final LightInfo isPlayingQueued = new LightInfo (green, green, true);
        final LightInfo isStopQueued = new LightInfo (green, green, true);
        final LightInfo hasContent = new LightInfo (amber, white, false);
        final LightInfo noContent = new LightInfo (black, -1, false);
        final LightInfo recArmed = new LightInfo (redLo, -1, false);
        final LightInfo isMuted = new LightInfo (gray, -1, false);
        this.setColors (isRecording, isRecordingQueued, isPlaying, isPlayingQueued, isStopQueued, hasContent, noContent, recArmed, isMuted);
    }


    /** {@inheritDoc} */
    @Override
    public void drawGrid ()
    {
        this.updateClipColors ();
        final List<RowType> trackRows = this.updateLayout ();

        final ITrackBank tb = this.model.getCurrentTrackBank ();
        for (int i = 0; i < tb.getPageSize (); i++)
        {
            final ITrack track = tb.getItem (i);
            for (int y = 0; y < trackRows.size (); y++)
                OxiOneTrackRows.drawTrackPad (this.surface, this.colorManager, i, y, track, trackRows.get (y));

            // Rows which are not used, if there are less scenes than free rows (Mk1)
            for (int y = trackRows.size (); y < this.getYOffset (); y++)
                this.surface.getPadGrid ().lightEx (i, y, OxiOneColorManager.OXI_ONE_COLOR_BLACK);
        }

        super.drawGrid ();
    }


    /** {@inheritDoc} */
    @Override
    public void onGridNote (final int note, final int velocity)
    {
        final List<RowType> trackRows = this.updateLayout ();

        // Note rows are counted from the bottom (0) to the top (7)
        final int row = note / 16;
        final int y = 7 - row;
        if (y >= this.getYOffset ())
        {
            super.onGridNote (note, velocity);
        }
        else if (y < trackRows.size ())
        {
            final int index = note % 16;
            final ITrack track = this.model.getCurrentTrackBank ().getItem (index);
            if (velocity > 0)
            {
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

        // Revert to last view of the selected track
        if (velocity == 0 && this.surface.isPressed (ButtonID.SESSION))
        {
            this.surface.setTriggerConsumed (ButtonID.SESSION);
            this.surface.recallPreferredView (this.model.getCursorTrack ());
        }
    }


    /**
     * Apply the configured clip colors.
     */
    private void updateClipColors ()
    {
        final OxiOneConfiguration config = this.surface.getConfiguration ();
        final LightInfo [] c = OxiOneClipColors.createColors (config);
        this.useClipColor = OxiOneClipColors.useClipColor (config);
        this.setColors (c[OxiOneClipColors.IS_RECORDING], c[OxiOneClipColors.IS_RECORDING_QUEUED], c[OxiOneClipColors.IS_PLAYING], c[OxiOneClipColors.IS_PLAYING_QUEUED], c[OxiOneClipColors.IS_STOP_QUEUED], c[OxiOneClipColors.HAS_CONTENT], c[OxiOneClipColors.NO_CONTENT], c[OxiOneClipColors.REC_ARMED], c[OxiOneClipColors.IS_MUTED]);
        this.birdColorHasContent = c[OxiOneClipColors.HAS_CONTENT];
    }


    /**
     * Update the number of clip rows depending on the number of track state rows which are
     * configured to be visible.
     *
     * @return The visible track state rows
     */
    private List<RowType> updateLayout ()
    {
        final List<RowType> trackRows = OxiOneTrackRows.getMixerRows (this.surface.getConfiguration (), this.surface.isShiftPressed ());
        // The clips are always aligned at the bottom, limited by the number of scenes (Mk1 has
        // only 4)
        final int numScenes = this.model.getCurrentTrackBank ().getSceneBank ().getPageSize ();
        this.rows = Math.min (8 - trackRows.size (), numScenes);
        return trackRows;
    }


    /** {@inheritDoc} */
    @Override
    protected boolean handleButtonCombinations (final ITrack track, final ISlot slot)
    {
        if (!track.doesExist ())
            return true;

        // Stop clip
        if (this.isButtonCombination (ButtonID.STOP))
        {
            track.stop (this.isAlternateFunction ());
            return true;
        }

        return super.handleButtonCombinations (track, slot);
    }


    /** {@inheritDoc} */
    @Override
    protected int getYOffset ()
    {
        return 8 - this.rows;
    }
}