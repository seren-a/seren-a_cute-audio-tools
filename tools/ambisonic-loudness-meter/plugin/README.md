# Plugin (AU/VST3, JUCE)

Echtzeit-Variante des Python-Kerns: BS.1770-5/EBU-R128-Meter
(Integrated, max. Short-Term, max. Momentary, LRA, True Peak, W-only)
plus Richtungs-Loudness-Karte der virtuellen Lautsprecher
(Energy-Decoding max-rE auf den virtuellen Layout-Lautsprechern).

Der DSP-Kern (`src/dsp/AmbisonicDsp.h`) ist JUCE-unabhängig (nur C++17)
und wird ohne JUCE gegen dieselben Normreferenzen getestet wie der
Python-Kern (`src/dsp/DspTests.cpp`).

- **Kanäle:** 1–16 diskrete Kanäle = B-Format/HOA (ACN/SN3D), Ordnung wählbar (1–3)
- **Parameter:** HOA Order (1/2/3)
- **Ausgang:** Durchgang (unverändert)

## Build

```bash
# ab Repo-Wurzel: baut DSP-Tests + Plugin (holt JUCE automatisch)
scripts/build-ambisonic-plugin.sh
```

oder manuell:

```bash
git clone --depth 1 https://github.com/juce-framework/JUCE.git JUCE   # neben plugin/ oder JUCE_DIR setzen
cmake -S tools/ambisonic-loudness-meter/plugin -B tools/ambisonic-loudness-meter/plugin/build \
      -DJUCE_DIR=$PWD/JUCE -DCMAKE_BUILD_TYPE=Release
cmake --build tools/ambisonic-loudness-meter/plugin/build --config Release
# Artefakte: *.vst3 / *.component (macOS) unter plugin/build
```

Nur DSP-Tests (ohne JUCE, z. B. in CI):

```bash
c++ -std=c++17 -O2 -Wall -I tools/ambisonic-loudness-meter/plugin/src/dsp \
    tools/ambisonic-loudness-meter/plugin/src/dsp/DspTests.cpp -o dsp_tests
./dsp_tests
```

## Validierung

`src/dsp/DspTests.cpp` prüft u. a.: 48-kHz-K-Filter-Koeffizienten exakt,
Stereo-1-kHz-Referenz (−23 dBFS ⇒ −23 LUFS), Surround-Gewicht +3.01 dB,
relatives Gating, LRA zweier Pegel, True Peak, A-Bewertung (1 kHz ≈ 0 dB,
100 Hz ≈ −19.1 dB), max-rE-Richtung, Richtungsinvarianz der Loudness.
 derselbe Kern liefert im Cross-Check mit dem Python-Referenzmodul
Abweichungen < 0.01 LU.

Hinweis: Die psychoakustischen Soundscape-Metriken (N10/N90, Sharpness,
Roughness, Fluctuation Strength) bleiben im Python-Kern (mosqito) –
siehe `../README.md`.
