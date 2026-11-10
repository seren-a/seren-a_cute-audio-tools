# Zwischenstand (geparkt am 07.11.26, Version kommt beim Fertigstellen): Puzzle + Insert-Seite + Launchpad Pro Mk3

Nicht fertig und nicht getestet. Das laufende Puzzle (v8.2/v8.3) in `3_Reaper/OXI/` ist unverändert.

## Schon im Code (`core.lua`, mit `python3 build.py` → `Reaper_OXI_Puzzle.lua`)

- **Seiten:** Option `pages` (Puzzle / Puzzle+Insert). ARRANGER (OXI) bzw. Session (Launchpad) schaltet um. Menü Seite 2, Zeile 8.
- **Insert-Seite:** Zeile = Spur, Spalten = FX-Slots. Farbe pro Plugin-Name (gleiches Plugin = gleiche Farbe) oder Spurfarbe (`fxColor`). Bypass = fast aus, offline = rot.
  - Push wählt und öffnet das Fenster (das vorher geöffnete geht zu, Option `fxOpen`). Ein Push auf das gewählte FX schaltet das Fenster auf/zu.
  - Shift + Push = Bypass, 2× = offline.
  - Encoder = 4 Parameter. TRACK und Push 3/4 blättern die Parameterbank. Push 1 = Bypass (2× offline), Push 2 = Fenster.
  - Left/Right = FX-Slots blättern.
- **Geräte-Häkchen:** `useOxi` und `useLp`. Ohne Häkchen gibt das Skript das Gerät frei (OXI: Remote aus + Übergabe, Launchpad: Live-Modus), dann kann Moss es nehmen.
- **Launchpad Pro Mk3** (Programmer-Modus, RGB-SysEx):
  - `lpOrient` quer/laengs, `lpPort`.
  - Spurtasten rechts (quer) bzw. untere Reihe 101–108 (längs).
  - Pfeile, Session = Seite, Note = Receives-Seite, Projects = Menü, Play/Rec, Fixed Length = Stop, Clear = Undo.
  - **Shift-Funktion** `lpShift`: shift (wie OXI, Standard) / page / menu / action (`lpShiftAct` = Aktions-ID oder eingebaute Funktion).

## Noch offen

1. Tests (`test_puzzle.py`): ARRANGER-Test anpassen (wechselt jetzt zu INSERTS), neue Tests für Insert und Launchpad schreiben. `fake_reaper.lua` hat schon FX-Funktionen und ein Launchpad als 4. MIDI-Gerät.
2. Einstellungsfenster: Häkchen OXI/Launchpad, Launchpad-Port, Ausrichtung, Shift-Funktion + Aktion, Insert-Seite, FX-Farbe, Fenster öffnen.
3. Anleitung LIESMICH_OXI.md, ÄNDERUNGEN, Version.
