#!/usr/bin/env python3
"""Kommandozeile fuer den ambisonic-loudness-meter.

Aufruf:
    python3 cli.py MEIN_HOA.wav [--order N] [--spl-offset DB]
                             [--soundscape] [--json]

Liest eine B-Format/HOA-WAV (ACN/SN3D, (order+1)^2 Kanaele) und gibt den
BS.1770-5/EBU-R128-Loudness-Report aus; optional die Indoor-Soundscape-
Parameter (Torresin et al. 2020) auf der Omni-Komponente W.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "src"))

from ambisonic_loudness import measure_file, print_report  # noqa: E402
from soundscape_metrics import measure_soundscape, print_soundscape_report  # noqa: E402


def _summary(result: dict) -> dict:
    """Report-Dict ohne Zeitreihen (fuer JSON-Ausgabe)."""
    out = {k: v for k, v in result.items()
           if k not in ("short_term_series", "momentary_series")}
    out["per_speaker_lufs"] = [
        {k: v for k, v in s.items()} for s in result["per_speaker_lufs"]
    ]
    return out


def main(argv=None) -> int:
    p = argparse.ArgumentParser(
        description="Loudness- & Soundscape-Analyse fuer Ambisonics (B-Format/HOA)")
    p.add_argument("file", help="B-Format-WAV (ACN/SN3D, (order+1)^2 Kanaele)")
    p.add_argument("--order", type=int, default=None,
                   help="Ambisonics-Ordnung (Default: aus Kanalzahl)")
    p.add_argument("--spl-offset", type=float, default=94.0,
                   help="dBFS->dB-SPL-Kalibrierung (RMS), Default 94")
    p.add_argument("--soundscape", action="store_true",
                   help="zusaetzlich Torresin-Parameter auf der W-Komponente")
    p.add_argument("--json", action="store_true", help="nur JSON ausgeben")
    args = p.parse_args(argv)

    import soundfile as sf

    kwargs = {}
    if args.order is not None:
        kwargs["order"] = args.order
    result = measure_file(args.file, **kwargs)

    payload = {"file": args.file, "loudness": _summary(result)}
    if args.soundscape:
        data, fs = sf.read(args.file, always_2d=True)
        omni = 2.0 * np.sqrt(np.pi) * data.T[0]
        sc = measure_soundscape(omni, fs, spl_offset_db=args.spl_offset)
        payload["soundscape"] = {k: v for k, v in sc.items()
                                if k != "loudness_series"}

    if args.json:
        print(json.dumps(payload, indent=2, default=float))
    else:
        print_report(result)
        if args.soundscape:
            print()
            print_soundscape_report(sc)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
