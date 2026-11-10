# Matrix Monitor · Kurzanleitung

## 1 · Ordner

Ein Ordner, zwei Dateien, beide zusammen:

| Datei | Rolle |
| --- | --- |
| `server.js` | Programm · Seite, WebSocket, OSC-Bridge (UDP) |
| `index.html` | Monitor-Seite · Name exakt so lassen |

## 2 · Start

1. Terminal öffnen.
2. `node -v` — erscheint eine Versionsnummer, passt alles. Sonst einmalig den Installer von nodejs.org ausführen.
3. `cd` tippen, Leertaste, den Ordner ins Terminal ziehen, Eingabetaste.
4. `node server.js`
5. Browser auf `http://localhost:8080`

Beenden mit `Strg + C`. Jeder weitere Start: nur Schritt 4.

Ports frei wählbar:

```
node server.js [Seiten-Port] [OSC-Port]
```

## 3 · Bedienung

| Element | Wirkung |
| --- | --- |
| `Filter` / `Oben` / `Rahmen` / `UI` (rechts oben) | Seitenleiste · Kopfzeilen · Blockrahmen · alle Menüleisten wegklappen |
| `F` · `O` · `U` · `R` · `C` | Filter · Kopfzeilen · Menüs · Rahmen an/aus · Clear |
| `Demo an/aus` | Probetakte ohne angeschlossene Geräte |
| `MIDI verbinden` | Web-MIDI, Systemabfrage bestätigen (Chrome/Edge; Firefox bietet kein Web MIDI) |
| `FARBE: auto` | folgt hell/dunkel der Systemeinstellung, live; das Menü färbt im Theme mit |
| `GRUPPIERUNG` | Raster · Gerät-Spalten · Mindmap (freie Fläche) · Fraktal |

Regelmäßigste Streams rutschen bei Andrang in den kompakten Streifen unten. Seltene Ereignisse werden hervorgehoben; die Rahmen (Taste `R`) lassen sich ganz ausblenden und blenden, wenn an, mit der Aktivität aus.

## 4 · OSC-Sender anschließen

Alle Geräte senden UDP an denselben Rechner, auf dem der Server läuft — Standardport `8000`:

| Quelle | Einstellung |
| --- | --- |
| REAPER | OSC-Gerät, Rückmeldung an `udp://127.0.0.1:8000` |
| TotalMix FX | Remote-Ziel auf Server-IP, Port `8000` |
| DiGiCo | Über Companion/OSC-Hub auf `8000` |
| Yamaha DM7 | OSC-Ziel auf `8000` |
| Max/MSP | `[oscformat]` → `[udpsend <ip> 8000]` |
| RNBO Runner | OSC remote aktivieren, Host = Server, Port `8000` |

## 5 · Port-Konflikt (REAPER)

REAPER belegt `8000` selbst, sobald dessen OSC aktiv ist. Dann:

```
node server.js 8080 9001
```

und in REAPER die Rückmeldung auf `udp://127.0.0.1:9001` stellen. Beide laufen parallel, keiner stört den anderen. Das Programm meldet Belegungen von selbst und nennt den Ausweg.

## 6 · LAN

Im Startbanner stehen die Adressen: `http://<mac-ip>:8080`. Jedes Gerät im selben Netz öffnet nur den Browser, Installation entfällt. macOS fragt einmalig nach Firewall-Freigabe für node — erlauben.

## 7 · Wenn etwas schweigt

| Symptom | Prüfen |
| --- | --- |
| Seite bleibt leer | Demo-Taste: Darstellung funktioniert, Verbindung folgt |
| MIDI fehlt | Chrome/Edge verwenden, Abfrage bei „MIDI verbinden“ bestätigen |
| OSC leer | Ziel-IP und Port im Sender gegen Startbanner vergleichen |
| Streams verschwunden | Taste `C` oder Filter zurücksetzen (`reset`) |

## 8 · Als App (ohne Terminal)

### Eigenständige App (Version 2)

«Matrix Monitor.app» der Version 2 ist eine vollwertige, eigenständige App: eigene Fenster-Instanz mit eigenem Dock-Symbol, ohne Browser, ohne Firefox-Profil und ohne installiertes Node.js. Die OSC-Bridge läuft eingebettet im App-Prozess, Web-MIDI ist über die eingebaute Chromium-Engine verfügbar.

| Schritt | Aktion |
| --- | --- |
| 1 | ZIP entpacken, `Matrix Monitor.app` in den Programme-Ordner legen |
| 2 | Erster Start: Doppelklick; macOS fragt nach → Systemeinstellungen → Datenschutz & Sicherheit → «Trotzdem öffnen» (App ist nicht notarisiert) |
| 3 | Fenster öffnet sich; OSC verbindet sich automatisch mit der eingebauten Bridge |
| 4 | Beenden über das Fenster (rote Taste) oder Dock → «Beenden» |

Ist der OSC-Port 8000 belegt (REAPER nutzt ihn selbst), weicht die App automatisch auf 9001 aus. Ports und Fenstergröße beim Start wählbar:

```
open -a "Matrix Monitor" --env MM_PORT=8080 MM_UDP=9001
```

### Leichte Variante (mit installiertem Node.js)

Das Programmbündel «Matrix Monitor.app» enthält alles: Seite, Server und Bridge.

| Schritt | Aktion |
| --- | --- |
| 1 | ZIP entpacken, `Matrix Monitor.app` in den Programme-Ordner legen |
| 2 | Erster Start: Rechtsklick → «Öffnen» → bestätigen (macOS Vertrauensfrage) |
| 3 | Doppelklick startet die App, ein eigenständiges Fenster öffnet sich (bevorzugt Firefox mit reduzierter Oberfläche; alternativ Chrome/Edge im App-Modus; sonst Tab im Standardbrowser) |
| 4 | Beenden über das Dock-Icon → «Beenden» stoppt auch den Server |

Voraussetzung bleibt einmalig Node.js — am einfachsten der LTS-Installer von nodejs.org (er installiert nach `/usr/local/bin`, wo die App ihn sicher findet). Die App erkennt Node zusätzlich bei Homebrew- und nvm-Installationen, auch wenn sie aus dem Dock gestartet wird. Die App läuft ohne sichtbares Terminal; Meldungen stehen im Logfile `matrix-monitor.log` (Ordner `~/Library/Logs`). Ports beim Start wählbar:

```
MM_PORT=8080 MM_UDP=9001 open -a "Matrix Monitor"
```

Die Firewall-Rückfrage beim ersten Start bestätigen, dann sind auch die LAN-Geräte wieder dabei.