// Written by Jürgen Moßgraber - mossgrabers.de
// (c) 2017-2026
// Licensed under LGPLv3 - http://www.gnu.org/licenses/lgpl-3.0.txt

package de.mossgrabers.controller.oxi.one.view;

import de.mossgrabers.controller.oxi.one.controller.OxiOneControlSurface;
import de.mossgrabers.framework.daw.IModel;
import de.mossgrabers.framework.view.Views;


/**
 * Send matrix: 16 tracks, rows 2-8 show 7 sends.
 *
 * @author seren.a / Claude
 */
public class OxiOneSend16View extends AbstractOxiOneSendView
{
    /**
     * Constructor.
     *
     * @param surface The surface
     * @param model The model
     */
    public OxiOneSend16View (final OxiOneControlSurface surface, final IModel model)
    {
        super (Views.NAME_SEND16, surface, model, 1);
    }
}
