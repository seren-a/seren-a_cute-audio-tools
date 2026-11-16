// PluginProcessor.h -- JUCE-AudioProcessor des ambisonic-loudness-meter.
// DSP siehe dsp/AmbisonicDsp.h (JUCE-unabhaengig, gegen pytest-Referenzwerte
// validiert). Bis zu 16 Kanaele ((order+1)^2, HOA order 1..3).

#pragma once

#include <array>
#include <atomic>
#include <juce_audio_processors/juce_audio_processors.h>

#include "dsp/AmbisonicDsp.h"

struct MeterSnapshot {
    double integratedLufs = -HUGE_VAL;
    double maxShortTermLufs = -HUGE_VAL;
    double maxMomentaryLufs = -HUGE_VAL;
    double lra = 0.0;
    double truePeakDbtp = -HUGE_VAL;
    double wOnlyLufs = -HUGE_VAL;
    // Soundscape (Torresin et al. 2020) auf W
    double lAeq = -HUGE_VAL, lCeq = -HUGE_VAL, lA10 = -HUGE_VAL, lA90 = -HUGE_VAL;
    double n10 = 0, n50 = 0, n90 = 0;
    double sharpnessAcum = 0, roughnessAsper = 0, fluctStrengthVacil = 0;
    int order = 1;
    int nSpeakers = 0;
    std::array<double, 24> perSpeakerLufs{};
    std::array<double, 24> speakerAz{};
    std::array<double, 24> speakerEl{};
};

class PsyWorkerThread;

class AmbisonicLoudnessMeterProcessor
    : public juce::AudioProcessor,
      private juce::AudioProcessorParameter::Listener {
public:
    AmbisonicLoudnessMeterProcessor();
    ~AmbisonicLoudnessMeterProcessor() override;

    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void releaseResources() override;
    void processBlock(juce::AudioBuffer<float>&, juce::MidiBuffer&) override;

    juce::AudioProcessorEditor* createEditor() override;
    bool hasEditor() const override { return true; }

    const juce::String getName() const override { return "Ambisonic Loudness Meter"; }
    bool acceptsMidi() const override { return false; }
    bool producesMidi() const override { return false; }
    double getTailLengthSeconds() const override { return 0.0; }

    int getNumPrograms() override { return 1; }
    int getCurrentProgram() override { return 0; }
    void setCurrentProgram(int) override {}
    const juce::String getProgramName(int) override { return {}; }
    void changeProgramName(int, const juce::String&) override {}

    bool isBusesLayoutSupported(const BusesLayout& layouts) const override;
    void getStateInformation(juce::MemoryBlock& destData) override;
    void setStateInformation(const void* data, int sizeInBytes) override;

    juce::AudioProcessorParameter* getOrderParameter() const { return orderParam; }
    juce::AudioProcessorParameter* getSplOffsetParameter() const { return splOffsetParam; }
    MeterSnapshot snapshot() const;
    void computePsychoNow(bool force = false);  // fuer Worker-Thread / Tests

private:
    void parameterValueChanged(int parameterIndex, float newValue) override;
    void parameterGestureChanged(int parameterIndex, bool gestureIsStarting) override;
    void applyOrder(int order);

    juce::AudioParameterChoice* orderParam = nullptr;
    juce::AudioParameterFloat* splOffsetParam = nullptr;
    std::atomic<int> pendingOrder{-1};
    std::atomic<int> currentOrder{1};

    ald::AmbisonicMeter meter;
    mutable juce::SpinLock meterLock;
    MeterSnapshot snap;
    double sampleRate_ = 48000.0;
    int blockSize_ = 512;
    std::vector<std::vector<double>> channelData;  // Scratch fuer processBlock
    juce::Thread* psyWorker = nullptr;              // rechnet Psychoakustik im Hintergrund
    size_t lastPsyLen_ = 0;

    JUCE_DECLARE_NON_COPYABLE_WITH_LEAK_DETECTOR(AmbisonicLoudnessMeterProcessor)
};
