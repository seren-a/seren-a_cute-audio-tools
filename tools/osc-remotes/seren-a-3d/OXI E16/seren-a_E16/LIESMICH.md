# E16 · Szene seren-a_E16 (seren.a 3D v6.1)

**Eine** Szene für alles. Sie ersetzt die beiden alten Szenen `DAW-Link` und `MultiEQ` (die Ordner bleiben als Archiv, die Szenen kannst du vom E16 löschen).

| Seite (Shift + Knopf) | Inhalt | Nuendo / Cubase | Reaper |
|---|---|---|---|
| 1 | **DAW Link** – Nuendo: Sends + QC / EQ / Inserts · Reaper (v8.0): Sends+Ziele / Spur / Menü (16 halten = nächste Unterseite) | serena/E16DAWLink | `Reaper_E16_Twister.lua` |
| 2 | **MultiEQ** (= Twister Bank 4, Ebene 1) | serena/E16DAWLink | `Reaper_E16_Twister.lua` |
| 3 | **Kompressor** – Omni, 8 halten = Directional ↔ Omni | serena/E16DAWLink | `Reaper_E16_Twister.lua` |
| 4 | **Reverb** – FDN Reverb oben, mcfx Convolver unten, 7 = FDN-Preset, 14 = Convolver-Preset | serena/E16DAWLink | `Reaper_E16_Twister.lua` |

## Laden
1. OXI App › Scenes › *Assign PC/Mac folder* zeigt deinen E16-Ordner. `seren-a_E16.oxie16` in dessen Unterordner `Scenes` legen.
2. Scenes › **Refresh Views**, die Szene von *On Computer* auf einen freien Platz unter *On Device* ziehen, am E16 aufrufen.
3. Nuendo: Gerät serena › E16DAWLink bleibt, wie es ist (Ein- und Ausgang = E16). Skript-Konsole: `[seren.a E16] Skript v6.1 geladen`.
   Reaper: E16-Ein- und -Ausgang an, nur `Touch OSC/v5/3_Reaper/Reaper_E16_Twister.lua` starten (ab v8.0; reaper_to_e16.lua und e16-reverb-remote nicht mehr). Die alte Reverb-Remote-Szene brauchst du nicht mehr.

`seren_E16.lua` ist das Skript in der Szene (zum Nachlesen). Nur das Skript in eine neue Szene zu laden reicht nicht – dann sind die
Encoder nicht verdrahtet.

## Farben
IEM-Farben, so nah, wie die E16-Palette kommt: Cyan 83 (Azimut, Zeiten), Grün 92 (Elevation, Makeup, Raumgröße),
Pfirsich 36 statt Orange (Threshold, Knee, Dry/Wet – die Palette hat kein Orange), Rot 57 (Ratio, Tiefen), Weiß 34 (Schalter, Presets),
MultiEQ-Bänder 87 / 74 / 18 / 40 / 44 / 56, vom Master 85. Solo blinkt gelb (44), gemutet ohne Solo pfirsich (36), Mute blinkt rot (57),
Band aus grauviolett (24). Threshold-Ringe laufen „von oben“: 0 dB = leer, je tiefer, desto voller.

## Gruppen lösen
Führenden Knopf halten und den Mitläufer antippen, bis er herausfällt (dritter Tipp).

Alles Weitere: Handbuch › Neu in v6.1 und › Midi Fighter Twister und OXI E16 (`Touch OSC/v5/HANDBUCH.html`).
