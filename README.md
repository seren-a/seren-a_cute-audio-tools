# cute-audio-tools

> it's more fun when it looks girly

Sammlung kleiner Audio-Tools, Skripte und Snippets rund um MIDI, OSC und
Sound-Engineering. Jedes Tool liegt in einem eigenen Ordner mit eigener
README – hier gibt es nur die Übersicht.

## Tools

| Tool | Was es tut |
| --- | --- |
| [midi-osc-matrix-monitor](tools/midi-osc-matrix-monitor/) | Echtzeit-Monitor für MIDI- und OSC-Datenströme: fallender Glyphenregen in vier Modi (Raster, Geräte-Spalten, Mindmap, Fraktal), mit OSC-Bridge (Node.js) und Bau-Skript für eine eigenständige macOS-App. |
| [osc-remotes](tools/osc-remotes/) | OSC-Fernbedienungen für Anwendungen und Geräte (REAPER, TotalMix FX, DiGiCo, DM7, Max/RNBO, …) – in Arbeit. |
| [synth-surfaces](tools/synth-surfaces/) | Control-Surfaces für Synthesizer per MIDI/OSC – in Arbeit. |
| [daw_key_commander](tools/daw_key_commander/) | Tasten-Commander: DAW-Befehle auf Tasten, Pads oder OSC legen – in Arbeit. |

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
