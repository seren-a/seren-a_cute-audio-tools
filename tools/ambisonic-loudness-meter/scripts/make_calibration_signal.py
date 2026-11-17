#!/usr/bin/env python3
"""Kalibriersignal erzeugen: 1-kHz-Sinus (EBU Tech 3341 Alignment Signal).

Default: -23 dBFS RMS, 60 s, 48 kHz, Stereo, PCM_24.

    python3 scripts/make_calibration_signal.py out.wav
    python3 scripts/make_calibration_signal.py out.wav --dbfs -20 --seconds 30 --mono

Danach in REAPER auf den Monitor-Out routen, abspielen, SPL-Meter (C, Slow)
auf 83 dB SPL(C) einpegeln -> im Plugin SPL Cal = 83 + 23 = 106.
"""

import argparse
import os
import sys

import numpy as np


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("out", help="Ziel-WAV")
    p.add_argument("--dbfs", type=float, default=-23.0, help="RMS-Pegel in dBFS (Default -23, EBU)")
    p.add_argument("--seconds", type=float, default=60.0)
    p.add_argument("--fs", type=int, default=48000)
    p.add_argument("--freq", type=float, default=1000.0, help="Hz (Default 1000, EBU Tech 3341)")
    p.add_argument("--mono", action="store_true")
    args = p.parse_args(argv)

    import soundfile as sf
    n = int(args.seconds * args.fs)
    t = np.arange(n, dtype=np.float64) / args.fs
    rms = 10.0 ** (args.dbfs / 20.0)
    sine = rms * np.sqrt(2.0) * np.sin(2.0 * np.pi * args.freq * t)  # peak = rms*sqrt(2)
    data = sine[:, None] if args.mono else np.repeat(sine[:, None], 2, axis=1)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    sf.write(args.out, data, args.fs, subtype="PCM_24")
    print(f"{args.out}: {args.seconds}s, {args.fs} Hz, {'mono' if args.mono else 'stereo'}, "
          f"{args.freq} Hz Sinus @ {args.dbfs} dBFS RMS (peak {args.dbfs + 3.01:.2f} dBFS)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
