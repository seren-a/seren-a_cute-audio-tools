# ambisonic-loudness-meter

Loudness- und Soundscape-Analyse für Ambisonics-Projekte (B-Format/HOA,
ACN/SN3D). Misst alle Parameter, die Torresin et al. (2020) im
*Indoor-Soundscape*-Experiment ausgeben – dort wurden die Szenarien mit
einem First-Order-Ambisonics-Mikrofon (Sennheiser AMBEO VR Mic) aufgenommen
– plus Broadcast-Loudness nach ITU-R BS.1770-5 / EBU R 128.

## Parameter

**Indoor-Soundscape (Torresin et al. 2020, *Building and Environment* 182,
107152):**

| Gruppe | Parameter | Einheit | Methode |
| --- | --- | --- | --- |
| Gesamtlautheit | L_Aeq | dB(A) | IEC 61672 A-Bewertung |
| Gesamtlautheit | N10, N50, N90 | sone | ISO 532-1 (Zwicker, zeitvariabel) |
| Variabilität | L_A10 − L_A90 | dB | statistische Pegel, 125-ms-Blöcke |
| Variabilität | N10 − N90 | sone | Lautheits-Perzentile |
| Variabilität | Fluctuation Strength FS | vacil | Zwicker/Fastl (Näherung aus Lautheitsverlauf) |
| Variabilität | Roughness R | asper | Daniel-Weber (mosqito) |
| Spektrum | L_C − L_A | dB | C-/A-Bewertungsdifferenz |
| Spektrum | Sharpness S | acum | DIN 45692 (mosqito) |

Die Studie fand: **Comfort** korreliert negativ mit N10, **Content** positiv
mit L_A10−L_A90, **Familiarity** negativ mit Sharpness S.

**Broadcast-Loudness (ITU-R BS.1770-5 / EBU R 128):** Integrated LUFS,
max. Short-Term (3 s), max. Momentary (400 ms), Loudness Range (LRA),
True Peak (dBTP, 4× Oversampling) – jeweils nach Energy-Decoding (max-rE)
auf eine virtuelle Lautsprecherkonfiguration mit BS.1770-Gewichten
(G = 1.41 für Elevation > 5° und Surround 60–120°). Zusätzlich die
W-basierte Direktschätzung (0. Ordnungskoeffizient, skaliert mit 2·√π)
nach *Loudness Perception of Scene-Based Audio across Loudspeaker
Configurations and HOA Orders* (AES) und eine Richtungs-Loudness pro
virtuellem Lautsprecher.

## Struktur

```
ambisonic-loudness-meter/
├── src/
│   ├── ambisonic_loudness.py    # BS.1770-5/EBU R 128 + HOA-Decoding
│   └── soundscape_metrics.py    # Torresin-Parameter (mosqito-basiert)
├── notebooks/
│   └── ambisonic_loudness_demo.ipynb   # Demo mit synthetischen Szenen
└── tests/                       # pytest (Referenz- und Sanity-Checks)
```

## Benutzung

```python
import sys; sys.path.insert(0, "src")
from ambisonic_loudness import measure_file, print_report
from soundscape_metrics import measure_soundscape, print_soundscape_report

r = measure_file("mein_hoa_signal.wav")     # B-Format WAV
print_report(r)

# Torresin-Parameter auf dem Schalldruck (omni W):
import soundfile as sf
b, fs = sf.read("mein_hoa_signal.wav", always_2d=True)
omni = 2 * np.sqrt(np.pi) * b.T[0]
s = measure_soundscape(omni, fs, spl_offset_db=94.0)
print_soundscape_report(s)
```

`spl_offset_db` kalibriert dBFS → dB SPL (RMS-Konvention:
0 dBFS RMS + 94 = 94 dB SPL). Ohne bekannte Kalibrierung sind die
dB-SPL-Groessen relativ zu betrachten; Lautheit, Sharpness und Roughness
haengen absolut von der Skalierung ab.

## Abhängigkeiten

`numpy`, `scipy`, `matplotlib`, `soundfile`, `mosqito` (>= 1.2,
psychoakustische Metriken), `pytest` (Tests).

## Tests

```
cd tools/ambisonic-loudness-meter
python3 -m pytest tests
```

Geprüft u. a.: Stereo-1-kHz-Referenz (−23 dBFS ⇒ −23 LUFS), A-Bewertung
(−19,1 dB bei 100 Hz), Zwicker-Referenz (60 dB SPL/1 kHz ⇒ 4 sone),
Richtungsvarianz der Loudness, Perzentil-Logik.

## AU/VST3-Plugin (`plugin/`)

JUCE-Plugin (C++17) mit allen Parametern der Studie und BS.1770-5/EBU-R128.
Der DSP-Kern (`src/MeterDSP.h`) ist bewusst **JUCE-frei** (reines C++17,
eigener kompakter FFT) – dadurch überall kompilier- und testbar.

```
plugin/
├── CMakeLists.txt              # JUCE 8, Formate: AU + VST3 + Standalone
├── bauen.sh                    # macOS: AU+VST3, Linux: VST3 (klont JUCE automatisch)
├── src/
│   ├── MeterDSP.h              # DSP-Kern (norm-exakt + dokumentierte Naeherungen)
│   ├── PluginProcessor.h/.cpp # Ambisonics-Bus (FOA bis 4. Ordnung), W-/Alle-Kanal-Modus
│   └── PluginEditor.h/.cpp     # cutiepro-GUI: 12 Themes, Meter, Soundscape-Panel
└── tests/test_meter_dsp.cpp    # C++-Referenztests (gleiche Werte wie pytest)
```

**Exakt nach Norm:** K-Filter (BS.1770-48-kHz-Koeffizienten bzw. RBJ-Design
für andere Raten), Gated Integrated/Momentary/Short-Term, LRA, True Peak
(4× Interpolation), A-/C-Bewertung (IEC 61672, exakte Bilinear-Polabbildung),
L_A10/L_A90 mit Gating.
**Dokumentierte Naeherungen:** Zwicker-Lautheit (20 Bark-Bänder, Hann-Fenster,
Schwellenwerte je Band), Sharpness (gewichtetes erstes Moment),
Fluctuation Strength (Lautheitsmodulation), Roughness (Hüllkurvenmodulation).
Referenz-Implementierung bleibt das Python-Modul (mosqito).

### Bauen

```bash
cd plugin
./bauen.sh          # klont JUCE 8.0.8 bei Bedarf, baut Release
```

macOS: `build/ambisonic_loudness_meter.artcomponent` (AU) und
`.vst3` nach `~/Library/Audio/Plug-Ins/` kopieren. Linux: VST3 (AU benötigt
macOS).

### GUI

Im Look des [midi-osc-matrix-monitor](../midi-osc-matrix-monitor/):
alle 12 cutiepro-Themes (matrix, pink, aqua, mint, sage, peach, rose, mix,
rosa, lilac, peachh, pistazie), Theme-Auswahl in der Kopfzeile,
Kalibrierungs-Slider, Umschalter „Alle Kanäle“ (BS.1770 auf allen
Kanälen statt nur W), Reset-Knopf, Momentary-/Short-Term-Balken mit
Peak-Hold und ein Panel mit allen Torresin-Parametern.

## Übergabe

Für die Weiterarbeit (z. B. in VSCode oder mit einem KI-Agent):
 siehe [HANDOVER.md](HANDOVER.md) – Projektstand, Befehle, Referenzwerte,
 offene Punkte.

## Quellen

- Torresin, S. et al. (2020): *Indoor soundscape assessment: A principal
  components model of acoustic perception in residential buildings*,
  Building and Environment 182, 107152.
- ITU-R BS.1770-5 (11/2023): *Algorithms to measure audio programme
  loudness and true-peak audio level*.
- EBU R 128 / Tech 3341 / Tech 3342.
- ISO 532-1:2017 (Zwicker-Lautheit), DIN 45692 (Sharpness).
- MCP/ECMA-418 für Roughness/Fluctuation (mosqito-Referenz).
