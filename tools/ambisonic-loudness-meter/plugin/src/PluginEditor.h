// PluginEditor.h -- GUI: BS.1770-Meter + Soundscape-Panel (jede Metrik eigene
// Anzeige, siehe Torresin et al. 2020) + Richtungs-Loudness-Karte.

#pragma once

#include <array>
#include <juce_audio_processors/juce_audio_processors.h>

#include "PluginProcessor.h"

class DirectionMeter : public juce::Component {
public:
    void setSnapshot(const MeterSnapshot& s) {
        snap = s;
        repaint();
    }
    void paint(juce::Graphics& g) override;

private:
    MeterSnapshot snap;
};

class AmbisonicLoudnessMeterEditor
    : public juce::AudioProcessorEditor,
      private juce::Timer,
      private juce::AudioProcessorParameter::Listener {
public:
    explicit AmbisonicLoudnessMeterEditor(AmbisonicLoudnessMeterProcessor& p);
    ~AmbisonicLoudnessMeterEditor() override;

    void paint(juce::Graphics& g) override;
    void resized() override;
    void timerCallback() override;
    void parameterValueChanged(int parameterIndex, float newValue) override;
    void parameterGestureChanged(int parameterIndex, bool gestureIsStarting) override;

private:
    void updateLabels();

    AmbisonicLoudnessMeterProcessor& proc;
    juce::ComboBox orderBox;
    juce::Slider splSlider;
    juce::Label orderLabel, splLabel;

    // 16 Anzeige-Zellen: 6x BS.1770 + 10x Soundscape (Torresin-Tabelle)
    static constexpr int kNumCells = 16;
    std::array<juce::Label, kNumCells> cellName;
    std::array<juce::Label, kNumCells> cellVal;
    DirectionMeter dirMeter;
    juce::TooltipWindow tipWindow { this, 700 };  // Mouseover-Erklaerungen

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(AmbisonicLoudnessMeterEditor)
};
