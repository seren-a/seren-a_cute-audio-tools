# Reaper-Backend v0.5.1: Kopieren, Ersetzen, Verschieben, Tauschen

## Das Problem in v0.5

Der Java-Teil schickt für die Plugin-Mixer-Gesten (COPY, COPY + Shift, Shift-Move/Swap) den Befehl

```
/track/{Spur}/fx/{FX}/edit  "copy|replace|move|swap {Zielspur} {Ziel-FX}"
```

Das C++-Backend v0.5 hat dafür keinen Empfänger. Es verarbeitet unter `/track/…/fx/…` nur `remove`, `duplicate`, `select`, `bypass`, `offline` und `window`. Der Textbefehl `edit` landet in einer Funktion, die nur `color`, `name` und `clip` kennt. Deshalb zeigt die OXI zwar „Copy to?“ bzw. „Move/Swap?“, in Reaper passiert aber nichts.

Was in v0.5 funktioniert: Auswählen, Bypass, Offline, Fenster, Löschen mit PASTE, Spur duplizieren/löschen.

## Der Fix

`oxi-reaper-backend-v0.5-auf-v0.5.1.patch` ergänzt in `TrackProcessor.cpp` einen Empfänger für `fx/…/edit` (92 Zeilen, nur diese eine Datei). Jede Geste ist ein Undo-Schritt.

| Befehl | Ergebnis in Reaper |
|---|---|
| `copy` | Kopie vor dem Ziel-FX einfügen, bei -1 ans Ende der Kette |
| `replace` | Kopie vor dem Ziel-FX einfügen, danach das alte Ziel-FX löschen |
| `move` | FX vor das Ziel-FX verschieben, bei -1 ans Ende (andere Spur oder gleiche Spur) |
| `swap` | Die beiden FX tauschen die Plätze (gleiche Spur oder zwei Spuren) |

Geprüft: Der Patch lässt sich auf v0.5 und, als Komplett-Patch `oxi-reaper-backend-v0.5.1.patch`, auf das saubere Release 26.6.5 anwenden. `TrackProcessor.cpp` kompiliert damit fehlerfrei (Syntax-Check unter Linux mit den Reaper-Headern aus dem Repo). In Reaper getestet ist er noch nicht.

**Bitte beim ersten Test prüfen:** Verschieben innerhalb derselben Spur. Reapers `TrackFX_CopyToTrack` bekommt dort die Endposition des FX. Landet ein FX eins zu weit links oder rechts, ist genau diese Stelle zu korrigieren (`finalIndex` im Abschnitt `move`).

## Bauen (nur Backend, Java-Teil bleibt)

Reaper beenden, die vorhandene `reaper_drivenbymoss.dylib` sichern. Dann in einem neuen Terminal:

```
export JAVA_HOME="$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
```

**Weg A: frisch klonen (empfohlen)**

```
cd ~
git clone https://github.com/git-moss/DrivenByMoss4Reaper-Backend.git DrivenByMoss4Reaper-Backend-v0.5.1
cd DrivenByMoss4Reaper-Backend-v0.5.1
git checkout 26.6.5
git apply --whitespace=nowarn ~/Downloads/oxi-reaper-backend-v0.5.1.patch
rm -rf build
cmake -S CMake -B build -D CMAKE_BUILD_TYPE=Release -D JAVA_HOME="$JAVA_HOME"
cmake --build build
cp "$(find build -name reaper_drivenbymoss.dylib | head -1)" ~/Library/Application\ Support/REAPER/UserPlugins/
cd ~
```

**Weg B: bestehenden v0.5-Ordner ergänzen** (nur wenn er genau 26.6.5 + v0.5 enthält)

```
cd ~/DrivenByMoss4Reaper-Backend
git apply --whitespace=nowarn ~/Downloads/oxi-reaper-backend-v0.5-auf-v0.5.1.patch
cmake --build build
cp "$(find build -name reaper_drivenbymoss.dylib | head -1)" ~/Library/Application\ Support/REAPER/UserPlugins/
cd ~
```

Wie bei v0.5: Nach `git apply` darf keine Fehlermeldung kommen. Die Patch-Dateien vorher nach `~/Downloads` legen.

## Hinweis zur Jar im ZIP

Die `DrivenByMoss4Reaper-26.6.5.jar` im ZIP `reaper_drivenbymoss_serena_v0_5.zip` (Stand 24.10., 15:08) enthält Plugin 32 und die MIXER-Reihenfolge, aber **nicht** die Klasse `OxiOneObservers`, die der Patch `oxi-reaper-java-v0.5.patch` mitbringt. Sie ist also aus einem etwas älteren Zwischenstand gebaut. Für Reaper ist der Unterschied klein (die Klasse behebt vor allem den Bitwig-Fehler „unsubscribe called more times than subscribe“), für einen sauberen Stand lohnt sich trotzdem einmal Weg A aus dem v0.5-Upgrade-Dokument für den Java-Teil.
