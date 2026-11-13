"""Loudness-Messung fuer Ambisonics (B-Format / HOA) nach ITU-R BS.1770-5
und EBU R 128.

Zwei Messwege:

1. **Decode-Weg** (empfohlen, BS.1770-5 Annex 3/4): Das B-Format wird per
   Energy-Decoding auf eine virtuelle Lautsprecherkonfiguration dekodiert
   und auf den Lautsprecherfeeds mit dem BS.1770-Algorithmus gemessen
   (K-Filter, Elevation-/Surround-Gewichte, Gating).
2. **W-Weg** (nach Wierstorf et al., "Loudness Perception of Scene-Based
   Audio across Loudspeaker Configurations and HOA Orders", AES 2020):
   Direkte Schaetzung aus dem 0. Ordnungs-Koeffizienten (Omni, W).

Ausgegeben werden: Integrated LUFS, max. Short-Term, max. Momentary,
Loudness Range (LRA), True Peak (dBTP) sowie optionale Kurzzeitverläufe
und eine Richtungs-Loudness-Karte (pro Virtueller Lautsprecher).

Konventionen: ACN-Kanalfolge, SN3D-Normalisierung (AmbiX).
"""

from __future__ import annotations

import numpy as np

try:
    from scipy.signal import resample_poly
except ImportError:  # pragma: no cover
    resample_poly = None

try:
    from scipy.signal import lfilter
except ImportError:  # pragma: no cover
    lfilter = None

# ---------------------------------------------------------------------------
# K-Filter (BS.1770 Annex 1, 48 kHz Referenzkoeffizienten)
# ---------------------------------------------------------------------------

_K_STAGE1_48K = {
    "b": [1.53512485958697, -2.69169618940638, 1.19839281085285],
    "a": [1.0, -1.69065929318241, 0.73248077421585],
}
_K_STAGE2_48K = {
    "b": [1.0, -2.0, 1.0],
    "a": [1.0, -1.99004745483398, 0.99007225036621],
}

# Elevation-/Surround-Gewichte nach BS.1770-5 Annex 1/3:
# - Kanäle mit |Elevation| > 5 Grad: G = 1.41 (oberer/unterer Layer)
# - Horizontale Surround-Kanäle (Azimuth 60..120 Grad): G = 1.41
_G_141 = 10 ** (3.01 / 10.0)  # 1.41 => +3.01 dB
_G_10 = 1.0


def _biquad(x: np.ndarray, b, a) -> np.ndarray:
    if lfilter is not None:
        return lfilter(b, a, x)
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    b0, b1, b2 = b
    a0, a1, a2 = a
    for i in range(len(x)):
        xn = x[i]
        yn = (b0 * xn + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1 = x1, xn
        y2, y1 = y1, yn
        y[i] = yn
    return y


def k_filter(x: np.ndarray, fs: int) -> np.ndarray:
    """BS.1770 K-Filter (zweistufiges Pre-Filter)."""
    if fs != 48000:
        if resample_poly is None:
            raise RuntimeError("fs != 48000 benoetigt scipy (resample_poly)")
        x = resample_poly(x, 48000, fs)
        y = _biquad(_biquad(x, _K_STAGE1_48K["b"], _K_STAGE1_48K["a"]),
                    _K_STAGE2_48K["b"], _K_STAGE2_48K["a"])
        return resample_poly(y, fs, 48000)
    return _biquad(_biquad(x, _K_STAGE1_48K["b"], _K_STAGE1_48K["a"]),
                   _K_STAGE2_48K["b"], _K_STAGE2_48K["a"])


def channel_gain(azimuth_deg: float, elevation_deg: float) -> float:
    """BS.1770-5 Gewicht fuer einen Lautsprecher in Grad."""
    if abs(elevation_deg) > 5.0:
        return _G_141
    if 60.0 <= abs(azimuth_deg) <= 120.0:
        return _G_141
    return _G_10


# ---------------------------------------------------------------------------
# Gating-Block-Loudness (BS.1770 Annex 1)
# ---------------------------------------------------------------------------

def _block_loudness(powers: np.ndarray) -> float:
    """Gated Loudness in LUFS aus Kanal-Mittelleistungen pro Block."""
    if powers.size == 0 or not np.any(powers > 0):
        return -float("inf")
    z = powers.sum(axis=0)
    lufs = -0.691 + 10.0 * np.log10(np.maximum(z, 1e-15))
    rel_thresh = lufs.max() - 10.0
    keep = (lufs > -70.0) & (lufs > rel_thresh)
    if not np.any(keep):
        keep = z > 0
    return -0.691 + 10.0 * np.log10(z[keep].mean())


def _mean_square_blocks(y: np.ndarray, fs: int, block_ms: int, hop_ms: int):
    """Mittlere quadratische Werte in ueberlappenden Bloecken."""
    n = int(round(fs * block_ms / 1000.0))
    hop = int(round(fs * hop_ms / 1000.0))
    if y.shape[1] < n:
        return np.zeros((y.shape[0], 0))
    starts = range(0, y.shape[1] - n + 1, hop)
    out = np.zeros((y.shape[0], len(starts)))
    for j, s in enumerate(starts):
        out[:, j] = (y[:, s : s + n] ** 2).mean(axis=1)
    return out


def measure_channels(x: np.ndarray, fs: int, gains: np.ndarray,
                     block_ms: int = 400, hop_ms: int = 100):
    """BS.1770 Gated Loudness fuer Kanal-Signale (n_ch, n_samples).

    x wird NICHT vorgefiltert; erwartet werden die K-gefilterten Signale.
    Liefert (integrated_lufs, block_powers).
    """
    powers = _mean_square_blocks(x, fs, block_ms, hop_ms) * np.asarray(gains)[:, None]
    return _block_loudness(powers), powers


def integrated_lufs(x: np.ndarray, fs: int, gains=None) -> float:
    """Integrated Loudness in LUFS fuer Roh-Signale (n_ch, n_samples)."""
    if gains is None:
        gains = np.ones(x.shape[0])
    y = np.vstack([k_filter(ch, fs) for ch in x])
    lufs, _ = measure_channels(y, fs, gains)
    return lufs


def short_term_series(x: np.ndarray, fs: int, gains=None, hop_ms: int = 1000):
    """Short-Term-Loudness (3 s Fenster, 1 s Hop) in LUFS."""
    if gains is None:
        gains = np.ones(x.shape[0])
    y = np.vstack([k_filter(ch, fs) for ch in x])
    powers = _mean_square_blocks(y, fs, 3000, hop_ms) * np.asarray(gains)[:, None]
    z = powers.sum(axis=0)
    return -0.691 + 10.0 * np.log10(np.maximum(z, 1e-15))


def momentary_series(x: np.ndarray, fs: int, gains=None, hop_ms: int = 100):
    """Momentary-Loudness (400 ms Fenster, 100 ms Hop) in LUFS."""
    if gains is None:
        gains = np.ones(x.shape[0])
    y = np.vstack([k_filter(ch, fs) for ch in x])
    powers = _mean_square_blocks(y, fs, 400, hop_ms) * np.asarray(gains)[:, None]
    z = powers.sum(axis=0)
    return -0.691 + 10.0 * np.log10(np.maximum(z, 1e-15))


def loudness_range(short_term: np.ndarray) -> float:
    """LRA nach EBU Tech 3342 aus Short-Term-Verlauf."""
    st = short_term[short_term > -70.0]
    if st.size == 0:
        return 0.0
    mean = _block_loudness(np.array([st]))
    keep = st > (mean - 20.0)
    if keep.sum() == 0:
        return 0.0
    st = np.sort(st[keep])
    n = st.size
    lo = st[max(0, int(np.floor(0.10 * n)) - 1)]
    hi = st[min(n - 1, int(np.ceil(0.95 * n)) - 1)]
    return float(hi - lo)


def true_peak_dbtp(x: np.ndarray, fs: int, oversample: int = 4) -> float:
    """True Peak in dBTP (4x Oversampling, BS.1770 Annex 2)."""
    if resample_poly is None:
        return 20.0 * np.log10(np.abs(x).max() + 1e-15)
    y = resample_poly(x, oversample, 1)
    peak = np.abs(y).max()
    return float(20.0 * np.log10(peak + 1e-15))


# ---------------------------------------------------------------------------
# Ambisonics: Spherical Harmonics, Encoding, Energy-Decoding
# ---------------------------------------------------------------------------

def acn_order(n_channels: int) -> int:
    """Ambisonics-Ordnung aus Kanalzahl ((N+1)^2 = K, 3D)."""
    n = round(np.sqrt(n_channels)) - 1
    if (n + 1) ** 2 != n_channels:
        raise ValueError(f"{n_channels} Kanäle sind kein vollständiges 3D-HOA-Signal")
    return n


def spherical_harmonics(azimuth_deg: float, elevation_deg: float, order: int) -> np.ndarray:
    """Realwertige SH in ACN/SN3D (AmbiX) fuer eine Richtung, Laenge (order+1)^2."""
    from scipy.special import lpmv

    az = np.deg2rad(azimuth_deg)
    el = np.deg2rad(elevation_deg)
    x = np.sin(el)
    out = []
    for l in range(order + 1):
        for m in range(-l, l + 1):
            norm = np.sqrt((2 * l + 1) / (4 * np.pi) *
                           _factorial_ratio(l, abs(m)))
            plm = ((-1) ** abs(m)) * lpmv(abs(m), l, x)
            if m > 0:
                val = norm * plm * np.cos(m * az) / np.sqrt(2.0)
            elif m < 0:
                val = norm * plm * np.sin(-m * az) / np.sqrt(2.0)
            else:
                val = norm * plm
            out.append(val)
    return np.array(out)


def _factorial_ratio(l: int, m: int) -> float:
    from math import factorial
    return factorial(l - m) / factorial(l + m)


def encode_plane_wave(signal: np.ndarray, azimuth_deg: float, elevation_deg: float,
                      order: int) -> np.ndarray:
    """Plane Wave -> B-Format (ACN/SN3D), Shape ((order+1)^2, n)."""
    y = spherical_harmonics(azimuth_deg, elevation_deg, order)
    return y[:, None] * signal[None, :]


def default_layout(order: int):
    """Virtuelle Lautsprecher: Horizont-Ring + optionaler Layer oben/unten."""
    layout = [(az, 0.0) for az in range(-150, 180, 30)]
    if order >= 1:
        pass
    if order >= 2:
        layout += [(0.0, 45.0), (90.0, 45.0), (180.0, 45.0), (-90.0, 45.0)]
        layout += [(0.0, -45.0), (90.0, -45.0), (180.0, -45.0), (-90.0, -45.0)]
    if order >= 3:
        layout.append((0.0, 90.0))
        layout.append((0.0, -90.0))
    return layout


def energy_decode(b: np.ndarray, layout, order: int) -> np.ndarray:
    """Energy-Decoding (max-rE) des B-Formats auf ein Layout.

    b: ((order+1)^2, n) -> (n_spk, n)
    """
    w = np.zeros(order + 1)
    for l in range(order + 1):
        alpha = np.pi / (2 * order + 2)
        w[l] = (np.sqrt(2 / np.pi) * np.sin((l + 1) * alpha) / ((l + 1) * alpha)
                if l > 0 else 1.0)
    sh = np.vstack([spherical_harmonics(az, el, order) for az, el in layout])
    gain_matrix = np.zeros((sh.shape[0], sh.shape[1]))
    idx = 0
    for l in range(order + 1):
        gain_matrix[:, idx : idx + 2 * l + 1] = w[l]
        idx += 2 * l + 1
    dec = sh * gain_matrix
    norm = np.sqrt((dec ** 2).sum(axis=1))
    norm[norm == 0] = 1.0
    dec = dec / norm[:, None]
    dirs = [(az, el) for az in np.arange(0, 360, 15)
            for el in np.arange(-90, 91, 15)]
    ys = np.vstack([spherical_harmonics(a, e, order) for a, e in dirs])
    mean_energy = ((dec @ ys.T) ** 2).sum(axis=0).mean()
    if mean_energy > 0:
        dec = dec / np.sqrt(mean_energy)
    return dec @ b


# ---------------------------------------------------------------------------
# Haupt-Messung fuer Ambisonics
# ---------------------------------------------------------------------------

def measure_ambisonics(b: np.ndarray, fs: int, layout=None,
                       order: int | None = None) -> dict:
    """Vollstaendige Loudness-Analyse eines B-Format-Signals.

    b: (n_ch, n_samples), ACN/SN3D. Liefert ein Dict mit allen Parametern.
    """
    b = np.atleast_2d(b)
    if order is None:
        order = acn_order(b.shape[0])
    if layout is None:
        layout = default_layout(order)
    gains = np.array([channel_gain(az, el) for az, el in layout])

    spk = energy_decode(b, layout, order)
    y = np.vstack([k_filter(ch, fs) for ch in spk])
    integrated, block_powers = measure_channels(y, fs, gains)

    st = short_term_series(spk, fs, gains)
    mt = momentary_series(spk, fs, gains)

    w_ch = 2.0 * np.sqrt(np.pi) * b[0]
    w_lufs = integrated_lufs(w_ch[None, :], fs)

    return {
        "order": order,
        "n_channels": b.shape[0],
        "integrated_lufs": integrated,
        "max_short_term_lufs": float(st.max()) if st.size else -np.inf,
        "max_momentary_lufs": float(mt.max()) if mt.size else -np.inf,
        "lra": loudness_range(st),
        "true_peak_dbtp": true_peak_dbtp(b, fs),
        "w_only_lufs": w_lufs,
        "short_term_series": st,
        "momentary_series": mt,
        "per_speaker_lufs": [
            {
                "azimuth": az,
                "elevation": el,
                "gain_g": channel_gain(az, el),
                "lufs": integrated_lufs(np.vstack([k_filter(spk[i], fs)]), fs, [gains[i]]),
            }
            for i, (az, el) in enumerate(layout)
        ],
        "layout": layout,
    }


def measure_file(path: str, **kwargs) -> dict:
    """B-Format-WAV einlesen (n_ch = Spalten) und messen."""
    import soundfile as sf

    data, fs = sf.read(path, always_2d=True)
    return measure_ambisonics(data.T, fs, **kwargs)


def print_report(result: dict) -> None:
    print("=== Ambisonic Loudness Report (ITU-R BS.1770-5 / EBU R 128) ===")
    print(f"HOA-Ordnung      : {result['order']} ({result['n_channels']} Kanäle)")
    print(f"Integrated       : {result['integrated_lufs']:.1f} LUFS")
    print(f"Max Short-Term   : {result['max_short_term_lufs']:.1f} LUFS")
    print(f"Max Momentary    : {result['max_momentary_lufs']:.1f} LUFS")
    print(f"Loudness Range   : {result['lra']:.1f} LU")
    print(f"True Peak        : {result['true_peak_dbtp']:.1f} dBTP")
    print(f"W-only (0. Ord.) : {result['w_only_lufs']:.1f} LUFS")
    print("Richtungs-Loudness (Virtuelle Lautsprecher):")
    for s in result["per_speaker_lufs"]:
        print(f"  az {s['azimuth']:>6.1f}° / el {s['elevation']:>5.1f}° "
              f"(G={s['gain_g']:.2f}): {s['lufs']:.1f} LUFS")
