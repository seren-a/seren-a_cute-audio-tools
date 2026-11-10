# Fehlersuche · 3 Schritte, ca. 10 Minuten

Ziel: herausfinden, an welcher Stelle es hängt (Netzwerk/Bridge, DAW-Skript oder Oberfläche).
Schick mir danach die drei Ergebnisse (Text oder Fotos).

## Schritt 1 · Kommt am Gerät überhaupt etwas an? (Bridge-Test)
1. `Bridge-Test.tosc` auf **Handy und iPad** öffnen (Play-Modus).
2. TouchOSC › Verbindungen prüfen, auf **beiden** Geräten:
   - Bridge-Tab: Verbindung 1 an, Host = dein Mac (Name oder IP).
   - MIDI-Tab: Verbindung 1 an, **Send Port = Bridge 1**, **Receive Port = Bridge 1**.
3. **TEST SENDEN** drücken.
Die Oberfläche zeigt jede ankommende Nachricht mit Verbindungsnummer. Oben steht, wie viele schon da sind.

## Schritt 2 · Reaper
1. Das laufende `Reaper_3D.lua` beenden (Actions-Liste: Skript nochmal starten → „Terminate“).
2. Actions › Show action list › New action › Load ReaScript › `Reaper_Diagnose.lua`, dann ausführen.
3. Während der 30 Sekunden schauen, was im Bridge-Test am Handy und iPad auftaucht:
   - `Test cmd 2 "REAPER n"`
   - `CC Kanal 16 #100`
   - `CC Kanal 16 #101`
   Dabei einmal TEST SENDEN drücken.
4. Danach das Konsolenfenster („ReaScript console output“): alles markieren, kopieren und mir schicken.
5. Dann das **neue** `Reaper_3D.lua` aus 3_Reaper starten (es ersetzt das alte, gleiche Datei überschreiben).

## Schritt 3 · Nuendo
1. Den Ordner `serena` aus 2_Nuendo-Cubase in den MIDI-Remote-Ordner „Local“ kopieren (vorhandene Dateien ersetzen).
2. Nuendo: Studio › MIDI Remote Manager › Reiter **Skripte** › **Skripte neu laden**.
3. Reiter **MIDI-Controller**: Steht dort „serena TouchOSC3D“?
   - Welche Ports sind eingetragen? Foto.
   - Steht dort auch „serena MFTView“ oder ein altes seren.a-Gerät? Foto.
4. **Skript-Konsole** öffnen (MIDI Remote Manager › Skripte, oder unten in der Zone „MIDI Remote“ › Skript-Werkzeuge). Dort steht im Idealfall:
   - `[seren.a 3D] Skript v3 geladen`
   - `[seren.a 3D] aktiv - sende an TouchOSC Bridge …`
   - Zeilen wie `Spur 1 … Insert 4: StereoEncoder (Azimuth P7, …)`
   - Rote Fehlerzeilen bitte mit abfotografieren.
5. Bridge-Test am Handy dabei offen lassen. Kommt etwas mit „seren.a 3D“ an?

## Was ich schon geändert habe
- Reaper (3D und Twister): Werte, Auswahl und Pegel gehen jetzt auf demselben Weg raus wie die Spurnamen.
  Die Spurnamen kamen bei dir ja an, die Werte nicht. Der alte Weg war vermutlich das Problem.
- Nuendo-Skripte schreiben jetzt in die Skript-Konsole, was sie tun.

## Zur Frage „OSC im Plugin aktivieren?“
Für Panner_Skript, Objekt-Übersicht und IEM-Space: **nein**. Die reden nur über die Bridge mit dem
DAW-Skript, OSC im Plugin bleibt aus. OSC im Plugin brauchst du nur für die Panner_OSC-Fassungen
(StereoEncoder: Listen 8001, Sender Handy-IP 9101 · Rotator 8002/9102 · MultiEncoder 8003/9103).
