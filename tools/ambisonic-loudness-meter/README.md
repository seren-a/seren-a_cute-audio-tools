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
├── cli.py                       # Kommandozeile: python3 cli.py MEIN_HOA.wav [--soundscape] [--json]
├── requirements.txt
├── src/
│   ├── ambisonic_loudness.py    # BS.1770-5/EBU R 128 + HOA-Decoding
│   └── soundscape_metrics.py    # Torresin-Parameter (mosqito-basiert)
├── notebooks/
│   └── ambisonic_loudness_demo.ipynb   # Demo mit synthetischen Szenen (ausgeführt)
├── tests/                       # pytest (Referenz- und Sanity-Checks, 22 Tests)
└── plugin/                      # AU/VST3-Plugin (JUCE, C++-Portierung des DSP-Kerns)
    ├── CMakeLists.txt
    ├── src/dsp/AmbisonicDsp.h   # JUCE-unabhängiger DSP-Kern (C++17)
    ├── src/dsp/DspTests.cpp     # Referenztests gegen die pytest-Werte
    ├── src/PluginProcessor.*    # bis 16 Kanäle, Parameter: HOA Order 1–3
    ├── src/PluginEditor.*       # BS.1770-Meter + Richtungs-Karte
    └── src/PluginSmokeTest.cpp  # headless End-to-End-Test
```

## Benutzung

Kommandozeile (B-Format-WAV, ACN/SN3D):

```
python3 cli.py mein_hoa_signal.wav                  # Loudness-Report
python3 cli.py mein_hoa_signal.wav --soundscape      # + Torresin-Parameter (W-Komponente)
python3 cli.py mein_hoa_signal.wav --json           # maschinenlesbar
```

Als Modul:

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

`pip install -r requirements.txt` – `numpy`, `scipy`, `matplotlib`,
`soundfile`, `mosqito` (>= 1.2, psychoakustische Metriken), `pytest` (Tests).

## Tests

```
cd tools/ambisonic-loudness-meter
python3 -m pytest tests          # 22 pytest-Checks (Python-Kern)
```

Geprüft u. a.: Stereo-1-kHz-Referenz (−23 dBFS ⇒ −23 LUFS), A-Bewertung
(−19,1 dB bei 100 Hz), Zwicker-Referenz (60 dB SPL/1 kHz ⇒ 4 sone),
relatives Gating, LRA zweier Pegelstufen, True Peak (auch mehrkanalig
entlang der Zeitachse), Richtungsvarianz der Loudness, Perzentil-Logik.

## AU/VST3-Plugin (JUCE)

Echtzeit-Meter als Plugin (`plugin/`, siehe `plugin/README.md`):
BS.1770-5 (Integrated/Short-Term/Momentary/LRA/True Peak/W-only) plus
Richtungs-Loudness-Karte nach Energy-Decoding (max-rE) — und die komplette
Soundscape-Psychoakustik (Torresin et al. 2020) auf der Omni-Komponente W:
L_Aeq, L_C−L_A, L_A10−L_A90, N10/N50/N90 (Zwicker, ISO 532-1), Sharpness
(DIN 45692), Roughness (Daniel-Weber), Fluctuation Strength. Bis zu 16
Kanäle ((order+1)²), Parameter HOA Order 1–3 und SPL-Kalibrierung
(dBFS→dB SPL, Default 94), Ausgang = Durchgang. Die Psychoakustik rechnet
auf einem Hintergrund-Thread (5-s-Fenster, ~1 s Takt).

Der DSP-Kern (`plugin/src/dsp/`) ist JUCE-unabhängig: `AmbisonicDsp.h`
(BS.1770/HOA) und `Psychoacoustics.h` (Portierung von mosqito: ISO 532-1
zeitvariabel, DIN 45692, Daniel-Weber; Tabellen in `PsychoTables.h`).
Validierung ohne JUCE: `DspTests.cpp` (31 Checks gegen die pytest-Referenzwerte)
und `PsyTests.cpp` (30 Checks gegen mosqito-Referenzwerte, Signale/Referenzen
via `plugin/tests/gen_psy_ref.py` erzeugen). `PluginSmokeTest.cpp` schickt
Audio headless durch den Prozessor. Cross-Check C++ vs. Python: < 0.01 LU;
N/S/FS matchen mosqito auf alle Nachkommastellen, R innerhalb ~8 %.

Build (holt JUCE automatisch, baut VST3 + AU auf macOS):

```
bash scripts/build-ambisonic-plugin.sh  # oder: chmod +x scripts/build-ambisonic-plugin.sh
```

## REAPER-Workflow: alles in eine zentrale CSV

Das Plugin legt alle 16 Metriken als **read-only Output-Parameter** an
(sichtbar in REAPER unter FX > Param). Damit lassen sich Projekte
automatisiert analysieren:

1. **Projekt scannen:** `scripts/reaper_collect.lua` in REAPER laden
   (Actions > ReaScript > Load). Das Script liest alle Meter-Instanzen aus,
   schreibt `analysis/fx_snapshot.csv` + `analysis/items.csv` ins
   Projektverzeichnis und hängt eine Zeile pro Instanz an die zentrale CSV
   (`AMBISONIC_ANALYSIS_CSV` oder
   `~/Library/Application Support/REAPER/ambisonic-analysis/results.csv`).
   Mit `POLL_SECONDS = 30` im Script startet es Playback automatisch und
   pollt 30 s lang (damit Integrated/LRA sich füllen).
2. **Dateien offline analysieren:**
   ```
   python3 scripts/batch_analyze.py --items-csv MeinProjekt/analysis/items.csv
   # oder: --dir /pfad/zu/wavs   /   einzelne WAVs als Argumente
   ```
   hängt pro Datei eine Zeile (`source=file`) an dieselbe zentrale CSV.

Beide Quellen landen im selben Schema — REAPER-Plug-in-Messungen
(`source=reaper-fx`) und Offline-Dateianalyse (`source=file`) in einer
Tabelle.

## Quellen

- Torresin, S. et al. (2020): *Indoor soundscape assessment: A principal
  components model of acoustic perception in residential buildings*,
  Building and Environment 182, 107152.
- ITU-R BS.1770-5 (11/2023): *Algorithms to measure audio programme
  loudness and true-peak audio level*.
- EBU R 128 / Tech 3341 / Tech 3342.
- ISO 532-1:2017 (Zwicker-Lautheit), DIN 45692 (Sharpness).
- MCP/ECMA-418 für Roughness/Fluctuation (mosqito-Referenz).
