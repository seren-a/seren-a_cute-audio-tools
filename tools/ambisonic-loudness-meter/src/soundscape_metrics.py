"""Soundscape-Parameter nach Torresin et al. (2020), "Indoor soundscape
assessment: A principal components model of acoustic perception in
residential buildings", Building and Environment 182, 107152.

Die Studie berechnet pro Szenario (1-min-Excerpts, aufgenommen mit
First-Order-Ambisonics-Mikrofon, Sennheiser AMBEO VR Mic):

Gesamtlautheit:
- L_Aeq,1min  : A-bewerteter equivalenter Dauerschallpegel
- N_10        : Zwicker-Lautheit (ISO 532-1), ueberschritten 10% der Zeit

Zeitliche Variabilitaet:
- L_A10 - L_A90 : Pegelvariabilitaet (statistische Pegel)
- N_10 - N_90   : Lautheitsvariabilitaet
- FS            : Fluctuation Strength [vacil]
- R             : Roughness [asper]

Spektraler Inhalt:
- L_C - L_A : Differenz C-/A-Bewertung (Tiefton-Anteil)
- S         : Sharpness [acum] (DIN 45692)

Diese Module implementiert alle acht Groessen. Loudness, Sharpness und
Roughness basieren auf der Open-Source-Bibliothek *mosqito* (v1.2),
Fluctuation Strength auf dem Modell von Zwicker & Fastl (vereinfachte
Einkanal-Naeherung aus der Zeitfunktion der Lautheit).

Signale werden in Pascal benoetigt; die Kalibrierung erfolgt ueber
``spl_offset_db`` (dBFS + spl_offset_db = dB SPL).
"""

from __future__ import annotations

import numpy as np

try:
    from scipy.signal import resample_poly, bilinear, zpk2tf
    from scipy.signal import lfilter
except ImportError:  # pragma: no cover
    bilinear = None

from mosqito.sq_metrics import (
    loudness_zwtv,
    roughness_dw,
    sharpness_din_tv,
)

P_REF = 2e-5  # 20 uPa, Schalldruckreferenz


# ---------------------------------------------------------------------------
# A-/C-Bewertung (IEC 61672-1), bilinear transformiert fuer beliebige fs
# ---------------------------------------------------------------------------

def _weighting_sos(kind: str, fs: int):
    """A- oder C-Bewertung als (b, a)-Koeffizientenpaare (2 Biquads)."""
    if bilinear is None:
        raise RuntimeError("scipy erforderlich")
    f1, f2, f3, f4 = 20.598997, 107.65265, 737.86223, 12194.217
    w1, w2, w3, w4 = (2 * np.pi * f for f in (f1, f2, f3, f4))
    if kind == "a":
        z_an = np.zeros(4)
        p_an = np.array([-w1, -w1, -w2, -w3, -w4, -w4])
    else:
        z_an = np.zeros(2)
        p_an = np.array([-w1, -w1, -w4, -w4])
    k = w4 ** 2
    b, a = zpk2tf(z_an, p_an, k)
    jw = 1j * 2 * np.pi * 1000.0
    h_ref = abs(np.polyval(b, jw) / np.polyval(a, jw))
    gain = 1.0 / h_ref
    b, a = bilinear(b, a, fs)
    return [(b, a)], gain


def apply_weighting(x: np.ndarray, fs: int, kind: str = "a") -> np.ndarray:
    sos, gain = _weighting_sos(kind, fs)
    y = x
    for b, a in sos:
        y = lfilter(b, a, y)
    return y * gain


def _eq_level_db(x: np.ndarray, fs: int, kind: str, spl_offset_db: float) -> float:
    y = apply_weighting(x, fs, kind)
    p2 = (y ** 2).mean()
    if p2 <= 0:
        return -np.inf
    rms_dbfs = 10.0 * np.log10(p2)
    return rms_dbfs + spl_offset_db


def level_percentiles(x: np.ndarray, fs: int, kind: str, spl_offset_db: float,
                      block_ms: int = 125, percentiles=(10, 90)) -> dict:
    """Statistische Pegel L_A10/L_A90 ueber Kurzzeitbloecke."""
    y = apply_weighting(x, fs, kind)
    n = max(1, int(fs * block_ms / 1000))
    nblocks = y.shape[-1] // n
    if nblocks == 0:
        blocks = np.sqrt((y ** 2).mean(axis=-1, keepdims=True))
    else:
        blocks = np.sqrt((y[: nblocks * n].reshape(nblocks, n) ** 2)
                         .mean(axis=-1))
    db = 20.0 * np.log10(np.maximum(blocks, 1e-12)) + spl_offset_db
    db = db[db > spl_offset_db - 70.0]  # Gating: Bloecke unter -70 dBFS
    if db.size == 0:
        return {p: -np.inf for p in percentiles}
    out = {}
    for p in percentiles:
        out[p] = float(np.percentile(db, 100 - p))
    return out


# ---------------------------------------------------------------------------
# Lautheit (ISO 532-1, zeitvariabel) und Perzentile
# ---------------------------------------------------------------------------

def zwicker_loudness_series(p_signal: np.ndarray, fs: int,
                            field_type: str = "free"):
    """Zeitfunktion der Lautheit N(t) in sone (2-ms-Schritte)."""
    n = loudness_zwtv(p_signal, fs, field_type)[0]
    return np.asarray(n)


def loudness_percentiles(p_signal: np.ndarray, fs: int,
                         field_type: str = "free",
                         percentiles=(10, 50, 90)) -> dict:
    n_series = zwicker_loudness_series(p_signal, fs, field_type)
    out = {p: float(np.percentile(n_series, 100 - p)) for p in percentiles}
    out["series"] = n_series
    return out


# ---------------------------------------------------------------------------
# Fluctuation Strength (Zwicker & Fastl, vereinfachte Einkanal-Naeherung)
# ---------------------------------------------------------------------------

def fluctuation_strength(n_series: np.ndarray, fs_n: float = 500.0) -> float:
    """FS [vacil] aus der Lautheitszeitfunktion.

    Modell: FS = 0.008 * dL / f_mod, Maximum bei f_mod = 4 Hz
    (1 vacil: 60 dB, 4 Hz, 100% modulierter 1-kHz-Ton).
    dL: Modulationstiefe der Lautheit in dB, f_mod: dominante
    Modulationsfrequenz der Lautheits-Huellkurve.
    """
    n = np.maximum(np.asarray(n_series, dtype=float), 1e-6)
    n_centered = n - n.mean()
    if n_centered.size < 32:
        return 0.0
    spec = np.abs(np.fft.rfft(n * np.hanning(n.size)))
    freqs = np.fft.rfftfreq(n.size, d=1.0 / fs_n)
    band = (freqs > 0.5) & (freqs < 30.0)
    if not np.any(band) or spec[band].max() == 0:
        return 0.0
    f_mod = freqs[band][np.argmax(spec[band])]
    n_db = 10.0 * np.log10(n)
    dl = max(n_db.max() - n_db.min(), 0.0)
    w = f_mod / 4.0 if f_mod < 4.0 else 4.0 / f_mod
    return float(0.008 * dl * w)


# ---------------------------------------------------------------------------
# Gesamtanalyse
# ---------------------------------------------------------------------------

def measure_soundscape(x: np.ndarray, fs: int, spl_offset_db: float = 94.0,
                       field_type: str = "free") -> dict:
    """Alle Parameter der Torresin-Studie fuer ein Mono-Signal (n_samples).

    x: Signal in [-1, 1] (dBFS) oder beliebig skaliert; die absolute
    Skalierung fliesst ueber spl_offset_db in dB-SPL-Groessen ein.
    Lautheits-/Sharpness-/Roughness-Berechnung erfolgt in Pascal.
    """
    x = np.asarray(x, dtype=float).squeeze()
    p = x * P_REF * 10 ** (spl_offset_db / 20.0)

    la = _eq_level_db(x, fs, "a", spl_offset_db)
    lc = _eq_level_db(x, fs, "c", spl_offset_db)
    la_p = level_percentiles(x, fs, "a", spl_offset_db)

    n_perc = loudness_percentiles(p, fs, field_type)
    n_series = n_perc.pop("series")
    n10 = n_perc[10]
    n90 = n_perc[90]

    sharp = sharpness_din_tv(p, fs, weighting="din", field_type=field_type,
                             skip=0)
    sharpness = float(np.mean(np.asarray(sharp[0])))

    if fs != 48000:
        p48 = resample_poly(p, 48000, fs)
    else:
        p48 = p
    rough = roughness_dw(p48, 48000)
    roughness = float(np.mean(np.asarray(rough[0])))

    fs_val = fluctuation_strength(n_series, fs_n=500.0)

    return {
        "L_Aeq": la,
        "L_Ceq": lc,
        "L_C_minus_L_A": lc - la,
        "L_A10": la_p[10],
        "L_A90": la_p[90],
        "L_A10_minus_L_A90": la_p[10] - la_p[90],
        "N10": n10,
        "N50": n_perc[50],
        "N90": n90,
        "N10_minus_N90": n10 - n90,
        "sharpness_S_acum": sharpness,
        "fluctuation_strength_FS_vacil": fs_val,
        "roughness_R_asper": roughness,
        "loudness_series": n_series,
    }


def print_soundscape_report(r: dict) -> None:
    print("=== Indoor-Soundscape-Parameter (Torresin et al. 2020) ===")
    print(f"L_Aeq          : {r['L_Aeq']:.1f} dB(A)")
    print(f"L_Ceq          : {r['L_Ceq']:.1f} dB(C)")
    print(f"L_C - L_A      : {r['L_C_minus_L_A']:.1f} dB")
    print(f"L_A10 - L_A90  : {r['L_A10_minus_L_A90']:.1f} dB  "
          f"(L_A10={r['L_A10']:.1f}, L_A90={r['L_A90']:.1f})")
    print(f"N10            : {r['N10']:.2f} sone")
    print(f"N50            : {r['N50']:.2f} sone")
    print(f"N10 - N90      : {r['N10_minus_N90']:.2f} sone  "
          f"(N90={r['N90']:.2f})")
    print(f"Sharpness S    : {r['sharpness_S_acum']:.2f} acum")
    print(f"Fluctuation FS : {r['fluctuation_strength_FS_vacil']:.2f} vacil")
    print(f"Roughness R    : {r['roughness_R_asper']:.2f} asper")
