# DrivenByMoss – OXI One: Mixer-Erweiterungen v0.5 (Reaper + Bitwig)

Drei Patches, Basis jeweils Release **26.6.5**:

| Patch | Projekt | Basis |
|---|---|---|
| `oxi-reaper-backend-v0.5.patch` | DrivenByMoss4Reaper-Backend (C++-Plugin in Reaper) | Release **26.6.5** |
| `oxi-reaper-java-v0.5.patch` | DrivenByMoss4Reaper (Java-Teil mit der OXI-Logik) | Release **26.6.5** |
| `oxi-bitwig-v0.5.patch` | DrivenByMoss für Bitwig | Release **26.6.5** |

Für Reaper brauchst du **beide** Reaper-Patches. Sie sind gegenseitig abwärtskompatibel: Passen Java- und C++-Teil nicht zusammen, fehlen nur die Plugins im Plugin Mixer, abstürzen sollte nichts.

Die Patches gelten jeweils gegen das saubere Release 26.6.5, nicht gegen v0.4. Wer v0.4 schon hat, findet den kürzeren Weg in `UPGRADE-reaper-v0.4-auf-v0.5.md`.

**Neu in v0.5**

- Einstellung, **welche Ansichten die MIXER-Taste durchschaltet** (Häkchen pro Ansicht), und deren **Reihenfolge**
- Neue Ansicht **Plugin 32**: 32 Spuren, dazu die Inserts auf den freien Feldern
- Bei „Mute only" oder „Solo only" zeigt **gehaltenes Shift die jeweils andere Zeile**
- **Bitwig** bekommt alle diese Funktionen ebenfalls

Der Backend-Patch ist inhaltlich unverändert gegenüber v0.4 (Plugin 32 nutzt dieselben FX-Daten wie der Plugin Mixer). Wer v0.4 schon installiert hat, muss nur den Java-Teil neu bauen.

---

## So gibst du die Befehle ein

Du kannst jeden Block aus dieser Anleitung komplett kopieren und ins Terminal einfügen. Die Zeilen laufen dann nacheinander. Beachte dabei:

- **Jeder Block beginnt mit `cd ~`.** Das springt in deinen Home-Ordner, damit `git clone` dort neue Ordner anlegt. Ohne diese Zeile landet ein zweiter Versuch im Ordner des ersten, und es entstehen verschachtelte Ordner wie `DrivenByMoss4Reaper-Backend/DrivenByMoss4Reaper-Backend`.
- **Alte Ordner vorher wegräumen.** Gibt es die Ordner `DrivenByMoss4Reaper-Backend`, `DrivenByMoss4Reaper` oder `DrivenByMoss` schon aus einem früheren Versuch, benenne sie um, z. B. `mv DrivenByMoss4Reaper-Backend DrivenByMoss4Reaper-Backend-alt`. Sonst scheitert `git clone`, und die folgenden Zeilen laufen im alten Ordner.
- **Ein Fehler stoppt nichts.** Läuft eine Zeile in einen Fehler, laufen die nächsten trotzdem weiter. Schau nach `git apply` auf die Ausgabe: Es darf keine Fehlermeldung kommen (Warnungen sind okay), sonst nicht weitermachen. Eine fehlende Patch-Datei in `~/Downloads` zeigt sich genau dort.
- **Einen Block nach dem anderen.** Warte, bis ein Block durchgelaufen ist, bevor du den nächsten einfügst.
- **Kommentare mit `#` gehören nicht in die Befehle.** Die macOS-Shell (zsh) behandelt `#` im Terminal oft nicht als Kommentar. In den Blöcken stehen deshalb keine Kommentare. Wenn du eigene dazuschreibst, lass sie beim Einfügen weg.
- **Abfragen:** Fragt ein Befehl etwas ab (z. B. ein Passwort bei `brew`), landen eingefügte Zeilen dort als Eingabe. Gib solche Zeilen einzeln ein.

---

## Reaper: bauen und installieren (macOS)

**Vorbereitung**

- Die offizielle Version **26.6.5** von DrivenByMoss4Reaper muss installiert sein. Die Patches ersetzen danach nur zwei Dateien.
- Reaper beenden.
- Diese beiden Dateien sichern (z. B. auf den Schreibtisch kopieren):
  - `~/Library/Application Support/REAPER/UserPlugins/reaper_drivenbymoss.dylib`
  - `~/Library/Application Support/REAPER/UserPlugins/drivenbymoss-libs/DrivenByMoss4Reaper-*.jar`

```
cd ~
xcode-select --install
brew install cmake openjdk@21
export JAVA_HOME="$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
ls "$JAVA_HOME/include/jni.h"
```

`xcode-select --install` ist nur nötig, wenn die Command Line Tools fehlen. Sind sie schon da, meldet der Befehl das und stört nicht. Die letzte Zeile muss den Pfad zu `jni.h` anzeigen, sonst stimmt etwas mit dem JDK nicht.

Die beiden `export`-Zeilen gelten nur für das Terminal-Fenster, in dem du sie ausführst. In einem neuen Fenster musst du sie wiederholen. Sind noch andere JDKs installiert (z. B. Temurin), nimmt CMake sonst das falsche und bricht mit „Could NOT find JNI" ab.

**1. C++-Backend** (nur nötig, wenn v0.4 noch nicht installiert ist)

```
cd ~
git clone https://github.com/git-moss/DrivenByMoss4Reaper-Backend.git
cd DrivenByMoss4Reaper-Backend
git checkout 26.6.5
git apply --whitespace=nowarn ~/Downloads/oxi-reaper-backend-v0.5.patch
rm -rf build
cmake -S CMake -B build -D CMAKE_BUILD_TYPE=Release -D JAVA_HOME="$JAVA_HOME"
cmake --build build
cp "$(find build -name reaper_drivenbymoss.dylib | head -1)" ~/Library/Application\ Support/REAPER/UserPlugins/
cd ~
```

**2. Java-Teil**

```
cd ~
git clone https://github.com/git-moss/DrivenByMoss4Reaper.git
cd DrivenByMoss4Reaper
git checkout 26.6.5
git apply --whitespace=nowarn ~/Downloads/oxi-reaper-java-v0.5.patch
./gradlew jar
cd ~
```

`./gradlew jar` baut `DrivenByMoss4Reaper-26.6.5.jar` und kopiert sie automatisch nach `UserPlugins/drivenbymoss-libs`. Dabei wird die gleichnamige Original-Datei überschrieben.
**Wichtig:** Dort darf nur eine `DrivenByMoss4Reaper-*.jar` liegen.

Danach Reaper starten. Zurück zur offiziellen Version: die beiden gesicherten Dateien zurückkopieren.

**Kontrolle nach dem Bauen**

Die geklonten Ordner (`DrivenByMoss4Reaper-Backend`, `DrivenByMoss4Reaper`) liegen in deinem Home-Ordner und **nicht** im Reaper-Ordner. In `UserPlugins` kommen nur zwei Dinge an: die `.dylib` und die `.jar`. So prüfst du das:

```
ls -l ~/Library/Application\ Support/REAPER/UserPlugins/
ls -l ~/Library/Application\ Support/REAPER/UserPlugins/drivenbymoss-libs/
```

- In `UserPlugins` steht `reaper_drivenbymoss.dylib` mit dem Datum vom Bauen, dazu der Ordner `drivenbymoss-libs`. Ein Ordner `DrivenByMoss4Reaper-Backend` oder `build` hat dort nichts zu suchen. Liegt einer da, hast du die Befehle aus diesem Ordner heraus ausgeführt. Verschiebe ihn in den Home-Ordner oder lösche ihn.
- In `drivenbymoss-libs` liegt genau eine `DrivenByMoss4Reaper-26.6.5.jar` mit dem Datum vom Bauen, daneben die übrigen Bibliotheken.

**Neu anfangen, wenn die Ordner verschachtelt sind**

Mit `pwd` siehst du, wo du gerade bist. Die geklonten Ordner findest du mit:

```
find ~ -maxdepth 5 -type d -name "DrivenByMoss4Reaper*"
```

Sind das nur Klone aus Versuchen und ist die `.dylib` bzw. `.jar` schon in `UserPlugins` kopiert, kannst du sie löschen (prüfe die Namen vorher genau):

```
cd ~
rm -rf DrivenByMoss4Reaper-Backend DrivenByMoss4Reaper
```

Danach beginnst du mit dem jeweiligen Block wieder bei `cd ~` und `git clone`.

---

## Bitwig: bauen und installieren (macOS)

Vorher die vorhandene `DrivenByMoss.bwextension` aus `~/Documents/Bitwig Studio/Extensions` sichern.

```
cd ~
brew install maven
git clone https://github.com/git-moss/DrivenByMoss.git && cd DrivenByMoss
git checkout 26.6.5
git apply --whitespace=nowarn ~/Downloads/oxi-bitwig-v0.5.patch
mvn clean install -Dbitwig.extension.directory="$HOME/Documents/Bitwig Studio/Extensions"
cd ~
```



**Fehler „unsubscribe called more times than subscribe":** Diese Meldung kam in v0.4 beim Start des Controllers. Mix 32 und Mix 64 teilen sich dieselbe Spurbank, und beide haben sie im Konstruktor einmal abgeschaltet. Bitwig zählt das mit und meldet den Fehler. In v0.5 merkt sich die Erweiterung den Zustand jeder Bank und schaltet sie nur bei einer echten Änderung (Klasse `OxiOneObservers`). Das ist aus dem Code abgeleitet. Ob es bei dir reicht, zeigt der erste Start in Bitwig.

Auf Bitwig zeigt Plugin 32 die Inserts der **ersten 32 Spuren der Seite**, so wie auch Mix 32 sie zeigt. Dafür legt die Erweiterung beim Start zusätzliche Geräte-Banks an. Aktiv beobachtet werden sie nur, solange Plugin 32 geöffnet ist.

---

## Neue Einstellungen

In Reaper in den DrivenByMoss-Einstellungen des OXI-One-Controllers, in Bitwig unter Controllers → OXI One. Gruppe **Mixer Views**:

| Einstellung | Optionen |
|---|---|
| Mute color / Solo color | Yellow, Blue, Red, Green, Orange, Pink, Purple, Cyan, Sky Blue, White |
| Show record arm row | On / Off |
| Track state rows | Mute & Solo / Mute only / Solo only |
| Mix 64: state row | Mute / Solo |
| Plugin Mixer: open plugin window | On first press / On second press / Never |
| Plugin Mixer: Shift + pad | Bypass (on/off) / Offline (on/off, Reaper) / Remove device |
| Plugin Mixer: Shift gesture | Move/Swap (action on Shift release) / Action immediately (no Move/Swap) |

Gruppe **Mixer Views - MIXER button** (neu in v0.5), je ein Häkchen pro Ansicht, alle standardmäßig an:

| Häkchen | Hinweis |
|---|---|
| Track Mixer | |
| Session | nur Mk2 |
| Plugin Mixer | |
| Mix 32 | |
| Plugin 32 | neu |
| Mix 64 | |

- Die MIXER-Taste schaltet nur durch die angehakten Ansichten, in der Reihenfolge aus der Gruppe „order".
- Sind alle Häkchen aus, bleibt der Track Mixer aktiv, die Taste funktioniert also immer.
- Steht die OXI gerade in einer abgewählten Ansicht (z. B. als Startansicht), springt der nächste Druck zur nächsten angehakten.
- Die Startansicht lässt sich unabhängig von den Häkchen wählen.
- Die Einstellungen kennen keine Mehrfachauswahl als Dropdown. Deshalb ist es eine Gruppe mit Häkchen.

Gruppe **Mixer Views - MIXER button order** (neu in v0.5), ein Auswahlfeld pro Position: **1st view** bis **6th view** (auf der Mk1 bis 5th view). Standard: Track Mixer, Session, Plugin Mixer, Mix 32, Plugin 32, Mix 64.

- Wähle für jede Position die Ansicht, die dort kommen soll. Am saubersten ist es, jede Ansicht genau einmal zu vergeben.
- Kommt eine Ansicht auf mehreren Positionen vor, zählt die erste. Ansichten, die auf keiner Position stehen, folgen am Ende in der Standardreihenfolge.
- Beispiel: **1st view = Plugin 32** und sonst nichts geändert ergibt Plugin 32, Session, Plugin Mixer, Mix 32, Mix 64, Track Mixer. Stellst du zusätzlich **2nd view = Track Mixer**, folgt der Track Mixer direkt auf Plugin 32.
- Abgewählte Ansichten (Häkchen aus) werden übersprungen, ihre Position bleibt aber erhalten.
Gruppe **Mixer Views - Colors**:

| Einstellung | Standard | Optionen |
|---|---|---|
| Clip color | Clip color (DAW) | DAW-Clipfarbe oder eine feste Farbe |
| Playing clip color | Green | feste Farbe |
| Recording clip color | Red | feste Farbe |
| Plugin color | Track color | Spurfarbe oder eine feste Farbe |
| Bypassed plugin color | Gray | feste Farbe |
| Offline plugin color | Red (dim) | feste Farbe |
| Plugin with open window color | White | feste Farbe |

Feste Farben: Yellow, Blue, Red, Green, Orange, Pink, Purple, Cyan, Sky Blue und White, jeweils hell oder „(dim)", dazu Gray und Off.

**Clipfarben:** Ja, die OXI übernimmt die Clipfarben aus der DAW, im Track Mixer und in der Session-Ansicht. Ausnahmen:
- Clips, die gerade spielen oder aufnehmen, zeigen die Abspiel- bzw. Aufnahmefarbe.
- Hat ein Clip keine Farbe, wird er orange.
- Mit einer festen „Clip color" werden alle gefüllten Slots in dieser Farbe angezeigt.

Jede ausgeblendete Zeile gibt dem Track Mixer eine Clip-Zeile mehr, maximal 6 Clip-Zeilen. Auf der Mk1 bleibt es bei 4 Zeilen, weil sie nur 4 Szenen hat.

## Ansichten auf der MIXER-Taste

MIXER schaltet der Reihe nach durch: standardmäßig **Track Mixer → Session → Plugin Mixer → Mix 32 → Plugin 32 → Mix 64**. Es kommen nur die angehakten Ansichten vor, in der eingestellten Reihenfolge (siehe oben). Auf der Mk1 entfällt Session. Alle neuen Ansichten lassen sich auch als Startansicht wählen.

### Shift zeigt die andere Zeile (Mute only / Solo only)

Steht „Track state rows" auf **Mute only**, zeigt gehaltenes Shift die **Solo**-Zeile an derselben Stelle. Bei **Solo only** zeigt Shift die **Mute**-Zeile. Das gilt im Track Mixer, Plugin Mixer, Mix 32 und Plugin 32. Bei „Mute & Solo" ändert Shift nichts.

- In Mix 64 gilt dasselbe für die eine Zeile („Mix 64: state row"): Shift zeigt die jeweils andere.
- Ein Pad wirkt auf die Zeile, die beim **Drücken** sichtbar war. Lässt du Shift vor dem Pad los, wird trotzdem Solo (bzw. Mute) geschaltet.
- Die Rec-Arm-Zeile und die Auswahlzeile ändern sich mit Shift nicht.

### Plugin Mixer

```
Zeile 1   Spur auswählen       (Spurfarbe, ausgewählt = blinkt weiß)
Zeile 2   Mute                 ┐
Zeile 3   Solo                 │ je nach Einstellung
Zeile 4   Rec Arm              ┘
Zeile 5–8 FX der Spur, von oben in der Reihenfolge der FX-Kette (4–6 Zeilen)
```

- **FX-Pads** (Standardfarben, alle einstellbar):
  - Spurfarbe = aktiv
  - Blinkt weiß = ausgewähltes FX
  - Blinkt schnell = Quelle einer Kopier-/Verschiebe-Aktion
  - Weiß = Fenster offen
  - Grau = Bypass
  - Dunkelrot = offline
  - Aus = leerer Slot
- **Pad drücken:** wählt Spur und FX aus (die Encoder steuern dann die Parameter). Je nach Einstellung öffnet das sofort oder beim zweiten Druck das FX-Fenster. Ein Druck auf ein offenes Fenster schließt es.
- **Hoch/Runter:** scrollt die FX aller sichtbaren Spuren um eins. Shift + Hoch springt zurück zum ersten FX.

### Plugin 32 (neu)

Zwei Blöcke à 16 Spuren, untereinander. Jeder Block hat 4 Zeilen: oben die Spur-Zeilen wie im Track Mixer eingestellt, die **freien Zeilen darunter zeigen die Inserts** der Spur, wie im Plugin Mixer.

```
Block oben   (Spur 1–16)    Zeile 1   Spur auswählen
                            Zeile 2…  Mute / Solo / Rec Arm, je nach Einstellung
                            Rest      FX der Spur
Block unten  (Spur 17–32)   Zeile 5   Spur auswählen
                            Zeile 6…  Mute / Solo / Rec Arm, je nach Einstellung
                            Rest      FX der Spur
```

**Wie viele FX-Zeilen du bekommst:** Das hängt an den Einstellungen für den Track Mixer. Pro Block ist mindestens eine Zeile für FX reserviert. Sind alle vier Spur-Zeilen eingestellt (Standard), entfällt dort zuerst Rec Arm, dann Solo.

| Einstellung | Zeilen pro Block |
|---|---|
| Standard (Mute & Solo, Rec Arm an) | Auswahl, Mute, Solo, **1 FX-Zeile** (Rec Arm entfällt) |
| Mute & Solo, Rec Arm aus | Auswahl, Mute, Solo, **1 FX-Zeile** |
| Mute only (oder Solo only), Rec Arm an | Auswahl, Mute, Rec Arm, **1 FX-Zeile** |
| Mute only (oder Solo only), Rec Arm aus | Auswahl, Mute, **2 FX-Zeilen** (Shift zeigt Solo) |

Für die meisten FX also: „Track state rows" auf **Mute only** oder **Solo only** und „Show record arm row" auf **Off**. Solo bzw. Mute erreichst du über Shift. Die Einstellungen gelten gemeinsam für Track Mixer, Plugin Mixer, Mix 32 und Plugin 32.

- **FX-Pads, Farben und Pad drücken:** wie im Plugin Mixer.
- **Links/Rechts:** blättert um 32 Spuren, Shift + Links/Rechts um 16 Spuren.
- **Hoch/Runter:** scrollt die FX aller 32 sichtbaren Spuren um eins. Shift + Hoch springt zurück zum ersten FX. Die Scrollposition der FX gehört zur Spur und ist im Plugin Mixer dieselbe.
- Beim Öffnen springt Plugin 32 auf den Bereich, in dem der Track Mixer gerade steht.

#### Insert-Slots bearbeiten (Plugin Mixer und Plugin 32)

Das geht über Spurgrenzen hinweg, innerhalb der sichtbaren Spuren (Plugin Mixer: 16, Plugin 32: 32).

| Geste | Display | Ergebnis |
|---|---|---|
| **COPY halten**, FX antippen, dann (COPY weiter gehalten) einen **leeren Slot** antippen | „Copy to? (+Shift: replace)" | Kopie am Ende der FX-Kette dieser Spur |
| … stattdessen ein **belegtes FX** antippen | | Kopie wird **davor eingefügt**, das FX rutscht eins weiter |
| … dabei zusätzlich **Shift** halten | „Replaced with …" | das FX wird durch die Kopie **ersetzt** |
| *Nur mit „Shift gesture: Move/Swap":* | | |
| **Shift halten**, FX antippen, dann ein **zweites FX** antippen | „Move/Swap?" | die beiden FX **tauschen** die Plätze |
| … stattdessen einen **leeren Slot** antippen | | FX wird ans Ende der Kette dieser Spur **verschoben** |
| **Shift halten**, FX antippen, **Shift loslassen** | | Shift-Aktion aus der Einstellung (Bypass / Offline / Entfernen) |
| *Mit „Shift gesture: Action immediately":* **Shift + FX** | | Shift-Aktion sofort, auch für mehrere FX nacheinander; kein Move/Swap |
| **PASTE halten**, FX antippen | | FX wird **gelöscht** |

- Solange COPY gehalten bleibt, kannst du die Quelle an mehrere Ziele kopieren.
- Ein zweites Antippen derselben Quelle mit Shift bricht ab, ebenso ein Pad in den Spurzeilen, Hoch/Runter oder ein Ansichtswechsel.
- Hat sich die Quelle inzwischen verändert (gescrollt, gelöscht, verschoben), zeigt das Display „Cancelled" und es passiert nichts.
- Jede Aktion ist **ein Undo-Schritt** in Reaper.
- Solange Shift für eine Geste gehalten wird, zeigen die Spur-Zeilen bei „Mute only" / „Solo only" die andere Zeile. Das ist nur Anzeige und stört die Geste nicht.

Leere Slots kann es mitten in der Kette nicht geben. „Leerer Slot" heißt deshalb immer: ans Ende der Kette.

### Mix 32

Zwei Blöcke à 16 Spuren, untereinander, ohne Launch-Buttons. Jeder Block hat 4 Zeilen: Auswahl, Mute, Solo, Rec Arm. Es gelten dieselben Einstellungen wie im Track Mixer; ausgeblendete Zeilen bleiben dunkel.

- **Links/Rechts:** blättert um 32 Spuren
- **Shift + Links/Rechts:** blättert um 16 Spuren

### Mix 64

Vier Blöcke à 16 Spuren mit je 2 Zeilen: Auswahl sowie Mute *oder* Solo (Einstellung „Mix 64: state row", Shift zeigt die andere).

- **Links/Rechts:** blättert um 64 Spuren
- **Shift + Links/Rechts:** blättert um 16 Spuren

**Für alle Mixer-Ansichten gilt:**
- Beim Öffnen springen Mix 32, Plugin 32 und Mix 64 auf den Bereich, in dem der Track Mixer gerade steht.
- Die Auswahlzeile funktioniert wie im Track Mixer:
  - Shift + Pad stoppt die Clips der Spur (nur in Bitwig).
  - **COPY halten + Pad** dupliziert die Spur.
  - **PASTE halten + Pad** löscht die Spur.
- Wenn du in den neuen Ansichten eine Spur auswählst, wechselt die OXI nicht automatisch in eine andere Ansicht.

## Was im Hintergrund passiert (Reaper)

- **Mix 32 / Mix 64:** Reaper schickt ohnehin die Daten aller Spuren. Die großen Mixer blättern nur lokal in derselben Spurliste wie der Track Mixer (flach bzw. aktueller Ordner).
- **Plugin Mixer und Plugin 32:** Das Backend sendet die FX-Liste **aller** Spuren (Name, Bypass, Offline, Fenster), aber **nur solange eine dieser beiden Ansichten aktiv ist**. Sonst entsteht keine zusätzliche Last.

## Grenzen

- **FX der Master-Spur** werden in den Plugin-Ansichten nicht angezeigt; ihre Spalte bleibt dunkel.
- **FX in Containern:** Nur die oberste Ebene der FX-Kette wird angezeigt.
- **Plugin 32:** Mit allen vier Spur-Zeilen bleibt nur eine FX-Zeile pro Block, siehe Tabelle oben.
- **Shift für andere Tasten:** Hast du mit Shift eine Quelle angetippt und benutzt dann Shift + eine andere Taste (z. B. MUTE), löst beim Loslassen von Shift trotzdem die Shift-Aktion aus.
- **Gepinnte Spur (Reaper):** Ist in DrivenByMoss eine Spur gepinnt, kann die Markierung des ausgewählten FX daneben liegen.
- **Bitwig kennt kein Offline:** Die Option „Offline" schaltet dort Bypass.
- **Tauschen in Bitwig:** Bitwig hat keinen eigenen Tausch-Befehl, deshalb sind es zwei Verschiebungen. Liegt das FX direkt vor dem Ziel außerhalb der sichtbaren Zeilen, meldet das Display „Not possible". Dann vorher mit Hoch/Runter scrollen.
- **Plugin 32 auf Bitwig:** Zeigt die FX nur für die ersten 32 Spuren der Seite (also genau die, die die Ansicht anzeigt).
