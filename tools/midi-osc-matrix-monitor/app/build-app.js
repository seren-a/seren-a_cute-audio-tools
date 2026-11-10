#!/usr/bin/env node
"use strict";
/* Baut die eigenständige macOS-App «Matrix Monitor.app» (Apple Silicon,
   arm64). Benötigt nur Node.js sowie unzip und zip im Systempfad; optional
   python3 für das App-Symbol. Läuft auch unter Linux (Cross-Build).
   Der komplette Bau reproduziert die veröffentlichte App Version 2:
   1. Chromium-Laufzeit (Electron-Fertigbau) herunterladen
   2. umbenennen und Info.plist anpassen
   3. App-Symbol erzeugen (make-icon.py)
   4. server.js + index.html + main.js einsetzen
   5. als ZIP mit erhaltenen symbolischen Verweisen verpacken
   Umgebungsvariablen: ELECTRON_VERSION (Standard 45.2.3), MM_ARCH (arm64). */
const { execFileSync } = require("child_process");
const https = require("https");
const fs = require("fs");
const path = require("path");

const VERSION = process.env.ELECTRON_VERSION || "45.2.3";
const ARCH = process.env.MM_ARCH || "arm64";
const APPNAME = "Matrix Monitor";
const BUNDLEID = "de.matrixmonitor.app";

const appdir = path.resolve(__dirname);
const root = path.resolve(appdir, "..");
const build = path.join(root, "build");
const zipName = "electron-v" + VERSION + "-darwin-" + ARCH + ".zip";

function run(cmd, args, opts){
  execFileSync(cmd, args, Object.assign({ stdio: "inherit" }, opts || {}));
}

function download(url, dest, redirects){
  redirects = redirects === undefined ? 6 : redirects;
  return new Promise(function(resolve, reject){
    const req = https.get(url, function(res){
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location && redirects > 0){
        res.resume();
        return download(res.headers.location, dest, redirects - 1).then(resolve, reject);
      }
      if (res.statusCode !== 200){
        res.resume();
        return reject(new Error("Download fehlgeschlagen: HTTP " + res.statusCode + " – " + url));
      }
      const out = fs.createWriteStream(dest);
      res.pipe(out);
      out.on("finish", function(){ out.close(function(){ resolve(); }); });
      out.on("error", reject);
    });
    req.on("error", reject);
  });
}

(async function main(){
  fs.mkdirSync(build, { recursive: true });
  const zipPath = path.join(build, zipName);
  if (!fs.existsSync(zipPath)){
    const url = "https://github.com/electron/electron/releases/download/v" + VERSION +
      "/electron-v" + VERSION + "-darwin-" + ARCH + ".zip";
    console.log("Lade Chromium-Laufzeit (Electron " + VERSION + ", darwin-" + ARCH + ") …");
    await download(url, zipPath);
  }
  console.log("Entpacke …");
  const bundleDir = path.join(build, APPNAME + ".app");
  run("rm", ["-rf", bundleDir]);
  run("unzip", ["-q", "-o", zipPath, "-d", build]);
  run("mv", [path.join(build, "Electron.app"), bundleDir]);

  /* Hauptprogramm umbenennen */
  const exeOld = path.join(bundleDir, "Contents/MacOS/Electron");
  const exeNew = path.join(bundleDir, "Contents/MacOS/MatrixMonitor");
  run("mv", [exeOld, exeNew]);

  /* Info.plist anpassen (die Framework- und Helfer-Namen bleiben
     unverändert – sie sind Teil der eingebetteten Signatur). */
  const plistPath = path.join(bundleDir, "Contents/Info.plist");
  let plist = fs.readFileSync(plistPath, "utf8");
  plist = plist
    .replace(/(<key>CFBundleDisplayName<\/key>\s*<string>)Electron<\/string>/, "$1" + APPNAME + "</string>")
    .replace(/(<key>CFBundleExecutable<\/key>\s*<string>)Electron<\/string>/, "$1MatrixMonitor</string>")
    .replace(/(<key>CFBundleName<\/key>\s*<string>)Electron<\/string>/, "$1" + APPNAME + "</string>")
    .replace(/com\.github\.Electron/, BUNDLEID)
    .replace(/(<key>CFBundleIconFile<\/key>\s*<string>)electron\.icns<\/string>/, "$1AppIcon.icns</string>")
    .replace(/(<key>CFBundleShortVersionString<\/key>\s*<string>)[^<]+/, "$12.0.0")
    .replace(/(<key>CFBundleVersion<\/key>\s*<string>)[^<]+/, "$12.0.0");
  fs.writeFileSync(plistPath, plist);

  /* App-Kern: Bridge, Seite, Hauptprozess */
  const core = path.join(bundleDir, "Contents/Resources/app");
  fs.mkdirSync(core, { recursive: true });
  fs.copyFileSync(path.join(root, "server/server.js"), path.join(core, "server.js"));
  fs.copyFileSync(path.join(root, "index.html"), path.join(core, "index.html"));
  fs.copyFileSync(path.join(appdir, "main.js"), path.join(core, "main.js"));
  fs.copyFileSync(path.join(appdir, "package.json"), path.join(core, "package.json"));

  /* App-Symbol */
  const iconDest = path.join(bundleDir, "Contents/Resources/AppIcon.icns");
  try {
    run("python3", [path.join(appdir, "make-icon.py"), iconDest]);
  } catch (e){
    console.log("Hinweis: python3 nicht verfügbar – die App erhält kein eigenes Symbol.");
  }

  console.log("Verpacke …");
  run("zip", ["-r", "-y", "-q", "Matrix-Monitor-App.zip", APPNAME + ".app"], { cwd: build });
  console.log("Fertig: " + path.join(build, "Matrix-Monitor-App.zip"));
  console.log("Erster Start auf dem Mac: Doppelklick, dann Systemeinstellungen →");
  console.log("Datenschutz & Sicherheit → «Trotzdem öffnen» (App ist nicht notarisiert).");
})().catch(function(e){ console.error(String(e && e.message || e)); process.exit(1); });