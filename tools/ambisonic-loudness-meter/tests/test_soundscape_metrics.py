"""Tests fuer soundscape_metrics (Torresin et al. 2020 Parameter)."""

import os
import sys

import numpy as np
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
from soundscape_metrics import (  # noqa: E402
    apply_weighting,
    fluctuation_strength,
    measure_soundscape,
)

FS = 48000


def sine(dbfs: float, seconds: float, freq: float = 1000.0) -> np.ndarray:
    amp = 10 ** (dbfs / 20.0)
    t = np.arange(int(FS * seconds)) / FS
    return amp * np.sin(2 * np.pi * freq * t)


def test_a_weighting_1khz():
    """A-Bewertung bei 1 kHz muss ~0 dB sein."""
    s = sine(-6.0, 2.0)
    y = apply_weighting(s, FS, "a")
    gain_db = 20 * np.log10(np.sqrt((y ** 2).mean()) / np.sqrt((s ** 2).mean()))
    assert gain_db == pytest.approx(0.0, abs=0.5)


def test_a_weighting_attenuates_bass():
    """A-Bewertung daempft 100 Hz gegenueber 1 kHz um ~19 dB."""
    s1k = apply_weighting(sine(-6.0, 2.0, 1000.0), FS, "a")
    s100 = apply_weighting(sine(-6.0, 2.0, 100.0), FS, "a")
    g1k = 10 * np.log10((s1k ** 2).mean())
    g100 = 10 * np.log10((s100 ** 2).mean())
    assert g100 - g1k == pytest.approx(-19.1, abs=1.5)


def test_c_minus_a_bass_heavy():
    """Tieffrequentes Signal muss L_C - L_A gross machen."""
    bass = sine(-6.0, 3.0, 60.0)
    r = measure_soundscape(bass, FS, spl_offset_db=94.0)
    assert r["L_C_minus_L_A"] > 15.0
    # und Flachtton (1 kHz) nahe 0
    r2 = measure_soundscape(sine(-6.0, 3.0, 1000.0), FS, spl_offset_db=94.0)
    assert abs(r2["L_C_minus_L_A"]) < 3.0


def test_laeq_calibration():
    """Vollskala-Sinus (RMS -3 dBFS) mit Offset 94 dB => L_Aeq ~91 dB."""
    r = measure_soundscape(sine(0.0, 3.0), FS, spl_offset_db=94.0)
    assert r["L_Aeq"] == pytest.approx(91.0, abs=1.0)


def test_zwicker_loudness_1khz_60db():
    """1 kHz bei 60 dB SPL (RMS-normiert) entspricht ~4 sone (ISO 532-1)."""
    t = np.arange(int(FS * 4)) / FS
    x = np.sqrt(2.0) * np.sin(2 * np.pi * 1000.0 * t)
    r = measure_soundscape(x, FS, spl_offset_db=60.0)
    assert r["N50"] == pytest.approx(4.0, abs=1.5)


def test_level_variability_modulated_signal():
    """AM-moduliertes Signal muss hoehere L_A10-L_A90 zeigen als Konstantton."""
    rng = np.random.default_rng(0)
    t = np.arange(int(FS * 10)) / FS
    carrier = sine(-20.0, 10.0)
    am = (0.5 + 0.5 * np.sin(2 * np.pi * 0.5 * t)) * carrier
    const = carrier
    assert measure_soundscape(am, FS)["L_A10_minus_L_A90"] > \
        measure_soundscape(const, FS)["L_A10_minus_L_A90"]


def test_fluctuation_strength_4hz():
    """Lautheitsverlauf mit 4-Hz-Modulation muss hoehere FS zeigen als 0.5 Hz."""
    fs_n = 500.0
    t = np.arange(int(fs_n * 8)) / fs_n
    base = 20.0
    n4 = base * (1 + 0.9 * np.sin(2 * np.pi * 4.0 * t))
    n05 = base * (1 + 0.9 * np.sin(2 * np.pi * 0.5 * t))
    assert fluctuation_strength(n4) > 0
    assert fluctuation_strength(n4) > fluctuation_strength(n05)
    assert fluctuation_strength(np.full_like(t, base)) == 0.0


def test_all_params_present():
    r = measure_soundscape(sine(-20.0, 5.0), FS)
    for key in ["L_Aeq", "L_Ceq", "L_C_minus_L_A", "L_A10", "L_A90",
                "L_A10_minus_L_A90", "N10", "N50", "N90", "N10_minus_N90",
                "sharpness_S_acum", "fluctuation_strength_FS_vacil",
                "roughness_R_asper"]:
        assert key in r
        assert np.isfinite(r[key])
