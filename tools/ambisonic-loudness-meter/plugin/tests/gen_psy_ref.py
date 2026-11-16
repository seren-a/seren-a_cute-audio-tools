#!/usr/bin/env python3
"""Generiert Testsignale + mosqito-Referenzwerte fuer psy_tests.

Aufruf:  python3 gen_psy_ref.py <outdir>
Erzeugt: <outdir>/psy_signals.bin  (int64 len + float64 samples, pro Signal)
         <outdir>/psy_ref.txt      (name N10=.. N50=.. N90=.. S=.. R=.. FS=.. Nmean=..)

Danach:  ./psy_tests <outdir>/psy_signals.bin <outdir>/psy_ref.txt
Benötigt: mosqito (pip install mosqito)
"""
import sys
import os
import numpy as np
from mosqito.sq_metrics import loudness_zwtv, roughness_dw, sharpness_din_tv

FS = 48000
P_REF = 2e-5


def sine_pa(freq, dur, db_spl):
    t = np.arange(int(FS * dur)) / FS
    rms = P_REF * 10 ** (db_spl / 20)
    return np.sqrt(2) * rms * np.sin(2 * np.pi * freq * t)


def refs(p, fs=FS):
    N, Nspec, bark, time = loudness_zwtv(p, fs, "free")
    S = sharpness_din_tv(p, fs, weighting="din", field_type="free", skip=0)[0]
    R = roughness_dw(p, fs)[0]
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "src"))
    from soundscape_metrics import fluctuation_strength
    return dict(N10=float(np.percentile(N, 90)), N50=float(np.percentile(N, 50)),
                N90=float(np.percentile(N, 10)), S=float(np.mean(S)),
                R=float(np.mean(R)), FS=float(fluctuation_strength(N, fs_n=500.0)),
                Nmean=float(np.mean(N)))


def main(outdir):
    os.makedirs(outdir, exist_ok=True)
    t = np.arange(int(FS * 4)) / FS
    carrier = np.sin(2 * np.pi * 1000 * t)
    am = (0.5 * (1 + np.sin(2 * np.pi * 70 * t))) * carrier
    rng = np.random.default_rng(42)
    noise = rng.standard_normal(int(FS * 4))
    noise = noise / np.sqrt(np.mean(noise ** 2)) * P_REF * 10 ** (60 / 20)
    t2 = np.arange(int(FS * 2)) / FS
    f = np.linspace(1000, 5000, len(t2))
    stim = 0.5 * (1 + np.sin(2 * np.pi * f * t2))

    signals = {
        "sine1k_60dB": sine_pa(1000.0, 4.0, 60.0),
        "am1k_70Hz_60dB": am * (P_REF * 10 ** (60 / 20) / np.sqrt(np.mean(am ** 2))),
        "noise_60dB": noise,
        "chirp1k5k_60dB": stim * (P_REF * 10 ** (60 / 20) / np.sqrt(np.mean(stim ** 2))),
        "sine100_60dB": sine_pa(100.0, 4.0, 60.0),
    }
    with open(os.path.join(outdir, "psy_signals.bin"), "wb") as f:
        for sig in signals.values():
            f.write(np.array([len(sig)], dtype=np.int64).tobytes())
            f.write(sig.astype(np.float64).tobytes())
    with open(os.path.join(outdir, "psy_ref.txt"), "w") as f:
        for name, sig in signals.items():
            r = refs(sig)
            f.write(name + " " + " ".join(f"{k}={v:.8g}" for k, v in r.items()) + "\n")
            print(name, {k: round(v, 5) for k, v in r.items()})


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
