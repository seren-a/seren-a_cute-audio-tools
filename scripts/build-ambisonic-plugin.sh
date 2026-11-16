#!/usr/bin/env bash
# Baut den DSP-Kern-Test und das AU/VST3-Plugin des ambisonic-loudness-meter.
#
# Aufruf (ab Repo-Wurzel):  scripts/build-ambisonic-plugin.sh
# Umgebungsvariablen:       JUCE_DIR=/pfad/zu/JUCE  (sonst wird JUCE nach <repo>/JUCE geclont)
#                           CXX=c++                (Compiler fuer die DSP-Tests)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/tools/ambisonic-loudness-meter"
PLUGIN="$TOOL/plugin"
BUILD="$PLUGIN/build"
JUCE_DIR="${JUCE_DIR:-$ROOT/JUCE}"
CXX="${CXX:-c++}"

echo "== 1) DSP-Kern-Tests (ohne JUCE) =="
mkdir -p "$BUILD"
"$CXX" -std=c++17 -O2 -Wall -I"$PLUGIN/src/dsp" \
    "$PLUGIN/src/dsp/DspTests.cpp" -o "$BUILD/dsp_tests"
"$BUILD/dsp_tests"

# Psychoakustik-Tests gegen mosqito-Referenzen, falls vorhanden
if [ -n "${PSY_REF_DIR:-}" ] && [ -f "$PSY_REF_DIR/psy_signals.bin" ]; then
    echo "== 1b) Psychoakustik-Tests gegen mosqito-Referenzen =="
    "$CXX" -std=c++17 -O2 -Wall -I"$PLUGIN/src/dsp" \
        "$PLUGIN/src/dsp/PsyTests.cpp" -o "$BUILD/psy_tests"
    "$BUILD/psy_tests" "$PSY_REF_DIR/psy_signals.bin" "$PSY_REF_DIR/psy_ref.txt"
fi

if [ ! -f "$JUCE_DIR/CMakeLists.txt" ]; then
    echo "== 2) JUCE holen nach $JUCE_DIR =="
    git clone --depth 1 https://github.com/juce-framework/JUCE.git "$JUCE_DIR"
fi

echo "== 3) Plugin konfigurieren und bauen (VST3 + AU auf macOS) =="
cmake -S "$PLUGIN" -B "$BUILD" -DJUCE_DIR="$JUCE_DIR" -DCMAKE_BUILD_TYPE=Release
cmake --build "$BUILD" --config Release

echo "== 4) Artefakte =="
find "$BUILD" \( -name '*.vst3' -o -name '*.component' \) -print
echo "Fertig."
