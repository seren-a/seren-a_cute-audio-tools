# Übergabe: ambisonic-loudness-meter (Stand: November 2025)

Diese Anleitung dokumentiert den Projektstand für die Weiterarbeit in
VSCode. Sie ist so geschrieben, dass auch ein KI-Agent (Copilot, Claude
etc.) damit direkt weiterarbeiten kann.

## 1. Was ist das Ziel?

Die Soundumgebung (Ambisonics) soll mit **allen Parametern** ausgewertet
werden, die die Indoor-Soundscape-Studie ausgibt:

> Torresin, S. et al. (2020): *Indoor soundscape assessment: A principal
> components model of acoustic perception in residential buildings*,
> Building and Environment 182, 107152.

Die Studie nahm ihre Szenarien mit einem **First-Order-Ambisonics-Mikrofon**
(Sennheiser AMBEO VR Mic) auf. Gemessen wurden pro 1-Min-Excerpt:

| Gruppe | Parameter | Umsetzung |
| --- | --- | --- |
| Gesamtlautheit | L_Aeq (dB A) | IEC 61672 A-Bewertung |
| Gesamtlautheit | N10, N50, N90 (sone) | ISO 532-1 Zwicker |
| Variabilität | L_A10 − L_A90 (dB) | statistische Pegel, 125-ms-Blöcke |
| Variabilität | N10 − N90 (sone) | Lautheits-Perzentile |
| Variabilität | Fluctuation Strength FS (vacil) | Zwicker/Fastl-Näherung |
| Variabilität | Roughness R (asper) | Daniel-Weber (mosqito) |
| Spektrum | L_C − L_A (dB) | C-/A-Bewertungsdifferenz |
| Spektrum | Sharpness S (acum) | DIN 45692 (mosqito) |

Zusätzlich Broadcast-Loudness nach **ITU-R BS.1770-5 / EBU R 128**
(Integrated LUFS, Short-Term, Momentary, LRA, True Peak dBTP) inkl.
W-basierter Direktschätzung (AES-Studie zu HOA-Loudness) und
Richtungs-Loudness nach Energy-Decoding (max-rE).

Studien-Kontext (perzentilbasierte Prädiktoren): **Comfort** ↓ mit N10,
**Content** ↑ mit L_A10−L_A90, **Familiarity** ↓ mit Sharpness S.

## 2. Projektstruktur

```
tools/ambisonic-loudness-meter/
├── README.md                 # Doku des Tools (Parameter, Nutzung, Builds)
├── HANDOVER.md               # diese Datei
├── src/                      # Python-Referenzimplementierung
│   ├── ambisonic_loudness.py #   BS.1770-5/EBU R128 + HOA-Decoding (genaueste Version)
│   └── soundscape_metrics.py #   Torresin-Parameter (mosqito-basiert)
├── tests/                    # pytest, 18 Tests, alle grün
├── notebooks/
│   └── ambisonic_loudness_demo.ipynb   # ausgeführte Demo (Verkehr/Vögel/Musik)
└── plugin/                   # JUCE-Plugin (AU/VST3/Standalone)
    ├── CMakeLists.txt
    ├── bauen.sh              # Build-Skript, klont JUCE 8.0.8 bei Bedarf
    ├── src/
    │   ├── MeterDSP.h        #   DSP-Kern, JUCE-FREI (reines C++17, eigener FFT)
    │   ├── PluginProcessor.h/.cpp
    │   └── PluginEditor.h/.cpp   # cutiepro-GUI
    └── tests/test_meter_dsp.cpp   # C++-Referenztests, alle grün
```

**Wichtigste Konvention:** `plugin/src/MeterDSP.h` ist absichtlich ohne
JUCE-Abhängigkeit (nur std C++17). Dadurch ist der DSP überall testbar;
die Python-Module sind die verbindliche Referenz (mosqito = validierte
Psychoakustik), das Plugin enthält bei N/FS/R dokumentierte Näherungen.

## 3. Konventionen (aus dem Repo übernehmen)

- Ambisonics: **ACN-Kanalfolge, SN3D-Normalisierung** (AmbiX).
- GUI-Design: **cutiepro-Palette** aus
  `tools/midi-osc-matrix-monitor/index.html` (12 Themes; dunkle Themes
  mit Neon-Pastell-Akzenten: pink `#d286b7`, aqua `#42d9c5`, mint
  `#37cb8a`, peach `#f58669`, sage `#bec975`; helle Themes: rosa,
  lilac, peachh, pistazie). Runde Ecken (9 px), dunkle Panels,
  Readouts in Theme-Farbe.
- Sprache: Doku auf Deutsch, Code-Identifikatoren Englisch.
- Neues Tool = eigener Ordner unter `tools/` mit eigener README,
  Eintrag in der Haupt-README-Tabelle.

## 4. Befehle

### Python (Referenz)

```bash
# Abhängigkeiten (einmalig)
pip install numpy scipy matplotlib soundfile mosqito pytest

# Tests (18 Stück, sollen alle grün sein)
cd tools/ambisonic-loudness-meter
python3 -m pytest tests -q

# Notebook
code notebooks/ambisonic_loudness_demo.ipynb
```

### Plugin bauen (macOS: AU + VST3, Linux: nur VST3)

```bash
cd tools/ambisonic-loudness-meter/plugin
./bauen.sh
# macOS: .artcomponent nach ~/Library/Audio/Plug-Ins/Components/,
#        .vst3 nach ~/Library/Audio/Plug-Ins/VST3/
```

### C++-DSP-Kerne (ohne JUCE, überall lauffähig)

```bash
cd tools/ambisonic-loudness-meter/plugin
g++ -std=c++17 -O2 -Wall -Wextra -o build/test_meter_dsp tests/test_meter_dsp.cpp
./build/test_meter_dsp     # → "ALLE TESTS BESTANDEN (0 Fehler)"
```

## 5. Referenzwerte (Regressionstests)

Wenn etwas an der DSP-Logik geändert wird, müssen diese Werte stabil
bleiben (Python **und** C++ prüfen dieselben):

| Test | Soll | Toleranz |
| --- | --- | --- |
| Stereo 1 kHz @ −23 dBFS | Integrated = −23 LUFS | ±0.2 |
| A-Bewertung 100 Hz rel. 1 kHz | −19.1 dB | ±1.5 |
| 1 kHz @ 60 dB SPL (RMS-normiert) | N50 ≈ 4 sone | ±1.5 (Py) / ±2.5 (C++) |
| AM-Signal vs. Konstantton | L_A10−L_A90 größer | – |
| Kalibrierung | dBFS + spl_offset = dB SPL (RMS) | ±1 |

## 6. Aktueller Status / offene Punkte

Erledigt:
- [x] Recherche (BS.1770-5 Annex 3/4, AES HOA-Loudness-Studie, Torresin 2020)
- [x] Python-Module + 18 pytest-Tests (alle grün)
- [x] Jupyter-Demo, ausgeführt und committet
- [x] JUCE-Plugin: DSP-Kern C++-getestet, GUI im cutiepro-Look
- [x] Draft-PR #5 (Branch `vibe/ambisonic-loudness-meter-3d488c`)

Offen / nächste Schritte (priorisiert):
1. **Plugin auf macOS bauen** (`./bauen.sh`) und Compile-Fehler der
   JUCE-Wrapper (PluginProcessor/PluginEditor) fixen – der DSP-Kern ist
   getestet, aber der *komplette* Plugin-Build lief noch nie durch
   (Sandbox hatte kein X11/ALSA). Erste verdächtige Stellen: JUCE-8-API
   (`FontOptions`), Attachment-Typen, Bus-Layout-Meldungen.
2. Plugin in REAPER/Nuendo mit einem FOA-Clip testen (W-Kanal-Messung vs.
   „Alle Kanäle"), Kalibrierung mit Referenzpegel abgleichen.
3. Optional: Lautheits-Näherung im Plugin gegen mosqito-Werte feinjustieren
   (Faktor/Exponent in `psychoacousticTick`), solange Test 3 grün bleibt.
4. Optional: Richtungs-Loudness-Karte (Python: `per_speaker_lufs`) als
   zweite GUI-Seite; True-Peak-FIR gegen BS.1770-Referenzfilter prüfen.
5. Nach Merge: Haupt-README ist aktuell; ggf. Screenshots der GUI ergänzen.

Bekannte bewusste Näherungen (dokumentiert, kein Bug):
- Plugin-Zwicker: 20 Bark-Bänder, Hann-Fenster, Schwellenwert-Tabelle statt
  vollständiger ISO-532-1-Maske; Sharpness als gewichtetes erstes Moment;
  FS/R aus Lautheits- bzw. Hüllkurvenmodulation. Referenz = Python/mosqito.
- Energy-Decoding hat ~1.3 dB Richtungsabhängigkeit (per-Speaker-Normierung,
  Standard bei max-rE-Decodern).
