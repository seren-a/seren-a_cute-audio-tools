# cute-audio-tools

> it's more fun when it looks girly

Sammlung kleiner Audio-Tools, Skripte und Snippets rund um MIDI, OSC und
Sound-Engineering. Jedes Tool liegt in einem eigenen Ordner mit eigener
README – hier gibt es nur die Übersicht.

## Tools

| Tool | Was es tut |
| --- | --- |
| [midi-osc-matrix-monitor](tools/midi-osc-matrix-monitor/) | Echtzeit-Monitor für MIDI- und OSC-Datenströme: fallender Glyphenregen in vier Modi (Raster, Geräte-Spalten, Mindmap, Fraktal), mit OSC-Bridge (Node.js) und Bau-Skript für eine eigenständige macOS-App. |
| [osc-remotes](tools/osc-remotes/) | OSC-Fernbedienungen für Anwendungen und Geräte (REAPER, TotalMix FX, DM7, OBS, Max/RNBO) – Konzept steht, erstes Remote in Arbeit. Dazu: [seren.a 3D](tools/osc-remotes/seren-a-3d/) (TouchOSC, Reaper/Nuendo-Skripte, E16, Twister, OXI). |
| [synth-surfaces](tools/synth-surfaces/) | Control-Surfaces für Synthesizer per MIDI/OSC, mit Learn-Modus, Mutate & Morph – Konzept steht. |
| [daw_key_commander](tools/daw_key_commander/) | Tasten-Commander: DAW-Befehle auf Pads/OSC legen, mit Macros und Feedback – Konzept steht. |
| [daw-helper](tools/daw-helper/) | Helfer rund um DAWs und Plugins – aktuell der **dearvr-konverter**: dearVR-Presets (PRO v1 ↔ PRO 2, .ini/.vstpreset/.aupreset/.fxp, Excel) in einer Browser-Werkstatt ansehen, bearbeiten und umwandeln. |
| [ambisonic-loudness-meter](tools/ambisonic-loudness-meter/) | Loudness- & Soundscape-Analyse für Ambisonics (B-Format/HOA): alle Parameter der Indoor-Soundscape-Studie (Torresin 2020: L_Aeq, N10/N90, L_A10−L_A90, FS, Roughness, L_C−L_A, Sharpness) plus BS.1770-5/EBU-R128-Loudness (LUFS, LRA, True Peak) – Python-Modul, Tests und Jupyter-Demo; AU/VST3-Plugin in Planung. |
## Struktur

```
cute-audio-tools/
├── tools/      # eigenständige Mini-Tools (je ein Ordner mit eigener README)
├── scripts/    # kleine Einzelskripte ohne eigenen Ordner
└── LICENSE
```

Neue Skripte kommen direkt in `scripts/`, größere Things bekommen einen
eigenen Ordner unter `tools/` mit einer kurzen README (Zweck, Aufruf,
Abhängigkeiten). Dieser Index hier wird entsprechend ergänzt.

## Lizenz

Siehe [LICENSE](LICENSE).
