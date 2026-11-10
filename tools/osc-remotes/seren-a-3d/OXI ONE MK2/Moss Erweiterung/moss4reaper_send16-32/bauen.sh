#!/bin/bash
# seren.a: DrivenByMoss4Reaper mit OXI-Erweiterungen (Mix 32/64, Plugin 32, Send 16/32) bauen
# Aufruf im Terminal:  bash bauen.sh
# Danach liegt das Jar automatisch in ~/Library/Application Support/REAPER/UserPlugins/drivenbymoss-libs
set -e
HIER="$(cd "$(dirname "$0")" && pwd)"
ZIEL="$HOME/DrivenByMoss4Reaper"
BASIS=30f6cb3d   # DrivenByMoss4Reaper 26.6.5 = die veröffentlichte Version (passt zum installierten C++-Teil)

if [ ! -d "$ZIEL/.git" ]; then
  git clone https://github.com/git-moss/DrivenByMoss4Reaper.git "$ZIEL"
fi
cd "$ZIEL"

# eigene Änderungen sichern, falls schon welche drin sind
if [ -n "$(git status --porcelain)" ]; then
  git stash push -u -m "seren_sicherung_$(date +%y%m%d-%H%M)"
  echo "Bisherige Änderungen gesichert: git stash list"
fi

git fetch -q origin
git checkout -q "$BASIS"
git apply "$HIER/seren_oxi_reaper.patch"
echo "Patch eingespielt."

# alte Jars sichern (auch ein früher gebautes 26.7.0)
LIBS="$HOME/Library/Application Support/REAPER/UserPlugins/drivenbymoss-libs"
if ls "$LIBS"/DrivenByMoss4Reaper-*.jar >/dev/null 2>&1; then
  mkdir -p "$LIBS/../drivenbymoss-libs_sicherung"
  for j in "$LIBS"/DrivenByMoss4Reaper-*.jar; do       # das erste Original bleibt erhalten
    n=$(basename "$j"); z="$LIBS/../drivenbymoss-libs_sicherung/$n"
    [ -e "$z" ] && z="$LIBS/../drivenbymoss-libs_sicherung/${n%.jar}_$(date +%y%m%d-%H%M).jar"
    mv "$j" "$z"
  done
  echo "Altes Jar verschoben nach UserPlugins/drivenbymoss-libs_sicherung (sonst laden zwei Versionen)"
fi

./gradlew jar --rerun-tasks
echo "Fertig. Reaper neu starten."
