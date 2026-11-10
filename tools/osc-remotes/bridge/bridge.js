/* ============================================================================
   OSC-BRIDGE  (wiederverwendbar, keine npm-Abhängigkeiten, Node.js >= 16)

   Eine Bridge für alle osc-remotes: HTTP (statische Seiten) + WebSocket
   (eigener Handshake) + OSC über UDP, in beide Richtungen:

       OSC-Sender (REAPER, TotalMix, DM7, Max/RNBO, ...)
              │  UDP an oscInPort
              ▼
          ┌────────────┐   WebSocket (Binary-Frame = rohes OSC-Paket)
          │  bridge.js │ ◄──────────────────────────────────► Browser-Remote
          └────────────┘   Text-Frame = JSON {"address":..., "args":[...]}
              │  UDP an oscOutHost:oscOutPort
              ▼
       OSC-Empfänger (REAPER, TotalMix, DM7, Max/RNBO, ...)

   ALS SKRIPT (Standardfall)
       node bridge.js                      HTTP 8090 · OSC rein 8000 · OSC raus localhost:8000
       node bridge.js 9090                  HTTP 9090
       node bridge.js 9090 9001             HTTP 9090 · OSC rein 9001
       node bridge.js 9090 9001 192.168.1.50 8000
       env: PORT, OSC_IN_PORT, OSC_OUT_HOST, OSC_OUT_PORT, HOST, STATIC_DIR

   ALS MODUL
       const { createBridge } = require("./bridge.js");
       createBridge({ httpPort: 8090, udpInPort: 9001,
                      udpOutHost: "127.0.0.1", udpOutPort: 8000,
                      staticDir: __dirname + "/remote",
                      onOsc: (buf) => {} }).start();

   PORT-KONFLIKTE
       UDP 8000 ist REAPERs/TouchOSCs Standard-OSC-Port. Läuft auf diesem
       Rechner schon ein OSC-Programm auf 8000, die Bridge auf einen freien
       Port legen:  node bridge.js 9090 9001 127.0.0.1 8000
       und im OSC-Sender die Rückmeldung auf udp://127.0.0.1:9001 stellen.

   SICHERHEITSHINWEIS
       Die Bridge lauscht standardmäßig im LAN (0.0.0.0). Wer nur lokal
       testen möchte:  HOST=127.0.0.1 node bridge.js
   ============================================================================ */

"use strict";

const http = require("http");
const dgram = require("dgram");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const os = require("os");

const WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

/* ---------- OSC: kleines Encoding für ausgehende Messages ---------- */
function oscPad(n) { return (4 - (n % 4)) % 4; }
function oscString(s) {
  const b = Buffer.from(String(s), "utf8");
  return Buffer.concat([b, Buffer.alloc(1 + oscPad(b.length + 1))]);
}
function oscEncode(address, args) {
  const types = [];
  const parts = [oscString(address)];
  for (const a of args || []) {
    if (a === null || a === undefined) { types.push("N"); continue; }
    switch (typeof a) {
      case "number":
        if (Number.isInteger(a)) { types.push("i"); parts.push(int32(a)); }
        else { types.push("f"); parts.push(float32(a)); }
        break;
      case "boolean": types.push(a ? "T" : "F"); break;
      case "string": types.push("s"); parts.push(oscString(a)); break;
      default: types.push("s"); parts.push(oscString(JSON.stringify(a)));
    }
  }
  const tt = Buffer.concat([Buffer.from("," + types.join("")), Buffer.alloc(oscPad(1 + types.length))]);
  return Buffer.concat([parts[0], tt, ...parts.slice(1)]);
}
function int32(v) {
  const b = Buffer.alloc(4); b.writeInt32BE(v | 0, 0); return b;
}
function float32(v) {
  const b = Buffer.alloc(4); b.writeFloatBE(v, 0); return b;
}

/* ---------- WebSocket-Frames (RFC 6455), ohne Abhängigkeiten ---------- */
function wsServerFrame(buf, opcode) {
  const len = buf.length;
  let head;
  if (len < 126) { head = Buffer.alloc(2); head[1] = len; }
  else if (len < 65536) { head = Buffer.alloc(4); head[1] = 126; head.writeUInt16BE(len, 2); }
  else { head = Buffer.alloc(10); head[1] = 127; head.writeBigUInt64BE(BigInt(len), 2); }
  head[0] = 0x80 | (opcode || 0x2);
  return Buffer.concat([head, buf]);
}
function wsParseFrames(state, chunk) {
  state.buf = state.buf.length ? Buffer.concat([state.buf, chunk]) : chunk;
  const out = [];
  for (;;) {
    const b = state.buf;
    if (b.length < 2) break;
    const opcode = b[0] & 0x0f;
    const masked = (b[1] & 0x80) !== 0;
    let len = b[1] & 0x7f;
    let off = 2;
    if (len === 126) { if (b.length < 4) break; len = b.readUInt16BE(2); off = 4; }
    else if (len === 127) { if (b.length < 10) break; len = Number(b.readBigUInt64BE(2)); off = 10; }
    let mask = null;
    if (masked) { if (b.length < off + 4) break; mask = b.slice(off, off + 4); off += 4; }
    if (b.length < off + len) break;
    let payload = b.slice(off, off + len);
    if (mask) {
      payload = Buffer.from(payload);
      for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i % 4];
    }
    state.buf = b.slice(off + len);
    out.push({ opcode, payload });
  }
  return out;
}

/* ---------- Bridge ---------- */
function createBridge(opts) {
  const o = Object.assign({
    httpPort: 8090,
    host: "0.0.0.0",
    udpInPort: 8000,
    udpOutHost: "127.0.0.1",
    udpOutPort: 8000,
    staticDir: null,
    onOsc: null,
    log: console.log
  }, opts || {});

  const clients = new Set();
  const udp = dgram.createSocket("udp4");

  function broadcast(buf) {
    if (clients.size === 0) return;
    const frame = wsServerFrame(buf, 0x2);
    for (const s of clients) { try { s.write(frame); } catch (e) { /* weg bei close */ } }
  }

  const server = http.createServer(function (req, res) {
    if (!o.staticDir) {
      res.writeHead(200, { "content-type": "text/plain; charset=utf-8" });
      res.end("OSC-Bridge laeuft. Kein STATIC_DIR gesetzt, keine Seiten ausgeliefert.\n");
      return;
    }
    const rel = decodeURIComponent((req.url || "/").split("?")[0]);
    const file = rel === "/" ? "/index.html" : rel;
    const full = path.normalize(path.join(o.staticDir, file));
    if (!full.startsWith(path.normalize(o.staticDir))) { res.writeHead(403); res.end("403"); return; }
    fs.readFile(full, function (err, data) {
      if (err) { res.writeHead(404, { "content-type": "text/plain" }); res.end("404"); return; }
      const types = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".png": "image/png", ".svg": "image/svg+xml" };
      res.writeHead(200, { "content-type": types[path.extname(full).toLowerCase()] || "application/octet-stream", "cache-control": "no-store" });
      res.end(data);
    });
  });

  server.on("upgrade", function (req, socket) {
    if (req.headers.upgrade !== "websocket") { socket.destroy(); return; }
    const key = req.headers["sec-websocket-key"];
    if (!key) { socket.destroy(); return; }
    const accept = crypto.createHash("sha1").update(key + WS_GUID).digest("base64");
    socket.write(
      "HTTP/1.1 101 Switching Protocols\r\n" +
      "Upgrade: websocket\r\n" +
      "Connection: Upgrade\r\n" +
      "Sec-WebSocket-Accept: " + accept + "\r\n\r\n");
    socket.setNoDelay(true);
    const state = { buf: Buffer.alloc(0) };
    clients.add(socket);
    socket.on("data", function (chunk) {
      for (const f of wsParseFrames(state, chunk)) {
        if (f.opcode === 0x8) { drop(); return; }
        if (f.opcode === 0x9) { try { socket.write(wsServerFrame(f.payload, 0xA)); } catch (e) {} continue; }
        if (f.opcode === 0x1) {
          let msg = null;
          try { msg = JSON.parse(f.payload.toString("utf8")); } catch (e) {}
          if (!msg || typeof msg.address !== "string") continue;
          udp.send(oscEncode(msg.address, msg.args), o.udpOutPort, o.udpOutHost);
        } else if (f.opcode === 0x2) {
          udp.send(f.payload, o.udpOutPort, o.udpOutHost);
        }
      }
    });
    const drop = function () { clients.delete(socket); try { socket.destroy(); } catch (e) {} };
    socket.on("close", drop);
    socket.on("end", drop);
    socket.on("error", drop);
  });

  udp.on("message", function (buf) {
    if (o.onOsc) { try { o.onOsc(buf); } catch (e) {} }
    broadcast(buf);
  });
  udp.on("error", function (err) {
    if (err.code === "EADDRINUSE" || err.code === "EACCES") {
      o.log("UDP-Port " + o.udpInPort + " ist bereits belegt (oder gesperrt).");
      o.log("Haeufige Ursache: REAPER/TouchOSC nutzt standardmaeßig Port 8000.");
      o.log("Ausweg:  node bridge.js " + o.httpPort + " <freier-udp-port> " + o.udpOutHost + " " + o.udpOutPort);
      process.exit(1);
    }
    o.log("UDP-Fehler: " + err.message);
  });

  function lanIps() {
    const out = [];
    const ifs = os.networkInterfaces();
    for (const name of Object.keys(ifs)) {
      for (const i of ifs[name] || []) {
        if (i.family === "IPv4" && !i.internal) out.push({ name, address: i.address });
      }
    }
    return out;
  }

  return {
    start: function (onReady) {
      udp.bind(o.udpInPort, function () {
        o.log("──────────────────────────────────────────────────");
        o.log("  OSC-BRIDGE");
        o.log("  Seite        http://localhost:" + o.httpPort);
        for (const ip of lanIps()) o.log("  LAN          http://" + ip.address + ":" + o.httpPort + "   (" + ip.name + ")");
        o.log("  OSC rein     UDP :" + o.udpInPort + " → WebSocket (Browser)");
        o.log("  OSC raus     UDP " + o.udpOutHost + ":" + o.udpOutPort + " ← WebSocket (Browser)");
        o.log("  Beenden      Strg+C");
        o.log("──────────────────────────────────────────────────");
        if (onReady) onReady();
      });
      server.listen(o.httpPort, o.host, function () {
        o.log("HTTP + WebSocket lauschen auf " + (o.host === "0.0.0.0" ? "allen Schnittstellen" : o.host) + ":" + o.httpPort);
      });
      server.on("error", function (err) {
        if (err.code === "EADDRINUSE") {
          o.log("HTTP-Port " + o.httpPort + " ist bereits belegt.");
          o.log("Ausweg: anderen HTTP-Port waehlen, z. B.:  node bridge.js 9091 " + o.udpInPort);
          process.exit(1);
        }
        o.log("HTTP-Fehler: " + err.message);
        process.exit(1);
      });
      return this;
    },
    stop: function () {
      try { udp.close(); } catch (e) {}
      try { server.close(); } catch (e) {}
      for (const s of clients) { try { s.destroy(); } catch (e) {} }
      clients.clear();
    },
    broadcast: broadcast,
    clients: clients,
    options: o
  };
}

module.exports = { createBridge, oscEncode };

/* ---------- CLI ---------- */
if (require.main === module) {
  const httpPort = parseInt(process.argv[2] || process.env.PORT || "8090", 10);
  const udpInPort = parseInt(process.argv[3] || process.env.OSC_IN_PORT || "8000", 10);
  const udpOutHost = process.argv[4] || process.env.OSC_OUT_HOST || "127.0.0.1";
  const udpOutPort = parseInt(process.argv[5] || process.env.OSC_OUT_PORT || "8000", 10);
  const bridge = createBridge({
    httpPort: httpPort,
    host: process.env.HOST || "0.0.0.0",
    udpInPort: udpInPort,
    udpOutHost: udpOutHost,
    udpOutPort: udpOutPort,
    staticDir: process.env.STATIC_DIR || path.join(__dirname, "remote")
  });
  bridge.start();
  process.on("SIGINT", function () {
    console.log("\nBeende OSC-Bridge ...");
    bridge.stop();
    process.exit(0);
  });
}
