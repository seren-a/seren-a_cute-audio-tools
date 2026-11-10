/* ============================================================================
   MATRIX MONITOR – SERVER  (Start: node server.js)
   Ein Programm, alles drin: HTTP-Auslieferung + WebSocket + OSC-UDP-Bridge.
   Keine npm-Abhängigkeiten, nur Node.js (>= 16).

   EINRICHTUNG (einmalig)
     1. Diese Datei als  server.js  speichern.
     2. Die Matrix-Monitor-HTML-Canvas als  index.html  in denselben Ordner exportieren.
     3. Start:            node server.js            (optional: node server.js 9090)
        Ports frei wählbar: node server.js [HTTP-Port] [OSC-UDP-Port]
        Standard:          HTTP 8080 · OSC-UDP 8000
        OSX/PORT-Umgebung: PORT=8080 UDP_PORT=8000 node server.js

   PORT-KONFLIKTE (wichtig!)
     UDP 8000 ist auch REAPERs Standard-OSC-Port. Läuft REAPER mit aktiviertem
     OSC auf demselben Rechner, belegt es den Port bereits – dann den Monitor
     auf einen freien Port legen und REAPER-Feedback dorthin schicken:
         node server.js 8080 9001
         REAPER: OSC-Gerät → lokale Adresse udp://127.0.0.1:9001
     Ebenso prüfen: TouchOSC (Standard 8000) und OSC-Router.
     Die Meldung »Port bereits belegt« im Terminal nennt den Ausweg.
     TotalMix (7001/7002), DiGiCo (TCP) und DM7 werden nicht berührt,
     sofern deren Ports nicht auf den Monitor-UDP-Port gestellt werden.

   BEDIENUNG
     Browser lokal:      http://localhost:8080
     Browser im LAN:     http://<Mac-IP>:8080     (IPs stehen im Startbanner)
     OSC-Sender:         REAPER, TotalMix, DiGiCo, Yamaha, Max/MSP, RNBO …
                         alle senden per UDP auf Port 8000 dieser Maschine.
                         Die Seite verbindet sich beim Hosting automatisch
                         mit der Bridge – das wsUrl-Feld kann ignoriert werden.
     Max/MSP konkret:    [oscformat] Adresse,Wert → [udpsend localhost 8000]
     RNBO Runner:        OSC remote aktivieren, Host = dieser Mac, Port 8000.

   ALS MAC-PROGRAMM STARTEN (ohne Terminal)
     Datei  start.command  neben server.js anlegen:
         #!/bin/bash
         cd "$(dirname "$0")" && node server.js
     Im Terminal einmalig:  chmod +x start.command
     Danach genügt Doppelklick im Finder. Hinweis: Port 8080/8000 im
     macOS-Firewall-Dialog für eingehende Verbindungen erlauben (LAN).

   ALS EINE EINZIGE BINARY (Mac-App, optional)
     npm install -g pkg
     pkg server.js          →  server (binär, startet ohne installiertes Node)
     index.html bleibt daneben liegen. Alternativ in ein .app-Bundle
     (Automator «Shell-Skript ausführen»: /Pfad/zu/server) packen.

   SICHERHEITSHINWEIS
     Der Server lauscht standardmäßig im LAN (0.0.0.0). Wer nur lokal testen
     möchte, startet mit:  HOST=127.0.0.1 node server.js
   ============================================================================ */

"use strict";

const http = require("http");
const dgram = require("dgram");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const os = require("os");

const PORT = parseInt(process.argv[2] || process.env.PORT || "8080", 10);
const UDP_PORT = parseInt(process.argv[3] || process.env.UDP_PORT || "8000", 10);
const HOST = process.env.HOST || "0.0.0.0";
const INDEX = path.join(__dirname, "index.html");

const clients = new Set();

/* ---------- HTTP: Seite ausliefern ---------- */
const FALLBACK = "<!doctype html><meta charset=utf-8><body style=\"background:#181818;color:#d5d0c9;" +
  "font-family:monospace;padding:40px;line-height:1.7\">" +
  "<h2 style=\"color:#d286b7\">Matrix Monitor Server</h2>" +
  "<p>index.html fehlt in diesem Ordner.</p>" +
  "<p>Bitte die Matrix-Monitor-HTML-Datei hierher exportieren und <b>index.html</b> nennen," +
  " dann die Seite neu laden.</p>";

const server = http.createServer(function (req, res) {
  if (req.url === "/" || req.url === "/index.html" || req.url === "/monitor") {
    fs.readFile(INDEX, function (err, data) {
      if (err) {
        res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
        res.end(FALLBACK);
      } else {
        res.writeHead(200, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" });
        res.end(data);
      }
    });
  } else {
    res.writeHead(404, { "content-type": "text/plain" });
    res.end("404");
  }
});

/* ---------- WebSocket: eigener Handshake, keine Abhängigkeiten ---------- */
server.on("upgrade", function (req, socket) {
  if (req.headers.upgrade !== "websocket") { socket.destroy(); return; }
  const key = req.headers["sec-websocket-key"];
  if (!key) { socket.destroy(); return; }
  const accept = crypto.createHash("sha1")
    .update(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
    .digest("base64");
  socket.write(
    "HTTP/1.1 101 Switching Protocols\r\n" +
    "Upgrade: websocket\r\n" +
    "Connection: Upgrade\r\n" +
    "Sec-WebSocket-Accept: " + accept + "\r\n\r\n");
  socket.setNoDelay(true);
  clients.add(socket);
  socket.on("data", function () { /* Client sendet nichts; nur konsumieren */ });
  const drop = function () { clients.delete(socket); try { socket.destroy(); } catch (e) {} };
  socket.on("close", drop);
  socket.on("end", drop);
  socket.on("error", drop);
});

/* ---------- OSC-Pakete (UDP :8000) an alle WebSocket-Clients ---------- */
function wsBinaryFrame(buf) {
  const len = buf.length;
  let head;
  if (len < 126) {
    head = Buffer.alloc(2); head[1] = len;
  } else if (len < 65536) {
    head = Buffer.alloc(4); head[1] = 126; head.writeUInt16BE(len, 2);
  } else {
    head = Buffer.alloc(10); head[1] = 127; head.writeBigUInt64BE(BigInt(len), 2);
  }
  head[0] = 0x82; // FIN + binary
  return Buffer.concat([head, buf]);
}
function broadcast(buf) {
  if (clients.size === 0) return;
  const frame = wsBinaryFrame(buf);
  for (const s of clients) {
    try { s.write(frame); } catch (e) { /* weg bei close */ }
  }
}

const udp = dgram.createSocket("udp4");
udp.on("message", broadcast);
udp.on("error", function (err) {
  if (err.code === "EADDRINUSE" || err.code === "EACCES") {
    console.error("");
    console.error("UDP-Port " + UDP_PORT + " ist bereits belegt (oder gesperrt).");
    console.error("Häufige Ursache: REAPER mit aktivem OSC nutzt standardmäßig Port 8000,");
    console.error("genauso wie TouchOSC. Der Monitor kann denselben Port nicht mitbenutzen.");
    console.error("");
    console.error("Ausweg – Monitor auf einen freien UDP-Port legen, z. B.:");
    console.error("    node server.js " + PORT + " 9001");
    console.error("und dann im OSC-Sender (z. B. REAPER: OSC-Gerät → udp://127.0.0.1:9001)");
    console.error("die Rückmeldung auf diesen Port schicken.");
    console.error("");
    process.exit(1);
  }
  console.error("UDP-Fehler:", err.message);
});

/* ---------- Startbanner ---------- */
function lanIps() {
  const out = [];
  const ifs = os.networkInterfaces();
  for (const name of Object.keys(ifs)) {
    for (const i of ifs[name] || []) {
      if (i.family === "IPv4" && !i.internal) out.push(name + " → " + i.address);
    }
  }
  return out;
}
udp.bind(UDP_PORT, function () {
  console.log("──────────────────────────────────────────────");
  console.log("  MATRIX MONITOR SERVER");
  console.log("  Seite        http://localhost:" + PORT);
  for (const line of lanIps()) console.log("  LAN           http://" + line.split(" → ")[1] + ":" + PORT + "   (" + line.split(" → ")[0] + ")");
  console.log("  OSC ein       UDP :" + UDP_PORT + " (REAPER/TotalMix/DiGiCo/DM7/Max/RNBO)");
  console.log("  WebSocket     auf derselben Adresse wie die Seite");
  console.log("  Beenden       Strg+C");
  console.log("──────────────────────────────────────────────");
});
server.listen(PORT, HOST, function () {
  console.log("HTTP + WebSocket lauschen auf " + (HOST === "0.0.0.0" ? "allen Schnittstellen" : HOST) + ":" + PORT);
});
server.on("error", function (err) {
  if (err.code === "EADDRINUSE") {
    console.error("");
    console.error("HTTP-Port " + PORT + " ist bereits belegt – ein anderes Web-Tool lauscht dort bereits.");
    console.error("Ausweg: anderen HTTP-Port wählen, z. B.:  node server.js 8090 " + UDP_PORT);
    console.error("");
    process.exit(1);
  }
  console.error("HTTP-Fehler:", err.message);
  process.exit(1);
});

process.on("SIGINT", function () {
  console.log("\nBeende Matrix Monitor Server …");
  try { udp.close(); } catch (e) {}
  server.close(function () { process.exit(0); });
  setTimeout(function () { process.exit(0); }, 500);
});