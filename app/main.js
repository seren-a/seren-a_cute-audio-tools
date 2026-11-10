"use strict";
/* Matrix Monitor – Hauptprozess der eigenständigen App.
   Startet die eingebaute OSC-Bridge (server.js) als Kindprozess im
   Node-Modus des Electron-Binary und öffnet das Fenster auf die
   lokal gehostete Seite. Ports wählbar: MM_PORT / MM_UDP,
   Fenstergröße: MM_WIDTH / MM_HEIGHT. */
const { app, BrowserWindow, Menu, dialog } = require("electron");
const path = require("path");
const { spawn } = require("child_process");

let win = null, bridge = null, quitting = false, retried = false, log = "";
let HTTP = parseInt(process.env.MM_PORT || "8080", 10);
let UDP = parseInt(process.env.MM_UDP || "8000", 10);

if (!app.requestSingleInstanceLock()){
  app.quit();
} else {
  app.on("second-instance", function(){
    if (win){ if (win.isMinimized()) win.restore(); win.focus(); }
  });

  function startBridge(http, udp){
    bridge = spawn(process.execPath,
      [path.join(__dirname, "server.js"), String(http), String(udp)],
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
      if (!retried){
        /* Erster Versuch gescheitert (Port belegt): einmalig auf
           freiere Ports ausweichen und erneut versuchen. */
        retried = true; HTTP = 8081; UDP = 9001;
        startBridge(HTTP, UDP);
        loadIn(win);
        return;
      }
      dialog.showErrorBox("Matrix Monitor konnte nicht starten",
        log.trim() +
        "\n\nAbhilfe: Ports beim Start aus dem Terminal wählen, z.B.\n" +
        "open -a \"Matrix Monitor\" --env MM_PORT=8080 MM_UDP=9001");
      app.quit();
    });
  }

  function loadIn(w){
    if (!w || w.isDestroyed()) return;
    const url = "http://127.0.0.1:" + HTTP + "/";
    let tries = 0;
    const load = function(){
      if (!w || w.isDestroyed() || tries > 25) return;
      tries++;
      w.loadURL(url).catch(function(){ setTimeout(load, 400); });
    };
    setTimeout(load, 500);
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
    loadIn(win);
  }

  app.whenReady().then(function(){
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