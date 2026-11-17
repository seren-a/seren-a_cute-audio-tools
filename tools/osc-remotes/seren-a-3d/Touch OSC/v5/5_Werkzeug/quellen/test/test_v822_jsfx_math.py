"""v8.22: Mathe des JSFX (Python-Nachbau, Formeln direkt aus der .jsfx gelesen) gegen unabhaengige Referenz (scipy, AmbiX: ACN/SN3D)."""
import re, math, os
import numpy as np
from scipy.special import lpmv, factorial
D = os.path.dirname(os.path.abspath(__file__))
fails = 0
def check(c, m):
    global fails
    print(('PASS ' if c else 'FAIL ') + m); fails += 0 if c else 1
P = next(p for p in (os.path.join(D, '..', 'jsfx', 'seren-a_3D_Energy.jsfx'), os.path.join(D, '..', 'reaper', 'seren-a_3D_Energy.jsfx')) if os.path.exists(p))
src = open(P).read()
init = src.split('@init')[1].split('@slider')[0]
consts = dict(s3=math.sqrt(3), s5_8=math.sqrt(5/8), s3_8=math.sqrt(3/8), s15=math.sqrt(15), s15_2=math.sqrt(15)/2, s3_2=math.sqrt(3)/2)
lines = {int(m.group(1)): m.group(2) for m in re.finditer(r'YB\[o\+(\d+)\]\s*=\s*([^;]+);', init)}
check(sorted(lines) == list(range(16)), '16 SH-Formeln im JSFX gefunden')
def sh_jsfx(az, el):
    x = math.cos(el) * math.cos(az); y = math.cos(el) * math.sin(az); z = math.sin(el)
    env = dict(consts, x=x, y=y, z=z, x2=x*x, y2=y*y, z2=z*z)
    return np.array([eval(lines[k], {}, env) for k in range(16)])
def sh_ref(az, el):                                  # AmbiX: ACN, SN3D, ohne Condon-Shortley-Phase
    out = np.zeros(16)
    for n in range(4):
        for m in range(-n, n + 1):
            am = abs(m)
            nrm = math.sqrt((2 - (1 if m == 0 else 0)) * factorial(n - am) / factorial(n + am))
            p = (-1) ** am * lpmv(am, n, math.sin(el))
            tr = math.cos(am * az) if m >= 0 else math.sin(am * az)
            out[n * n + n + m] = nrm * p * tr
    return out
rng = np.random.default_rng(1)
err = max(np.abs(sh_jsfx(a, e) - sh_ref(a, e)).max() for a, e in zip(rng.uniform(-math.pi, math.pi, 200), rng.uniform(-math.pi/2, math.pi/2, 200)))
check(err < 1e-12, f'SH-Formeln = AmbiX (ACN/SN3D) bis 3. Ordnung, max. Abweichung {err:.1e}')
# Orthogonalitaet: Kugelmittel von Y_k*Y_l = delta/(2n+1)
cz = (np.arange(100) + 0.5) / 50 - 1; th = (np.arange(200) + 0.5) * 2 * math.pi / 200 - math.pi
G = np.array([sh_ref(a, math.asin(z)) for z in cz for a in th]); w = np.ones(len(G))   # Mittelpunktsregel, gleichverteilt in sin(Elevation)
M = (G.T * w) @ G / w.sum()
ex = np.diag([1 / (2 * math.floor(math.sqrt(k)) + 1) for k in range(16)])
check(np.abs(M - ex).max() < 5e-3, f'Orthogonalitaet SN3D (Abweichung {np.abs(M-ex).max():.1e})')

# Algorithmus-Nachbau (wie @sample/@block)
def grid():
    cells = []
    for c in range(288):
        row, col = divmod(c, 24)
        az = math.radians(180 - (col + 0.5) * 15); el = math.radians(90 - (row + 0.5) * 15)
        cells.append((az, el))
    return cells
CELLS = grid(); Y = np.array([sh_jsfx(a, e) for a, e in CELLS])
def energy_map(sig, ordr):                           # sig: (samples, 16)
    n = (ordr + 1) ** 2
    S = (sig[:, :n].T @ sig[:, :n]) / len(sig)
    e = np.einsum('ci,ij,cj->c', Y[:, :n], S, Y[:, :n]) / (ordr + 1) ** 2
    return 10 * np.log10(np.maximum(1e-10, e)).reshape(12, 24), 10 * np.log10(max(1e-10, S[0, 0]))
t = np.arange(48000) / 48000.0
sine = np.sin(2 * math.pi * 997 * t)
for ordr in (1, 2, 3):
    for az_d, el_d in ((0, 0), (90, 0), (-135, 30), (45, -50), (180, 0)):
        d = sh_ref(math.radians(az_d), math.radians(el_d))
        sig = np.outer(sine, d)
        m, mean = energy_map(sig, ordr)
        r, c = np.unravel_index(np.argmax(m), m.shape)
        az = 180 - (c + 0.5) * 15; el = 90 - (r + 0.5) * 15
        dAz = abs((az - az_d + 180) % 360 - 180); dEl = abs(el - el_d)
        if ordr == 3 or ordr == 2:
            check(dAz <= 15 and dEl <= 15, f'Ordnung {ordr}: Ebene Welle ({az_d},{el_d}) -> Spitze bei ({az:.1f},{el:.1f})')
        else:
            check(dAz <= 30 and dEl <= 30, f'Ordnung {ordr}: Ebene Welle ({az_d},{el_d}) -> Spitze bei ({az:.1f},{el:.1f}) (grob)')
        check(abs(m.max() - (-3.0)) < 1.2 + (0 if ordr > 1 else 1.0), f'  Spitzenpegel {m.max():.2f} dB (Sinus RMS = -3 dB)')
        check(abs(mean - (-3.0)) < 0.05, f'  Mittelwert (W) {mean:.2f} dB')
        if ordr == 3: pass
# diffuses Feld: unkorrelierte Kanaele -> Karte flach
sig = rng.standard_normal((48000, 16)) * np.array([1 / math.sqrt(2 * math.floor(math.sqrt(k)) + 1) for k in range(16)])
m, mean = energy_map(sig, 3)
check(m.max() - m.min() < 3.0, f'diffus: Karte nahezu flach (Streuung {m.max()-m.min():.2f} dB)')
# Stille
m, mean = energy_map(np.zeros((1000, 16)), 3)
check(m.max() <= -99.9 and mean <= -99.9, 'Stille -> -100 dB (Surface: Bereich -80..+10 dB)')
print('\nALL OK' if not fails else f'\n{fails} FAILED')
