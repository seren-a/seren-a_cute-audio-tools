# daw_key_commander

> it's more fun when it looks girly

Tasten-Commander für DAWs: ein Keypad/Layer, das DAW-Befehle auf Tasten,
Pads und OSC legt – wie ein Stream Deck, nur im Browser und girly.

## Geplante Commander

| Commander | Ziel | Idee |
| --- | --- | --- |
| `reaper-commander` | REAPER | Seiten pro Arbeitsphase: Tracking (Rec-Arm, Takes, Loop), Editing (Splits, Fades, Zoom), Mixing (Groups, FX-Bypass, Sends), Mastering (Referenz-A/B, Loudness). Befehle über REAPER-OSC oder Custom-Action-IDs. |
| `logic-commander` | Logic Pro | Key-Command-Seiten (Logic hat kein OSC): häufigste Shortcuts als Pads, plus Smart-Indicator für aktive Werkzeuge. |
| `live-commander` | Ableton Live | Clip-Trigger-Grid, Scene-Jumps, Track-Mutes – via OSC-Gateway (LiveOSC) oder MIDI-Notes. |

## Konzept

- **Web-Keypad:** eine Seite im Browser (Handy/Tablet/Touchscreen), Pads als
  Buttons, mehrere Seiten, Umschalten per Swipe oder Bank-Taste.
- **Befehle sind Zutaten:** ein Pad kann eine Sequenz starten (z. B.
  „Markierung setzen → Loop an → Play“), mit Verzögerungen zwischen den
  Schritten – einfache Macro-Engine, JSON-basiert.
- **Vier Wege zum Ziel:** OSC (REAPER, LiveOSC), MIDI-Notes/CC (für alles mit
  MIDI-Learn), Web-MIDI raus an Hardware, Tastatur-Emulation als Fallback.
- **Feedback:** Pads leuchten, wenn der Zustand stimmt (Play, Rec, Mute) –
  Status kommt per OSC/MIDI zurück, nicht nur Feuer-und-vergessen.
- **Themes:** cutiepro-Palette, hell/dunkel/Auto; Pads tragen die Farben der
  DAW-Tracks.

## Roadmap

1. Keypad-Engine (Seiten, Pads, Macros, Feedback)
2. `reaper-commander` als erster Commander (OSC)
3. Macro-Sequenzen mit Verzögerungen
4. Logic/Live-Commander + MIDI-Pads

Teil der [cute-audio-tools](../../README.md)-Sammlung.
