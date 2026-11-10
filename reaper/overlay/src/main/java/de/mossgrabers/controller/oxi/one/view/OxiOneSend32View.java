// Written by Jürgen Moßgraber - mossgrabers.de
// (c) 2017-2026
// Licensed under LGPLv3 - http://www.gnu.org/licenses/lgpl-3.0.txt

package de.mossgrabers.controller.oxi.one.view;

import de.mossgrabers.controller.oxi.one.controller.OxiOneControlSurface;
import de.mossgrabers.framework.daw.IModel;
import de.mossgrabers.framework.view.Views;


/**
 * Send matrix: 2 blocks of 16 tracks, rows 2-4 show 3 sends each.
 *
 * @author seren.a / Claude
 */
public class OxiOneSend32View extends AbstractOxiOneSendView
{
    /**
     * Constructor.
     *
     * @param surface The surface
     * @param model The model
     */
    public OxiOneSend32View (final OxiOneControlSurface surface, final IModel model)
    {
        super (Views.NAME_SEND32, surface, model, 2);
    }
}
