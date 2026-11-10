// Written by Jürgen Moßgraber - mossgrabers.de
// (c) 2017-2026
// Licensed under LGPLv3 - http://www.gnu.org/licenses/lgpl-3.0.txt

package de.mossgrabers.controller.oxi.one;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;

import de.mossgrabers.controller.oxi.one.controller.OxiOneColorManager;
import de.mossgrabers.framework.configuration.AbstractConfiguration;
import de.mossgrabers.framework.configuration.IBooleanSetting;
import de.mossgrabers.framework.configuration.IEnumSetting;
import de.mossgrabers.framework.configuration.ISettingsUI;
import de.mossgrabers.framework.controller.valuechanger.IValueChanger;
import de.mossgrabers.framework.daw.IHost;
import de.mossgrabers.framework.daw.constants.Capability;
import de.mossgrabers.framework.daw.midi.ArpeggiatorMode;
import de.mossgrabers.framework.view.Views;


/**
 * The configuration settings for OXI One.
 *
 * @author Jürgen Moßgraber
 */
public class OxiOneConfiguration extends AbstractConfiguration
{
    /** The pad brightness. */
    public static final Integer       PAD_BRIGHTNESS           = Integer.valueOf (NEXT_SETTING_ID);
    /** The mixer layout (colors, visible rows) has changed. */
    public static final Integer       MIXER_LAYOUT             = Integer.valueOf (NEXT_SETTING_ID + 1);

    private static final String       CATEGORY_MIXER           = "Mixer Views";
    private static final String       CATEGORY_MIXER_BUTTON    = "Mixer Views - MIXER button";
    private static final String       CATEGORY_MIXER_ORDER     = "Mixer Views - MIXER button order";
    private static final String []    SLOT_LABELS              =
    {
        "1st view",
        "2nd view",
        "3rd view",
        "4th view",
        "5th view",
        "6th view",
        "7th view",
        "8th view"
    };
    private static final String       CATEGORY_COLORS          = "Mixer Views - Colors";
    /** What a press and a double press on an encoder do in the send views. */
    private static final List<String> SEND_PRESS_OPTIONS       = List.of ("Mute, 2x Pre/Post", "Pre/Post, 2x Mute");

    /** The names of the selectable colors for the mute and solo pads. */
    private static final List<String> MIXER_COLOR_OPTIONS      = List.of ("Yellow", "Blue", "Red", "Green", "Orange", "Pink", "Purple", "Cyan", "Sky Blue", "White");
    /** The active colors matching the color options. */
    private static final int []       MIXER_COLORS_ACTIVE      =
    {
        OxiOneColorManager.OXI_ONE_COLOR_YELLOW,
        OxiOneColorManager.OXI_ONE_COLOR_BLUE,
        OxiOneColorManager.OXI_ONE_COLOR_RED,
        OxiOneColorManager.OXI_ONE_COLOR_GREEN,
        OxiOneColorManager.OXI_ONE_COLOR_ORANGE,
        OxiOneColorManager.OXI_ONE_COLOR_PINK,
        OxiOneColorManager.OXI_ONE_COLOR_PURPLE,
        OxiOneColorManager.OXI_ONE_COLOR_CYAN,
        OxiOneColorManager.OXI_ONE_COLOR_DARK_OCEAN,
        OxiOneColorManager.OXI_ONE_COLOR_WHITE
    };
    /** The inactive (dimmed) colors matching the color options. */
    private static final int []       MIXER_COLORS_INACTIVE    =
    {
        OxiOneColorManager.OXI_ONE_COLOR_DARKER_YELLOW,
        OxiOneColorManager.OXI_ONE_COLOR_DARKER_BLUE,
        OxiOneColorManager.OXI_ONE_COLOR_DARKER_RED,
        OxiOneColorManager.OXI_ONE_COLOR_DARKER_GREEN,
        OxiOneColorManager.OXI_ONE_COLOR_DARKER_ORANGE,
        OxiOneColorManager.OXI_ONE_COLOR_DARK_PINK,
        OxiOneColorManager.OXI_ONE_COLOR_DARK_PURPLE,
        OxiOneColorManager.OXI_ONE_COLOR_DARK_CYAN,
        OxiOneColorManager.OXI_ONE_COLOR_DARKER_BLUE,
        OxiOneColorManager.OXI_ONE_COLOR_GRAY
    };

    /** The names of all selectable colors for clips and plugins (bright and dim variants). */
    private static final List<String> STATE_COLOR_OPTIONS      = new ArrayList<> ();
    /** The color indices matching the state color options. */
    private static final List<Integer> STATE_COLORS            = new ArrayList<> ();
    private static final String       OPTION_DAW_COLOR         = "Clip color (DAW)";
    private static final String       OPTION_TRACK_COLOR       = "Track color";
    private static final List<String> CLIP_COLOR_OPTIONS       = new ArrayList<> ();
    private static final List<String> PLUGIN_COLOR_OPTIONS     = new ArrayList<> ();

    static
    {
        for (int i = 0; i < MIXER_COLOR_OPTIONS.size (); i++)
        {
            STATE_COLOR_OPTIONS.add (MIXER_COLOR_OPTIONS.get (i));
            STATE_COLORS.add (Integer.valueOf (MIXER_COLORS_ACTIVE[i]));
            STATE_COLOR_OPTIONS.add (MIXER_COLOR_OPTIONS.get (i) + " (dim)");
            STATE_COLORS.add (Integer.valueOf (MIXER_COLORS_INACTIVE[i]));
        }
        STATE_COLOR_OPTIONS.add ("Gray");
        STATE_COLORS.add (Integer.valueOf (OxiOneColorManager.OXI_ONE_COLOR_GRAY));
        STATE_COLOR_OPTIONS.add ("Off");
        STATE_COLORS.add (Integer.valueOf (OxiOneColorManager.OXI_ONE_COLOR_BLACK));

        CLIP_COLOR_OPTIONS.add (OPTION_DAW_COLOR);
        CLIP_COLOR_OPTIONS.addAll (STATE_COLOR_OPTIONS);
        PLUGIN_COLOR_OPTIONS.add (OPTION_TRACK_COLOR);
        PLUGIN_COLOR_OPTIONS.addAll (STATE_COLOR_OPTIONS);
    }

    private static final List<String> TRACK_BUTTON_OPTIONS     = List.of ("Mute & Solo", "Mute only", "Solo only");
    private static final List<String> MIX64_BUTTON_OPTIONS     = List.of ("Mute", "Solo");
    private static final List<String> PLUGIN_WINDOW_OPTIONS    = List.of ("On first press", "On second press", "Never");
    private static final List<String> SHIFT_GESTURE_OPTIONS    = List.of ("Move/Swap (action on Shift release)", "Action immediately (no Move/Swap)");
    private static final List<String> PLUGIN_SHIFT_OPTIONS     = List.of ("Bypass (on/off)", "Offline (on/off, Reaper)", "Remove device");

    /** Which state rows are shown below the select row in the mixer views. */
    public enum TrackButtons
    {
        /** Show mute and solo. */
        MUTE_AND_SOLO,
        /** Show only mute. */
        MUTE_ONLY,
        /** Show only solo. */
        SOLO_ONLY
    }

    /** What happens when a plugin pad is pressed together with Shift in the plugin mixer. */
    public enum PluginShiftAction
    {
        /** Toggle the bypass (enabled) state. */
        BYPASS,
        /** Toggle the offline state (Reaper), falls back to bypass if not supported. */
        OFFLINE,
        /** Remove the device. */
        REMOVE
    }

    /** What happens when a plugin pad is pressed in the plugin mixer. */
    public enum PluginWindowBehaviour
    {
        /** Select the device and open its window. */
        FIRST_PRESS,
        /** Select the device, open its window when pressed again. */
        SECOND_PRESS,
        /** Only select the device. */
        NEVER
    }

    private static final List<String> BRIGHTNESS_OPTIONS       = List.of ("10%", "25%", "50%", "65%", "75%", "90%", "100%");
    private static final double []    BRIGHTNESS_VALUES        = new double []
    {
        0.1,
        0.25,
        0.5,
        0.65,
        0.75,
        0.9,
        1
    };

    private static final Views []     PREFERRED_NOTE_VIEWS_MK1 =
    {
        Views.MIX,
        Views.PLUGIN_MIXER,
        Views.MIX32,
        Views.PLUGIN32,
        Views.MIX64,
        Views.SEND16,
        Views.SEND32,
        Views.DRUM_XOX,
        Views.PLAY,
        Views.DRUM64,
        Views.DRUM8,
        Views.SEQUENCER,
        Views.POLY_SEQUENCER,
        Views.RAINDROPS
    };

    private static final Views []     PREFERRED_NOTE_VIEWS_MK2 =
    {
        Views.MIX,
        Views.SESSION,
        Views.PLUGIN_MIXER,
        Views.MIX32,
        Views.PLUGIN32,
        Views.MIX64,
        Views.SEND16,
        Views.SEND32,
        Views.DRUM_XOX,
        Views.PLAY,
        Views.DRUM64,
        Views.DRUM8,
        Views.SEQUENCER,
        Views.POLY_SEQUENCER,
        Views.RAINDROPS
    };

    /** The views which can be selected with the MIXER button in the default order. */
    private final Map<Views, String>  mixerViewLabels          = new LinkedHashMap<> ();
    /** The views which are currently activated for selection with the MIXER button. */
    private final List<Views>         activeMixerViews         = new CopyOnWriteArrayList<> ();
    /** The views selected for each position of the order (a view might be selected twice). */
    private final List<Views>         mixerViewSlots           = new CopyOnWriteArrayList<> ();
    private double                    padBrightness            = 0.5;
    private int                       muteColorIndex           = 0;
    private int                       soloColorIndex           = 1;
    private boolean                   showRecArm               = true;
    private TrackButtons              trackButtons             = TrackButtons.MUTE_AND_SOLO;
    private boolean                   mix64ShowsSolo           = false;
    private boolean                   sendPressMutes           = true;
    private PluginWindowBehaviour     pluginWindowBehaviour    = PluginWindowBehaviour.SECOND_PRESS;
    private PluginShiftAction         pluginShiftAction        = PluginShiftAction.BYPASS;
    private boolean                   shiftMoveSwap            = true;
    /** -1 = use the DAW clip color. */
    private int                       clipColor                = -1;
    private int                       clipPlayingColor         = OxiOneColorManager.OXI_ONE_COLOR_GREEN;
    private int                       clipRecordingColor       = OxiOneColorManager.OXI_ONE_COLOR_RED;
    /** -1 = use the track color. */
    private int                       pluginColor              = -1;
    private int                       pluginBypassColor        = OxiOneColorManager.OXI_ONE_COLOR_GRAY;
    private int                       pluginOfflineColor       = OxiOneColorManager.OXI_ONE_COLOR_DARKER_RED;
    private int                       pluginWindowColor        = OxiOneColorManager.OXI_ONE_COLOR_WHITE;
    private final boolean             isMk2;


    /**
     * Constructor.
     *
     * @param host The DAW host
     * @param valueChanger The value changer
     * @param arpeggiatorModes The available arpeggiator modes
     * @param isMk2 True if it is the Mk2 otherwise the Mk1
     */
    public OxiOneConfiguration (final IHost host, final IValueChanger valueChanger, final List<ArpeggiatorMode> arpeggiatorModes, final boolean isMk2)
    {
        super (host, valueChanger, arpeggiatorModes);

        this.isMk2 = isMk2;

        // The Mk1 has no session view
        this.mixerViewLabels.put (Views.MIX, "Track Mixer");
        if (isMk2)
            this.mixerViewLabels.put (Views.SESSION, "Session");
        this.mixerViewLabels.put (Views.PLUGIN_MIXER, "Plugin Mixer");
        this.mixerViewLabels.put (Views.MIX32, "Mix 32");
        this.mixerViewLabels.put (Views.PLUGIN32, "Plugin 32");
        this.mixerViewLabels.put (Views.MIX64, "Mix 64");
        this.mixerViewLabels.put (Views.SEND16, "Send 16");
        this.mixerViewLabels.put (Views.SEND32, "Send 32");
        this.activeMixerViews.addAll (this.mixerViewLabels.keySet ());
        this.mixerViewSlots.addAll (this.mixerViewLabels.keySet ());

        Views.setViewName (Views.DRUM64, "Drum 128");

        // Force note on velocity to 127 since the pads only send 1
        this.accentActive = true;
    }


    /** {@inheritDoc} */
    @Override
    public void init (final ISettingsUI globalSettings, final ISettingsUI documentSettings)
    {
        // ----------------------------------------------------------------
        // Scale

        this.activateScaleSetting (documentSettings);
        this.activateScaleBaseSetting (documentSettings);
        this.activateScaleInScaleSetting (documentSettings);
        this.activateScaleLayoutSetting (documentSettings);

        // ----------------------------------------------------------------
        // Note Repeat

        this.activateNoteRepeatSetting (documentSettings);

        // ----------------------------------------------------------------
        // Hardware

        final IEnumSetting padBrightnessSetting = globalSettings.getEnumSetting ("Grid Pad Brightness", CATEGORY_HARDWARE_SETUP, BRIGHTNESS_OPTIONS, BRIGHTNESS_OPTIONS.get (2));
        padBrightnessSetting.addValueObserver (value -> {
            this.padBrightness = BRIGHTNESS_VALUES[lookupIndex (BRIGHTNESS_OPTIONS, value)];
            this.notifyObservers (PAD_BRIGHTNESS);
        });

        // ----------------------------------------------------------------
        // Session

        this.activateSelectClipOnLaunchSetting (globalSettings);
        this.activateDrawRecordStripeSetting (globalSettings);
        this.activateActionForRecArmedPad (globalSettings);

        // ----------------------------------------------------------------
        // Transport

        this.activateBehaviourOnStopSetting (globalSettings);
        this.activateBehaviourOnPauseSetting (globalSettings);
        this.activateRecordButtonSetting (globalSettings);
        this.activateShiftedRecordButtonSetting (globalSettings);
        this.activateDoubleClickPlayButton (globalSettings);
        this.activateDoubleClickStopButton (globalSettings);

        // ----------------------------------------------------------------
        // Play and Sequence

        this.activateQuantizeAmountSetting (globalSettings);
        this.activateMidiEditChannelSetting (documentSettings);
        this.activateTurnOffScalePadsSetting (globalSettings);
        this.activateShowPlayedChordsSetting (globalSettings);
        this.activateStartupViewSetting (globalSettings, this.isMk2 ? PREFERRED_NOTE_VIEWS_MK2 : PREFERRED_NOTE_VIEWS_MK1);

        // ----------------------------------------------------------------
        // Drum Sequencer

        if (this.host.supports (Capability.HAS_DRUM_DEVICE))
            this.activateTurnOffEmptyDrumPadsSetting (globalSettings);

        // ----------------------------------------------------------------
        // Workflow

        this.activateExcludeDeactivatedItemsSetting (globalSettings);
        this.activateNewClipLengthSetting (globalSettings);
        this.activateKnobSpeedSetting (globalSettings);
        this.activateColorTrackStates (globalSettings);

        // ----------------------------------------------------------------
        // Mixer views

        final IEnumSetting muteColorSetting = globalSettings.getEnumSetting ("Mute color", CATEGORY_MIXER, MIXER_COLOR_OPTIONS, MIXER_COLOR_OPTIONS.get (0));
        muteColorSetting.addValueObserver (value -> {
            this.muteColorIndex = lookupIndex (MIXER_COLOR_OPTIONS, value);
            this.notifyObservers (MIXER_LAYOUT);
        });

        final IEnumSetting soloColorSetting = globalSettings.getEnumSetting ("Solo color", CATEGORY_MIXER, MIXER_COLOR_OPTIONS, MIXER_COLOR_OPTIONS.get (1));
        soloColorSetting.addValueObserver (value -> {
            this.soloColorIndex = lookupIndex (MIXER_COLOR_OPTIONS, value);
            this.notifyObservers (MIXER_LAYOUT);
        });

        final IEnumSetting showRecArmSetting = globalSettings.getEnumSetting ("Show record arm row", CATEGORY_MIXER, ON_OFF_OPTIONS, ON_OFF_OPTIONS[1]);
        showRecArmSetting.addValueObserver (value -> {
            this.showRecArm = ON_OFF_OPTIONS[1].equals (value);
            this.notifyObservers (MIXER_LAYOUT);
        });

        final IEnumSetting trackButtonsSetting = globalSettings.getEnumSetting ("Track state rows", CATEGORY_MIXER, TRACK_BUTTON_OPTIONS, TRACK_BUTTON_OPTIONS.get (0));
        trackButtonsSetting.addValueObserver (value -> {
            this.trackButtons = TrackButtons.values ()[lookupIndex (TRACK_BUTTON_OPTIONS, value)];
            this.notifyObservers (MIXER_LAYOUT);
        });

        final IEnumSetting mix64ButtonSetting = globalSettings.getEnumSetting ("Mix 64: state row", CATEGORY_MIXER, MIX64_BUTTON_OPTIONS, MIX64_BUTTON_OPTIONS.get (0));
        mix64ButtonSetting.addValueObserver (value -> {
            this.mix64ShowsSolo = lookupIndex (MIX64_BUTTON_OPTIONS, value) == 1;
            this.notifyObservers (MIXER_LAYOUT);
        });

        final IEnumSetting sendPressSetting = globalSettings.getEnumSetting ("Send 16/32: encoder press", CATEGORY_MIXER, SEND_PRESS_OPTIONS, SEND_PRESS_OPTIONS.get (0));
        sendPressSetting.addValueObserver (value -> this.sendPressMutes = lookupIndex (SEND_PRESS_OPTIONS, value) == 0);

        final IEnumSetting pluginWindowSetting = globalSettings.getEnumSetting ("Plugin Mixer: open plugin window", CATEGORY_MIXER, PLUGIN_WINDOW_OPTIONS, PLUGIN_WINDOW_OPTIONS.get (1));
        pluginWindowSetting.addValueObserver (value -> this.pluginWindowBehaviour = PluginWindowBehaviour.values ()[lookupIndex (PLUGIN_WINDOW_OPTIONS, value)]);

        final IEnumSetting pluginShiftSetting = globalSettings.getEnumSetting ("Plugin Mixer: Shift + pad", CATEGORY_MIXER, PLUGIN_SHIFT_OPTIONS, PLUGIN_SHIFT_OPTIONS.get (0));
        pluginShiftSetting.addValueObserver (value -> this.pluginShiftAction = PluginShiftAction.values ()[lookupIndex (PLUGIN_SHIFT_OPTIONS, value)]);

        final IEnumSetting shiftGestureSetting = globalSettings.getEnumSetting ("Plugin Mixer: Shift gesture", CATEGORY_MIXER, SHIFT_GESTURE_OPTIONS, SHIFT_GESTURE_OPTIONS.get (0));
        shiftGestureSetting.addValueObserver (value -> this.shiftMoveSwap = lookupIndex (SHIFT_GESTURE_OPTIONS, value) == 0);

        // ----------------------------------------------------------------
        // Views which are selected with the MIXER button

        for (final Map.Entry<Views, String> entry: this.mixerViewLabels.entrySet ())
        {
            final Views view = entry.getKey ();
            final IBooleanSetting viewSetting = globalSettings.getBooleanSetting (entry.getValue (), CATEGORY_MIXER_BUTTON, true);
            viewSetting.addValueObserver (isActive -> this.setMixerViewActive (view, isActive.booleanValue ()));
        }

        // ----------------------------------------------------------------
        // Order of the views which are selected with the MIXER button

        final List<String> viewOptions = new ArrayList<> (this.mixerViewLabels.values ());
        final List<Views> defaultOrder = new ArrayList<> (this.mixerViewLabels.keySet ());
        for (int i = 0; i < defaultOrder.size (); i++)
        {
            final int slot = i;
            final IEnumSetting slotSetting = globalSettings.getEnumSetting (SLOT_LABELS[i], CATEGORY_MIXER_ORDER, viewOptions, viewOptions.get (i));
            slotSetting.addValueObserver (value -> {
                final int index = viewOptions.indexOf (value);
                if (index >= 0)
                    this.mixerViewSlots.set (slot, defaultOrder.get (index));
            });
        }

        // ----------------------------------------------------------------
        // Colors of clips and plugins

        final IEnumSetting clipColorSetting = globalSettings.getEnumSetting ("Clip color", CATEGORY_COLORS, CLIP_COLOR_OPTIONS, OPTION_DAW_COLOR);
        clipColorSetting.addValueObserver (value -> this.clipColor = OPTION_DAW_COLOR.equals (value) ? -1 : lookupStateColor (value));

        final IEnumSetting clipPlayingColorSetting = globalSettings.getEnumSetting ("Playing clip color", CATEGORY_COLORS, STATE_COLOR_OPTIONS, "Green");
        clipPlayingColorSetting.addValueObserver (value -> this.clipPlayingColor = lookupStateColor (value));

        final IEnumSetting clipRecordingColorSetting = globalSettings.getEnumSetting ("Recording clip color", CATEGORY_COLORS, STATE_COLOR_OPTIONS, "Red");
        clipRecordingColorSetting.addValueObserver (value -> this.clipRecordingColor = lookupStateColor (value));

        final IEnumSetting pluginColorSetting = globalSettings.getEnumSetting ("Plugin color", CATEGORY_COLORS, PLUGIN_COLOR_OPTIONS, OPTION_TRACK_COLOR);
        pluginColorSetting.addValueObserver (value -> this.pluginColor = OPTION_TRACK_COLOR.equals (value) ? -1 : lookupStateColor (value));

        final IEnumSetting pluginBypassColorSetting = globalSettings.getEnumSetting ("Bypassed plugin color", CATEGORY_COLORS, STATE_COLOR_OPTIONS, "Gray");
        pluginBypassColorSetting.addValueObserver (value -> this.pluginBypassColor = lookupStateColor (value));

        final IEnumSetting pluginOfflineColorSetting = globalSettings.getEnumSetting ("Offline plugin color", CATEGORY_COLORS, STATE_COLOR_OPTIONS, "Red (dim)");
        pluginOfflineColorSetting.addValueObserver (value -> this.pluginOfflineColor = lookupStateColor (value));

        final IEnumSetting pluginWindowColorSetting = globalSettings.getEnumSetting ("Plugin with open window color", CATEGORY_COLORS, STATE_COLOR_OPTIONS, "White");
        pluginWindowColorSetting.addValueObserver (value -> this.pluginWindowColor = lookupStateColor (value));
    }


    private void setMixerViewActive (final Views view, final boolean isActive)
    {
        if (!isActive)
        {
            this.activeMixerViews.remove (view);
            return;
        }
        if (!this.activeMixerViews.contains (view))
            this.activeMixerViews.add (view);
    }


    private static int lookupStateColor (final String value)
    {
        final int index = STATE_COLOR_OPTIONS.indexOf (value);
        return STATE_COLORS.get (Math.max (0, index)).intValue ();
    }


    /**
     * Get the views which are selected one after the other by the MIXER button. Contains the track
     * mixer if all views have been deactivated, so that the button always works.
     *
     * @return The activated views in the configured order
     */
    public List<Views> getMixerViews ()
    {
        final List<Views> views = new ArrayList<> ();
        for (final Views view: this.getAllMixerViews ())
        {
            if (this.activeMixerViews.contains (view))
                views.add (view);
        }
        return views.isEmpty () ? List.of (Views.MIX) : views;
    }


    /**
     * Get all views which can be selected by the MIXER button (independent of which are
     * activated) in the configured order. The order is defined by the views selected for each
     * position. If a view is selected for several positions only the first one counts, views which
     * are not selected at all are appended in the default order.
     *
     * @return The views in the configured order
     */
    public List<Views> getAllMixerViews ()
    {
        final List<Views> views = new ArrayList<> ();
        for (final Views view: this.mixerViewSlots)
        {
            if (!views.contains (view))
                views.add (view);
        }
        for (final Views view: this.mixerViewLabels.keySet ())
        {
            if (!views.contains (view))
                views.add (view);
        }
        return views;
    }


    /**
     * Get the pad brightness.
     *
     * @return The pad brightness in the range of [0..1]
     */
    public double getPadBrightness ()
    {
        return this.padBrightness;
    }


    /**
     * Get the color for the mute pads.
     *
     * @param isActive True to get the color for an active (muted) state
     * @return The color index
     */
    public int getMuteColor (final boolean isActive)
    {
        return isActive ? MIXER_COLORS_ACTIVE[this.muteColorIndex] : MIXER_COLORS_INACTIVE[this.muteColorIndex];
    }


    /**
     * Get the color for the solo pads.
     *
     * @param isActive True to get the color for an active (soloed) state
     * @return The color index
     */
    public int getSoloColor (final boolean isActive)
    {
        return isActive ? MIXER_COLORS_ACTIVE[this.soloColorIndex] : MIXER_COLORS_INACTIVE[this.soloColorIndex];
    }


    /**
     * Should the record arm row be displayed in the mixer views?
     *
     * @return True if shown
     */
    public boolean isShowRecArm ()
    {
        return this.showRecArm;
    }


    /**
     * Which mute/solo rows should be shown in the mixer views?
     *
     * @return The setting
     */
    public TrackButtons getTrackButtons ()
    {
        return this.trackButtons;
    }


    /**
     * Should the Mix 64 view show solo instead of mute?
     *
     * @return True for solo, false for mute
     */
    public boolean isMix64ShowsSolo ()
    {
        return this.mix64ShowsSolo;
    }


    /**
     * When should the plugin window be opened in the plugin mixer?
     *
     * @return The behaviour
     */
    public PluginWindowBehaviour getPluginWindowBehaviour ()
    {
        return this.pluginWindowBehaviour;
    }


    /**
     * What should happen when a plugin pad is pressed together with Shift?
     *
     * @return The action
     */
    public PluginShiftAction getPluginShiftAction ()
    {
        return this.pluginShiftAction;
    }


    /**
     * Is Shift + plugin used for move/swap (Shift action on release) or is the Shift action
     * executed immediately (classic behaviour)?
     *
     * @return True for move/swap
     */
    public boolean isShiftMoveSwap ()
    {
        return this.shiftMoveSwap;
    }


    /**
     * Get the color for clips with content.
     *
     * @return The color index or -1 if the clip color of the DAW should be used
     */
    public int getClipColor ()
    {
        return this.clipColor;
    }


    /**
     * Get the color for playing clips.
     *
     * @return The color index
     */
    public int getClipPlayingColor ()
    {
        return this.clipPlayingColor;
    }


    /**
     * Get the color for recording clips.
     *
     * @return The color index
     */
    public int getClipRecordingColor ()
    {
        return this.clipRecordingColor;
    }


    /**
     * Get the color for active plugins.
     *
     * @return The color index or -1 if the track color should be used
     */
    public int getPluginColor ()
    {
        return this.pluginColor;
    }


    /**
     * Get the color for bypassed plugins.
     *
     * @return The color index
     */
    public int getPluginBypassColor ()
    {
        return this.pluginBypassColor;
    }


    /**
     * Get the color for offline plugins.
     *
     * @return The color index
     */
    public int getPluginOfflineColor ()
    {
        return this.pluginOfflineColor;
    }


    /**
     * Get the color for plugins with an open window.
     *
     * @return The color index
     */
    public int getPluginWindowColor ()
    {
        return this.pluginWindowColor;
    }


    /**
     * What does a press on an encoder do in the send views?
     *
     * @return True if a press toggles the send on/off (and a double press switches pre/post),
     *         false for the opposite
     */
    public boolean isSendPressMutes ()
    {
        return this.sendPressMutes;
    }
}
