// Written by Jürgen Moßgraber - mossgrabers.de
// (c) 2017-2026
// Licensed under LGPLv3 - http://www.gnu.org/licenses/lgpl-3.0.txt

package de.mossgrabers.controller.oxi.one.view;

import java.util.Collections;
import java.util.Map;
import java.util.WeakHashMap;

import de.mossgrabers.framework.observer.IObserverManagement;


/**
 * Helper to enable/disable the observers of banks only while a view is active. Several views can
 * share the same bank (e.g. all the views for more than 16 tracks) and the DAW might count the
 * subscriptions (Bitwig reports an error if there are more unsubscribes than subscribes). Therefore,
 * the state of each bank is remembered and a bank is only switched if the state really changes.
 *
 * @author Jürgen Moßgraber
 */
public final class OxiOneObservers
{
    /** The banks which are currently unsubscribed, all other banks are subscribed by default. */
    private static final Map<IObserverManagement, Boolean> STATES = Collections.synchronizedMap (new WeakHashMap<> ());


    /**
     * Private constructor for utility class.
     */
    private OxiOneObservers ()
    {
        // Intentionally empty
    }


    /**
     * Enable or disable the observers of an object, but only if this is a change.
     *
     * @param target The object (e.g. a bank), may be null
     * @param enable True to enable, false to disable the observers
     */
    public static void setEnabled (final IObserverManagement target, final boolean enable)
    {
        if (target == null)
            return;
        synchronized (STATES)
        {
            final boolean isEnabled = !STATES.containsKey (target);
            if (isEnabled == enable)
                return;
            if (enable)
                STATES.remove (target);
            else
                STATES.put (target, Boolean.TRUE);
        }
        target.enableObservers (enable);
    }
}
