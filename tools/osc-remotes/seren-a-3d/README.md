# seren.a – Übersicht über alle Skripte und Oberflächen

**Stand: 13.11.26, 13:30 · aktuelle Version v8.17**
Diese Datei ist der Einstieg. Ich halte sie bei jeder Änderung aktuell: Was wohin gehört, steht oben, die Update-Liste darunter. Die ausführlichen Anleitungen sind unten verlinkt.

---

> **Einzelne Werkzeuge als eigene Branches:** Puzzle, E16 und Twister (Reaper, Nuendo) in [seren-a-reaper-scripts](https://github.com/seren-a/seren-a-reaper-scripts#branches-seren-a-3d), die Moss-Erweiterung der OXI (Reaper, Bitwig) in [`oxi-mk2-moss-extended`](https://github.com/seren-a/seren-a_cute-audio-tools/tree/oxi-mk2-moss-extended). Dieser Ordner ist das Gesamtpaket.


## 1. Was gehört wohin (Stand v8.17)

### Reaper – Aktionsliste (ReaScript laden)

| Skript | liegt in | wofür | läuft |
| --- | --- | --- | --- |
| `Reaper_3D.lua` | `Touch OSC/v5/3_Reaper/` | 3D-Oberflächen: Panner, Objekt-Übersicht, iPad, Monitor | dauerhaft |
| `Reaper_Twister.lua` | `Touch OSC/v5/3_Reaper/` | Twister Bänke 1–3 und die Twister View | dauerhaft |
| `Reaper_E16_Twister.lua` | `Touch OSC/v5/3_Reaper/` | E16 (alle Seiten) und Twister Bank 4: MultiEQ, Kompressoren, Hall, Sends | dauerhaft |
| `Reaper_E16_Einstellungen.lua` | `Touch OSC/v5/3_Reaper/` | Einstellungsfenster für E16/Twister | bei Bedarf |
| `Reaper_E16_Ziele_zuweisen.lua` | `Touch OSC/v5/3_Reaper/` | Send-Ziele festlegen | bei Bedarf |
| `Reaper_OXI_Puzzle.lua` | `Touch OSC/v5/3_Reaper/OXI/` | OXI One als Item-Puzzle | wenn Moss die OXI gerade nicht hat |
| `Reaper_OXI_Einstellungen.lua` | `Touch OSC/v5/3_Reaper/OXI/` | Einstellungsfenster Puzzle | bei Bedarf |

**Aus der Aktionsliste entfernen:**
- `reaper_mft_hub.lua`, beide Einträge. Der aktuelle Twister-Hub heißt `Reaper_Twister.lua`.
- `Reaper_MultiEQ.lua`, `reaper_to_e16.lua` und `e16-reverb-remote`: ersetzt durch `Reaper_E16_Twister.lua`.
- Alles aus `seren-a_v3`, `z_alt` oder mit `_old` im Namen.

### Reaper – DrivenByMoss (OXI Mixer-Ansichten)

| was | liegt in | wohin |
| --- | --- | --- |
| moss4reaper mit Send 16/32 + Mix 32/64 + Plugin 32 | `OXI ONE MK2/Moss Erweiterung/moss4reaper_send16-32/bauen.sh` | baut und kopiert sich selbst nach `~/Library/Application Support/REAPER/UserPlugins/drivenbymoss-libs` |

### Nuendo / Cubase – MIDI Remote

| Skript | liegt in | wohin |
| --- | --- | --- |
| `serena_TouchOSC3D.js` | `Touch OSC/v5/2_Nuendo-Cubase/serena/TouchOSC3D/` | `…/MIDI Remote/Driver Scripts/Local/serena/TouchOSC3D/` |
| `serena_MFTView.js` | `Touch OSC/v5/2_Nuendo-Cubase/serena/MFTView/` | `…/Local/serena/MFTView/` |
| `serena_E16DAWLink.js` | `Touch OSC/v5/2_Nuendo-Cubase/serena/E16DAWLink/` | `…/Local/serena/E16DAWLink/` |

### TouchOSC – Oberflächen (`Touch OSC/v5/1_Oberflaechen/`)

| Datei | Gerät | Version im Layout |
| --- | --- | --- |
| `iPad_IEM-Space/IEM-Space.tosc` | iPad | v8.17 · 13.11.26 |
| `Monitor_5zu4/IEM-Monitor.tosc` | Monitor 5:4 | v8.17 · 13.11.26 |
| `Monitor_HD/IEM-Monitor_HD.tosc` | Monitor Full HD 1920 × 1080 | v8.17 · 13.11.26 |
| `Handy_Objekt-Uebersicht/Objekt-Uebersicht.tosc` | Handy quer | v8.4 · 07.11.26 |
| `Handy_Pan/…` (6 Varianten) | Handy | v6.1 |
| `Handy_Twister-View/Twister_View(_quer).tosc` | Handy | v6.1 |

### OXI E16 (OXI App)

| Datei | wohin |
| --- | --- |
| `OXI E16/seren-a_E16/seren-a_E16.oxie16` | über die OXI App auf einen Platz der E16 laden (die einzige Szene, die alten liegen in `OXI E16/z_alt`) |

### Midi Fighter Twister (Midi Fighter Utility)

| Datei | wohin |
| --- | --- |
| `Touch OSC/v5/3_Reaper/Twister_Bank4_MultiEQ.mfs` | in die Utility laden und auf den Twister schreiben (nur Bank 4 geändert) |

---

## 2. Update-Liste (neueste oben)

| Datum, Uhrzeit | Version | Was | Neu einspielen |
| --- | --- | --- | --- |
| 13.11.26, 13:30 | **v8.17** | Room „groß“ auf iPad, Monitor 5:4 und Monitor HD: Raum füllt den ganzen Bildschirm | iPad-, Monitor- und Monitor-HD-Oberfläche neu öffnen |
| 13.11.26, 13:00 | **v8.16** | Monitor in Full HD (1920 × 1080): neue Oberfläche `IEM-Monitor_HD`, alle Ansichten wie beim 5:4-Monitor | `Monitor_HD/IEM-Monitor_HD.tosc` auf den Bildschirm laden (Reaper-Skript bleibt) |
| 10.11.26, 17:20 | **v8.15** | iPad + Monitor starten mit der zuletzt eingestellten Ansicht/Config (in Reaper gespeichert) | `Reaper_3D.lua` neu starten · iPad + Monitor neu öffnen |
| 10.11.26, 14:40 | v8.14 | Gruppen in iPad/Monitor (Reaper): A–D selbst zuordnen + Reaper-Ordner, an = nur deren Spuren | `Reaper_3D.lua` neu starten · iPad + Monitor neu öffnen |
| 10.11.26, 13:30 | v8.13 | 32 Spuren: iPad Taste „32“ (17–32 als Kacheln unten), Monitor Ansicht „4×8“ | iPad- und Monitor-Oberfläche neu öffnen |
| 09.11.26, 12:15 | v8.12.3 | Marker-Zeile in echten Regionsfarben, Loop/Cycle durch Abdunkeln | `Reaper_OXI_Puzzle.lua` neu starten |
| 09.11.26, 12:10 | v8.12.2 | Marker-Zeile: Regionen dezent gelb, Cycle wird dunkler wie Mute | `Reaper_OXI_Puzzle.lua` neu starten |
| 09.11.26, 12:05 | v8.12.1 | Fix Marker-Zeile: Farben wieder da, Cycle blinkt wie Mute | `Reaper_OXI_Puzzle.lua` neu starten |
| 09.11.26, 12:00 | v8.12 | Puzzle: Loop-Marker/-Region in der Marker-Zeile hervorgehoben (Cycle an = wechselt mit Weiß); Taste „Spurliste prüfen“ | `Reaper_OXI_Puzzle.lua` neu starten |
| 09.11.26, 10:10 | v8.11 | E16/Twister: MultiEQ nur von der gewählten Spur (kein Master); Fader-Grenze 0/+6/+12/aus für Spuren, Gruppen, Receive-Spuren | `Reaper_E16_Twister.lua` neu starten + Fenster |
| 09.11.26, 09:50 | v8.10 | MultiEQ (E16/Twister) nur noch von der gewählten Spur, sonst Master | `Reaper_E16_Twister.lua` neu starten |
| 08.11.26, 22:55 | v8.9.1 | Solo-LED auf der OXI blinkt im Mute-Takt | `Reaper_OXI_Puzzle.lua` neu starten |
| 08.11.26, 22:50 | v8.9 | OXI-Spurtasten ruhiger: Mute im E16-Takt, Solo = 2. LED, Rec = 2× kurz + Pause | `Reaper_OXI_Puzzle.lua` neu starten |
| 08.11.26, 22:45 | v8.8 | OXI Puzzle: Spurtasten zeigen Mute/Solo (blinken) und Rec (2. LED); optionale Statusspalte im Grid | `Reaper_OXI_Puzzle.lua` neu starten |
| 08.11.26, 22:35 | v8.7.1 | Puzzle: nur die gewählte Marker-Lane zählt, oder ein Nummernbereich | `Reaper_OXI_Puzzle.lua` neu starten |
| 08.11.26, 22:45 | v8.7 | OXI Puzzle: Regionen als Felder (mit Lücken), gruppierte Items = ein Feld, Marker-Zeile nur Lane 1 | `Reaper_OXI_Puzzle.lua` neu starten |
| 08.11.26, 12:45 | v8.6 | OXI Puzzle: Spurtaste 2× = Mute, halten = Solo · Moss läuft (26.6.5) | `Reaper_OXI_Puzzle.lua` neu starten |
| 08.11.26, 03:15 | v8.5 | E16 einheitlich: 15 = Spur, 16 = Master auf allen Seiten, Enc 16 wie MultiEQ (drehen = Spur vor/zurück, drücken + drehen = Master), Sends und Fader max 0 dB (Option), Stummes blinkt überall. Moss: `bauen.sh` verschiebt das alte Jar (Grund, warum Send 16/32 fehlte) | `Reaper_E16_Twister.lua` neu starten (+ Einstellungsfenster) · Moss: `bauen.sh` nochmal (baut jetzt auf 26.6.5 auf, Stand 02:50) |
| 07.11.26, 23:10 | – | Moss-Paket an seinen Platz verschoben: `OXI ONE MK2/Moss Erweiterung/moss4reaper_send16-32/` (lag versehentlich in Touch OSC) | – |
| 07.11.26, 22:50 | v8.4 | 3D-Übersichten: Reaper filtert selbst (Spurtypen + „nur Spuren mit Plugin“), Bänke nur aus passenden Spuren, echte Spurnummern, leere Bänke werden übersprungen. `Reaper_3D.lua` / `Reaper_Twister.lua` heißen wieder richtig. | `Reaper_3D.lua` neu starten · iPad, Monitor, Handy-Übersicht neu öffnen |
| 07.11.26, 22:20 | v8.3 | Send 16 / Send 32 für Reaper in DrivenByMoss (moss4reaper), Push = Mute, Pre/Post über die E16 | `bauen.sh` ausführen (Reaper zu) |
| 07.11.26 | v8.2 | Sends 16/32 aus dem Lua-Puzzle raus, Fassung für Bitwig geparkt | `Reaper_OXI_Puzzle.lua` |
| 07.11.26 | v8.1 | E16-Fenster schlägt Reverb-/Delay-/dearVR-Ziele vor; beide Fenster im TouchOSC-Look | E16- und OXI-Fenster |
| 07.11.26 | v8.0 | `Reaper_E16_Twister.lua`: E16 + Twister Bank 4 in einem Skript, mit Sends-Seite | neu einrichten |
| 07.11.26 | v7.0–7.2 | OXI One Puzzle (Items, Sends, Display, Menü) | `Reaper_OXI_Puzzle.lua` |
| 04.11.26 | v6.1 | Twister View mit 5 Looks; E16 in einer Szene | Twister View, E16-Szene |

Ältere Versionen und alle Details: [`Touch OSC/v5/ÄNDERUNGEN.md`](Touch%20OSC/v5/%C3%84NDERUNGEN.md).
Sicherungen jeder Version: `Touch OSC/z_alt/JJMMTT-vX.Y(Neuerung)/`.

---

## 3. Anleitungen (die ausführlichen)

| Thema | Datei |
| --- | --- |
| Einrichten, alle Oberflächen, Bedienung | [`Touch OSC/v5/LIESMICH.md`](Touch%20OSC/v5/LIESMICH.md) · `Touch OSC/v5/HANDBUCH.pdf` (Stand v6.1, wird aktualisiert) |
| E16 + Twister in Reaper | [`Touch OSC/v5/3_Reaper/LIESMICH_E16_Twister.md`](Touch%20OSC/v5/3_Reaper/LIESMICH_E16_Twister.md) |
| E16-Szene | [`OXI E16/seren-a_E16/LIESMICH.md`](OXI%20E16/seren-a_E16/LIESMICH.md) |
| OXI Puzzle | [`Touch OSC/v5/3_Reaper/OXI/LIESMICH_OXI.md`](Touch%20OSC/v5/3_Reaper/OXI/LIESMICH_OXI.md) |
| OXI in DrivenByMoss: Send 16/32 | [`OXI ONE MK2/Moss Erweiterung/moss4reaper_send16-32/LIESMICH_Moss_Send16_32.md`](OXI%20ONE%20MK2/Moss%20Erweiterung/moss4reaper_send16-32/LIESMICH_Moss_Send16_32.md) |
| Fehlersuche | [`Touch OSC/v5/0_Fehlersuche/FEHLERSUCHE.md`](Touch%20OSC/v5/0_Fehlersuche/FEHLERSUCHE.md) |
| MIDI-Protokoll (technisch) | [`Touch OSC/v5/PROTOKOLL.md`](Touch%20OSC/v5/PROTOKOLL.md) |

Ältere eigene Moss-Anleitungen (oxi-mixer-views v0.5) in `OXI ONE MK2/Moss Erweiterung/` sind durch das moss4reaper-Paket überholt.

---

## 4. Offen

- **Launchpad Pro Mk3 + Insert-Seite im Puzzle**: angefangen, geparkt in `Touch OSC/v5/5_Werkzeug/oxi/wip_launchpad_insert/` (siehe NOTIZ.md dort).
- **Handbuch** (HANDBUCH.pdf / Handbuch.html) von v6.1 auf v8.x bringen.
- **Paket 5**: Übersicht, was davon in Nuendo geht.
- **dearVR PRO 2**: Position wird über die Parameternamen erkannt. Zeigt die ROOM-Ansicht nichts, die LOG-Zeile „Position nicht erkannt“ schicken.
- **OXI-Farbsets** (deine Looks fürs Grid, Puzzle + Moss): Vorschau angeboten.
- **Push-Schalter + Aktions-/Toolbar-Dropdown** in den Einstellungsfenstern (gewünscht 08.11.).
- **Bitwig-Test** der Moss-Fassung (geparkt in `z_alt/261107-v8.2(moss send16 32)`).
