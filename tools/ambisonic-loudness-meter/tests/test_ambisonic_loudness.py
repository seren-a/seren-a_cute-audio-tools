"""Tests fuer ambisonic_loudness (ITU-R BS.1770-5 / EBU R 128)."""

import os
import sys

import numpy as np
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))
from ambisonic_loudness import (  # noqa: E402
    acn_order,
    channel_gain,
    encode_plane_wave,
    energy_decode,
    integrated_lufs,
    loudness_range,
    measure_ambisonics,
    spherical_harmonics,
    true_peak_dbtp,
)

FS = 48000


def sine(dbfs: float, seconds: float = 20.0, freq: float = 1000.0) -> np.ndarray:
    amp = 10 ** (dbfs / 20.0)
    t = np.arange(int(FS * seconds)) / FS
    return amp * np.sin(2 * np.pi * freq * t)


def test_acn_order():
    assert acn_order(4) == 1
    assert acn_order(9) == 2
    assert acn_order(16) == 3
    with pytest.raises(ValueError):
        acn_order(5)


def test_channel_gain():
    assert channel_gain(0, 0) == 1.0
    assert channel_gain(30, 0) == 1.0
    assert channel_gain(110, 0) == pytest.approx(10 ** (3.01 / 10))
    assert channel_gain(0, 45) == pytest.approx(10 ** (3.01 / 10))


def test_stereo_reference():
    """BS.1770-Referenz: Stereo 1 kHz Sine bei -23 dBFS => -23 LUFS (+/-0.1)."""
    s = sine(-23.0)
    lufs = integrated_lufs(np.vstack([s, s]), FS)
    assert lufs == pytest.approx(-23.0, abs=0.1)


def test_surround_gain():
    """Ein einzelner Kanal mit G=1.41 muss +3.01 dB dazugeben."""
    s = sine(-23.0)
    front = integrated_lufs(s[None, :], FS, [1.0])
    surround = integrated_lufs(s[None, :], FS, [10 ** (3.01 / 10)])
    assert surround - front == pytest.approx(3.01, abs=0.1)


def test_sh_orthonality_first_order():
    """ACN/SN3D: Y(0,0) konstant 1/(2*sqrt(pi)), Orthonormierung grob."""
    y0 = spherical_harmonics(0.0, 0.0, 1)
    assert y0[0] == pytest.approx(1 / (2 * np.sqrt(np.pi)))
    assert y0.shape == (4,)


def test_plane_wave_decode_direction():
    """Energy-Decoding: Maximum des dekodierten Signals beim Ziel-Lautsprecher."""
    order = 1
    sig = sine(-20.0, 5.0)
    b = encode_plane_wave(sig, 90.0, 0.0, order)
    layout = [(-90.0, 0.0), (0.0, 0.0), (90.0, 0.0), (180.0, 0.0)]
    spk = energy_decode(b, layout, order)
    rms = np.sqrt((spk ** 2).mean(axis=1))
    assert int(np.argmax(rms)) == 2


def test_direction_invariance_hoa():
    """Rotation des B-Format-Signals darf Integrated Loudness kaum aendern."""
    sig = sine(-23.0, 10.0)
    lufs = []
    for az in [0.0, 45.0, 90.0, 135.0]:
        b = encode_plane_wave(sig, az, 0.0, 3)
        r = measure_ambisonics(b, FS)
        lufs.append(r["integrated_lufs"])
    assert max(lufs) - min(lufs) < 1.5


def test_report_params_present():
    sig = sine(-23.0, 10.0)
    b = encode_plane_wave(sig, 30.0, 0.0, 1)
    r = measure_ambisonics(b, FS)
    for key in ["integrated_lufs", "max_short_term_lufs", "max_momentary_lufs",
                "lra", "true_peak_dbtp", "w_only_lufs", "per_speaker_lufs"]:
        assert key in r
    assert r["integrated_lufs"] == pytest.approx(r["w_only_lufs"], abs=2.5)


def test_lra_constant_signal():
    st = np.full(20, -23.0)
    assert loudness_range(st) == pytest.approx(0.0, abs=0.1)


def test_true_peak():
    s = sine(-3.0, 1.0)
    tp = true_peak_dbtp(s[None, :], FS)
    assert tp > -3.0
    assert tp < -2.5
