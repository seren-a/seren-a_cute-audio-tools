# seren.a 3D · v6.1

Alles Aktuelle liegt in diesem Ordner. Was sich wann geändert hat: **ÄNDERUNGEN.md**.
Das **Handbuch** (Einrichten, Oberflächen, Modi, Optionen, Fehlersuche) liegt als `HANDBUCH.html` hier im Ordner
und als Seite: https://claude.ai/artifact/HT6qbhmpyyEauoZx6uRkyp
Die Übersicht (welches Plugin in welchem Slot, Verbindungen, Plugins pro Spur, Fehlercheck MultiPanner)
steht im Dokument „seren.a 3D v3 – Vergleichstabelle“: https://claude.ai/artifact/Sit7ob74cNqEmNtDzfvwS7

## Einrichten
1. **Nuendo:** die Skripte liegen schon in `Dokumente › Steinberg › Nuendo › MIDI Remote › Driver Scripts › Local › serena`
   (Kopie hier in `2_Nuendo-Cubase`). MIDI Remote › Skripte neu laden.
   Gerät serena › TouchOSC3D: Eingang + Ausgang = TouchOSC Bridge.
   Gerät serena › MFTView (Twister, seit v6.1 vier Ports – nach dem Update entfernen und neu anlegen): Eingang „Twister“ = Midi Fighter Twister,
   Eingang „View“ = TouchOSC Bridge, Ausgang „TouchOSC“ = TouchOSC Bridge, Ausgang „Twister“ = Midi Fighter Twister.
   Seit v5.5: Insert 5 oder 6 = IEM StereoEncoder, MultiEncoder oder dearVR PRO, Insert 5–9 = IEM SceneRotator
   (jeweils das erste eingeschaltete zählt; ganzer Plan: Handbuch › Insert-Plan). dearVR PROs Positions-/Raum-Parameter müssen
   unter den ersten 16 Parametern liegen (Remote Control Editor) – die Taste LOG zeigt, was erkannt wurde.
2. **Reaper:** `3_Reaper/Reaper_3D.lua` als ReaScript laden und starten (Bridge-Ein- und -Ausgang an).
   Plugins in beliebigem FX-Slot. Twister: `3_Reaper/Reaper_Twister.lua`.
   Der Ordner heißt jetzt `v5`: die Reaper-Aktionen auf `v4/3_Reaper/…` einmal neu laden.
   **MultiEQ, Kompressoren, Hall, Spur, Sends (v5.1–v8.0):** `3_Reaper/Reaper_E16_Twister.lua` starten (ab v8.0, ersetzt Reaper_MultiEQ.lua, reaper_to_e16.lua und e16-reverb-remote; siehe `3_Reaper/LIESMICH_E16_Twister.md`). Twister Bank 4 hat vier Ebenen
   (Encoder 8 halten und loslassen: MultiEQ → OmniCompressor → DirectionalCompressor → Hall → Hall-EQ, wenn ein MultiEQ direkt vor dem FDN liegt); auf jeder Ebene 8 drücken = Omni-Bypass,
   15 = Solo, 16 = Spur wählen / Master / Mute. Drehen an einem Plugin-Wert öffnet dessen Fenster. E16: Szene `OXI E16/seren-a_E16/seren-a_E16.oxie16`
   über die OXI App auf einen freien Platz laden. **Seit v6.1 stattdessen die eine Szene** `OXI E16/seren-a_E16/seren-a_E16.oxie16`
   (Seite 1 DAW Link, 2 MultiEQ, 3 Kompressor, 4 Reverb). Vorher Twister Bank 4 umstellen:
   `3_Reaper/Twister_Bank4_MultiEQ.mfs` im Midi Fighter Utility laden und senden (Anleitung: Handbuch › Neu in v6.0).
   **Dasselbe in Nuendo (v6.0, Nuendo/Cubase 13+):** Twister Bank 4: Encoder 16 halten und loslassen = Sends/QC ↔ Plugins
   (Gerät serena › MFTView, Ports siehe 1.). E16: Szene seren-a_E16, Seiten 2–4; E16DAWLink erkennt die Seite.
3. **TouchOSC** (jedes Gerät): Bridge 1 = Mac, MIDI 1 Send + Receive = Bridge 1.
4. tosc aus `1_Oberflaechen` öffnen. Unten bzw. oben in jeder Oberfläche steht die Version (z. B. „v8.15 · 10.11.26“).
   Twister View: Taste „Look“ oben rechts wechselt zwischen Klar, Spalte, Neon, IEM Neon und Kawaii Nacht; Bank-Tasten antippen = Twister wechselt die Bank.
5. Seite MONITOR / Taste LOG: oben steht, was das Skript erkannt hat; die DAW-Skripte melden dort auch ihre Version.
6. Optionen (⚙): „nur Spuren mit Plugin“ (an = Listen zeigen pro Modus nur passende Spuren) und
   „Auslastung (Reaper)“ (CPU dezent neben der Versionsnummer; Nuendo meldet keine Auslastung).
   **Seit v8.4 filtert Reaper selbst:** „nur Spuren mit Plugin“ und die Spurtypen (Audio, FX = Spuren mit Receives,
   Gruppe/Ordner, MIDI/Instr) gehen an `Reaper_3D.lua`. Die Bänke bestehen dann nur aus passenden Spuren, die Liste zeigt die
   echten Spurnummern. Alle Oberflächen übernehmen denselben Stand, Reaper merkt ihn sich. Nuendo kann das nicht
   (die Bank wird beim Laden des Skripts festgelegt): Dort überspringt Bank vor/zurück leere Bänke von selbst.
7. **32 Spuren auf einmal (v8.13):** iPad: Taste „32“ oben – Spuren 17–32 erscheinen als Kacheln in zwei Reihen à 8 unten (statt Panorama), die Draufsicht zeigt alle 32 Punkte, Bank vor/zurück springt 32 weit. Monitor: Ansicht „4×8“ – Kreis oben, 32 Spuren in vier Reihen à 8 darunter.
8. **Gruppen (v8.14, Reaper):** Config (⚙) → „GRUPPEN zeigen“: A–D sind deine eigenen Gruppen, dahinter die Reaper-Ordner ohne dearVR/Hall. Antippen = nur diese Spuren zeigen (mehrere gehen, nichts an = alle). Zuordnen: „+A“ … „+D“ tippen, die Config geht zu, dann Spuren in der Liste antippen (nochmal = wieder raus); fertig mit ⚙ → „+A“ nochmal. Alles wird im Reaper-Projekt gespeichert.
9. **Voreinstellung (v8.15, Reaper):** iPad und Monitor merken sich in Reaper, wie du sie zuletzt eingestellt hast (Modus, 32er/Layout, Horizont, alle Config-Werte), und starten beim nächsten Öffnen genau so. Nichts zu tun – einfach einstellen.

OSC im IEM-Plugin nur für `Pan_OSC*.tosc`:
StereoEncoder 8001/9101 (TouchOSC OSC 2), SceneRotator 8002/9102 (OSC 3), MultiEncoder 8003/9103 (OSC 4),
TotalMix 7001/9001 (OSC 1).

## Ordner
- `0_Fehlersuche` – Bridge-Test.tosc, Reaper_Diagnose.lua (Anleitung: Handbuch › Fehlersuche)
- `1_Oberflaechen`
  - `Handy_Pan` – Pan_Skript / Pan_OSC, je mit und ohne TotalMix, Pan_Skript hochkant (mit/ohne TotalMix)
  - `Handy_Objekt-Uebersicht` – Objekt-Uebersicht
  - `iPad_IEM-Space` – IEM-Space (Modi space · multi · panner · room)
  - `Monitor_5zu4` – IEM-Monitor (Modi space · multi · panner · room; Ansichten 16/32v/32h/64)
  - `Handy_Twister-View` – Twister_View hoch und quer
- `2_Nuendo-Cubase` – Kopie der MIDI-Remote-Skripte (serena/TouchOSC3D, MFTView, E16DAWLink)
- `3_Reaper` – Reaper_3D.lua (3D), Reaper_Twister.lua (Twister), Reaper_E16_Twister.lua (MultiEQ, Omni-/DirectionalCompressor, Hall, Sends/Ziele auf Twister Bank 4 + E16 alle Seiten), Reaper_E16_Einstellungen.lua, Reaper_E16_Ziele_zuweisen.lua, OXI/ (OXI One Puzzle)
  und Twister_Bank4_MultiEQ.mfs (Twister-Einstellung, nur Bank 4 geändert)
- `4_Vorschau` – Bilder aller Seiten (Twister View: alle fünf Looks hoch und quer)
- `5_Werkzeug` – Quellen, Build-Skripte, Tests; PROTOKOLL.md liegt auch hier oben

## Versionen (ab v5.0, für alles in diesem Projekt)
- Schema **vX.Y.Z**
- **X** zählt hoch bei einer großen Ergänzung, oder wenn Oberflächen und DAW-Skripte nur noch gemeinsam passen (Protokoll) bzw. die Einrichtung neu gemacht werden muss.
- **Y** zählt hoch bei neuen Funktionen.
- **Z** zählt hoch bei Korrekturen; steht nur da, wenn größer 0 (v5.0, v5.0.1, v5.1 …).
- Sicherungen in `z_alt` heißen `JJMMTT-vX.Y.Z(wichtigste Neuerung)` und enthalten den Stand **dieser** Version.

Nicht in echten DAWs gelaufen; geprüft gegen API-Definitionen, Handbücher und Mocks (alle Tests grün).
