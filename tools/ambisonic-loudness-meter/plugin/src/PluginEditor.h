#pragma once

#include "PluginProcessor.h"
#include <juce_gui_basics/juce_gui_basics.h>

// cutiepro-Palette aus tools/midi-osc-matrix-monitor
struct CutieTheme
{
    const char* name;
    juce::Colour bg, readout, flash, accent, dim;
    bool light = false;
};

class MeterBar;
class StatLabel;

class AmbisonicLoudnessMeterAudioProcessorEditor : public juce::AudioProcessorEditor,
                                                   private juce::Timer,
                                                   private juce::ComboBox::Listener,
                                                   private juce::Button::Listener
{
public:
    explicit AmbisonicLoudnessMeterAudioProcessorEditor (AmbisonicLoudnessMeterAudioProcessor&);
    ~AmbisonicLoudnessMeterAudioProcessorEditor() override;

    void paint (juce::Graphics&) override;
    void resized() override;

private:
    void timerCallback() override;
    void applyTheme();

    AmbisonicLoudnessMeterAudioProcessor& processor;
    juce::ComboBox themeBox;
    juce::ToggleButton allChannelsButton { "Alle Kanaele" };
    juce::Slider calSlider;
    juce::Label calLabel;
    juce::TextButton resetButton { "Reset" };
    std::unique_ptr<juce::AudioProcessorValueTreeState::ComboBoxAttachment> themeAttachment;
    std::unique_ptr<juce::AudioProcessorValueTreeState::ButtonAttachment> allChAttachment;
    std::unique_ptr<juce::AudioProcessorValueTreeState::SliderAttachment> calAttachment;

    juce::Label lufsValue, stValue, mtValue, tpValue, lraValue;
    juce::Label n10Value, n50Value, laVarValue, sharpValue, fsValue,
                roughValue, lcaValue, laeqValue, lceqValue;
    std::vector<std::pair<juce::Rectangle<int>, juce::String>> rows;
    class MeterBar;
    std::unique_ptr<MeterBar> mtBar, stBar;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR (AmbisonicLoudnessMeterAudioProcessorEditor)
};
