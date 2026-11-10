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
 * Mixer for 32 tracks without clips: 2 blocks of 16 tracks with 4 rows each (select, mute, solo,
 * record arm - as configured for the track mixer, including the Shift behavior if only mute or
 * only solo is shown).
 *
 * @author Jürgen Moßgraber
 */
public class OxiOneMix32View extends AbstractOxiOneWideMixerView
{
    /**
     * Constructor.
     *
     * @param surface The surface
     * @param model The model
     */
    public OxiOneMix32View (final OxiOneControlSurface surface, final IModel model)
    {
        super (Views.NAME_MIX32, surface, model, 2);
    }


    /** {@inheritDoc} */
    @Override
    protected List<RowType> getBlockRows (final OxiOneConfiguration configuration)
    {
        return OxiOneTrackRows.getMixerRows (configuration, this.surface.isShiftPressed ());
    }
}
