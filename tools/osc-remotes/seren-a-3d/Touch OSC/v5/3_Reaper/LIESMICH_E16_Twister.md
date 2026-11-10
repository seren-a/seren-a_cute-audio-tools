# seren.a 3D v8.10 · Reaper: E16 + Twister in einem Skript

`3_Reaper/Reaper_E16_Twister.lua` ersetzt drei Skripte:

| bisher | jetzt |
| --- | --- |
| `Reaper_MultiEQ.lua` (E16 Seiten 2–4, Twister Bank 4) | unverändert drin |
| `reaper_to_e16.lua` (E16 Seite 1 in Reaper) | Unterseite **Spur** |
| `e16-reverb-remote` + Szene `dawlink(e16rm)` | Unterseiten **Sends / Ziele** und Twister-Ebene **Sends** |

Die alten Skripte dürfen nicht mitlaufen. `Reaper_MultiEQ.lua` beendet sich von selbst, wenn das neue startet. `reaper_to_e16.lua` und `e16-reverb-remote` musst du selbst stoppen bzw. aus der Startliste nehmen. Die Szene **seren-a_E16** bleibt, wie sie ist. Die alte Reverb-Remote-Szene brauchst du nicht mehr.

Dazu gehören:

- `Reaper_E16_Einstellungen.lua`: Fenster mit allen Optionen und der Ziel-Zuweisung. Es braucht ReaImGui.
- `Reaper_E16_Ziele_zuweisen.lua`: macht die ausgewählten Spuren zu Zielen, gedacht für die Toolbar.

## Ziele

Ziele sind deine Hallspuren bzw. FX-Returns, bis zu 32. Das Skript sucht sie in dieser Reihenfolge:

1. Spuren, die im Fenster oder mit `Reaper_E16_Ziele_zuweisen.lua` zugewiesen wurden (im Projekt gespeichert)
2. die alte Zuweisung aus `e16-reverb-assign.lua`, falls vorhanden
3. Spuren, deren Name mit dem Präfix beginnt (Standard `RVB`; das Präfix fällt in den 4-Zeichen-Namen weg)

**Vorschläge im Fenster (v8.1):** `Reaper_E16_Einstellungen.lua` listet alle Spuren, die **Receives** haben und auf denen ein Plugin liegt, das

- in REAPERs FX-Browser in der Kategorie **Reverb**, **Delay** oder **Room** steht (aus `reaper-fxtags.ini`, auch eigene Ordner aus `reaper-fxfolders.ini` mit diesen Namen), oder
- dem Namen nach dazugehört: dearVR / dearVR PRO, Reverb, Verb, Hall, Room, Delay, Echo, Plate, Space, Convolver.

Daneben steht, welches Plugin den Ausschlag gab. Ein Haken macht die Spur zum Ziel, Haken weg nimmt sie raus. „Alle Vorschläge“ übernimmt alle auf einmal. Die Liste aktualisiert sich alle 2 s.

Alternativ (Option **Ziele = Sends der Spur**) sind die Ziele einfach die Sends der ausgewählten Spur, in ihrer Reihenfolge.

Ist eine Hallspur oder der Master ausgewählt, gehören die Sends weiter der zuletzt gewählten normalen Spur. Der Titel zeigt dann `<Vox`.

## MultiEQ A/B (seit v8.10)

MultiEQ A und B kommen nur noch von der **gewählten Spur**. Hat sie keinen MultiEQ, wird der vom Master bzw. aus dem Monitoring genommen. Vorher wurden die ersten zwei MultiEQs im ganzen Projekt genommen, auch von zwei verschiedenen Spuren. Das alte Verhalten lässt sich im Fenster unter „MultiEQ“ wieder einschalten.

## Einheitlich seit v8.5

Auf allen E16-Seiten gilt: **Encoder 15 = Spur, Encoder 16 = Master** (bei Layout 1-8/9-16: 8 = Spur, 16 = Master). Encoder 16 überall wie im MultiEQ: **drehen = nächste/vorige Spur, drücken + drehen = Master-Pegel** (Push wählt den Master, 2× Master stumm). Auf Seite 1 regelt 15 den Spur-Pegel (drücken + drehen = Spur wechseln), Push = Solo.

**Höchstens 0 dB (Standard an, im Fenster abschaltbar):** Sends und Fader (Spur, Ziele, Master) gehen per Encoder nicht über 0 dB. Was schon darüber steht, bleibt beim Hochdrehen stehen, runter geht immer. Stumme Sends, Ziele, Spur und Master **blinken** überall (vorher nur auf den Plugin-Seiten). Ringfarben gibt es auf allen Seiten.

## E16 Seite 1 (DAW Link)

**Encoder 16 halten** schaltet die Unterseiten weiter, wie in Nuendo:

**Sends+Ziele** (bzw. **Sends** und **Ziele**) → weitere Gruppen → **Spur** → **Menü**.

| Layout | Encoder |
| --- | --- |
| **1-8 Sends / 9-16 Ziele**, feste Encoder an | 1–7 Sends zu Ziel 1–7, **8 Spur**, 9–15 Fader der Ziele 1–7, **16 Master**. Ab 8 Zielen gibt es eine zweite Gruppe (Ziel 8–14 …). |
| 1-8 / 9-16, alles Sends | 1–8 Sends, 9–16 Ziele |
| **eigene Seiten**, feste Encoder an | Seite Sends: 1–14, Seite Ziele: 1–14, **15 Spur**, **16 Master** |
| eigene Seiten, alles Sends | je Seite 16 |

**Send:**

- Drehen ändert den Pegel (0,3 dB je Raste, schneller drehen springt weiter). Fehlt der Send, wird er beim ersten Drehen nach oben angelegt.
- Push nach Einstellung:
  - Pre/Post, 2× springt zum Ziel (wie im alten Reverb-Remote)
  - Mute, 2× springt zum Ziel
  - Mute, 2× Pre/Post
  - Pre/Post, 2× Mute
- Pre heißt Pre-Fader (Post-FX). Mit „Pre-FX mit“ geht die Runde Post → Pre → Pre-FX.

**Ziel:** Drehen bewegt den Fader. Der Ring zeigt die Pegelanzeige, nach dem Drehen 1,2 s lang den Fader-Wert. Push schaltet stumm, 2× wählt die Hallspur aus.

**Master:** Drehen ändert die Lautstärke, Push wählt den Master aus, 2× schaltet ihn stumm.

**Spur:**

- Drehen ändert die Lautstärke, Drücken + Drehen wählt die nächste/vorige Spur.
- Push schaltet Solo (der Ring wird gelb).
- 3× schaltet zwischen 0 dB und -inf.
- 2× schaltet den Master-Send an/aus. Das ist abschaltbar. Ist es an, kommt Solo 0,4 s später.

**Spur-Seite:** wie `reaper_to_e16.lua`. Sie zeigt die TCP-Regler der Spur, sonst StereoEncoder/SceneRotator, sonst Volume, Pan, Mute, Solo, Rec, Phase und Breite.

**Menü:** 16 Encoder = 16 Optionen. Drehen oder Push stellt um, der Titel zeigt die Option im Klartext. Bei den Farb-Optionen leuchtet der Ring in der gewählten Farbe.

| Enc | Option | | Enc | Option |
| --- | --- | --- | --- | --- |
| 1 LAYT | Layout | | 9 cMTR | Farbe Pegelanzeige |
| 2 FEST | feste Encoder Spur/Master | | 10 cFDR | Farbe Fader |
| 3 PUSH | Push-Verhalten | | 11 cMAS | Farbe Master |
| 4 PRFX | Pre-FX mitschalten | | 12 cSPU | Farbe Spur |
| 5 ZIEL | zugewiesen / Sends der Spur | | 13 3xSP | 3× Spur = 0 dB/-inf |
| 6 cSND | Farbe Send | | 14 2xSP | 2× Spur = Master-Send |
| 7 cPRE | Farbe Pre-Send | | 15 TWST | Twister-Ebene Sends |
| 8 cMUT | Farbe stumm | | 16 SPUR | Spur-Unterseite (halten = weiter) |

**Farben** (statt alles Blau wie im alten Reverb-Remote):

| Was | Farbe |
| --- | --- |
| Send | Cyan |
| Pre-Send | Weiß |
| stumm | Rot |
| Pegelanzeige | Pink |
| Fader beim Drehen | Hellblau |
| Master | Pfirsich |
| Spur | Weiß, bei Solo gelb |

Zur Auswahl stehen: Cyan, Grün, Pfirsich/Orange, Rot, Weiß, Gelb, Pink, Hellblau, Violett, Türkis. Seit v8.5 blinkt alles Stumme, wie auf den Plugin-Seiten: stumme Sends, Ziele, Master und Spur; die Spur blinkt gelb bei Solo.

## Twister: Ebene 6 „Sends“ (Bank 4)

**Encoder 8 halten** schaltet weiter durch MultiEQ → Omni → Directional → Hall → (Hall-EQ) → **Sends**. Encoder 8 leuchtet auf der Sends-Ebene **blau**.

| feste Encoder | Belegung |
| --- | --- |
| an | 1–6 Sends, 9–14 Ziele. **8 drehen** = nächste Gruppe bzw. Sends ↔ Ziele, halten = Ebene. **15/16** wie im MultiEQ (Solo/Yaw, Spur/Master/Mute). |
| aus | 1–8 Sends, 9–16 Ziele. 8 drücken + drehen = Gruppe, halten = Ebene. |

Push, Farben und Layout richten sich nach denselben Einstellungen wie beim E16. Die Twister View zeigt Namen, Werte und Farben.

## Look der Fenster

Beide Einstellungsfenster (E16/Twister und OXI) tragen jetzt die Farben der TouchOSC-Oberflächen. Oben im Fenster wählst du den Look: **IEM Neon** (Standard), **Neon**, **Kawaii Nacht** oder **Klar**. Die Abschnittstitel laufen durch die IEM-Farben Cyan, Grün, Orange, Pink und Rot. Bei den Ringfarben steht ein Farbfeld vor jeder Auswahl. Der gewählte Look gilt für beide Fenster.

## Was nicht in Reaper getestet ist

Alles ist gegen eine Reaper-Attrappe getestet, die E16-Seite auch zusammen mit der echten Szene im E16-Simulator (59 Prüfungen). Dazu kommen die bisherigen 155 MultiEQ-Prüfungen, unverändert grün. Getestet in Reaper selbst und an den Geräten ist es noch nicht.
