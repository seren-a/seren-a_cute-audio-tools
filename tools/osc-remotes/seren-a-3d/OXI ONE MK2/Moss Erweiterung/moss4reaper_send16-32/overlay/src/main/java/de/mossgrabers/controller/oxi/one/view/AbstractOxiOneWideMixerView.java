// Written by Jürgen Moßgraber - mossgrabers.de
// (c) 2017-2026
// Licensed under LGPLv3 - http://www.gnu.org/licenses/lgpl-3.0.txt

package de.mossgrabers.controller.oxi.one.view;

import java.util.List;

import de.mossgrabers.controller.oxi.one.OxiOneConfiguration;
import de.mossgrabers.controller.oxi.one.controller.OxiOneColorManager;
import de.mossgrabers.controller.oxi.one.controller.OxiOneControlSurface;
import de.mossgrabers.controller.oxi.one.view.OxiOneTrackRows.RowType;
import de.mossgrabers.framework.command.trigger.Direction;
import de.mossgrabers.framework.controller.ButtonID;
import de.mossgrabers.framework.controller.grid.IPadGrid;
import de.mossgrabers.framework.daw.IModel;
import de.mossgrabers.framework.daw.data.ITrack;
import de.mossgrabers.framework.daw.data.bank.ITrackBank;
import de.mossgrabers.framework.featuregroup.AbstractView;


/**
 * Base class for mixer views which display more than 16 tracks without clips. The tracks are
 * arranged in blocks of 16 tracks (one track per column). Each block has a fixed number of rows,
 * the first row of a block selects the track, the others are track states (mute, solo, record
 * arm). Left/Right scroll by the number of visible tracks, with Shift by 16 tracks. Rows of a block
 * which are not used by the track state rows can be filled by subclasses (extra rows).
 *
 * @author Jürgen Moßgraber
 */
public abstract class AbstractOxiOneWideMixerView extends AbstractView<OxiOneControlSurface, OxiOneConfiguration> implements IOxiCursorView
{
    /** The size of the track bank used by all wide mixer views. */
    public static final int  TRACK_BANK_SIZE = 64;

    private static final int COLUMNS         = 16;

    private final int        numBlocks;
    private final int        rowsPerBlock;
    private final int        numTracks;
    private final OxiOneTrackRows.PressedRows pressedRows = new OxiOneTrackRows.PressedRows ();
    private int              consumedNote    = -1;


    /**
     * Constructor.
     *
     * @param name The name of the view
     * @param surface The surface
     * @param model The model
     * @param numBlocks The number of blocks of 16 tracks
     */
    protected AbstractOxiOneWideMixerView (final String name, final OxiOneControlSurface surface, final IModel model, final int numBlocks)
    {
        super (name, surface, model);

        this.numBlocks = numBlocks;
        this.rowsPerBlock = 8 / numBlocks;
        this.numTracks = numBlocks * COLUMNS;

        // Only monitor the large bank while the view is active
        OxiOneObservers.setEnabled (this.model.getAdditionalTrackBank (TRACK_BANK_SIZE), false);
    }


    /**
     * Get the rows of a block from top to bottom. Must not contain more rows than rows per block.
     *
     * @param configuration The configuration
     * @return The rows
     */
    protected abstract List<RowType> getBlockRows (OxiOneConfiguration configuration);


    /**
     * Draw a pad in the rows of a block below the track state rows. The default implementation
     * turns the pad off.
     *
     * @param x The x position on the grid (0 is left)
     * @param y The y position on the grid (0 is top)
     * @param trackIndex The index of the track in the view (0 to number of visible tracks - 1)
     * @param track The track
     * @param extraRow The index of the row below the track state rows (0 is the first)
     */
    protected void drawExtraPad (final int x, final int y, final int trackIndex, final ITrack track, final int extraRow)
    {
        this.surface.getPadGrid ().lightEx (x, y, OxiOneColorManager.OXI_ONE_COLOR_BLACK);
    }


    /**
     * A pad in the rows of a block below the track state rows was pressed. The default
     * implementation does nothing.
     *
     * @param trackIndex The index of the track in the view (0 to number of visible tracks - 1)
     * @param track The track
     * @param extraRow The index of the row below the track state rows (0 is the first)
     */
    protected void onExtraPadPressed (final int trackIndex, final ITrack track, final int extraRow)
    {
        // Intentionally empty
    }


    /**
     * A pad in one of the track state rows was pressed. The default implementation does nothing.
     */
    protected void onTrackRowPressed ()
    {
        // Intentionally empty
    }


    /**
     * Get the number of rows in a block.
     *
     * @return The number of rows
     */
    protected int getRowsPerBlock ()
    {
        return this.rowsPerBlock;
    }


    /**
     * Get the number of tracks which are visible in the view.
     *
     * @return The number of tracks
     */
    protected int getNumTracks ()
    {
        return this.numTracks;
    }


    /** {@inheritDoc} */
    @Override
    public void onActivate ()
    {
        super.onActivate ();

        final ITrackBank bank = this.model.getAdditionalTrackBank (TRACK_BANK_SIZE);
        if (bank == null)
            return;
        OxiOneObservers.setEnabled (bank, true);

        // Show the page which contains the current page of the main track bank (in Bitwig the bank
        // also follows the cursor track)
        final int mainPosition = Math.max (0, this.model.getTrackBank ().getScrollPosition ());
        bank.scrollTo (mainPosition / this.numTracks * this.numTracks);
    }


    /** {@inheritDoc} */
    @Override
    public void onDeactivate ()
    {
        OxiOneObservers.setEnabled (this.model.getAdditionalTrackBank (TRACK_BANK_SIZE), false);

        super.onDeactivate ();
    }


    /** {@inheritDoc} */
    @Override
    public void drawGrid ()
    {
        final IPadGrid padGrid = this.surface.getPadGrid ();
        final List<RowType> blockRows = this.getBlockRows (this.surface.getConfiguration ());
        final ITrackBank bank = this.getBank ();

        for (int block = 0; block < this.numBlocks; block++)
        {
            for (int x = 0; x < COLUMNS; x++)
            {
                final int trackIndex = block * COLUMNS + x;
                final ITrack track = this.getTrack (bank, trackIndex);
                for (int r = 0; r < this.rowsPerBlock; r++)
                {
                    final int y = block * this.rowsPerBlock + r;
                    if (track == null)
                        padGrid.lightEx (x, y, OxiOneColorManager.OXI_ONE_COLOR_BLACK);
                    else if (r < blockRows.size ())
                        OxiOneTrackRows.drawTrackPad (this.surface, this.colorManager, x, y, track, blockRows.get (r));
                    else
                        this.drawExtraPad (x, y, trackIndex, track, r - blockRows.size ());
                }
            }
        }
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
        final List<RowType> blockRows = this.getBlockRows (this.surface.getConfiguration ());
        final int trackIndex = block * COLUMNS + x;
        final ITrack track = this.getTrack (this.getBank (), trackIndex);
        final boolean isTrackPad = track != null && r < blockRows.size ();

        if (velocity > 0)
        {
            if (isTrackPad)
            {
                this.onTrackRowPressed ();
                this.pressedRows.press (note, blockRows.get (r));
                if (OxiOneTrackRows.handleTrackPadPress (this.surface, track, blockRows.get (r)))
                    this.consumedNote = note;
            }
            else if (track != null)
                this.onExtraPadPressed (trackIndex, track, r - blockRows.size ());
            return;
        }

        if (this.consumedNote == note)
        {
            this.consumedNote = -1;
            this.pressedRows.release (note, null);
            return;
        }

        if (isTrackPad)
            OxiOneTrackRows.handleTrackPad (this.surface, track, this.pressedRows.release (note, blockRows.get (r)));

        // Revert to last view of the selected track
        if (this.surface.isPressed (ButtonID.SESSION))
        {
            this.surface.setTriggerConsumed (ButtonID.SESSION);
            this.surface.recallPreferredView (this.model.getCursorTrack ());
        }
    }


    /** {@inheritDoc} */
    @Override
    public boolean handlesCursor (final Direction direction)
    {
        return direction == Direction.LEFT || direction == Direction.RIGHT;
    }


    /** {@inheritDoc} */
    @Override
    public void onCursor (final Direction direction, final boolean isShifted)
    {
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
        final ITrackBank bank = this.getBank ();
        final int position = Math.max (0, bank.getScrollPosition ());
        if (direction == Direction.LEFT)
            return position > 0;
        return position + (isShifted ? COLUMNS : this.numTracks) < bank.getItemCount ();
    }


    /**
     * Get the track bank to use. Falls back to the current track bank (16 tracks) if the DAW does
     * not support additional track banks.
     *
     * @return The bank
     */
    protected ITrackBank getBank ()
    {
        final ITrackBank bank = this.model.getAdditionalTrackBank (TRACK_BANK_SIZE);
        return bank == null ? this.model.getCurrentTrackBank () : bank;
    }


    /**
     * Get a track of the bank.
     *
     * @param bank The bank
     * @param index The index of the track in the page of the bank
     * @return The track or null if the index is outside of the page
     */
    protected ITrack getTrack (final ITrackBank bank, final int index)
    {
        return index < bank.getPageSize () ? bank.getItem (index) : null;
    }
}
