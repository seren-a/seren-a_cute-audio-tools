# Send 16 / Send 32 für die OXI One MkII (DrivenByMoss-Fork, v8.2)

Zwei neue Mixer-Ansichten in deinem DrivenByMoss-Fork, vertikal wie Mix 32: Spalten = Spuren.

| Ansicht | Grid |
| --- | --- |
| **Send 16** | 16 Spuren. Zeile 1 = Spur wählen (Spurfarbe), Zeilen 2–8 = Send 1–7 jeder Spur |
| **Send 32** | 2 Blöcke à 16 Spuren. Pro Block Zeile 1 = Spur wählen, Zeilen 2–4 = Send 1–3 |

**Send-Feld:** Es leuchtet in der Farbe des Send-Ziels. Voll heißt laut, gedimmt heißt leise, fast aus heißt sehr leise, grau heißt 0. **Rot** = Send aus (stumm), **blass** = Pre-Fader. Bei der gewählten Spur sind die 4 Sends, die gerade auf den Encodern liegen, hervorgehoben.

## Bedienung

- **MIXER/ARRANGER** schaltet durch die Mixer-Ansichten. Send 16 und Send 32 sind neu dabei. Welche Ansichten in welcher Reihenfolge kommen, legst du in den Controller-Einstellungen fest (Mixer Views).
- **Pad Zeile 1:** Spur wählen, wie in Mix 32.
- **Pad auf einem Send:** Spur wählen, die Encoder springen auf die 4er-Gruppe dieses Sends. **2×** schaltet Pre/Post, **Shift + Pad** schaltet den Send an/aus.
- **Encoder 1–4:** Pegel der Sends 1–4, 5–8, 9–12 oder 13–16 der gewählten Spur.
  - Push = Send an/aus, 2× = Pre/Post. Das lässt sich in den Einstellungen tauschen: „Send 16/32: encoder press“.
  - Lang drücken setzt den Pegel zurück.
- **Up/Down:** nächste/vorige 4er-Gruppe, die Zeilen gehen mit. **Shift + Up/Down** schiebt nur die Zeilen um einen Send.
- **Left/Right:** Spuren seitenweise weiter, mit Shift um 16.
- **Display:** Spur, Name und Wert des Sends unter dem zuletzt bedienten Encoder (mit „Pre“ bzw. „Muted“) und die 4 Send-Namen.

## Einstellungen (Bitwig: Controller-Einstellungen der OXI)

- *Mixer Views → Send 16/32: encoder press*: „Mute, 2x Pre/Post“ oder „Pre/Post, 2x Mute“
- *Mixer Button*: Send 16 / Send 32 an/aus
- *Mixer Order*: jetzt 8 Plätze statt 6

Diese Einstellungsseite zeichnet Bitwig selbst. Farben oder ein eigener Look lassen sich dort nicht setzen.

## Bauen

Wie gewohnt in `~/DrivenByMoss`: `mvn install`, dann die Extension aus `target/` nach Bitwig. Ich habe den Fork mit deinen Bibliotheken komplett kompiliert, ohne Fehler. Gepackt und in Bitwig getestet habe ich es nicht.

Deine bisherigen Dateien liegen unverändert in `~/DrivenByMoss/seren_backup_261107/`.

## Geändert

| Datei | was |
| --- | --- |
| `framework/daw/data/ISend.java` | Pre/Post-Abfrage, Standard: nicht unterstützt |
| `framework/daw/IModel.java` | Spurbank mit Sends |
| `framework/view/Views.java` | SEND16, SEND32 |
| `bitwig/.../ModelImpl.java` | Spurbank mit Sends (16 Sends je Spur) |
| `bitwig/.../data/SendImpl.java` | Pre/Post über `sendMode` (PRE/POST) |
| `oxi/one/view/AbstractOxiOneSendView.java`, `OxiOneSend16View.java`, `OxiOneSend32View.java` | neu |
| `oxi/one/mode/OxiOneSendsMode.java` | neu: Encoder = 4 Sends |
| `oxi/one/OxiOneConfiguration.java`, `OxiOneControllerSetup.java`, `controller/OxiOneColorManager.java` | Einstellung, Anmeldung, Farbstufen |

## Grenzen

- **Pre/Post in Bitwig:** Das Umschalten setzt den Send-Modus auf „PRE“ bzw. „POST“. Ob Bitwig genau diese Werte erwartet, habe ich nicht prüfen können. Tut sich beim 2× nichts, sag Bescheid.
- **Reaper:** moss4reaper hat eine eigene Kopie des Moss-Codes und eine Reaper-Brücke, die keinen Befehl für Pre/Post kennt.
  - Um die Ansichten in Reaper zu haben, müssen die neuen Dateien in DrivenByMoss4Reaper übernommen und dort gebaut werden.
  - Send 32 zeigt dort nur 16 Spuren. Es gibt keine zusätzliche Spurbank, wie schon bei Mix 32.
  - Pre/Post meldet „n/a“, Mute funktioniert.
  - Das machen wir als eigenen Schritt, wenn du willst.
- Die bisherigen Lua-Seiten Sends 16/32 im Reaper-Puzzle-Skript sind entfernt.
