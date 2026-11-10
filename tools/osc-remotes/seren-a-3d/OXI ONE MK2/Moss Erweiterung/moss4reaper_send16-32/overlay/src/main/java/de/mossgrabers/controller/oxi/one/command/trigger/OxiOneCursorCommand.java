// Written by Jürgen Moßgraber - mossgrabers.de
// (c) 2017-2026
// Licensed under LGPLv3 - http://www.gnu.org/licenses/lgpl-3.0.txt

package de.mossgrabers.controller.oxi.one.command.trigger;

import de.mossgrabers.controller.oxi.one.OxiOneConfiguration;
import de.mossgrabers.controller.oxi.one.controller.OxiOneControlSurface;
import de.mossgrabers.controller.oxi.one.view.IOxiCursorView;
import de.mossgrabers.framework.command.trigger.Direction;
import de.mossgrabers.framework.command.trigger.mode.CursorCommand;
import de.mossgrabers.framework.daw.IModel;
import de.mossgrabers.framework.featuregroup.IView;


/**
 * Command for the left, right,up, down buttons.
 *
 * @author Jürgen Moßgraber
 */
public class OxiOneCursorCommand extends CursorCommand<OxiOneControlSurface, OxiOneConfiguration>
{
    /**
     * Constructor.
     *
     * @param direction The direction of the pushed cursor arrow
     * @param model The model
     * @param surface The surface
     */
    public OxiOneCursorCommand (final Direction direction, final IModel model, final OxiOneControlSurface surface)
    {
        super (direction, model, surface, false, true);
    }


    /** {@inheritDoc} */
    @Override
    protected void updateArrowStates ()
    {
        super.updateArrowStates ();

        final boolean isShiftPressed = this.isShifted ();
        this.scrollStates.setCanScrollUp (this.canSelectSceneItemOrPage (isShiftPressed, false));
        this.scrollStates.setCanScrollDown (this.canSelectSceneItemOrPage (isShiftPressed, true));

        // Let the active view overwrite some directions
        final IOxiCursorView cursorView = this.getCursorView ();
        if (cursorView == null)
            return;
        if (cursorView.handlesCursor (Direction.LEFT))
            this.scrollStates.setCanScrollLeft (cursorView.canCursor (Direction.LEFT, isShiftPressed));
        if (cursorView.handlesCursor (Direction.RIGHT))
            this.scrollStates.setCanScrollRight (cursorView.canCursor (Direction.RIGHT, isShiftPressed));
        if (cursorView.handlesCursor (Direction.UP))
            this.scrollStates.setCanScrollUp (cursorView.canCursor (Direction.UP, isShiftPressed));
        if (cursorView.handlesCursor (Direction.DOWN))
            this.scrollStates.setCanScrollDown (cursorView.canCursor (Direction.DOWN, isShiftPressed));
    }


    /** {@inheritDoc} */
    @Override
    protected void scrollLeft ()
    {
        if (!this.delegateToView (Direction.LEFT))
            super.scrollLeft ();
    }


    /** {@inheritDoc} */
    @Override
    protected void scrollRight ()
    {
        if (!this.delegateToView (Direction.RIGHT))
            super.scrollRight ();
    }


    /** {@inheritDoc} */
    @Override
    protected void scrollUp ()
    {
        if (!this.delegateToView (Direction.UP))
            super.scrollUp ();
    }


    /** {@inheritDoc} */
    @Override
    protected void scrollDown ()
    {
        if (!this.delegateToView (Direction.DOWN))
            super.scrollDown ();
    }


    private boolean delegateToView (final Direction scrollDirection)
    {
        final IOxiCursorView cursorView = this.getCursorView ();
        if (cursorView == null || !cursorView.handlesCursor (scrollDirection))
            return false;
        cursorView.onCursor (scrollDirection, this.isShifted ());
        return true;
    }


    private IOxiCursorView getCursorView ()
    {
        final IView activeView = this.surface.getViewManager ().getActive ();
        return activeView instanceof final IOxiCursorView cursorView ? cursorView : null;
    }
}
