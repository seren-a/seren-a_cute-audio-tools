#!/usr/bin/env python3
"""Batch-Analyse: B-Format/HOA-Dateien analysieren und in die zentrale CSV anhaengen.

Dateiliste kommt aus einer der Quellen:
    python3 scripts/batch_analyze.py DATEI.wav [weitere.wav ...]
    python3 scripts/batch_analyze.py --dir /pfad/zu/wavs        # rekursiv
    python3 scripts/batch_analyze.py --items-csv analysis/items.csv   # Export aus REAPER

Zentrale CSV (alle Analysen fliessen hier zusammen):
    --csv PATH  oder  Umgebungsvariable AMBISONIC_ANALYSIS_CSV  oder
    <REAPER-ResourcePath>/ambisonic-analysis/results.csv
    (macOS default: ~/Library/Application Support/REAPER/ambisonic-analysis/results.csv)

Spalten sind identisch mit scripts/reaper_collect.lua (source="file").
"""

from __future__ import annotations

import argparse
import csv
import datetime
import glob
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src"))

from ambisonic_loudness import measure_file  # noqa: E402
from soundscape_metrics import measure_soundscape  # noqa: E402

COLS = [
    "timestamp", "source", "project", "track", "fx", "file",
    "integrated_lufs", "max_shortterm_lufs", "max_momentary_lufs", "lra_lu",
    "true_peak_dbtp", "w_only_lufs", "l_aeq_db", "l_c_minus_l_a_db",
    "l_a10_minus_l_a90_db", "n10_sone", "n50_sone", "n90_sone", "n10_minus_n90_sone",
    "sharpness_acum", "roughness_asper", "fluctuation_strength_vacil",
]

DEFAULT_CSV = os.path.join(
    os.path.expanduser("~/Library/Application Support/REAPER"),
    "ambisonic-analysis", "results.csv")


def collect_files(args) -> list[str]:
    files: list[str] = list(args.files or [])
    if args.dir:
        files += sorted(glob.glob(os.path.join(args.dir, "**", "*.wav"), recursive=True))
    if args.items_csv:
        with open(args.items_csv, newline="") as fh:
            for row in csv.DictReader(fh):
                f = (row.get("file") or "").strip()
                if f and os.path.exists(f) and f not in files:
                    files.append(f)
    return files


def analyze(path: str, order, spl_offset: float) -> dict:
    kwargs = {"order": order} if order is not None else {}
    r = measure_file(path, **kwargs)
    import soundfile as sf
    data, fs = sf.read(path, always_2d=True)
    omni = 2.0 * np.sqrt(np.pi) * data.T[0]
    sc = measure_soundscape(omni, fs, spl_offset_db=spl_offset)

    def fin(v):
        return float(v) if np.isfinite(v) else ""

    return {
        "timestamp": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "source": "file",
        "project": "",
        "track": "",
        "fx": "",
        "file": path,
        "integrated_lufs": fin(r["integrated_lufs"]),
        "max_shortterm_lufs": fin(r["max_short_term_lufs"]),
        "max_momentary_lufs": fin(r["max_momentary_lufs"]),
        "lra_lu": fin(r["lra"]),
        "true_peak_dbtp": fin(r["true_peak_dbtp"]),
        "w_only_lufs": fin(r["w_only_lufs"]),
        "l_aeq_db": fin(sc["L_Aeq"]),
        "l_c_minus_l_a_db": fin(sc["L_C_minus_L_A"]),
        "l_a10_minus_l_a90_db": fin(sc["L_A10_minus_L_A90"]),
        "n10_sone": fin(sc["N10"]),
        "n50_sone": fin(sc["N50"]),
        "n90_sone": fin(sc["N90"]),
        "n10_minus_n90_sone": fin(sc["N10_minus_N90"]),
        "sharpness_acum": fin(sc["sharpness_S_acum"]),
        "roughness_asper": fin(sc["roughness_R_asper"]),
        "fluctuation_strength_vacil": fin(sc["fluctuation_strength_FS_vacil"]),
    }


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("files", nargs="*", help="B-Format-WAVs")
    p.add_argument("--dir", help="Ordner mit WAVs (rekursiv)")
    p.add_argument("--items-csv", help="items.csv aus reaper_collect.lua")
    p.add_argument("--csv", default=os.environ.get("AMBISONIC_ANALYSIS_CSV", DEFAULT_CSV),
                   help="zentrale Analyse-CSV (Default: %(default)s)")
    p.add_argument("--order", type=int, default=None)
    p.add_argument("--spl-offset", type=float, default=94.0)
    args = p.parse_args(argv)

    files = collect_files(args)
    if not files:
        p.error("keine Dateien gefunden (files/--dir/--items-csv)")

    os.makedirs(os.path.dirname(os.path.abspath(args.csv)), exist_ok=True)
    write_header = not os.path.exists(args.csv)
    n = 0
    with open(args.csv, "a", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=COLS)
        if write_header:
            w.writeheader()
        for f in files:
            try:
                row = analyze(f, args.order, args.spl_offset)
            except Exception as e:  # noqa: BLE001
                print(f"FEHLER bei {f}: {e}", file=sys.stderr)
                continue
            w.writerow(row)
            n += 1
            print(f"ok: {os.path.basename(f)}  integrated={row['integrated_lufs']} LUFS"
                  f"  L_Aeq={row['l_aeq_db']} dB(A)  N10={row['n10_sone']} sone")
    print(f"\n{n} Datei(en) -> {args.csv}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
