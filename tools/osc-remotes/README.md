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
  [midi-osc-matrix-monitor](../midi-osc-matrix-monitor/) ist jetzt als eigenständiges,
  bidirektionales Modul extrahiert: [`bridge/bridge.js`](bridge/bridge.js) –
  HTTP für Remote-Seiten + WebSocket (eigener Handshake) + OSC über UDP in beide
  Richtungen, ohne npm-Abhängigkeiten (Node.js ≥ 16). Pro Ziel-Gerät nur ein Port/Mapping.
- **Learn-Modus:** erst lauschen (wie im Matrix Monitor), dann gefundene
  Adressen per Klick auf ein Bedienelement binden – Mapping als JSON
  speichern, kein Handgeschriebel.
- **Layout = JSON:** pro Remote eine Datei (Seiten, Elemente, Adressen,
  Argument-Typen, Skalen). Gleiche Engine rendert alle Remotes.
- **Themes:** cutiepro-Palette, hell/dunkel/Auto wie im Matrix Monitor.
- **Offline-Demo:** jede Remote-Seite läuft ohne Bridge mit einer Demo-Queue.

## Bridge benutzen

```bash
# HTTP 9090 · OSC rein UDP 9001 · OSC raus 127.0.0.1:8000 (z. B. REAPER)
node bridge/bridge.js 9090 9001 127.0.0.1 8000

# umgekehrt: OSC-Feedback einer App ansehen (Learn-Modus)
# REAPER/TotalMix schicken auf UDP 9001, die Seite hört mit
node bridge/bridge.js 9090 9001
```

Als Modul: `const { createBridge, oscEncode } = require("./bridge/bridge.js")`.
Browser-Seiten senden entweder rohe OSC-Pakete (Binary-Frame) oder komfortables
JSON `{"address":"/track/1/volume","args":[0.75]}` (Text-Frame, Bridge encodiert).
Test: `node bridge/bridge-test.js` (prüft alle drei Richtungen).

## Roadmap

1. ~~Bridge als eigenständiges, wiederverwendbares Modul extrahieren~~ ✓
2. `reaper-remote` als erste vollwertige Remote (Transport + Mixer + Paging)
3. Learn-Modus und Layout-JSON-Editor
4. Weitere Ziele (TotalMix FX, DM7, OBS, Max/RNBO)

Teil der [cute-audio-tools](../../README.md)-Sammlung.
