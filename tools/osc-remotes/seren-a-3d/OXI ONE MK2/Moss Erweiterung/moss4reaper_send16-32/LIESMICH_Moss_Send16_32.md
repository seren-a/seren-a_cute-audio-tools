# Send 16 / Send 32 für die OXI One MkII in DrivenByMoss (v8.3, Reaper)

Zwei Mixer-Ansichten für die OXI in DrivenByMoss, vertikal wie Mix 32: Spalten = Spuren. Seit v8.3 gibt es sie für **Reaper** (moss4reaper). Die Bitwig-Fassung liegt geparkt in `z_alt/261107-v8.2(moss send16 32)`.

| Ansicht | Grid |
| --- | --- |
| **Send 16** | 16 Spuren. Zeile 1 = Spur wählen (Spurfarbe), Zeilen 2–8 = Send 1–7 jeder Spur |
| **Send 32** | 2 Blöcke à 16 Spuren. Pro Block Zeile 1 = Spur wählen, Zeilen 2–4 = Send 1–3. In Reaper ist nur der obere Block belegt (siehe Grenzen). |

**Send-Feld:** Es leuchtet in der Farbe des Send-Ziels. Voll heißt laut, gedimmt heißt leise, fast aus heißt sehr leise, grau heißt 0. **Rot** = Send aus (stumm). Bei der gewählten Spur sind die 4 Sends hervorgehoben, die gerade auf den Encodern liegen.

## Bedienung

- **MIXER/ARRANGER** schaltet durch die Mixer-Ansichten. Send 16 und Send 32 sind neu dabei. Welche Ansichten in welcher Reihenfolge kommen, legst du in den Controller-Einstellungen fest (Mixer Views).
- **Pad Zeile 1:** Spur wählen, wie in Mix 32.
- **Pad auf einem Send:** Spur wählen, die Encoder springen auf die 4er-Gruppe dieses Sends. **Shift + Pad** schaltet den Send an/aus.
- **Encoder 1–4:** Pegel der Sends 1–4, 5–8, 9–12 oder 13–16 der gewählten Spur.
  - **Push = Send an/aus**, sofort, ohne Warten auf einen Doppelklick.
  - Lang drücken setzt den Pegel zurück.
  - Pre/Post machst du in Reaper über die E16 (Seite Sends). Ein Doppelklick auf der OXI zeigt nur „Pre/Post: E16“.
- **Up/Down:** nächste/vorige 4er-Gruppe, die Zeilen gehen mit. **Shift + Up/Down** schiebt nur die Zeilen um einen Send.
- **Left/Right:** Spuren seitenweise weiter, mit Shift um 16.
- **Display:** Spur, Name und Wert des Sends unter dem zuletzt bedienten Encoder („Muted“, wenn aus) und die 4 Send-Namen.

## Einstellungen (Reaper: DrivenByMoss-Fenster > OXI One MkII > Einstellungen)

- *Mixer Button*: Send 16 / Send 32 an/aus
- *Mixer Order*: jetzt 8 Plätze statt 6
- *Send 16/32: encoder press*: wirkt nur in Bitwig. In Reaper ist Push immer Mute.

## Bauen und installieren (Mac)

Alles liegt hier in `OXI ONE MK2/Moss Erweiterung/moss4reaper_send16-32/`:

| Datei | was |
| --- | --- |
| `bauen.sh` | holt DrivenByMoss4Reaper nach `~/DrivenByMoss4Reaper`, spielt den Patch ein, baut und kopiert das Jar nach Reaper |
| `seren_oxi_reaper.patch` | alle Änderungen als ein Patch (für `git apply`) |
| `overlay/` | dieselben 26 Dateien zum Drüberkopieren, falls du lieber von Hand arbeitest |

1. Reaper beenden.
2. Terminal: `bash ".../OXI ONE MK2/Moss Erweiterung/moss4reaper_send16-32/bauen.sh"`
   - Gebraucht werden git und Java 21 (JDK). Gradle lädt das Skript selbst.
   - Hast du dort schon eigene Änderungen, sichert das Skript sie vorher mit `git stash`.
   - Das bisherige Jar landet in `UserPlugins/drivenbymoss-libs_sicherung`.
3. Reaper starten.

**Version:** Der Patch baut auf **DrivenByMoss4Reaper 26.6.5** auf, der veröffentlichten Version, die du installiert hast. Jar und C++-Teil passen so zusammen. (Bis 08.11. 02:50 baute das Skript 26.7.0 aus dem Entwicklungsstand. Das gibt es nicht als Release.)

**Zurück zum Original:** Jar aus `drivenbymoss-libs_sicherung` zurückkopieren, oder die offizielle Version neu installieren.

## Was drin ist

Mit dabei sind auch deine bisherigen OXI-Erweiterungen aus `~/DrivenByMoss`: Mix 32, Mix 64, Plugin 32, Plugin-Mixer, die Mixer-Taste und die Track-Zeilen.

| Datei | was |
| --- | --- |
| `framework/daw/IModel.java`, `ModelSetup.java`, `data/IDevice.java`, `data/ISend.java`, `constants/DeviceChainOperation.java` | Zusatzfunktionen mit Standardwerten, Reaper braucht keine eigene Umsetzung |
| `framework/view/Views.java` | SEND16, SEND32 |
| `oxi/one/view/...Send16/Send32/AbstractOxiOneSendView` | neu |
| `oxi/one/mode/OxiOneSendsMode.java` | neu: Encoder = 4 Sends, Push = Mute |
| `oxi/one/OxiOneConfiguration.java`, `OxiOneControllerSetup.java`, `controller/OxiOneColorManager.java` | Einstellung, Anmeldung, Farbstufen |
| übrige `oxi/one/view/...` | deine Mix-32/64- und Plugin-Ansichten |

**Geprüft:** Der gesamte moss4reaper-Quellcode ist mit Patch kompiliert. Fehler gab es nur in Dateien, die 4 hier nicht ladbare Bibliotheken brauchen (OSC, USB, SVG, INI). Diese Fehler sind ohne Patch genau dieselben, Gradle holt die Bibliotheken bei dir. In Reaper getestet ist der Patch noch nicht.

## Grenzen in Reaper

- **Pre/Post:** Die Reaper-Brücke von moss4reaper hat dafür keinen Befehl, deshalb läuft es über die E16.
- **Send 32 und Mix 32/64:** In Reaper gibt es keine zweite, unabhängige Spurbank. Die Ansichten nutzen die normale Spurbank der OXI, der zweite Block bleibt leer.
- **Plugin 32:** Reaper liefert keine Geräte je Spur. Die Felder bleiben leer.
- **Puzzle und Moss gleichzeitig:** geht nicht, siehe `LIESMICH_OXI.md`.
