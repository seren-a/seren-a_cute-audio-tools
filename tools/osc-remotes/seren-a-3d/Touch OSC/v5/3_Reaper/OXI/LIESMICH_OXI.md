# seren.a OXI Puzzle (v8.12.3) – OXI One MkII in Reaper

Zwei Skripte in `3_Reaper/OXI/`:

- `Reaper_OXI_Puzzle.lua` übernimmt die OXI One MkII im Remote-Modus (Grid, 4 Encoder, Display, Tasten).
- `Reaper_OXI_Einstellungen.lua` ist das Einstellungsfenster. Es braucht ReaImGui (ReaPack > ReaTeam Extensions). Änderungen gelten sofort, das Puzzle läuft dabei weiter.

## Einrichten

1. Reaper > Einstellungen > MIDI-Geräte: die OXI als **Eingang aktivieren** und den **Ausgang aktivieren**. Gefunden wird die OXI über den Namensteil `oxi`, im Fenster unter „Gerät“ änderbar.
2. **DrivenByMoss und Puzzle können die OXI nicht gleichzeitig steuern.** Sonst reagieren beide auf die Pads und überschreiben sich das Display. Solange das Puzzle läuft, also die OXI in DrivenByMoss deaktivieren. Beim Beenden schaltet das Puzzle die OXI aus dem Remote-Modus und wieder hinein. So zeichnet Moss sofort neu, wenn du es wieder aktivierst (abschaltbar unter „Gerät“).
3. Armierte MIDI-Spuren mit Eingang „Alle MIDI-Eingänge“ würden die Pads mit aufnehmen. Deshalb dort ein bestimmtes Gerät als Eingang wählen.
4. `Reaper_OXI_Puzzle.lua` starten, am besten über eine Toolbar-Taste. Ein zweiter Start ersetzt das laufende Skript.

## Grid

| | |
| --- | --- |
| Zeilen | 8 Spuren untereinander, oben die erste, oder 7, wenn oben die Marker-Zeile an ist |
| Spalte 1 | erstes Item in **Spurfarbe**. Hat die Spur keine Items, zeigt das Feld nur die Spur. Ein Push wählt die Spur. |
| Spalten 2–16 | weitere Items der Spur in Item-Farbe (10/12/14/16 Items, einstellbar) |
| hell / mittel / schwach | ausgewähltes Item / ausgewählte Spur / andere Spuren; fast aus = Item stumm |
| Push | Spur und Item auswählen |
| 2× Push | Loop/Cycle auf das Item, Cursor an den Anfang |
| Shift + Push | Item stumm an/aus |
| Marker-Zeile, Anzeige (v8.12.3) | Alle in ihrer echten Farbe (volle Stufe, Regionen ohne Farbe dezent gelb). **Loop + Cycle**: wird im E16-Takt dunkler, wie Mute. **Loop ohne Cycle**: alle 1,6 s ein kurzes Abdunkeln. |
| Marker-Zeile | Push springt zum Marker oder zur Region, 2× setzt den Loop über die Region (bei Markern bis zum nächsten Marker) |
| Layout „10 + States“ | 10 Items, Spalte 11 frei, Spalten 12–16 = die ersten 5 Encoder-States. Ein Push wählt Spur und State. |

### Felder: Regionen oder Items (seit v8.7)

- **Regionen:** Gibt es Regionen (auf Marker-Lane 1), ist jede Spalte eine Region. Ein Feld enthält alle Items der Spur, die in der Region liegen. Liegt nichts drin, bleibt das Feld dunkel: Lücken siehst du also direkt.
  - Push wählt alle diese Items aus.
  - Shift + Push schaltet sie zusammen stumm. Spielt eins, werden alle stumm, sonst gehen alle an.
  - 2× setzt den Loop auf die Region.
- **Items:** Ohne Regionen oder mit der Einstellung „Items“ ist jedes Item ein Feld. **Gruppierte Items** zählen als ein Feld (abschaltbar).
- **Marker-Zeile:** zeigt Marker oder Regionen, nur von Lane 1. Bei „automatisch“ werden Regionen gezeigt, sobald es welche gibt. Sind die Felder Regionen, steht die Region genau über ihrer Spalte.
- Einstellen: im Fenster (Marker-Zeile zeigt, Felder im Grid, Gruppen) und im Menü Seite 2, Zeile 8 „Felder“.
- **Nur eine Marker-Lane zählt** (seit v8.7.1): Einstellung „Marker-Lane“, 1 = die oberste benutzte Lane, 2 = die nächste usw. Liegen mehrere Regionen auf denselben Bereichen, nimmt das Grid nur die der gewählten Lane.
- **Statt Lane: Nummernbereich**, z. B. `100-199`. Dann zählen nur Marker/Regionen mit diesen Nummern, egal auf welcher Lane. Leer = aus.
- Ältere REAPER-Versionen ohne Marker-Lanes: dort hilft der Nummernbereich.

Tasten: **32/Up** und **48/Down** verschieben die Ansicht um eine Spur (mit Shift um eine Seite). **16/Left** und **64/Right** verschieben die Items. **TRACK** schaltet zum nächsten Encoder-State (mit Shift zurück). **PAGE** öffnet das Menü am Gerät. **BACK** wechselt Spuren ↔ Spuren mit Receives, wenn „eigene Seite“ gewählt ist. **PLAY / STOP / REC** steuern das Transport. **UNDO** macht rückgängig, mit Shift wiederholt es.

## Encoder-States

Die States wirken immer auf die ausgewählte Spur und ihre ausgewählten Items, sonst auf das zuletzt gedrückte Item.

| State | Enc 1 | Enc 2 | Enc 3 | Enc 4 |
| --- | --- | --- | --- | --- |
| 1 Items | Gain (0,5 dB) | Fade-in (10 ms, schnell ×4) | Fade-out | Spur-Ansicht ±1 |
| 2–5 Sends 1–4 … 13–16 | Send-Pegel | Send | Send | Send |
| 6 Item (Vorschlag) | Position (10 ms, Shift = 1 Schlag) | Pitch (1 HT, Shift 0,1) | Playrate | Länge |
| 7 Spur (Vorschlag) | Volume | Pan | Breite | Spur-Ansicht ±1 |

**Pushes im State Items** (alle im Fenster frei belegbar, mit eingebauter Funktion oder einer Reaper-Aktions-ID):

| | Enc 1 | Enc 2 | Enc 3 | Enc 4 |
| --- | --- | --- | --- | --- |
| 1× | `_SWS_TAKESCHANMODE0` | `_SWS_TAKESCHANMODE3` | alle Items der Spur + `_BR_NORMALIZE_LOUDNESS_ITEMS23` | Zoom auf Item |
| 2× | FX-Kette kopieren | Sends kopieren | – | – |
| lang | FX-Kette einfügen | Sends ersetzen | FX-Kette entfernen | Sends entfernen |

Einfügen, Ersetzen und Entfernen gelten für alle ausgewählten Spuren.

**Sends:** Ein Push schaltet den Send stumm, 2× schaltet Post ↔ Pre-Fader (Post-FX). Optional geht Pre-FX mit in die Runde, oder Push und 2× werden getauscht (Menü). Lang drücken setzt den Send auf 0 dB. Im Display steht der Name des Ziels, ein `*` heißt Pre.

**Item / Spur:** Ein Push setzt den Wert zurück (Pitch 0, Rate 1, 0 dB, Pan Mitte, Breite 100 %).

Weitere Ideen für States, aus Edit-Sicht: Take-Volume/Pan/Stretch, Snap-Offset, Item-Lautheit, Spur-Phase/Mono, Automations-Lane der Spur.

## Menü am Gerät (PAGE)

Jede Grid-Zeile ist eine Option, die Spalten sind die Möglichkeiten. Das Display zeigt dieselben 8 Zeilen, die zuletzt geänderte invertiert:

1. Marker-Zeile aus/an
2. Ordner zeigen
3. Leere Spuren zeigen
4. Receives: zeigen / aus / eigene Seite
5. Spuren: alle / wie TCP / wie MCP
6. Items: 10+States / 12 / 14 / 16
7. Send-Push: Mute / Pre/Post
8. Pre-FX mit/ohne

Nur im Fenster einstellbar: Reihenfolge der States, Belegung der Pushes, angepinnte Spuren zuerst, MIDI-Name, Übergabe an Moss.

## Sends 16 / Sends 32

Die Send-Seiten sind in **DrivenByMoss** als Mixer-Ansichten **Send 16** und **Send 32**, vertikal wie Mix 32, für Reaper seit v8.3 (moss4reaper, auf Basis 26.6.5). Paket, `bauen.sh` und Anleitung liegen in `Projekte/OXI ONE MK2/Moss Erweiterung/moss4reaper_send16-32/`. Im Puzzle-Skript gibt es sie nicht mehr.

## Spurtasten (die 8 Sequencer-Tasten links)

Jede Taste wählt die Spur ihrer Grid-Zeile. Die LED leuchtet, wo eine Spur liegt.

- **Shift + Spurtaste:** Master-/Parent-Send der Spur an/aus. Das ist das Häkchen „Parent send channels“ im Routing-Fenster.
- **2× Spurtaste:** Spur stumm an/aus (seit v8.6).
- **Spurtaste halten** (0,5 s): Solo an/aus (seit v8.6).
- **3× Spurtaste:** Spur auf -inf, beim nächsten 3× wieder auf 0 dB. Das Mute vom 2. Druck wird dabei zurückgenommen.

Shift und 3× lassen sich im Menü (Seite 2) abschalten, alle vier im Fenster.

**Status auf den Spurtasten (seit v8.9):** Mute = blinkt im selben Takt wie die E16 (0,4 s an, 0,4 s aus). Solo = die zweite LED blinkt im selben Takt. Rec = alle 1,6 s zweimal kurz umgeschaltet, sonst zeigt die Taste weiter normal/Mute. Faden oder Farbe können die Spurtasten nicht: die OXI kennt dort nur an/aus, farbig und dimmbar sind nur die Pads.

**Statusspalte (Option, seit v8.8):** Spalte 16 im Grid zeigt jede Spur in ihrer Spurfarbe, grau = Mute, gelb = Solo, rot = Rec. Push = Mute, Shift + Push = Solo, 2× = Rec. Die Items haben dann 15 Spalten.

## Menü Seite 2

Im Menü (PAGE) schaltet **16/Left** oder **64/Right** zwischen den Seiten 1 und 2. Auf Seite 2 stehen:

- Shift + Spurtaste (Master-Send)
- 3× Spurtaste (0 dB / -inf)
- Grid normal / umgedreht
- Auswahl: + Ansicht / Reaper / nur OXI
- Folgen an/aus
- Wert beim Drehen: groß / unten / beides / aus
- Laufschrift an/aus

## Display (v7.2)

- **Beim Drehen** steht 1,5 s lang oben der Parametername und darunter groß der Wert, z. B. „Gain“ und „+1.0 dB“. Alternativ steht er in der untersten Zeile, oder beides. Ein Tastendruck holt sofort die normale Anzeige zurück.
- **Auswahl:** In der Grundeinstellung wählt ein Push Spur und Item auch in Reaper aus, und Mixer und Arrangement springen hin. Mit „Reaper“ wird nur ausgewählt, ohne dass die Ansicht springt. Mit „nur OXI“ merkt sich die OXI Spur und Item selbst, in Reaper ändert sich nichts. Die Encoder wirken dann auf die OXI-Auswahl. FX/Sends einfügen, ersetzen und entfernen gilt dann nur für diese eine Spur. Die SWS-Aktionen wirken weiter auf die Auswahl in Reaper.
- **Folgen:** Wählst du in Reaper eine Spur, die gerade nicht im Grid zu sehen ist, springt das Puzzle hin. Das lässt sich abschalten.
- **Start:** Das Puzzle beginnt bei der in Reaper ausgewählten Spur. Sie steht oben bzw. so weit oben, wie es am Ende der Spurliste geht.
- **Laufschrift:** Zu lange Spur- und Item-Namen laufen durch. Erst 1,5 s Pause, dann ein Zeichen alle 0,3 s, am Ende wieder Pause. Abschaltbar.

## Fenster-Look (v8.1)

Das Einstellungsfenster trägt die Farben der TouchOSC-Oberflächen. Den Look wählst du oben im Fenster: IEM Neon, Neon, Kawaii Nacht oder Klar. Er gilt auch für das E16-Fenster. Neben den Encoder-States steht ein Farbfeld in der Farbe, die der State auf dem Grid hat.

## Spur fehlt im Grid?

Im Fenster unter „Gerät“ gibt es die Taste **„Spurliste prüfen (Konsole)“**. Das Puzzle schreibt dann alle Spuren in die Reaper-Konsole: Nummer, Name, ob sie im Grid ist und wenn nicht, warum (z. B. „keine Items (leere Spuren aus)“, „hat Receives (eigene Seite, BACK)“, „in TCP ausgeblendet“).

## Hinweise

- Das Protokoll (Remote-Modus, Pad-LEDs, Tasten, 128×64-Display) stammt aus dem DrivenByMoss-Quellcode. Getestet ist alles mit einer nachgebauten OXI, an echter Hardware noch nicht. Seit v7.2 ist die oberste Pad-Reihe die erste Spur. Die v7.0/7.1 standen auf dem Kopf.
- Die Pad-Farben haben je Farbkanal nur 4 Stufen, wie bei Moss.
- Tests: `5_Werkzeug/oxi/test/test_puzzle.py` (Python + lupa), 83 Prüfungen.
