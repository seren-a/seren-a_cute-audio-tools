# dearvr-konverter

> it's more fun when it looks girly

Werkzeuge für dearVR-Presets (Dear Reality / Sennheiser AMBEO): **dearVR PRO (v1, Plugin Alliance)** und **dearVR PRO 2**.

| Datei | Was es ist |
| --- | --- |
| `dearvr-preset-werkstatt.html` | **Preset-Werkstatt** – Browser-Oberfläche, eine einzige Datei, läuft offline (Doppelklick genügt) |
| `dearvr2convert.py` | Kommandozeile: Reaper-.ini / .vstpreset / .aupreset von PRO v1 → PRO 2 (nur Python-Standardbibliothek) |
| `vorlagen/` | Excel- und CSV-Vorlage zum Ausfüllen ohne Browser, danach in die Werkstatt laden |
| `src/` | Quelle der Werkstatt (`werkstatt.template.html` + eingebettete Werkspresets) und `build.py` |

## Preset-Werkstatt

**Laden:** Reaper-Preset-Listen (`.ini`), `.vstpreset`, `.aupreset`, CSV, Excel – auch ganze Ordner per Drag & Drop. PRO-v1-Presets werden dabei automatisch auf PRO 2 umgerechnet. Die 47 Werkspresets von PRO 2 sind eingebaut.

**Ansehen & bearbeiten**
- Liste links (einklappbar): per Häkchen wählen, welche Presets gezeigt werden – auch per Ziehen über mehrere Häkchen
- Pro Interface-Bereich (Position, Reverb, Reflections, Master) eine Tabelle, Presets nebeneinander, daneben der passende Ausschnitt des Plugins als Vektor-Nachbau (live, Regler ziehbar, Wände im XY-Pad)
- Werte in **Plugin-Einheiten** (°, m, dB, Hz, Raumname, Ausgabeformat) – oder als Rohwerte 0–1
- „Änderungen wirken auf“: nur dieses Preset / alle gezeigten (gleicher Wert) / alle gezeigten (relativ) – gilt für Regler und Tabelleneingaben
- Umbenennen, Duplizieren, Löschen, „Alle entfernen“, Rückgängig + Verlauf
- Parameter-Menü zum Ausblenden einzelner Zeilen, Bilder pro Abschnitt skalier- und ausblendbar, Unterschiede markieren, Themes Referenz/Dunkel/Kawaii, Schriftgröße S/M/L

**Exportieren**
- Tabelle als Excel/CSV (Plugin-Einheiten, wieder einlesbar)
- Plugin-Presets mit Zielformat **PRO 2** (`.vstpreset`, `.aupreset`) oder **PRO v1** (`.vstpreset`, `.fxp` für Reaper-VST2, `.aupreset`); ein Preset + ein Typ = einzelne Datei, sonst ZIP

**Wohin mit den Dateien**
- PRO 2: `~/Library/Audio/Presets/Dear Reality/dearVR PRO 2/` (Nuendo-MediaBay, Reaper, Logic finden sie dort)
- PRO v1 VST3: `~/Library/Audio/Presets/Plugin Alliance/dearVR pro/`
- `.fxp`: in Reaper im FX-Fenster → „+“ → *Import preset…*

Der Zustand (geladene Presets, Einstellungen) wird im Browser gespeichert (localStorage) und ist nach dem Neuladen wieder da.

## Kommandozeile

```bash
python3 dearvr2convert.py "vst-dearVR pro.ini"                 # → ~/Library/Audio/Presets/Dear Reality/dearVR PRO 2/
python3 dearvr2convert.py "vst-dearVR pro.ini" -o ./ausgabe --prefix "Cantina/"
python3 dearvr2convert.py *.vstpreset --output-mode referenz.vstpreset --dry-run
```

## Umrechnungen (Dateiwert 0–1 ↔ Plugin-Anzeige)

Bestätigt an einem Plugin-Screenshot und den Werkspresets:

| Parameter | Umrechnung |
| --- | --- |
| X / Y / Z | (Wert − 0,5) × 60 m · Y = oben, Z = vorn |
| Azimut / Elevation / Distanz | aus X/Y/Z berechnet (wie im Plugin) |
| alle Gains | (Wert − 0,8) × 120 dB, 0 = −inf |
| Wände | Wert × 30 m |
| Raumgröße | Wert × 100 |
| Azimuth Scale / Distance Scale | 0,1 + 3,9 × Wert / 0,01 + 9,99 × Wert |
| XY-Pad | Zoom 2 = 24 m Padbreite |
| v1 → PRO 2 | Polar → CoordinateSystem, Damping → LowPass (1:1, an allen 47 Werkspresets geprüft), HighPass = 0 |

**Noch Annahmen** (in der Werkstatt markiert): Hz-Kurve beim Damping (bestätigt nur 1 = 20000 Hz), Ausgabeformat-Werte außer Binaural und TOA ambiX (v1), Distanz-Rohwert, Zoomstufen ≠ 2.

## Entwickeln

Die Werkstatt wird aus `src/` gebaut: `python3 src/build.py` schreibt `dearvr-preset-werkstatt.html` neu (Werkspresets werden eingebettet).

## Geplant

- Transfer zum **IEM RoomEncoder** mit eigener Ansicht
- Export als Reaper-Preset-Liste (`.ini`)
