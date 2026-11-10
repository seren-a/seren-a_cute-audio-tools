#!/usr/bin/env python3
"""
dearvr2convert - dearVR PRO (v1) Presets -> dearVR PRO 2 (.vstpreset + .aupreset)

Liest:
  * Reaper-Preset-Listen (.ini) von dearVR PRO (VST2 oder VST3)  - z.B. "vst-dearVR pro.ini"
  * einzelne dearVR-PRO-v1-Presets (.vstpreset / .aupreset)
  * auch PRO-2-Quellen (dann wird nur umverpackt, nichts umgerechnet)

Schreibt pro Preset:
  * <Name>.vstpreset  -> Nuendo / Cubase / Reaper / alle VST3-Hosts
  * <Name>.aupreset   -> Logic / alle AU-Hosts

Standard-Zielordner (dort finden Nuendo-MediaBay, Reaper und Logic die Presets):
  ~/Library/Audio/Presets/Dear Reality/dearVR PRO 2/

Nur Python-Standardbibliothek, keine Installation noetig.

Beispiele:
  python3 dearvr2convert.py "vst-dearVR pro.ini"
  python3 dearvr2convert.py "vst-dearVR pro.ini" -o ./ausgabe --prefix "Cantina/"
  python3 dearvr2convert.py *.vstpreset --output-mode 0.064 --dry-run
"""
import argparse
import base64
import binascii
import configparser
import os
import plistlib
import re
import struct
import sys

# ---------------------------------------------------------------- Konstanten
VST3_CLASS_ID = b"ABCDEF019182FAEB4445415244727032"   # dearVR PRO 2 (VST3)
AU_TYPE = 0x61756678          # 'aufx'
AU_SUBTYPE = 0x44727032       # 'Drp2'
AU_MANUFACTURER = 0x44454152  # 'DEAR'

DEFAULT_DIR = os.path.expanduser("~/Library/Audio/Presets/Dear Reality/dearVR PRO 2")

# Reihenfolge der Attribute im PRO-2-State (exakt wie das Plugin sie schreibt)
V2_ORDER = [
    "OutputMode", "CoordinateSystem", "Azimuth", "Elevation", "Distance", "X", "Y", "Z",
    "DirectGain", "AzimuthScale", "DistanceScale", "Occlusion", "VirtualAcoustics", "RoomSize",
    "ReverbON", "ReverbGain", "ReverbLowPass", "ReverbHighPass",
    "ReflectionON", "ReflectionGain", "ReflectionLowPass", "ReflectionHighPass",
    "RealTimeAuralization", "TopWall", "BottomWall", "FrontWall", "BackWall", "LeftWall", "RightWall",
    "Bypass", "BassBoost", "PerformanceMode", "StereoWidth", "MasterGain", "LfeGain", "Clarity",
    "xyPadView", "xyPadZoom",
]
# Host-Parameter (AU) = alle ausser OutputMode und den beiden UI-Werten
V2_PARAMS = [k for k in V2_ORDER if k not in ("OutputMode", "xyPadView", "xyPadZoom")]

# Werte, die PRO 2 im Neuzustand hat (aus den Werkspresets)
V2_DEFAULTS = {
    "OutputMode": "0.02400000020861626",
    "CoordinateSystem": "0",
    "AzimuthScale": "0.23076921701431274414",
    "DistanceScale": "0.099099099636077880859",
    "ReverbLowPass": "1", "ReverbHighPass": "0",
    "ReflectionLowPass": "1", "ReflectionHighPass": "0",
    "StereoWidth": "0.3333333432674407959",
    "LfeGain": "0", "Clarity": "0",
    "xyPadView": "0", "xyPadZoom": "2",
}

# v1 -> v2 Umbenennungen (verifiziert an allen 47 gleichnamigen Werkspresets:
# Damping-Wert == LowPass-Wert, HighPass immer 0)
RENAME = {
    "Polar": "CoordinateSystem",
    "ReverbDamping": "ReverbLowPass",
    "ReflectionDamping": "ReflectionLowPass",
}
DROPPED_V1 = {"InputChannel", "VRLinkTrackName"}

JUCE_PRIVATE_TRAILER = (
    b"\x00" * 8 + b"JUCEPrivateData\x00\x01\x01Bypass\x00\x01\x01\x03\x00"
    + struct.pack("<q", 0x1D) + b"JUCEPrivateData"
)
INFO_XML = (
    '﻿<?xml version="1.0" encoding="utf-8"?>\r\n<MetaInfo>\r\n'
    '\t<Attribute id="MediaType" value="VstPreset" type="string" flags="writeProtected"/>\r\n'
    '\t<Attribute id="PlugInCategory" value="Spatial|Fx|Ambisonics" type="string" flags="writeProtected"/>\r\n'
    '\t<Attribute id="PlugInName" value="dearVR PRO 2" type="string" flags="writeProtected"/>\r\n'
    '\t<Attribute id="PlugInVendor" value="Dear Reality" type="string" flags="writeProtected"/>\r\n'
    '</MetaInfo>\r\n'
).encode("utf-8")


# ---------------------------------------------------------------- Lesen
def parse_state_blob(blob):
    """Sucht den JUCE-XML-State (VC2!) in beliebigen Binaerdaten -> geordnete Attributliste."""
    i = blob.find(b"VC2!")
    if i < 0:
        raise ValueError("kein JUCE-State (VC2!) gefunden")
    n = struct.unpack("<I", blob[i + 4:i + 8])[0]
    xml = blob[i + 8:i + 8 + n].decode("utf-8", "replace")
    m = re.search(r"<DEARVRPLUGINSTATE\s(.*?)/>", xml, re.S)
    if not m:
        raise ValueError("kein DEARVRPLUGINSTATE im State")
    return re.findall(r'(\w+)="([^"]*)"', m.group(1))


def read_reaper_ini(path):
    cp = configparser.RawConfigParser(strict=False, interpolation=None)
    cp.optionxform = str
    with open(path, encoding="utf-8", errors="replace") as fh:
        cp.read_file(fh)
    out = []
    for sec in cp.sections():
        if not sec.startswith("Preset"):
            continue
        s = cp[sec]
        keys = ["Data"] + sorted((k for k in s if re.fullmatch(r"Data_\d+", k)),
                                 key=lambda k: int(k[5:]))
        hexdata = "".join(s[k].strip() for k in keys if k in s)
        try:
            blob = binascii.unhexlify(hexdata)
        except binascii.Error:
            blob = base64.b64decode(hexdata)
        name = s.get("Name", sec)
        try:
            out.append((name, parse_state_blob(blob)))
        except ValueError as e:
            print(f"  ! {name}: {e} - uebersprungen", file=sys.stderr)
    return out


def read_input(path):
    ext = os.path.splitext(path)[1].lower()
    base = os.path.splitext(os.path.basename(path))[0]
    if ext == ".ini":
        return read_reaper_ini(path)
    if ext == ".aupreset":
        with open(path, "rb") as fh:
            pl = plistlib.load(fh)
        return [(pl.get("name", base), parse_state_blob(pl["jucePluginState"]))]
    if ext in (".vstpreset", ".fxp", ".rfxchain", ".rpp"):
        with open(path, "rb") as fh:
            return [(base, parse_state_blob(fh.read()))]
    raise ValueError(f"unbekanntes Format: {path}")


# ---------------------------------------------------------------- Umrechnen
def convert(attrs, output_mode=None):
    """v1- (oder v2-)Attribute -> geordnetes PRO-2-Attribut-Dict + Hinweise."""
    src = dict(attrs)
    notes = []
    is_v1 = "Polar" in src or "ReverbDamping" in src
    v2 = {}
    for k, v in src.items():
        if k in DROPPED_V1:
            if k == "InputChannel" and float(v) != 0.0:
                notes.append(f"InputChannel={v} gibt es in PRO 2 nicht (ignoriert)")
            elif k == "VRLinkTrackName" and v:
                notes.append(f"VRLinkTrackName '{v}' ignoriert")
            continue
        v2[RENAME.get(k, k)] = v
    for k, v in V2_DEFAULTS.items():
        v2.setdefault(k, v)
    if is_v1:
        om = v2.get("OutputMode")
        # alter v1-Standard der AzimuthScale (0.2256) -> heutiger Standard (gleiche Anzeige)
        if abs(float(v2["AzimuthScale"]) - 0.22556391358375549) < 1e-6:
            v2["AzimuthScale"] = V2_DEFAULTS["AzimuthScale"]
        if output_mode is None and abs(float(om) - 0.02) < 1e-6:
            v2["OutputMode"] = V2_DEFAULTS["OutputMode"]   # Binaural -> Binaural
        elif output_mode is None:
            notes.append(f"OutputMode {om} unveraendert uebernommen - Ausgabeformat im Plugin pruefen")
    if output_mode is not None:
        v2["OutputMode"] = output_mode
    unknown = [k for k in v2 if k not in V2_ORDER]
    for k in unknown:
        notes.append(f"unbekannter Parameter {k} ignoriert")
    return {k: v2[k] for k in V2_ORDER}, notes, is_v1


def state_xml(v2):
    body = " ".join(f'{k}="{v}"' for k, v in v2.items())
    return f'<?xml version="1.0" encoding="UTF-8"?> <DEARVRPLUGINSTATE {body}/>'.encode("utf-8")


def juce_blob(v2):
    xml = state_xml(v2)
    return b"VC2!" + struct.pack("<I", len(xml)) + xml + b"\x00"


# ---------------------------------------------------------------- Schreiben
def build_vstpreset(v2):
    comp = juce_blob(v2) + JUCE_PRIVATE_TRAILER
    header_len = 48
    comp_off = header_len
    cont_off = comp_off + len(comp)
    info_off = cont_off
    list_off = info_off + len(INFO_XML)
    entries = [(b"Comp", comp_off, len(comp)), (b"Cont", cont_off, 0), (b"Info", info_off, len(INFO_XML))]
    lst = b"List" + struct.pack("<i", len(entries)) + b"".join(
        cid + struct.pack("<qq", o, s) for cid, o, s in entries)
    header = b"VST3" + struct.pack("<i", 1) + VST3_CLASS_ID + struct.pack("<q", list_off)
    return header + comp + INFO_XML + lst


def juce_hash(s):
    h = 0
    for ch in s:
        h = (h * 31 + ord(ch)) & 0xFFFFFFFF
    return h


def build_aupreset(v2, name):
    data = struct.pack(">III", 0, 0, len(V2_PARAMS))
    for idx, key in enumerate(V2_PARAMS):
        data += struct.pack(">If", juce_hash(str(idx)), float(v2[key]))
    pl = {
        "data": data,
        "element-name": {"1": {"0": "Input"}, "2": {"0": "Output"}},
        "jucePluginState": juce_blob(v2),
        "manufacturer": AU_MANUFACTURER,
        "name": name,
        "subtype": AU_SUBTYPE,
        "type": AU_TYPE,
        "version": 0,
    }
    return plistlib.dumps(pl, fmt=plistlib.FMT_XML)


def safe_filename(name):
    name = re.sub(r'[/\\:*?"<>|]+', "-", name).strip().strip(".")
    return name or "Preset"


# ---------------------------------------------------------------- Main
def main():
    ap = argparse.ArgumentParser(description="dearVR PRO (v1) Presets -> dearVR PRO 2 .vstpreset + .aupreset")
    ap.add_argument("inputs", nargs="+", help="Reaper .ini, .vstpreset oder .aupreset")
    ap.add_argument("-o", "--out", default=DEFAULT_DIR, help=f"Zielordner (Standard: {DEFAULT_DIR})")
    ap.add_argument("--formats", default="vst3,au", help="vst3, au oder vst3,au (Standard)")
    ap.add_argument("--prefix", default="", help="Unterordner/Praefix fuer alle Presets, z.B. 'Cantina/'")
    ap.add_argument("--output-mode", help="OutputMode fest setzen: Zahl, oder Pfad zu einem PRO-2-Preset, "
                                          "dessen Ausgabeformat uebernommen werden soll")
    ap.add_argument("--overwrite", action="store_true", help="vorhandene Dateien ueberschreiben")
    ap.add_argument("--dry-run", action="store_true", help="nur anzeigen, nichts schreiben")
    a = ap.parse_args()

    fmts = {f.strip().lower() for f in a.formats.split(",")}
    om = a.output_mode
    if om and os.path.exists(om):
        om = dict(read_input(om)[0][1])["OutputMode"]
        print(f"OutputMode aus Referenz-Preset: {om}")

    presets = []
    for p in a.inputs:
        try:
            got = read_input(p)
        except Exception as e:
            print(f"! {p}: {e}", file=sys.stderr)
            continue
        print(f"{os.path.basename(p)}: {len(got)} Preset(s)")
        presets += got

    used = set()
    written = 0
    for name, attrs in presets:
        v2, notes, was_v1 = convert(attrs, om)
        rel = a.prefix + safe_filename(name)
        base, n = rel, 2
        while base.lower() in used:
            base = f"{rel} ({n})"; n += 1
        used.add(base.lower())
        tag = "v1->PRO2" if was_v1 else "PRO2"
        print(f"  [{tag}] {name}")
        for msg in notes:
            print(f"        - {msg}")
        files = []
        if "vst3" in fmts:
            files.append((base + ".vstpreset", build_vstpreset(v2)))
        if "au" in fmts:
            files.append((base + ".aupreset", build_aupreset(v2, os.path.basename(base))))
        for fn, data in files:
            dst = os.path.join(a.out, fn)
            if a.dry_run:
                continue
            if os.path.exists(dst) and not a.overwrite:
                print(f"        - existiert schon, uebersprungen: {fn} (--overwrite)")
                continue
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, "wb") as fh:
                fh.write(data)
            written += 1
    print(f"\n{len(presets)} Preset(s), {written} Datei(en) geschrieben"
          + (" (dry run)" if a.dry_run else f" nach:\n  {a.out}"))


if __name__ == "__main__":
    main()
