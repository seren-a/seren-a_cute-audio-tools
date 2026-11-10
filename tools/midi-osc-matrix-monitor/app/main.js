"use strict";
/* Matrix Monitor – Hauptprozess der eigenständigen App.
   Startet die eingebaute OSC-Bridge (server.js) als Kindprozess im
   Node-Modus des Electron-Binary und öffnet das Fenster auf die
   lokal gehostete Seite. Ports wählbar: MM_PORT / MM_UDP,
   Fenstergröße: MM_WIDTH / MM_HEIGHT.

   Diagnose: Wird die App aus dem Terminal gestartet
   ("/Applications/Matrix Monitor.app/Contents/MacOS/MatrixMonitor"),
   schreibt der Hauptprozess seinen Startverlauf ins Terminal. */
const { app, BrowserWindow, Menu, dialog } = require("electron");
const path = require("path");
const http = require("http");
const { spawn } = require("child_process");

let win = null, bridge = null, quitting = false, retried = false, log = "";
let HTTP = parseInt(process.env.MM_PORT || "8080", 10);
let UDP = parseInt(process.env.MM_UDP || "8000", 10);
let loadToken = 0;

function say(msg){
  try { process.stdout.write("[Matrix Monitor] " + msg + "\n"); } catch (e) {}
}

if (!app.requestSingleInstanceLock()){
  app.quit();
} else {
  app.on("second-instance", function(){
    if (win){ if (win.isMinimized()) win.restore(); win.focus(); }
  });

  function startBridge(httpPort, udpPort){
    bridge = spawn(process.execPath,
      [path.join(__dirname, "server.js"), String(httpPort), String(udpPort)],
      { env: Object.assign({}, process.env, { ELECTRON_RUN_AS_NODE: "1" }),
        stdio: ["ignore", "pipe", "pipe"] });
    log = "";
    bridge.stdout.on("data", function(d){ log += d.toString(); });
    bridge.stderr.on("data", function(d){ log += d.toString(); });
    bridge.on("error", function(e){
      if (quitting) return;
      dialog.showErrorBox("Matrix Monitor konnte nicht starten",
        "Die Bridge konnte nicht gestartet werden: " + e.message);
      app.quit();
    });
    bridge.on("exit", function(code){
      if (quitting || code === 0 || code === null) return;
      say("Bridge beendet (Code " + code + "):\n" + log.trim());
      if (!retried){
        /* Erster Versuch gescheitert (Port belegt, z. B. REAPER auf UDP 8000
           oder ein noch laufender Server der Browser-Variante): einmalig
           auf freiere Ports ausweichen und erneut versuchen. */
        retried = true; HTTP = 8081; UDP = 9001;
        say("Weiche aus auf HTTP " + HTTP + " / UDP " + UDP + " …");
        startBridge(HTTP, UDP);
        loadIn(win, HTTP);
        return;
      }
      dialog.showErrorBox("Matrix Monitor konnte nicht starten",
        log.trim() +
        "\n\nAbhilfe: Ports beim Start aus dem Terminal wählen, z. B.\n" +
        "MM_PORT=8090 MM_UDP=9001 \"/Applications/Matrix Monitor.app/Contents/MacOS/MatrixMonitor\"");
      app.quit();
    });
  }

  /* Lädt die Monitor-Seite, sobald die Bridge HTTP bedient. Jeder neue
     Auftrag (etwa nach dem Ausweichen auf einen anderen Port) verwirft
     alle älteren, noch laufenden Versuche: Nur der letzte Auftrag darf
     am Ende im Fenster stehen – sonst können sich zwei Ladeschleifen
     gegenseitig die Seite wegnehmen und das Fenster bleibt leer. */
  function loadIn(w, port){
    if (!w || w.isDestroyed()) return;
    const my = ++loadToken;
    const url = "http://127.0.0.1:" + port + "/";
    say("Fenster lädt " + url + " (sobald die Bridge antwortet)");
    let tries = 0;
    const probe = function(){
      if (quitting || !w || w.isDestroyed() || my !== loadToken) return;
      if (tries > 50){ say("Bridge antwortet nicht auf " + url + " – gebe auf."); return; }
      tries++;
      const req = http.get(url, function(res){
        res.resume();
        if (res.statusCode === 200) load();
        else setTimeout(probe, 300);
      });
      req.setTimeout(1500, function(){ try { req.destroy(); } catch (e) {} });
      req.on("error", function(){ setTimeout(probe, 300); });
    };
    const load = function(){
      if (quitting || !w || w.isDestroyed() || my !== loadToken) return;
      w.loadURL(url).then(function(){ say("Seite steht: " + url); })
        .catch(function(err){
          say("Laden fehlgeschlagen (" + ((err && err.code) || err) + "), neuer Versuch …");
          setTimeout(load, 400);
        });
    };
    setTimeout(probe, 300);
  }

  function createWindow(){
    win = new BrowserWindow({
      width: parseInt(process.env.MM_WIDTH || "1440", 10),
      height: parseInt(process.env.MM_HEIGHT || "900", 10),
      backgroundColor: "#160a13",
      title: "Matrix Monitor",
      show: false,
      autoHideMenuBar: true
    });
    Menu.setApplicationMenu(null);
    win.once("ready-to-show", function(){ win.show(); });
    win.on("closed", function(){ win = null; });
    loadIn(win, HTTP);
  }

  app.whenReady().then(function(){
    say("Starte Bridge auf HTTP " + HTTP + " / UDP " + UDP + " …");
    startBridge(HTTP, UDP);
    createWindow();
    app.on("activate", function(){ if (!win) createWindow(); });
  });

  app.on("window-all-closed", function(){
    quitting = true;
    if (bridge) bridge.kill();
    app.quit();
  });
  app.on("will-quit", function(){
    quitting = true;
    if (bridge) bridge.kill();
  });
}