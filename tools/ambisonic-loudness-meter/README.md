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

## Roadmap: AU/VST3-Plugin

Der Python-Kern ist bewusst plugin-tauglich strukturiert (Block-basierte
Filter, keine Abhängigkeit von Dateien). Geplanter Weg:

1. **JUCE**-Projekt (C++), Portierung von K-Filter, A-/C-Bewertung und
   Zwicker-Loudness aus dem Python-Referenzcode (Validierung gegen die
   pytest-Referenzwerte).
2. Prozessor für bis zu 16 Kanäle ((order+1)²), Parameter: Ordnung,
   Layout, Kalibrierung.
3. GUI: BS.1770-Meter (Integrated/ST/M/LRA/TP) + Torrescape-Panel
   (N10, L_A10−L_A90, S, FS, R, L_C−L_A) + Richtungs-Karte.
4. Build: VST3 + AU (macOS) aus einer Codebasis (JUCE), CI-Build-Skript
   unter `scripts/`.

## Quellen

- Torresin, S. et al. (2020): *Indoor soundscape assessment: A principal
  components model of acoustic perception in residential buildings*,
  Building and Environment 182, 107152.
- ITU-R BS.1770-5 (11/2023): *Algorithms to measure audio programme
  loudness and true-peak audio level*.
- EBU R 128 / Tech 3341 / Tech 3342.
- ISO 532-1:2017 (Zwicker-Lautheit), DIN 45692 (Sharpness).
- MCP/ECMA-418 für Roughness/Fluctuation (mosqito-Referenz).
