# Plugin (AU/VST3, JUCE)

Echtzeit-Variante des Python-Kerns: BS.1770-5/EBU-R128-Meter
(Integrated, max. Short-Term, max. Momentary, LRA, True Peak, W-only)
plus Richtungs-Loudness-Karte der virtuellen Lautsprecher
(Energy-Decoding max-rE) — und die Soundscape-Psychoakustik auf der
Omni-Komponente W: L_Aeq, L_C−L_A, L_A10−L_A90, N10/N50/N90 (Zwicker,
ISO 532-1), Sharpness (DIN 45692), Roughness (Daniel-Weber), Fluctuation
Strength. Die Psychoakustik rechnet auf einem Hintergrund-Thread.

Der DSP-Kern (`src/dsp/`) ist JUCE-unabhängig (nur C++17):
`AmbisonicDsp.h` (BS.1770/HOA) + `Psychoacoustics.h` (mosqito-Portierung)
+ `PsychoTables.h` (generierte Tabellen).

- **Kanäle:** 1–16 diskrete Kanäle = B-Format/HOA (ACN/SN3D), Ordnung wählbar (1–3)
- **Parameter:** HOA Order (1/2/3), SPL Calibration (dBFS→dB SPL, Default 94)
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

`src/dsp/PsyTests.cpp` vergleicht die portierte Psychoakustik gegen
mosqito-Referenzwerte (30 Checks; N10/N50/N90, Sharpness und FS matchen
mosqito auf alle Nachkommastellen, Roughness innerhalb ~8 %):

```bash
python3 tests/gen_psy_ref.py /tmp/psyref      # braucht mosqito
cmake --build build --target psy_tests
./build/psy_tests /tmp/psyref/psy_signals.bin /tmp/psyref/psy_ref.txt
```

`src/dsp/DspTests.cpp` und `PsyTests.cpp` bauen auch ohne JUCE (nur C++17).
Cross-Check BS.1770 C++ vs. Python-Referenzmodul: Abweichungen < 0.01 LU.
