#!/bin/bash
# Matrix Monitor – leichtes App-Bündel (benötigt installiertes Node.js).
# Ports wählbar: MM_PORT=8080 MM_UDP=9001 open -a "Matrix Monitor"
# Fenster: bevorzugt Firefox (eigenes Profil ohne Tab-/Adressleiste),
# alternativ Chrome/Edge im App-Modus, sonst Tab im Standardbrowser.
# Einrichtung: dieses Skript, server/server.js und index.html liegen im
# selben Ordner «Matrix Monitor.app/Contents/Resources/».
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$HOME/Library/Logs/matrix-monitor.log"
MM_PORT="${MM_PORT:-8080}"
MM_UDP="${MM_UDP:-8000}"
MM_WIDTH="${MM_WIDTH:-1440}"
MM_HEIGHT="${MM_HEIGHT:-900}"

NODE_BIN="$(command -v node 2>/dev/null || true)"
if [ -z "$NODE_BIN" ]; then
  for KAND in /usr/local/bin/node /opt/homebrew/bin/node "$HOME/.volta/bin/node" "$HOME"/.nvm/versions/node/*/bin/node; do
    if [ -x "$KAND" ]; then NODE_BIN="$KAND"; break; fi
  done
fi
if [ -z "$NODE_BIN" ]; then
  osascript -e 'display alert "Matrix Monitor benötigt Node.js" message "Bitte einmalig die LTS-Version von nodejs.org installieren und die App erneut öffnen." as critical' 2>/dev/null
  exit 1
fi

echo "── Matrix Monitor Start $(date '+%Y-%m-%d %H:%M:%S') ──" >> "$LOG"
"$NODE_BIN" "$DIR/server.js" "$MM_PORT" "$MM_UDP" >> "$LOG" 2>&1 &
SRV=$!
sleep 1
if ! kill -0 "$SRV" 2>/dev/null; then
  osascript -e "display alert \"Matrix Monitor konnte nicht starten\" message \"Ein Port ist belegt. Details stehen im Logfile: $LOG — Abhilfe: andere Ports beim Start wählen, z.B. MM_PORT=8080 MM_UDP=9001\" as critical" 2>/dev/null
  exit 1
fi

URL="http://localhost:$MM_PORT/"
WIN=""

FFAPP=""
for FF in /Applications/Firefox.app ~/Applications/Firefox.app; do
  if [ -d "$FF" ]; then FFAPP="$FF"; break; fi
done
if [ -n "$FFAPP" ]; then
  PROF="$HOME/.matrix-monitor-firefox"
  mkdir -p "$PROF/chrome"
  printf '%s\n' \
    'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' \
    'user_pref("browser.shell.checkDefaultBrowser", false);' \
    > "$PROF/user.js"
  cat > "$PROF/chrome/userChrome.css" <<'CSS'
#nav-bar, #PersonalToolbar { visibility: collapse !important; }
#tabbrowser-tabs { visibility: collapse !important; }
#TabsToolbar #new-tab-button, #TabsToolbar #alltabs-button { display: none !important; }
CSS
  if open -na "$FFAPP" --args -profile "$PROF" -no-remote -width "$MM_WIDTH" -height "$MM_HEIGHT" "$URL" 2>/dev/null; then
    WIN="firefox"
  fi
fi

if [ -z "$WIN" ]; then
  if open -na "Google Chrome" --args "--app=$URL" "--window-size=$MM_WIDTH,$MM_HEIGHT" 2>/dev/null; then
    WIN="chrome"
  elif open -na "Microsoft Edge" --args "--app=$URL" "--window-size=$MM_WIDTH,$MM_HEIGHT" 2>/dev/null; then
    WIN="edge"
  fi
fi
if [ -z "$WIN" ]; then
  open "$URL"
fi

trap 'kill "$SRV" 2>/dev/null' EXIT
wait "$SRV"