# seren.a 3D v3 – MIDI-Protokoll (TouchOSC Bridge, MIDI 1)

Alle Oberflächen mit Skriptweg sprechen dasselbe Protokoll mit dem DAW-Skript
(Nuendo: serena_TouchOSC3D.js, Reaper: reaper_seren3D.lua). 14-Bit-Werte: MSB auf CC n,
LSB auf CC n+32, Wert 0..16383 = voller Parameterbereich des Plugins.

| MIDI-Kanal | Inhalt | Richtung |
|---|---|---|
| 1–12 | Pitchbend: MultiPanner der gewählten Spur, Kanal = Parameter (X, Y, Z, Rot Z, Tilt Y, Tilt X, Distance, Divergence, Field Size, Source Size, Width, Depth) | beide (Nuendo, Mapping Assistant) |
| 7 / 8 | SceneRotator je Objekt 1–8 / 9–16: CC = 4·((Obj−1) mod 8) + p, p 0 Yaw, 1 Pitch, 2 Roll (±180°) | beide |
| 9 / 10 | MultiEncoder-Eingänge der gewählten Spur 1–8 / 9–16: CC = 4·((n−1) mod 8) + p, p 0 Azimuth, 1 Elevation (±180°), 2 Gain (−60..+10 dB) | beide |
| 11 / 12 | MultiPanner-Objekte 1–8 / 9–16 (Mapping Assistant, fest je Spur): p 0 X, 1 Y, 2 Z (−100..100) | beide |
| 13 / 14 | Encoder je Objekt 1–8 / 9–16: p 0 Azimuth, 1 Elevation (±180°), 2 Width (±360°, nur StereoEncoder). Beim MultiEncoder = Master-Richtung | beide |
| 15 | Note 0–15: Spur gewählt (DAW → Gerät) / Spur wählen (Gerät → DAW). CC 0–15: Pegel 0–127 | |
| 16 | gewählte Spur (Panner): CC 1 Azimuth, 2 Elevation, 4 Width (Encoder; MultiEncoder: Master), 5 Yaw, 6 Pitch, 7 Roll (Rotator). Note 0/1 Spur zurück/vor, Note 2/3 Bank zurück/vor | beide |

SysEx F0 7D 4F <cmd> … F7 (DAW → Gerät):
1 Name <obj> <Text> · 2 Farbe <obj> <r> <g> <b> · 3 Flags <obj> <bits> (1 Encoder da, 2 MultiPanner
zugewiesen, 4 Encoder ist MultiEncoder, 8 SceneRotator da) · 4 Quelle <Text> · 5 Bank <n> ·
6 MultiPanner-Name <obj> <Text> · 7 alles löschen · 8 Log <Text> · 9 MultiEncoder der gewählten
Spur <Anzahl Eingänge> <Spurname>

SysEx F0 7D 54 <Feld> <Text> F7 (Panner, gewählte Spur): 0 Spur, 1–7 Parameternamen,
11–17 Anzeigewerte, 20 Encoder-Plugin, 21 Rotator-Plugin.

Plugin-Slots: Nuendo Insert 4 = StereoEncoder oder MultiEncoder, Insert 5 = SceneRotator
(MIDI Remote kennt Plugins nur über die Slot-Nummer). Reaper: beliebiger Slot, gesucht nach Namen.
Parameter werden in beiden DAWs am Namen erkannt (z. B. „Azimuth Angle“), nie an der Position.

## v3.1 (64 Objekte, Spurtypen, Symbole)
- Objekte 0–63. Objekte 0–15 wie oben per CC, ab 16 per SysEx **F0 7D 4F 0A <Art> <Obj> <p> <MSB> <LSB> F7**
  (Art 0 Encoder: p Az/El/Width · 1 Rotator: Yaw/Pitch/Roll · 2 MultiPanner: X/Y/Z), in beide Richtungen.
- Kanal 15: Note 0–63 Auswahl, CC 0–63 Pegel (0–127 = −60..0 dBFS).
- Flags (cmd 3) zusätzlich: 16 FX-Kanal, 32 Gruppe/Ordner, 64 MIDI/Instrument. VCA wird nie gesendet.
- cmd 11 Symbolname <Obj> <Text> (Reaper: Name der Icon-Datei ohne Pfad/Endung).
- cmd 12 Fenster <W>: so viele Objekte liefert die DAW (Reaper 64, Nuendo OV_N = 32).
- Bank (cmd 5, Note 2/3 auf Kanal 16) = Schritte von 16 Spuren.
- Reaper zeigt nur sichtbare Spuren (TCP), Nuendo das, was die MixConsole liefert.
- MultiPanner in Nuendo: Track-Quick-Controls, am Parameternamen erkannt (beliebige QC-Reihenfolge).

## v4.4 – dearVR PRO (ROOM-Ansicht)
- **SysEx 10, kind 3** = dearVR-Position eines Objekts, für **alle** Objekte (auch 0–15) als SysEx:
  `F0 7D 4F 0A 03 <obj> <part> <msb> <lsb> F7`, part 0 = x (rechts +), 1 = y (vorn +), 2 = z (oben +),
  14 bit = −32…+32 m relativ zum Hörer. Nur DAW → Oberfläche (die ROOM-Ansicht ist reine Anzeige).
- **cmd 14** = Raum eines Objekts: `F0 7D 4F 0E <obj> <L msb lsb> <F> <R> <T> <B> <Bo> <Presetname ASCII> F7`,
  Wandabstände in cm (14 bit, bis 163 m), Reihenfolge links, vorn, rechts, Decke, hinten, Boden; 0 = offene Seite.
  `F0 7D 4F 0E <obj> F7` = kein dearVR bzw. Raum unbekannt.
- Wände: aus den Wand-Parametern des Plugins, sonst aus der Preset-Tabelle des dearVR-PRO-2-Handbuchs (46 Presets).
- Plugin-Auswahl (Reaper): pro Rolle das erste **aktive** Plugin (nicht umgangen, nicht offline):
  Encoder = StereoEncoder/MultiEncoder, Rotator = SceneRotator, Raum = dearVR PRO. Log-Zeile `u<Spur>`
  listet alle gefundenen Plugins mit `*` (benutzt), `(aus)`, `(ignoriert)`.

## v5.0 – Auslastung, dearVR in Nuendo, gefilterte Listen
- **cmd 15** = Auslastung: `F0 7D 4F 0F <System %> <DAW %> <Aussetzer> F7`, Werte 0–100, 127 = unbekannt,
  Aussetzer 1 = in den letzten 10 s gab es einen Audio-Aussetzer. Nur Reaper sendet das (alle 3 s; macOS
  über `ps`, Windows nur Aussetzer). Nuendo gibt MIDI-Remote-Skripten keine Auslastung → nichts.
  Oberflächen zeigen das dezent neben der Versionsnummer, wenn in den Optionen „Auslastung“ an ist.
- **Nuendo + dearVR PRO**: Insert 4 **oder** Insert 5, das erste eingeschaltete und nicht umgangene zählt.
  Gesendet wird wie in Reaper (SysEx 10 kind 3 + cmd 14), Werte aus den Anzeigetexten der Parameter.
  Die Positions-/Raum-Parameter müssen unter den ersten 16 Parametern des Slots liegen (Remote Control Editor).
  K_ENC / K_ROT = 16 Parameter je Slot.
- Listen (iPad, Monitor, Handy-Übersicht) zeigen nur Spuren, auf denen das Plugin des Modus liegt
  (SPACE: Encoder, MULTI: MultiEncoder-Eingänge, PANNER: MultiPanner, ROOM: dearVR). iPad/Monitor:
  abschaltbar in den Optionen („nur Spuren mit Plugin“). Protokoll unverändert.


## MultiEQ (v5.1) – Reaper_MultiEQ.lua, unabhängig vom 3D-Protokoll
Twister Bank 4 (Midi Fighter Utility: Encoder relativ ENC 3FH/41H, Switch CC Hold):
- Twister → Reaper: Kanal 1 CC 49–64 = Drehen (64 ± Schritte), Kanal 2 CC 49–64 = Drücken 127 / Loslassen 0, Kanal 4 = Bankwechsel
- Reaper → Twister: Kanal 1 CC 49–64 = Ring (Frequenz log 20 Hz–20 kHz; beim Drücken Gain ±18 dB, beim Halten Q 0,05–8),
  Kanal 2 = Farbe (127 Utility-Farbe, 0 = Band aus, 85 = gesperrt), Kanal 3 = Animation (11 = Q-Modus pulsiert, 95/70 Ringhelligkeit)
- Reaper → Twister View (Bridge): SysEx 7D 4D wie Reaper_Twister.lua für Bank 4 (Name = Frequenz + Band, Text = Gain + Q), Tab-Name „MultiEQ“;
  ExtState `seren_MultiEQ/alive` sagt Reaper_Twister.lua, dass Bank 4 belegt ist.
Ebenen (v5.3): Encoder 8 halten + loslassen = MultiEQ → Omni → Directional, 8 drücken = Omni-Bypass; die Ringe zeigen bei
  Kompressoren den normierten Wert. Farben (klassische Farbtabelle): 25 Kompressor vom Master, 113 gesperrt, 64 Solo,
  69 gemutet ohne Solo (15), 81 Mute (16), Master einstellen 81 gedimmt (Kanal 3 Wert 22), Encoder 8 = Farbe der Ebene (127 / 45 / 100);
  Blinken = Kanal 3 Wert 3, Ringhelligkeit = Kanal 6 (95 an, 70 aus).
OXI E16, Szene MultiEQ (E16_MultiEQ.lua, MultiEQ.oxie16): Seite 1 = MultiEQ, Seite 3 = Kompressoren
- E16 → Reaper: Seite 1 auf Kanal 13, Seite 3 auf Kanal 12: CC 20–35 Drehen (64 ± Schritte), CC 40–55 Drücken 127 / 0,
  CC 1 = Seitennummer (bei jedem Wechsel und jede Sekunde); Reaper zeichnet nur die Seite, die zu sehen ist
- Reaper → E16: Kanal 12 = Titel (CC 0–14) und Slotnamen (CC 16–79, je 4 Zeichen), CC 127 löschen;
  Kanal 10 = Flash-Titel (CC 0–14, CC 15 zeigen), Slotwerte (CC 16–79), Ring (CC 80–95), Ring aus (CC 96–111);
  Kanal 8 = Zustand CC 1–16: +1 aus, +2 gesperrt, +4 Halten, +8 Drücken, +16 vom Master; 64 Solo, 65 gemutet ohne Solo, 66 Mute (blinken), 67 Master einstellen (ruhig)

## v6.0 – Hall-Ebene, Plugin-Steuerung in Nuendo
- Ebene 4 **Hall** (Reaper_MultiEQ.lua und Nuendo): oben FDN Reverb (1 Room Size, 2 Reverberation Time, 3 Fade-in, 4 Dry/Wet,
  5 Lows Cutoff / drücken Lows Gain, 6 Highs Cutoff / drücken Highs Gain), unten 9–14 = die ersten 6 Parameter des Convolvers
  (Name enthält „convol“; Reapers Bypass/Wet/Delta am Ende zählen nicht). Encoder-8-Farbe Hall = 13. E16 Seite 3: Omni → Directional → Hall.
  Das E16-Protokoll ist unverändert (die Slotnamen schickt die DAW).
- **Nuendo, gemeinsamer Block** `common_mr/plugctl.js` (PLUGCTL) in serena_MFTView.js und serena_E16DAWLink.js: Direct Access
  (API 1.2, Nuendo/Cubase 13+) auf der ausgewählten Spur und dem ersten Ausgangskanal (Stereo Out). Plugins am Objekttitel erkannt
  (multi eq, omni comp, directional comp, fdn reverb, convol, scene rotator / ambi decoder), Parameter am Titel (wie Reaper).
  Werte: API 1.3 (Nuendo 15) rechnet in Hz/dB/Q um, sonst normierte Schritte mit Rücklesen. Bypass: Parameter „Bypass“ am Plugin
  oder am Insert-Platz darüber. Spur/Solo/Mute/Volume und Stereo-Out-Volume über eigene Variablen.
- **Twister Bank 4 (MFTView)**: alle 16 Encoder relativ (ENC 3FH/41H wie in Reaper), Drücken Kanal 2 CC 49–64.
  Zwei Unterseiten „Bank 4 › Sends/QC“ und „Plugins“; Encoder 16 halten ≥ 0,6 s ohne Drehen = umschalten.
  Im Modus Plugins schickt das Skript an den Ausgang „Twister“: Kanal 1 Ring, Kanal 2 Farbe, Kanal 3 Animation, Kanal 6 Ringhelligkeit
  (Werte wie Reaper_MultiEQ.lua); an die Twister View SysEx 7D 4D wie bisher (cmd 1/2 Name/Text, cmd 6 Tab = Ebene oder „Sends/QC“).
- **E16 (E16DAWLink)**: hört zusätzlich auf die Szene MultiEQ (Kanal 13 = Seite 1, Kanal 12 = Seite 3: CC 1 Seite, CC 20–35 Drehen,
  CC 40–55 Drücken) und zeichnet auf Kanal 12/10/8 wie Reaper – nur solange die Szene sich meldet (Seitenmeldung jede Sekunde,
  3 s Ruhe = Szene weg). Die DAW-Link-Szene (Kanal 16/14) bleibt unverändert.

## v6.1 – Twister View, eine E16-Szene, Farben
- **Hall-EQ (Ebene 5)**: `collect()` stuft einen `eq` unmittelbar vor einem `fdn` (Nuendo: Insert-Slot davor; Reaper: FX-Index − 1) zu `feq` um. Eigene Instanzliste `feq` (max. 1), Ebene 5 mit Bändern 1–3 → Encoder 1–3, 4–6 → 5–7, Slots tragen `k:'feq'`. Twister-Zyklus 1→5, 5 wird ohne `feq` übersprungen; E16 Seite 4: `e16Hall` 4↔5. Twister-Farbe Ebene 5 = 92, Ansichts-Tab „Hall-EQ“. Keine Änderung an Ports oder E16-Szene.
- **Twister View, SysEx F0 7D 4D** (DAW-Skript → View), neu:
  cmd **8** Balkenfarbe `<bank 0-3> <slot 0-15> <r> <g> <b>` (je 0–127), Slot **127** = alle Farben der Bank zurück auf die .mfs-Farben;
  cmd 7 (alles löschen) setzt die Farben ebenfalls zurück. Text in cmd 1/2/3/6: Codes **1–8** = ä ö ü Ä Ö Ü ß ° (SysEx hat nur 7 Bit),
  10 = Zeilenumbruch (Name ↵ Plugin/Spur). Ältere Views lassen die Codes einfach weg.
- **Bank-Taste in der View** → DAW-Skript: Kanal 4 (System-Kanal des Twister) CC `<bank 0-3>` = 127, wie der Twister selbst seine Bank meldet.
  Das DAW-Skript schickt dasselbe an den Twister (Bankwechsel) und cmd 4 an die View. Nuendo: Eingang „View“ von MFTView, Reaper: Reaper_Twister.lua.
  Banknamen (cmd 6): Nuendo „Kanal/EQ“, „Insert 1+2“, „frei“, Bank 4 = „Sends/QC“ bzw. Ebene; Reaper: „Bank 1–3“, Bank 4 wie gehabt.
- **Twister Bank 4, Farben** (Kanal 2): IEM-Farben auf dem Farbrad: Cyan 20, Grün 51, Orange 68, Rot 83, Weiß/Utility 127,
  MultiEQ-Bänder 25 / 118 / 9 / 56 / 64 / 75, Convolver 9, Master 25. **Threshold**: Ring umgekehrt (127 − Wert), 0 dB = leer.
- **OXI E16, Szene seren-a_E16** (seren_E16.lua, ersetzt die Szenen DAW-Link und MultiEQ):
  - E16 → DAW: Seite 1 auf Kanal 16 (wie DAW-Link), Seite 2 auf 13, Seite 3 auf 12, Seite 4 auf **11**: CC 20–35 Drehen (64 ± Schritte),
    CC 40–55 Drücken 127 / Loslassen 0. Seiten 2–4: CC 1 = 1 / 3 / 4 bei jedem Wechsel und jede Sekunde; Seite 1: einmal CC 1 = **127** auf Kanal 13
    (= Plugin-Seiten nicht zu sehen, DAW hört auf zu zeichnen).
  - DAW → E16, Seite 1: Kanal 16 = Titel / Namen wie DAW-Link, **CC 80–95 = Ringfarbe** Slot 1–16 (neu); Kanal 14 = Werte, Ringe.
  - DAW → E16, Seiten 2–4: Kanal 12 / 10 / 8 wie die alte Szene MultiEQ, dazu Kanal 8 **CC 17–32 = Ringfarbe** Slot 1–16.
  - Farben = Index der OXI-Palette (Zeile × 10 + Spalte): Cyan 83, Grün 92, „Orange“ = Pfirsich 36 (die Palette hat kein Orange), Rot 57, Weiß 34,
    Bänder 87 / 74 / 18 / 40 / 44 / 56, Convolver 77, Master 85. Zustände: aus 24, gesperrt 34, drücken/halten 44, Solo 44 (blinkt),
    gemutet 36, Mute 57 (blinkt), Master einstellen 85.
- **Plugin-Ebenen**: E16 Seite 2 = Ebene 1, Seite 3 = Ebene 2 (8 halten ↔ Ebene 3), Seite 4 = Ebene 4 (Hall).
  Ebene 2: 8 drehen = Omni A Makeup, 7 tippen = A LookAhead. Ebene 4: 7 = FDN-Preset, 9–13 = Convolver Parameter 1–5, 14 = Convolver-Preset.
  Presets: Reaper über die Presetliste des Plugins (TrackFX_NavigatePresets); Nuendo über einen Parameter „Program“/„Preset“ des Plugins,
  eine Raste = nächster Wert, der den Anzeigetext ändert.
- **Nuendo, Werte**: liefert `convertParameterProcessValueToPlain` den normierten Wert zurück (IEM-Plugins), rechnet das Skript mit dem
  Anzeigetext (kHz × 1000). Schritte: Gain 0,5 dB, Frequenz ≤ 15 % pro Raste.

## v8.4 – Spurfilter in der DAW, echte Spurnummern, leere Bänke überspringen
- **Gerät → DAW: SysEx `F0 7D 4F 0B <Typen> <Plugin> F7`** = Spurfilter aus der Config (iPad, Monitor).
  Typen-Bits: 1 Audio, 2 FX (Reaper: Spur mit Receives), 4 Gruppe/Ordner, 8 MIDI/Instrument. Plugin 1 = nur Spuren mit
  Encoder, Rotator oder dearVR PRO (auch umgangene). Reaper baut die Bänke nur aus passenden Spuren und merkt sich den
  Filter (ExtState `seren_3D/filter`, Standard 15,1). Nach einem Wechsel: Bank 0.
- **DAW → Gerät: cmd 16 `<Typen> <Plugin>`** = aktueller Filter (bei Wechsel und alle 5 s). Die Oberflächen übernehmen ihn
  in die Config, so zeigen alle denselben Stand. Nuendo sendet das nicht.
- **DAW → Gerät: cmd 17 `<Obj> <Nummer MSB> <LSB>`** = echte Spurnummer des Objekts (Reaper). Listen und Bereichsanzeige
  zeigen sie statt „Bank × 16 + Platz“.
- Reaper setzt jetzt auch die Flags 16 (Spur mit Receives) und 64 (Instrument-Plugin auf der Spur).
- **Leere Bänke überspringen** (alle Oberflächen, gemeinsamer Block `common/bank.lua`): nach Bank vor/zurück 0,7 s warten;
  zeigt die Ansicht (SPACE / ROOM) auf der neuen Bank nichts, geht es von selbst weiter, höchstens 16 Bänke.
  Kommt 1,5 s kein Bankwechsel mehr, ist das Ende erreicht. Das hilft vor allem in Nuendo: dort legt das Skript die
  Spurliste der Bank beim Laden fest und kann nicht nach Plugins filtern.

## v8.14 – Gruppen (Reaper)
- **DAW → Gerät: cmd 19 `<Anzahl>`**, **cmd 18 `<idx> <flags> <Name>`** = Gruppenliste (höchstens 12): zuerst A–D (eigene Gruppen,
  flags 2), dann Reaper-Ordnerspuren ohne dearVR/Hall-Plugin (Name = Spurname). flags 1 = wird gezeigt, 4 = hat Spuren.
  Gesendet bei Änderung und alle 5 s.
- **Gerät → DAW: SysEx `0C <idx> 0`** = Gruppe zeigen an/aus. Ist mindestens eine an, bestehen die Bänke nur aus Spuren dieser
  Gruppen (Ordner: der Ordner und alles darin; A–D: die zugeordneten Spuren), zusätzlich zu Spurtyp-/Plugin-Filter. Bank 0.
- **Gerät → DAW: SysEx `0D <A–D 0–3> <Objekt>`** = Spur des Objekts in die Gruppe bzw. wieder heraus.
- Gespeichert im Projekt (ProjExtState `seren_3D`: `grp_A` … `grp_D` = GUIDs, `grp_vis` = gezeigte Gruppen).

## v8.15 – Voreinstellung der Oberflächen in Reaper
- **Gerät → DAW: SysEx `0F <Oberfläche>`** (0 = iPad, 1 = Monitor) einmal nach dem Start: „schick meine Voreinstellung“.
  **DAW → Gerät: cmd 20 `<Oberfläche> <Text>`** = gespeicherter Stand (ExtState `seren_3D/view0` bzw. `view1`, bleibt über Neustarts).
  Kommt in 2 s nichts, bleibt die Oberfläche bei ihren Werten.
- **Gerät → DAW: SysEx `0E <Oberfläche> <Text>`** bei jeder Änderung (höchstens 1× pro s): `k=v;…` – Modus, iPad `n32`,
  Monitor `lay`/`pano`, Pegel-Skala/-Modus/AES17/LUFS/LU-Bezug, Farben, Look, Kennzeichnung, CPU, Symbole und alle Config-Fader.
- Spurfilter (Typen, nur mit Plugin) und Gruppen waren schon in Reaper gespeichert (v8.4 / v8.14).
