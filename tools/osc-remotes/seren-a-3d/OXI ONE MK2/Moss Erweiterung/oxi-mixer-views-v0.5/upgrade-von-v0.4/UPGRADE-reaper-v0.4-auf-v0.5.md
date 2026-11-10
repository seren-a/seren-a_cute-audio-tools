# Upgrade Reaper: v0.4 auf v0.5

Für alle, die v0.4 schon gebaut haben und nur auf v0.5 aktualisieren wollen.

## Was du brauchst

| | |
|---|---|
| **Nötig** | `oxi-reaper-java-v0.5.patch` (kompletter Patch gegen das saubere Release 26.6.5) **oder** `oxi-reaper-java-v0.4-auf-v0.5.patch` (nur die Änderungen von v0.4 auf v0.5) |
| **Nicht nötig** | `oxi-reaper-backend-v0.5.patch`. Das C++-Backend ist unverändert gegenüber v0.4. Deine installierte `reaper_drivenbymoss.dylib` aus v0.4 bleibt, wie sie ist. |
| **Schon vorhanden** | Homebrew, cmake, openjdk@21 und die Command Line Tools aus der ersten Installation. Es muss nichts neu installiert werden. |

Was sich ändert: nur die Datei `DrivenByMoss4Reaper-26.6.5.jar` in `UserPlugins/drivenbymoss-libs`.

## Vorher

1. Reaper beenden.
2. Die aktuelle Jar sichern (z. B. auf den Schreibtisch kopieren):
   `~/Library/Application Support/REAPER/UserPlugins/drivenbymoss-libs/DrivenByMoss4Reaper-26.6.5.jar`
3. In einem neuen Terminal-Fenster `JAVA_HOME` setzen (gilt nur für dieses Fenster):

```bash
export JAVA_HOME="$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home"
```

## Weg A: neu bauen mit dem kompletten Patch (empfohlen)

Funktioniert immer, egal in welchem Zustand dein alter Ordner ist.

```bash
cd ~
git clone https://github.com/git-moss/DrivenByMoss4Reaper.git DrivenByMoss4Reaper-v0.5
cd DrivenByMoss4Reaper-v0.5
git checkout 26.6.5
git apply --whitespace=nowarn ~/Downloads/oxi-reaper-java-v0.5.patch
./gradlew jar
cd ~
```

Schau nach `git apply` auf die Ausgabe. Eine Fehlermeldung heißt meist, dass der Patch nicht in `~/Downloads` liegt. Dann nicht weiterbauen. Gibt es den Ordner `DrivenByMoss4Reaper-v0.5` schon, benenne ihn vorher um.

## Weg B: bestehenden Ordner aktualisieren

Nur wenn dein bisheriger Ordner `DrivenByMoss4Reaper` noch genau den Stand 26.6.5 + `oxi-reaper-java.patch` (v0.4) hat und du nichts daran geändert hast.

```bash
cd ~/DrivenByMoss4Reaper
git apply --whitespace=nowarn ~/Downloads/oxi-reaper-java-v0.4-auf-v0.5.patch
./gradlew jar
cd ~
```

Liegt dein Ordner `DrivenByMoss4Reaper` nicht im Home-Ordner, passe den Pfad in der ersten Zeile an.

Kommt eine Fehlermeldung beim `git apply`, ist der Ordner nicht im erwarteten Zustand. Dann Weg A nehmen. Der Patch wird bei einem Fehler komplett abgelehnt, es bleibt also nichts halb angewendet.

## Danach

- `./gradlew jar` überschreibt die Jar in `UserPlugins/drivenbymoss-libs` automatisch.
- **Wichtig:** Dort darf nur eine `DrivenByMoss4Reaper-*.jar` liegen.
- Reaper starten und in den DrivenByMoss-Einstellungen des OXI One prüfen, ob die neuen Gruppen da sind: **Mixer Views - MIXER button** und **Mixer Views - MIXER button order**.
- Die neuen Häkchen stehen standardmäßig alle auf an, die Reihenfolge ist die Standardreihenfolge.

## Zurück auf v0.4

Die gesicherte Jar zurück nach `UserPlugins/drivenbymoss-libs` kopieren (die vorhandene ersetzen). Das Backend musst du dafür nicht anfassen.
