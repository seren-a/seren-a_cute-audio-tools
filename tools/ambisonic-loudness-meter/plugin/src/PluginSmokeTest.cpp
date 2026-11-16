// PluginSmokeTest.cpp -- End-to-End-Test: instanziiert den AudioProcessor,
// schickt synthetisches B-Format-Audio durch processBlock und prueft den
// Snapshot. Laeuft headless (kein Editor, keine GUI).
//
// Build/Run ueber CMake-Target plugin_smoke_test (siehe CMakeLists.txt).

#include <cmath>
#include <cstdio>

#include "PluginProcessor.h"

static int failures = 0;
#define CHECK(cond)                                                     \
    do {                                                                \
        if (!(cond)) {                                                  \
            ++failures;                                                 \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
        }                                                               \
    } while (0)

int main() {
    AmbisonicLoudnessMeterProcessor proc;

    juce::AudioProcessor::BusesLayout layout;
    layout.inputBuses.add(juce::AudioChannelSet::discreteChannels(4));
    layout.outputBuses.add(juce::AudioChannelSet::discreteChannels(4));
    if (!proc.setBusesLayout(layout)) {
        std::printf("FAIL: setBusesLayout(4ch)\n");
        return 1;
    }
    // Nicht-diskrete Layouts (Quad 4.0 etc., wie normale Mehrkanal-Spuren in
    // Logic/REAPER) muessen akzeptiert werden, sonst routet der Host kein Audio.
    juce::AudioProcessor::BusesLayout quad;
    quad.inputBuses.add(juce::AudioChannelSet::quadraphonic());
    quad.outputBuses.add(juce::AudioChannelSet::quadraphonic());
    CHECK(proc.isBusesLayoutSupported(quad));
    juce::AudioProcessor::BusesLayout fiveOne;
    fiveOne.inputBuses.add(juce::AudioChannelSet::create5point1());
    fiveOne.outputBuses.add(juce::AudioChannelSet::create5point1());
    CHECK(proc.isBusesLayoutSupported(fiveOne));
    proc.prepareToPlay(48000.0, 512);

    // 20 s: W-Kanal (ACN 0) mit -23 dBFS 1 kHz, Rest 0 -> omni-Signal
    const double amp = std::pow(10.0, -23.0 / 20.0);
    juce::MidiBuffer midi;
    const int nBlocks = (int)(48000 * 20 / 512);
    for (int b = 0; b < nBlocks; ++b) {
        juce::AudioBuffer<float> buf(4, 512);
        buf.clear();
        for (int i = 0; i < 512; ++i) {
            double t = (b * 512 + i) / 48000.0;
            buf.setSample(0, i, (float)(amp * std::sin(2 * 3.14159265358979 * 1000.0 * t)));
        }
        proc.processBlock(buf, midi);
    }

    // Psychoakustik (laeuft im Plugin auf Worker-Thread; hier direkt forciert)
    proc.computePsychoNow(true);
    auto s = proc.snapshot();
    std::printf("order=%d nSpk=%d integrated=%.3f maxST=%.3f maxM=%.3f LRA=%.3f TP=%.3f wOnly=%.3f\n",
                s.order, s.nSpeakers, s.integratedLufs, s.maxShortTermLufs, s.maxMomentaryLufs,
                s.lra, s.truePeakDbtp, s.wOnlyLufs);
    std::printf("soundscape: L_Aeq=%.1f L_C-L_A=%.1f L_A10-L_A90=%.1f N10=%.2f N90=%.2f S=%.2f R=%.2f FS=%.2f\n",
                s.lAeq, s.lCeq - s.lAeq, s.lA10 - s.lA90, s.n10, s.n90,
                s.sharpnessAcum, s.roughnessAsper, s.fluctStrengthVacil);

    CHECK(s.order == 1);
    CHECK(s.nSpeakers == 11);
    CHECK(std::isfinite(s.integratedLufs) && s.integratedLufs > -40.0 && s.integratedLufs < -5.0);
    CHECK(std::isfinite(s.wOnlyLufs));
    // W-only: 2*sqrt(pi) skaliert den -23-dBFS-Peak-Sinus (RMS -26 dBFS)
    // um ca. +11 dB, K-Filter bei 1 kHz ~ +0.6 dB => ca. -15 LUFS
    CHECK(s.wOnlyLufs > -17.0 && s.wOnlyLufs < -13.0);
    CHECK(std::isfinite(s.truePeakDbtp) && s.truePeakDbtp < 0.0);
    CHECK(s.maxMomentaryLufs >= s.integratedLufs - 1.0);
    // Soundscape-Plausibilitaet: 1-kHz-artiges Omni-Signal bei 94 dB SPL cal
    CHECK(std::isfinite(s.lAeq) && s.lAeq > 60.0 && s.lAeq < 100.0);
    CHECK(std::isfinite(s.n10) && s.n10 > 0.0);
    CHECK(std::isfinite(s.sharpnessAcum) && s.sharpnessAcum > 0.0);
    CHECK(std::isfinite(s.roughnessAsper) && s.roughnessAsper >= 0.0);
    CHECK(std::isfinite(s.fluctStrengthVacil) && s.fluctStrengthVacil >= 0.0);

    // Order wechseln (Parameter auf 2 -> 9 Kanäle) und weiterlaufen lassen
    if (auto* p = dynamic_cast<juce::AudioParameterChoice*>(proc.getOrderParameter()))
        *p = 1;  // Index 1 = Order 2
    proc.prepareToPlay(48000.0, 512);  // Layout neu setzen noetig? -> processBlock nutzt pendingOrder
    juce::AudioProcessor::BusesLayout layout9;
    layout9.inputBuses.add(juce::AudioChannelSet::discreteChannels(9));
    layout9.outputBuses.add(juce::AudioChannelSet::discreteChannels(9));
    proc.setBusesLayout(layout9);
    for (int b = 0; b < 200; ++b) {
        juce::AudioBuffer<float> buf(9, 512);
        buf.clear();
        for (int i = 0; i < 512; ++i) {
            double t = (b * 512 + i) / 48000.0;
            buf.setSample(0, i, (float)(amp * std::sin(2 * 3.14159265358979 * 1000.0 * t)));
        }
        proc.processBlock(buf, midi);
    }
    auto s2 = proc.snapshot();
    std::printf("order=%d nSpk=%d integrated=%.3f\n", s2.order, s2.nSpeakers, s2.integratedLufs);
    CHECK(s2.order == 2);
    CHECK(s2.nSpeakers == 19);

    std::printf(failures == 0 ? "SMOKE OK\n" : "SMOKE FAIL (%d)\n", failures);
    return failures == 0 ? 0 : 1;
}
