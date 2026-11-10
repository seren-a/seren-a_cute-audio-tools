// Written by Jürgen Moßgraber - mossgrabers.de
// (c) 2017-2026
// Licensed under LGPLv3 - http://www.gnu.org/licenses/lgpl-3.0.txt

package de.mossgrabers.controller.oxi.one.command.trigger;

import java.util.List;

import de.mossgrabers.controller.oxi.one.OxiOneConfiguration;
import de.mossgrabers.controller.oxi.one.controller.OxiOneControlSurface;
import de.mossgrabers.framework.command.trigger.view.ViewMultiSelectCommand;
import de.mossgrabers.framework.daw.IModel;
import de.mossgrabers.framework.featuregroup.ViewManager;
import de.mossgrabers.framework.utils.ButtonEvent;
import de.mossgrabers.framework.view.Views;


/**
 * Selects the next mixer view with the MIXER button. Only the views which are activated in the
 * configuration are used, the configuration is evaluated on each button press.
 *
 * @author Jürgen Moßgraber
 */
public class OxiOneMixerViewCommand extends ViewMultiSelectCommand<OxiOneControlSurface, OxiOneConfiguration>
{
    /**
     * Constructor.
     *
     * @param model The model
     * @param surface The surface
     */
    public OxiOneMixerViewCommand (final IModel model, final OxiOneControlSurface surface)
    {
        super (model, surface);
    }


    /** {@inheritDoc} */
    @Override
    public void executeNormal (final ButtonEvent event)
    {
        if (event != ButtonEvent.DOWN)
            return;

        final ViewManager viewManager = this.surface.getViewManager ();
        final Views nextView = this.getNextView (viewManager.getActiveID ());
        if (viewManager.isActive (nextView) || viewManager.get (nextView) == null)
            return;

        viewManager.setActive (nextView);
        this.surface.getDisplay ().notify (viewManager.get (nextView).getName ());
    }


    /**
     * Get the next activated view. If the active view is not one of the mixer views, or the active
     * mixer view is deactivated in the configuration, the next activated view in the order of all
     * mixer views is selected.
     *
     * @param activeView The currently active view
     * @return The view to select
     */
    private Views getNextView (final Views activeView)
    {
        final OxiOneConfiguration configuration = this.surface.getConfiguration ();
        final List<Views> activatedViews = configuration.getMixerViews ();
        final List<Views> allViews = configuration.getAllMixerViews ();

        final int activeIndex = allViews.indexOf (activeView);
        if (activeIndex < 0)
            return activatedViews.get (0);

        for (int i = 1; i <= allViews.size (); i++)
        {
            final Views candidate = allViews.get ((activeIndex + i) % allViews.size ());
            if (activatedViews.contains (candidate))
                return candidate;
        }
        return activatedViews.get (0);
    }
}
