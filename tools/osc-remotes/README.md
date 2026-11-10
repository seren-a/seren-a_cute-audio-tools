# osc-remotes

> it's more fun when it looks girly

OSC-Fernbedienungen: kleine Web-Remotes, die Anwendungen und Geräte im
lokalen Netz per OSC steuern – Handy/Tablet/Laptop als Surface, die App
bleibt, wo sie ist.

## Geplante Remotes

| Remote | Ziel | Idee |
| --- | --- | --- |
| `reaper-remote` | REAPER | Transport (Play/Stop/Rec, Tap-Tempo), Track-Mixer mit Fadern, Pan, Mute/Solo/Arm, Bank-Paging über alle Tracks, Marker-Jump. Steuert REAPER über `oscii-router`/REAPER-OSC. |
| `totalmix-remote` | RME TotalMix FX | Submix-Busse (Cue/Stream/VoIP) auf einer Seite, Fader + Mute pro Kanal, Presets „Szene wechseln“ per Macro. |
| `dm7-remote` | Yamaha DM7 | Kanal-Mutes und Bus-Sends für die wichtigsten Kanäle, Fader-Bänke je Show-Szene. |
| `obs-remote` | OBS Studio | Szenen wechseln, Rec/Stream, Audio-Muter – praktisch für Streaming-Mischungen. |
| `max-remote` | Max/RNBO | Freie Pad-Grid-Seite, die OSC-Adressen aus dem Patch lernt und als Buttons/Slider rendert. |

## Konzept

- **Eine Bridge, viele Remotes:** die WebSocket-OSC-Bridge aus
  [midi-osc-matrix-monitor](../midi-osc-matrix-monitor/) wird wiederverwendet
  (Browser ↔ WebSocket ↔ UDP-OSC). Pro Ziel-Gerät nur ein Port/Mapping.
- **Learn-Modus:** erst lauschen (wie im Matrix Monitor), dann gefundene
  Adressen per Klick auf ein Bedienelement binden – Mapping als JSON
  speichern, kein Handgeschriebel.
- **Layout = JSON:** pro Remote eine Datei (Seiten, Elemente, Adressen,
  Argument-Typen, Skalen). Gleiche Engine rendert alle Remotes.
- **Themes:** cutiepro-Palette, hell/dunkel/Auto wie im Matrix Monitor.
- **Offline-Demo:** jede Remote-Seite läuft ohne Bridge mit einer Demo-Queue.

## Roadmap

1. Bridge als eigenständiges, wiederverwendbares Modul extrahieren
2. `reaper-remote` als erste vollwertige Remote (Transport + Mixer + Paging)
3. Learn-Modus und Layout-JSON-Editor
4. Weitere Ziele (TotalMix FX, DM7, OBS, Max/RNBO)

Teil der [cute-audio-tools](../../README.md)-Sammlung.
