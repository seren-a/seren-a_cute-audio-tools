#!/usr/bin/env bash
# Baut das ambisonic-loudness-meter-Plugin (AU + VST3 auf macOS, VST3 auf Linux).
# JUCE wird automatisch geklont, falls noch nicht vorhanden.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JUCE_VERSION="8.0.8"
JUCE_DIR="$SCRIPT_DIR/JUCE"
BUILD_DIR="$SCRIPT_DIR/build"

if [ ! -d "$JUCE_DIR" ]; then
    echo ">> Klone JUCE $JUCE_VERSION ..."
    git clone --depth 1 --branch "$JUCE_VERSION" \
        https://github.com/juce-framework/JUCE.git "$JUCE_DIR"
fi

echo ">> Konfiguriere ..."
cmake -S "$SCRIPT_DIR" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release "$@"

echo ">> Baue ..."
cmake --build "$BUILD_DIR" --parallel "$(sysctl -n hw.ncpu 2>/dev/null || nproc)"

OS="$(uname -s)"
if [ "$OS" = "Darwin" ]; then
    echo ""
    echo ">> Fertig. Artefakte:"
    find "$BUILD_DIR" -name "*.aupa" -o -name "*.vst3" | sed 's/^/   /'
    cat <<'HINWEIS'

Plugin installieren (macOS):
   cp -R <Pfad-zu-ambisonic-loudness-meter.artcomponent>/  \
      ~/Library/Audio/Plug-Ins/Components/
   cp -R <Pfad-zu-ambisonic-loudness-meter.vst3>/  \
      ~/Library/Audio/Plug-Ins/VST3/
HINWEIS
else
    echo ""
    echo ">> Fertig. VST3-Artefakt:"
    find "$BUILD_DIR" -name "*.vst3" | sed 's/^/   /'
    echo "   (AU ist nur auf macOS moeglich)"
fi
