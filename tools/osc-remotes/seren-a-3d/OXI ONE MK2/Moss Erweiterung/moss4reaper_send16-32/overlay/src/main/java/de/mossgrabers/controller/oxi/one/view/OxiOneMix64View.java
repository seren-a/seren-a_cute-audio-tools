// Written by Jürgen Moßgraber - mossgrabers.de
// (c) 2017-2026
// Licensed under LGPLv3 - http://www.gnu.org/licenses/lgpl-3.0.txt

package de.mossgrabers.controller.oxi.one.view;

import java.util.List;

import de.mossgrabers.controller.oxi.one.OxiOneConfiguration;
import de.mossgrabers.controller.oxi.one.controller.OxiOneControlSurface;
import de.mossgrabers.controller.oxi.one.view.OxiOneTrackRows.RowType;
import de.mossgrabers.framework.daw.IModel;
import de.mossgrabers.framework.view.Views;


/**
 * Mixer for 64 tracks without clips: 4 blocks of 16 tracks with 2 rows each. The first row selects
 * the track, the second row is either mute or solo (see configuration). Holding Shift displays the
 * other one.
 *
 * @author Jürgen Moßgraber
 */
public class OxiOneMix64View extends AbstractOxiOneWideMixerView
{
    private static final List<RowType> ROWS_MUTE = List.of (RowType.SELECT, RowType.MUTE);
    private static final List<RowType> ROWS_SOLO = List.of (RowType.SELECT, RowType.SOLO);


    /**
     * Constructor.
     *
     * @param surface The surface
     * @param model The model
     */
    public OxiOneMix64View (final OxiOneControlSurface surface, final IModel model)
    {
        super (Views.NAME_MIX64, surface, model, 4);
    }


    /** {@inheritDoc} */
    @Override
    protected List<RowType> getBlockRows (final OxiOneConfiguration configuration)
    {
        return OxiOneTrackRows.getMix64StateRow (configuration, this.surface.isShiftPressed ()) == RowType.SOLO ? ROWS_SOLO : ROWS_MUTE;
    }
}
