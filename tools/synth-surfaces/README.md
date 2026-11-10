# synth-surfaces

> it's more fun when it looks girly

Control-Surfaces für Synthesizer: Web-Seiten, die Synth-Parameter per
MIDI (CC/NRPN/SysEx) und OSC sichtbar und steuerbar machen – mit Layouts,
die man wirklich auf einen Blick versteht.

## Geplante Surfaces

| Surface | Ziel | Idee |
| --- | --- | --- |
| `generic-cc` | beliebige Synths | Freie Grid-/Slider-Seite auf 128 CCs, 14-bit-fähig, Learn-Modus per MIDI-Monitor (Drehregler bewegen → Parameter übernehmen). |
| `blofeld-surface` | Waldorf Blofeld | Alle Modul-Seiten (Oszillatoren, Filter, Envelopes, LFOs, Effekte) gruppiert; Programme browsen und favorisieren; Zufalls-Mutation pro Modul mit „gefällt mir / nochmal“. |
| `obxd-surface` | OB-Xd (Plugin) | Klassisches Panel als Seite: Drehregler im Panel-Layout, Patch-Morph zwischen zwei Klängen (A/B-Regler interpoliert alle Parameter). |
| `digitakt-pages` | Elektron Digitakt | Track-Selektor, Parameter-Pages wie am Gerät, plus Pattern-Browser und Performance-Pads für Live-Locks. |

## Konzept

- **MIDI-Engine im Browser:** Web-MIDI (Chrome/Edge) – gleiche Schnittstelle
  wie im [midi-osc-matrix-monitor](../midi-osc-matrix-monitor/). Optional über
  die Bridge auch von außen (rtp-MIDI/OSC-Gateways).
- **Mapping = JSON:** pro Synth eine Mapping-Datei (CC/NRPN/SysEx, Wertebereiche,
  Kurven, Seiten-Layout, Anzeigen-Formate).
- **Learn-Modus:** Regler am Synth bewegen, Parameter erscheint im Monitor,
  auf ein Bedienelement ziehen – Mapping entsteht beim Spielen.
- **Extras, die Spaß machen:** Mutate (sanftes Randomisieren pro Modul),
  Morph (zwischen zwei Patches interpolieren), Freeze-Vergleich, History
  (jede Änderung rückgängig).
- **Themes:** cutiepro-Palette, hell/dunkel/Auto; Panels im Look des Synths.

## Roadmap

1. Wiederverwendbare MIDI-Learn-Engine (Monitor + Bindung)
2. `generic-cc` als erste Surface
3. Ein echtes Gerät als Referenz (Blofeld oder OB-Xd)
4. Mutate/Morph/History

Teil der [cute-audio-tools](../../README.md)-Sammlung.
