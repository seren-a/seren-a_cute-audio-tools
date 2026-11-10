"use strict";
const net = require("net");
const dgram = require("dgram");
const crypto = require("crypto");
const { createBridge, oscEncode } = require("./bridge.js");

const HTTP = 8301, IN = 8302, OUT = 8303;
const bridge = createBridge({ httpPort: HTTP, udpInPort: IN, udpOutHost: "127.0.0.1", udpOutPort: OUT, staticDir: null, log: () => {} });
bridge.start();

const results = [];
function check(name, ok) { results.push([name, ok]); }
function finish() {
  bridge.stop();
  let allOk = true;
  for (const [n, ok] of results) { console.log((ok ? "PASS" : "FAIL") + "  " + n); if (!ok) allOk = false; }
  process.exit(allOk ? 0 : 1);
}
setTimeout(() => { check("Gesamt-Timeout", false); finish(); }, 8000);

function clientFrame(payload, opcode) {
  const mask = crypto.randomBytes(4);
  const head = Buffer.from([0x80 | opcode, 0x80 | payload.length]);
  const masked = Buffer.from(payload);
  for (let i = 0; i < masked.length; i++) masked[i] ^= mask[i % 4];
  return Buffer.concat([head, mask, masked]);
}

const outSock = dgram.createSocket("udp4");
outSock.bind(OUT, start);

function start() {
  const sock = net.connect(HTTP, "127.0.0.1", () => {
    const key = crypto.randomBytes(16).toString("base64");
    sock.write("GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: " + key + "\r\nSec-WebSocket-Version: 13\r\n\r\n");
  });
  let wsReady = false;
  let wsBuf = Buffer.alloc(0);
  const wsReceived = [];
  sock.on("data", (d) => {
    if (!wsReady) {
      if (!d.toString().includes("101 Switching Protocols")) { check("WS-Handshake", false); finish(); return; }
      wsReady = true;
      phaseA();
      return;
    }
    wsBuf = Buffer.concat([wsBuf, d]);
    while (wsBuf.length >= 2) {
      let len = wsBuf[1] & 0x7f, off = 2;
      if (len === 126) { if (wsBuf.length < 4) return; len = wsBuf.readUInt16BE(2); off = 4; }
      else if (len === 127) { if (wsBuf.length < 10) return; len = Number(wsBuf.readBigUInt64BE(2)); off = 10; }
      if (wsBuf.length < off + len) return;
      wsReceived.push(wsBuf.slice(off, off + len));
      wsBuf = wsBuf.slice(off + len);
    }
  });

  const rawMsg = oscEncode("/test", [1, 2.5, "hi", true]);

  function phaseA() {
    const onMsg = (buf) => {
      outSock.removeListener("message", onMsg);
      check("A: WS->UDP binary (rohes OSC-Paket)", buf.equals(rawMsg));
      phaseB();
    };
    outSock.on("message", onMsg);
    sock.write(clientFrame(rawMsg, 0x2));
  }

  function phaseB() {
    const json = Buffer.from(JSON.stringify({ address: "/json", args: [42] }));
    const expect = oscEncode("/json", [42]);
    const onMsg = (buf) => {
      outSock.removeListener("message", onMsg);
      check("B: WS->UDP text (JSON -> OSC encoded)", buf.equals(expect));
      phaseC();
    };
    outSock.on("message", onMsg);
    sock.write(clientFrame(json, 0x1));
  }

  function phaseC() {
    const ping = Buffer.from("PING");
    const udpIn = dgram.createSocket("udp4");
    udpIn.bind(() => {
      udpIn.send(ping, IN, "127.0.0.1");
      setTimeout(() => {
        const got = wsReceived.find((b) => b.equals(ping));
        check("C: UDP->WS broadcast (OSC rein an alle Browser)", Boolean(got));
        udpIn.close();
        finish();
      }, 500);
    });
  }
}
