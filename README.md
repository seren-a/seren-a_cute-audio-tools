# midi-osc-matrix-monitor

> it's more fun when it looks girly

Echtzeit-Monitor für MIDI- und OSC-Datenströme, gebaut für den Arbeitsplatz von
Isabella Forster (Sound Engineering, Live, Recording, Komposition): Er zeigt,
was Controller, Synthesizer, Mischpulte und DAWs tatsächlich senden – als
fallender Glyphenregen im Look der cutiepro-Palette.

## Funktionen

- **Quellen:** Web-MIDI (Chrome/Edge/eingebaute App-Engine) und OSC über eine
  WebSocket-Bridge (UDP :8000). Eigener OSC-Dekoder: Messages und `#bundle`,
  Typen `i,f,s,b,T,F,N,I,h,t,d`, JSON `{address,args}` wird ebenfalls verstanden.
- **Vier Modi:** Raster · Gerät-Spalten · Mindmap (freie Canvas-Fläche, Pulse
  wandern bei jeder Nachricht vom Hub zum Knoten) · Fraktal (Treemap).
- **Überlauf invertiert:** Die regelmäßigsten Streams rutschen verdrängt in den
  kompakten Streifen unten mit, seltene Ereignisse werden hervorgehoben.
- **Zwölf Themes plus Auto-Modus** (folgt der Systemeinstellung hell/dunkel,
  live). Das gesamte Menü färbt im Theme mit; die Themen-Wahlfelder tragen
  jeweils ihr eigenes Farbschema.
- **Filter:** MIDI-Geräte, Kanäle, Nachrichtenarten, OSC-Adressbaum,
  Volltextsuche – alles einzeln abschaltbar.
- Sauberer Hintergrund: pro Frame deckend neu gesetzt, nichts brennt ein;
  Streams blenden aus und verschwinden nach 45 s Ruhe.

## Schnellstart

1. **Nur Browser:** `index.html` im Browser öffnen (Demo läuft sofort).
   Ohne Bridge bleibt OSC stumm; MIDI braucht Chrome/Edge (Web MIDI).
2. **Mit Bridge:** `node server/server.js 8080 8000`, dann Browser auf
   `http://localhost:8080` – die Seite verbindet sich automatisch.
3. **macOS-App:** siehe unten.

## Bedienung

| Taste | Wirkung |
| --- | --- |
| `F` | Filter-Seitenleiste ein/aus |
| `O` | Kopfzeilen ein/aus |
| `U` | gesamte Menüoberfläche ein/aus |
| `R` | Rahmen ein/aus (wenn an: blenden mit der Aktivität aus) |
| `C` | Clear (alles leeren) |

## OSC-Sender anschließen

Max/MSP/RNBO senden an `localhost:8000` (`[oscformat]` → `[udpsend localhost 8000]`,
RNBO-Runner: OSC remote). REAPER nutzt Port 8000 selbst → Brücke auf
`node server/server.js 8080 9001` starten und REAPER auf `udp://127.0.0.1:9001`
melden. Der Monitor wurde mit den OSC-Bäumen von REAPER, TotalMix FX, DiGiCo
und Yamaha DM7 abgestimmt (Beispiele in der Demo).

## Eigenständige macOS-App (Apple Silicon)

```bash
node app/build-app.js
```

Das Skript lädt die Chromium-Laufzeit, baut `Matrix Monitor.app` und das
fertige ZIP im Ordner `build/` – reproduzierbar und ohne npm-Abhängigkeiten.
Die App bietet ein eigenes Fenster mit eigenem Dock-Symbol, ohne Browser und
ohne installiertes Node.js; die OSC-Bridge läuft eingebettet, Web-MIDI ist
verfügbar. Ist der OSC-Port 8000 belegt, weicht die App automatisch auf 9001
aus. Ports und Fenstergröße beim Start:

```bash
open -a "Matrix Monitor" --env MM_PORT=8080 MM_UDP=9001
```

Die App ist nicht notarisiert: Erster Start über Doppelklick, dann
Systemeinstellungen → Datenschutz & Sicherheit → «Trotzdem öffnen».

Wer lieber das leichte Bündel mit installiertem Node.js nutzt:
`bash app/launcher-light.sh` (öffnet bevorzugt ein reduziertes Firefox-Fenster,
alternativ Chrome/Edge im App-Modus).

## Projektstruktur

```
index.html                      Monitor-Seite (eine Datei, offline lauffähig)
server/server.js                HTTP + WebSocket + OSC-UDP-Bridge (ohne npm)
app/main.js                     Hauptprozess der eigenständigen App
app/build-app.js                App-Bau (lädt Chromium-Laufzeit, packt das ZIP)
app/make-icon.py                App-Symbol (reine Standardbibliothek)
app/launcher-light.sh           Leichtes App-Bündel (`bash app/…`) mit installiertem Node.js
anleitung/anleitung.md          Kurzanleitung (Textfassung)
anleitung/anleitung-girly.html  Kurzanleitung, Girly Edition (girly pink /
                                girly dark, folgt der Systemeinstellung)
```

## Lizenz

GPL-3.0 – siehe [LICENSE](LICENSE).