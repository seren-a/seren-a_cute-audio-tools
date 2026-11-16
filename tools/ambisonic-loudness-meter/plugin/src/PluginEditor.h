// PluginEditor.h -- GUI: BS.1770-Meter (Integrated/ST/M/LRA/TP/W-only) +
// Richtungs-Loudness-Karte der virtuellen Lautsprecher.

#pragma once

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
    juce::Label orderLabel, integratedLbl, stLbl, mLbl, lraLbl, tpLbl, wOnlyLbl;
    juce::Label integratedVal, stVal, mVal, lraVal, tpVal, wOnlyVal;
    DirectionMeter dirMeter;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(AmbisonicLoudnessMeterEditor)
};
