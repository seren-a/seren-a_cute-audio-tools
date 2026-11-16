// Psychoacoustics.h -- Portierung der mosqito-Psychoakustik (ISO 532-1 Zwicker
// zeitvariabel, DIN 45692 Sharpness, Daniel-Weber Roughness, Fluctuation
// Strength) in den JUCE-unabhaengigen DSP-Kern. Validiert gegen mosqito
// (siehe PsyTests.cpp). Tabellen: PsychoTables.h (generiert aus mosqito).
//
// Signale in Pascal, fs wird intern auf 48 kHz gebracht (wie mosqito).

#pragma once

#include <algorithm>
#include <cmath>
#include <complex>
#include <cstddef>
#include <vector>

#include "PsychoTables.h"

#ifndef ALD_KPI_DEFINED
#define ALD_KPI_DEFINED
namespace ald {
constexpr double kPi = 3.14159265358979323846;
}
#endif

namespace ald {

// ---------------------------------------------------------------------------
// kleine Helfer
// ---------------------------------------------------------------------------

inline double interpLin(double x, const double* xp, const double* yp, int n) {
    if (x <= xp[0]) return yp[0];
    if (x >= xp[n - 1]) return yp[n - 1];
    int i = 0;
    while (i < n - 2 && xp[i + 1] < x) ++i;
    double t = (x - xp[i]) / (xp[i + 1] - xp[i]);
    return yp[i] + t * (yp[i + 1] - yp[i]);
}

inline double freq2bark(double f) {
    return interpLin(f, tables::f2b_xp, tables::f2b_yp, (int)tables::f2b_xp_size);
}
inline double bark2freq(double b) {
    return interpLin(b, tables::b2f_xp, tables::b2f_yp, (int)tables::b2f_xp_size);
}

// FFT fuer beliebige Laenge via Bluestein (chirp-z); inverse mit 1/n.
inline void fftBluestein(std::vector<std::complex<double>>& a, bool inverse) {
    const size_t n = a.size();
    if (n <= 1) return;
    if ((n & (n - 1)) == 0) {  // power of two: radix-2
        for (size_t i = 1, j = 0; i < n; ++i) {
            size_t bit = n >> 1;
            for (; j & bit; bit >>= 1) j ^= bit;
            j ^= bit;
            if (i < j) std::swap(a[i], a[j]);
        }
        for (size_t len = 2; len <= n; len <<= 1) {
            double ang = 2.0 * kPi / (double)len * (inverse ? 1.0 : -1.0);
            std::complex<double> wlen(std::cos(ang), std::sin(ang));
            for (size_t i = 0; i < n; i += len) {
                std::complex<double> w(1.0, 0.0);
                for (size_t j = 0; j < len / 2; ++j) {
                    auto u = a[i + j];
                    auto v = a[i + j + len / 2] * w;
                    a[i + j] = u + v;
                    a[i + j + len / 2] = u - v;
                    w *= wlen;
                }
            }
        }
        if (inverse)
            for (auto& v : a) v /= (double)n;
        return;
    }
    // Bluestein: X[k] = chirp[k] * sum_j (x[j] chirp[j]) conj(chirp[k-j]),
    // chirp[k] = exp(-i pi k^2 / n) vorwaerts, exp(+i pi k^2 / n) rueckwaerts (mit 1/n)
    size_t m = 1;
    while (m < 2 * n - 1) m <<= 1;
    std::vector<std::complex<double>> chirp(n), A(m), B(m);
    for (size_t k = 0; k < n; ++k) {
        double ang = kPi * (double)k * (double)k / (double)n * (inverse ? 1.0 : -1.0);
        chirp[k] = std::complex<double>(std::cos(ang), std::sin(ang));
    }
    for (size_t k = 0; k < n; ++k) {
        A[k] = a[k] * chirp[k];
        B[k] = std::conj(chirp[k]);
        if (k > 0) B[m - k] = std::conj(chirp[k]);
    }
    fftBluestein(A, false);
    fftBluestein(B, false);
    for (size_t k = 0; k < m; ++k) A[k] *= B[k];
    fftBluestein(A, true);
    for (size_t k = 0; k < n; ++k) a[k] = A[k] * chirp[k] / (inverse ? (double)n : 1.0);
}

// Fenstered-Sinc-Resampler auf 48 kHz (mosqito resampelt <48 kHz hoch)
inline std::vector<double> resampleTo48k(const double* x, size_t n, double fs) {
    if (fs == 48000.0) return std::vector<double>(x, x + n);
    const double ratio = 48000.0 / fs;
    size_t nOut = (size_t)std::llround(n * ratio);
    std::vector<double> out(nOut);
    const int M = 32;  // Halblaenge in Quelleinheiten
    for (size_t i = 0; i < nOut; ++i) {
        double pos = i / ratio;
        long base = (long)std::floor(pos);
        double sum = 0, wsum = 0;
        for (int k = -M; k <= M; ++k) {
            long idx = base + k;
            if (idx < 0 || idx >= (long)n) continue;
            double t = pos - idx;
            double sinc = (std::abs(t) < 1e-12) ? 1.0 : std::sin(kPi * t) / (kPi * t);
            double r = t / M;
            double w = 0.42 + 0.5 * std::cos(kPi * r) + 0.08 * std::cos(2 * kPi * r);  // Blackman
            sum += x[idx] * sinc * w;
            wsum += sinc * w;
        }
        out[i] = wsum != 0 ? sum / wsum : 0.0;
    }
    return out;
}

// ---------------------------------------------------------------------------
// Zwicker-Lautheit, zeitvariabel (ISO 532-1 Methode 1, wie mosqito loudness_zwtv)
// ---------------------------------------------------------------------------

namespace zwicker {

constexpr int kBands = 28;      // 1/3-Oktavbaender 25 Hz .. 12.5 kHz
constexpr int kCore = 21;       // kritische Baender (nm)
constexpr int kSpec = 240;      // Bark-Raster 0.1..24

struct ThirdOctave {
    // Biquad-Zustaende pro Band (3 Sektionen) + Glättung
    struct BandState {
        double bq[3][5] = {{0}};  // x1,x2,y1,y2 pro Sektion
        double lp[3] = {0, 0, 0};
    };
    BandState st[kBands];

    void reset() { *this = ThirdOctave(); }

    // sig in Pa bei 48 kHz -> spec[kBands][nOut] in dB re 2e-5, decimiert auf 2 kHz
    void levels(const double* sig, size_t n, std::vector<std::vector<double>>& spec) {
        const int dec = 24;  // 48000/2000
        size_t nOut = n / dec;
        spec.assign(kBands, std::vector<double>(nOut, 0.0));
        for (int b = 0; b < kBands; ++b) {
            // Koeffizienten: ref - diff, als 3 SOS [b0,b1,b2,a0,a1,a2]
            double sos[3][6];
            for (int s = 0; s < 3; ++s)
                for (int c = 0; c < 6; ++c)
                    sos[s][c] = tables::third_octave_filter_ref[s][c] -
                                tables::third_octave_filter[b * 18 + s * 6 + c];
            double fc = std::pow(10.0, (b - 16) / 10.0) * 1000.0;
            double tau = (fc <= 1000.0) ? 2.0 / (3.0 * fc) : 2.0 / 3000.0;
            double a1 = std::exp(-1.0 / (48000.0 * tau));
            double b0 = 1.0 - a1;
            std::vector<double> filt(n);
            for (size_t i = 0; i < n; ++i) {
                double x = sig[i] * tables::filter_gain[b];
                for (int s = 0; s < 3; ++s) {
                    double* q = st[b].bq[s];
                    double y = (sos[s][0] * x + sos[s][1] * q[0] + sos[s][2] * q[1] -
                                sos[s][4] * q[2] - sos[s][5] * q[3]) /
                               sos[s][3];
                    q[1] = q[0]; q[0] = x;
                    q[3] = q[2]; q[2] = y;
                    x = y;
                }
                filt[i] = x;
            }
            for (size_t i = 0; i < n; ++i) {
                double v = filt[i] * filt[i];
                for (int k = 0; k < 3; ++k) {
                    st[b].lp[k] = b0 * v + a1 * st[b].lp[k];
                    v = st[b].lp[k];
                }
                filt[i] = v;
            }
            for (size_t j = 0; j < nOut; ++j)
                spec[b][j] = 10.0 * std::log10((filt[j * dec] + 1e-12) / 4e-10);
        }
    }
};

// Core-Loudness nm[21] pro Frame (spec[28])
inline void mainLoudness(const double* spec, bool diffuse, double* nm) {
    double ti[11];
    for (int j = 0; j < 11; ++j) {
        double L = spec[j];
        bool logic[8];
        for (int k = 0; k < 8; ++k) logic[k] = L > (tables::rap[k] - tables::dll[k][j]);
        double dllRes = tables::dll[0][j];
        if (logic[0]) dllRes = 0.0;
        for (int k = 1; k <= 6; ++k)
            if (logic[k - 1] != logic[k]) dllRes = tables::dll[k][j];
        ti[j] = std::pow(10.0, (dllRes + L) / 10.0);
    }
    double gi[3] = {0, 0, 0};
    for (int i = 0; i < 6; ++i) gi[0] += ti[i];
    for (int i = 6; i < 9; ++i) gi[1] += ti[i];
    for (int i = 9; i < 11; ++i) gi[2] += ti[i];
    double lcb[3];
    for (int c = 0; c < 3; ++c) lcb[c] = gi[c] > 0 ? 10.0 * std::log10(gi[c]) : 0.0;

    for (int i = 0; i < 20; ++i) {
        double le = spec[8 + i];
        if (i < 3) le = lcb[i];
        le -= tables::a0[i];
        if (diffuse) le += tables::ddf[i];
        bool above = le > tables::ltq[i];
        if (above) le -= tables::dcb[i];
        double mp1 = above ? 0.0635 * std::pow(10.0, 0.025 * tables::ltq[i]) : 0.0;
        double mp2 = above ? std::pow(1.0 - 0.25 + 0.25 * std::pow(10.0, 0.1 * (le - tables::ltq[i])), 0.25) - 1.0 : 0.0;
        double v = mp1 * mp2;
        if (!above) v = 0.0;
        if (v < 0) v = 0;
        nm[i] = v;
    }
    nm[20] = 0.0;
    double korry = 0.4 + 0.32 * std::pow(nm[0], 0.2);
    if (korry <= 1.0) nm[0] *= korry;
}

// nichtlinearer zeitlicher Verlauf (State-Machine), core[21][T] @ 2 kHz
inline void nlLoudness(const std::vector<std::vector<double>>& core,
                       std::vector<std::vector<double>>& out) {
    const int T = (int)core[0].size();
    const int iter = 24;
    const double sr = 2000.0;
    const double tShort = 0.005, tLong = 0.015, tVar = 0.075;
    const double dt = 1.0 / (sr * iter);
    const double P = (tVar + tLong) / (tVar * tShort);
    const double Q = 1.0 / (tShort * tVar);
    const double l1 = -P / 2 + std::sqrt(P * P / 4 - Q);
    const double l2 = -P / 2 - std::sqrt(P * P / 4 - Q);
    const double den = tVar * (l1 - l2);
    const double e1 = std::exp(l1 * dt), e2 = std::exp(l2 * dt);
    const double B[6] = {
        (e1 - e2) / den,
        ((tVar * l2 + 1) * e1 - (tVar * l1 + 1) * e2) / den,
        ((tVar * l1 + 1) * e1 - (tVar * l2 + 1) * e2) / den,
        (tVar * l1 + 1) * (tVar * l2 + 1) * (e1 - e2) / den,
        std::exp(-dt / tLong),
        std::exp(-dt / tVar),
    };
    // upsampling
    std::vector<std::vector<double>> ui(kCore, std::vector<double>((size_t)T * iter));
    for (int b = 0; b < kCore; ++b)
        for (int t = 0; t < T; ++t) {
            // mosqito: delta[-1] = 0 vor (delta - core)/iter -> letzter Schritt = -core[-1]/iter
            double d = (t + 1 < T) ? (core[b][t + 1] - core[b][t]) / iter : -core[b][t] / iter;
            ui[b][(size_t)t * iter] = core[b][t];
            for (int k = 1; k < iter; ++k) ui[b][(size_t)t * iter + k] = ui[b][(size_t)t * iter + k - 1] + d;
        }
    std::vector<std::vector<double>> uo = ui, u2(kCore, std::vector<double>((size_t)T * iter, 0.0));
    for (int b = 0; b < kCore; ++b)
        if (core[b][0] >= 1e-5) u2[b][0] = core[b][0] * (1.0 - B[5]);
    const int cols = T * iter;
    for (int col = 0; col < cols; ++col) {
        int prev = (col - 1 + cols) % cols;
        for (int b = 0; b < kCore; ++b) {
            double uoP = uo[b][prev], u2P = u2[b][prev], uiC = ui[b][col];
            double uo2 = uoP * B[2] - u2P * B[3];
            if (uoP > u2P && uo2 >= uiC) uo[b][col] = uo2;
            double uo2b = uoP * B[4];
            if (uoP <= u2P && uo2b >= uiC) uo[b][col] = uo2b;
            u2[b][col] = uo[b][col];
            double u22 = uoP * B[0] - u2P * B[1];
            if (uiC < uoP && uoP > u2P && u22 <= uo[b][col]) u2[b][col] = u22;
            double u2n = (u2P - uiC) * B[5] + uiC;
            if (uiC >= uoP && !(std::abs(uiC - uoP) < 1e-5 && uo[b][col] <= u2P)) u2[b][col] = u2n;
        }
    }
    out.assign(kCore, std::vector<double>(T));
    for (int b = 0; b < kCore; ++b)
        for (int t = 0; t < T; ++t) out[b][t] = uo[b][(size_t)t * iter];
}

inline int rnsIndex(double v, bool equalToo) {
    int idx = 0;
    double vr = std::round(v * 1e8) / 1e8;
    for (int k = 0; k < 18; ++k) {
        double rk = std::round(tables::rns[k] * 1e8) / 1e8;
        if (equalToo ? (vr <= rk) : (vr < rk)) ++idx;
    }
    if (idx == 18) idx = 17;
    return idx;
}

// Spreading/Slopes: nm[21] pro Frame -> N, Nspec[240]
inline void calcSlopes(const double* nm, double& N, double* Nspec) {
    const int nmWide = kCore;  // 21
    // usl_reshaped[18][21]: Spalten 0..7 = usl, 8..20 = usl[:,7]
    auto uslR = [](int r, int c) { return tables::usl[r][c < 8 ? c : 7]; };
    int zupEa[nmWide + 1];
    double zup[nmWide];
    for (int i = 0; i < nmWide; ++i) {
        zup[i] = tables::zup[i];
        zupEa[i] = (int)(zup[i] * 10.0);  // wie np.astype(int32) nach *10
    }
    zupEa[nmWide] = 0;

    for (int j = 0; j < kSpec; ++j) Nspec[j] = 0.0;
    for (int i = 0; i < nmWide - 1; ++i) {
        int lo = zupEa[(i - 1 + nmWide + 1) % (nmWide + 1)];
        int hi = zupEa[i];
        for (int j = lo; j < hi; ++j) Nspec[j] = nm[i];
    }

    int rnsInd[nmWide];
    double rnsVal[nmWide], uslArr[nmWide], dz[nmWide];
    for (int i = 0; i < nmWide; ++i) {
        rnsInd[i] = rnsIndex(nm[i], false);
        rnsVal[i] = tables::rns[rnsInd[i]];
        uslArr[i] = uslR(rnsInd[i], i);
    }
    for (int i = 0; i < nmWide; ++i) {
        int prev = (i - 1 + nmWide) % nmWide;
        dz[i] = zup[i] - zup[prev];
    }
    dz[0] = zup[1];
    dz[1] = zup[1];

    double n2a[kSpec], z2a[kSpec], usla[kSpec], dza[kSpec], rnsva[kSpec];
    for (int j = 0; j < kSpec; ++j) {
        n2a[j] = z2a[j] = usla[j] = dza[j] = rnsva[j] = 1.0;
    }
    for (int i = 0; i < nmWide; ++i) {
        int lo = zupEa[(i - 1 + nmWide + 1) % (nmWide + 1)];
        int hi = zupEa[i];
        for (int j = lo; j < hi; ++j) {
            n2a[j] = nm[i];
            dza[j] = dz[i];
            z2a[j] = zup[i];
            usla[j] = uslArr[i];
            rnsva[j] = rnsVal[i];
        }
    }

    N = 0.0;
    double n1aux = 0.0, z1aux = 0.0;
    auto r8 = [](double v) { return std::round(v * 1e8) / 1e8; };

    for (int i = 0; i < nmWide; ++i) {
        int j = zupEa[(i - 1 + nmWide + 1) % (nmWide + 1)];
        int jm1 = (j - 1 + kSpec) % kSpec;
        int idx = rnsIndex(n2a[jm1], false);
        rnsva[j] = tables::rns[idx];
        usla[j] = uslR(idx, (i - 1 + nmWide) % nmWide);

        bool m = r8(n2a[jm1]) > r8(nm[i]);
        if (!m) {
            N += n2a[j] * (z2a[j] - z1aux);
            n1aux = n2a[j];
            z1aux = z2a[j];
        }
        if (m) {
            double mx = std::max(rnsva[jm1], nm[i]);
            z2a[j] = std::min((n1aux - mx) / usla[j] + z1aux, zup[i]);
            dza[j] = z2a[j] - z1aux;
            n2a[j] = n1aux - dza[j] * usla[j];
            N += dza[j] * (n1aux + n2a[j]) / 2.0;

            double zArray = zup[(i - 1 + nmWide) % nmWide] + 0.1;
            int lastJ = j;
            bool lastZbigger = false;
            for (int jj = zupEa[(i - 1 + nmWide + 1) % (nmWide + 1)]; jj < zupEa[i]; ++jj) {
                lastJ = jj;
                if (jj != zupEa[(i - 1 + nmWide + 1) % (nmWide + 1)]) {
                    z2a[jj] = z2a[jj - 1];
                    n2a[jj] = n2a[jj - 1];
                    dza[jj] = dza[jj - 1];
                    usla[jj] = usla[jj - 1];
                    rnsva[jj] = rnsva[jj - 1];
                }
                bool zbigger = m && (r8(z2a[jj]) <= r8(zArray));
                lastZbigger = zbigger;
                if (zbigger) {
                    int idx2 = rnsIndex(n2a[jj], true);
                    rnsva[jj] = tables::rns[idx2];
                    usla[jj] = uslR(idx2, (i - 1 + nmWide) % nmWide);
                    double n1c = n2a[jj], z1c = z2a[jj];
                    bool b1 = r8(n1c) <= r8(nm[i]);
                    if (b1) {
                        n2a[jj] = nm[i];
                        z2a[jj] = zup[i];
                        dza[jj] = z2a[jj] - z1c;
                        N += n2a[jj] * (z2a[jj] - z1c);
                    } else {
                        double mx2 = std::max(rnsva[jj], nm[i]);
                        z2a[jj] = std::min((n1c - mx2) / usla[jj] + z1c, zup[i]);
                        dza[jj] = z2a[jj] - z1c;
                        n2a[jj] = n1c - dza[jj] * usla[jj];
                        N += dza[jj] * (n1c + n2a[jj]) / 2.0;
                        Nspec[jj] = n1c - (zArray - z1c) * usla[jj];
                    }
                    m = m != b1;  // xor
                } else if (m) {
                    Nspec[jj] = n1aux - (zArray - z1aux) * usla[jj];
                }
                zArray += 0.1;
                z1aux = z2a[jj];
                n1aux = n2a[jj];
                if (!m) break;
            }
            z1aux = z2a[zupEa[i] - 1];
            n1aux = n2a[zupEa[i] - 1];
            if (lastZbigger) {
                int idx3 = rnsIndex(n2a[lastJ], true);
                rnsva[lastJ] = tables::rns[idx3];
                usla[lastJ] = uslR(idx3, (i - 1 + nmWide) % nmWide);
            }
        }
    }
    if (N < 0) N = 0;
    if (N <= 16.0) N = std::floor(N * 1000 + 0.5) / 1000;
    else N = std::floor(N * 100 + 0.5) / 100;
}

// 1st-order LP mit linearer Interpolation (upsample x24), wie mosqito _lowpass_intp
inline void lowpassIntp(const std::vector<double>& x, double tau, double sr,
                        std::vector<double>& out) {
    const int iter = 24;
    const size_t n = x.size();
    const double a1 = std::exp(-1.0 / (sr * iter * tau));
    const double b0 = 1.0 - a1;
    std::vector<double> up(n * iter);
    for (size_t t = 0; t < n; ++t) {
        double d = (t + 1 < n) ? (x[t + 1] - x[t]) / iter : -x[t] / iter;
        up[t * iter] = x[t];
        for (int k = 1; k < iter; ++k) up[t * iter + k] = up[t * iter + k - 1] + d;
    }
    double y = 0;
    for (auto& v : up) {
        y = b0 * v + a1 * y;
        v = y;
    }
    out.assign(n, 0.0);
    for (size_t t = 0; t < n; ++t) out[t] = up[t * iter];
}

}  // namespace zwicker

// Gesamte zeitvariante Zwicker-Loudness. p in Pa, fs beliebig (>=8kHz sinnvoll).
// Rueckgabe: N(t) @ 2 ms [sone], Nspec[kSpec][nT] [sone/bark]
struct LoudnessTV {
    std::vector<double> N;                        // 2-ms-Raster
    std::vector<std::vector<double>> Nspec;      // [240][nT]
};

inline LoudnessTV loudnessZwtv(const double* p, size_t n, double fs, bool diffuse = false) {
    std::vector<double> p48 = resampleTo48k(p, n, fs);
    const size_t n48 = p48.size();

    zwicker::ThirdOctave to;
    std::vector<std::vector<double>> spec;
    to.levels(p48.data(), n48, spec);
    const int T = (int)spec[0].size();

    std::vector<std::vector<double>> core(zwicker::kCore, std::vector<double>(T));
    for (int t = 0; t < T; ++t) {
        double col[zwicker::kBands];
        for (int b = 0; b < zwicker::kBands; ++b) col[b] = spec[b][t];
        double nm[zwicker::kCore];
        zwicker::mainLoudness(col, diffuse, nm);
        for (int b = 0; b < zwicker::kCore; ++b) core[b][t] = nm[b];
    }

    std::vector<std::vector<double>> nl;
    zwicker::nlLoudness(core, nl);

    std::vector<double> N2k(T);
    std::vector<std::vector<double>> Nspec2k(zwicker::kSpec, std::vector<double>(T));
    for (int t = 0; t < T; ++t) {
        double nm[zwicker::kCore], Nspec[zwicker::kSpec];
        for (int b = 0; b < zwicker::kCore; ++b) nm[b] = nl[b][t];
        zwicker::calcSlopes(nm, N2k[t], Nspec);
        for (int j = 0; j < zwicker::kSpec; ++j) Nspec2k[j][t] = Nspec[j];
    }

    // zeitliche Gewichtung
    std::vector<double> lp1, lp2;
    zwicker::lowpassIntp(N2k, 3.5e-3, 2000.0, lp1);
    zwicker::lowpassIntp(N2k, 70e-3, 2000.0, lp2);
    std::vector<double> filt(T);
    for (int t = 0; t < T; ++t) filt[t] = 0.47 * lp1[t] + 0.53 * lp2[t];

    LoudnessTV out;
    out.N.assign(T / 4, 0.0);
    out.Nspec.assign(zwicker::kSpec, std::vector<double>(T / 4, 0.0));
    for (int t = 0; t < T / 4; ++t) {
        out.N[t] = filt[t * 4];
        for (int j = 0; j < zwicker::kSpec; ++j) out.Nspec[j][t] = Nspec2k[j][t * 4];
    }
    return out;
}

// ---------------------------------------------------------------------------
// Sharpness DIN 45692 aus N und N' (wie mosqito sharpness_din_from_loudness)
// ---------------------------------------------------------------------------

inline std::vector<double> sharpnessDin(const std::vector<double>& N,
                                        const std::vector<std::vector<double>>& Nspec) {
    const size_t T = N.size();
    std::vector<double> S(T, 0.0);
    for (size_t t = 0; t < T; ++t) {
        if (N[t] < 0.1) continue;
        double sum = 0;
        for (int j = 0; j < zwicker::kSpec; ++j) {
            double z = 0.1 * (j + 1);
            double g = (z > 15.8) ? 0.15 * std::exp(0.42 * (z - 15.8)) + 0.85 : 1.0;
            sum += Nspec[j][t] * g * z * 0.1;
        }
        S[t] = 0.11 * sum / N[t];
    }
    return S;
}

// ---------------------------------------------------------------------------
// Fluctuation Strength (Zwicker/Fastl-Naeherung wie im Python-Referenzkern)
// ---------------------------------------------------------------------------

inline double fluctuationStrength(const std::vector<double>& nSeries, double fsN = 500.0) {
    const size_t n = nSeries.size();
    if (n < 32) return 0.0;
    std::vector<double> v(n);
    double mean = 0;
    for (size_t i = 0; i < n; ++i) {
        v[i] = std::max(nSeries[i], 1e-6);
        mean += v[i];
    }
    mean /= n;
    for (size_t i = 0; i < n; ++i) v[i] -= mean;
    // Hann + rfft
    std::vector<std::complex<double>> a(n);
    for (size_t i = 0; i < n; ++i) {
        double w = 0.5 - 0.5 * std::cos(2.0 * kPi * i / (n - 1));
        a[i] = std::complex<double>((nSeries[i] > 1e-6 ? nSeries[i] : 1e-6) * w, 0.0);
    }
    fftBluestein(a, false);
    size_t nR = n / 2 + 1;
    std::vector<double> mag(nR), freqs(nR);
    for (size_t k = 0; k < nR; ++k) {
        mag[k] = std::abs(a[k]);
        freqs[k] = k * fsN / n;
    }
    int best = -1;
    double bestMag = 0;
    for (size_t k = 0; k < nR; ++k)
        if (freqs[k] > 0.5 && freqs[k] < 30.0 && mag[k] > bestMag) {
            bestMag = mag[k];
            best = (int)k;
        }
    if (best < 0 || bestMag == 0) return 0.0;
    double fMod = freqs[best];
    double nDbMax = -1e300, nDbMin = 1e300;
    for (size_t i = 0; i < n; ++i) {
        double d = 10.0 * std::log10(v[i] + mean > 0 ? v[i] + mean : 1e-12);
        nDbMax = std::max(nDbMax, d);
        nDbMin = std::min(nDbMin, d);
    }
    double dl = std::max(nDbMax - nDbMin, 0.0);
    double w = (fMod < 4.0) ? fMod / 4.0 : 4.0 / fMod;
    return 0.008 * dl * w;
}

// ---------------------------------------------------------------------------
// Roughness Daniel-Weber (wie mosqito roughness_dw), p in Pa bei 48 kHz
// ---------------------------------------------------------------------------

namespace dw {

inline void hWeighting(int n, double fs, std::vector<std::vector<double>>& H) {
    const int cut = 2;
    H.assign(47, std::vector<double>(n, 0.0));
    auto fill = [&](int row, const double* xx, const double* yy, int xn, double lastHz) {
        int last = (int)std::floor((lastHz / fs) * n);
        for (int j = cut; j < last; ++j) {
            double f = (j - cut) * fs / n;
            H[row][j] = interpLin(f, xx, yy, xn);
        }
    };
    fill(1, tables::H2_x, tables::H2_y, (int)tables::H2_x_size, 358.0);
    fill(4, tables::H5_x, tables::H5_y, (int)tables::H5_x_size, 502.0);
    fill(15, tables::H16_x, tables::H16_y, (int)tables::H16_x_size, 502.0);
    fill(20, tables::H21_x, tables::H21_y, (int)tables::H21_x_size, 502.0);
    fill(41, tables::H42_x, tables::H42_y, (int)tables::H42_x_size, 502.0);
    for (int j = 0; j < n; ++j) H[0][j] = H[2][j] = H[3][j] = H[1][j];
    for (int i = 5; i < 15; ++i) H[i] = H[4];
    for (int i = 16; i < 20; ++i) H[i] = H[15];
    for (int i = 21; i < 41; ++i) H[i] = H[20];
    for (int i = 42; i < 47; ++i) H[i] = H[41];
}

inline double gziWeight(double z) {  // center_freq = zi = 0.5..23.5
    return interpLin(z, tables::gzi_x, tables::gzi_y, (int)tables::gzi_x_size);
}

inline double earFilter(double bark) {
    return interpLin(bark, tables::ear_xp, tables::ear_yp, (int)tables::ear_xp_size);
}

inline double ltqRoughness(double bark) {
    return interpLin(bark, tables::ltq_rough_x, tables::ltq_rough_y, (int)tables::ltq_rough_x_size);
}

// ein 200-ms-Fenster -> R [asper]
inline double roughnessWindow(const double* seg, int nperseg, double fs,
                              const std::vector<std::vector<double>>& H) {
    const int n = nperseg;  // volle symmetrische Laenge
    const int nHalf = n / 2;
    // Blackman-Fenster, normiert (wie numpy blackman / sum)
    std::vector<double> w(n);
    double wsum = 0;
    for (int i = 0; i < n; ++i) {
        w[i] = 0.42 - 0.5 * std::cos(2 * kPi * i / (n - 1)) + 0.08 * std::cos(4 * kPi * i / (n - 1));
        wsum += w[i];
    }
    for (int i = 0; i < n; ++i) w[i] /= wsum;
    std::vector<std::complex<double>> specC(n);
    for (int i = 0; i < n; ++i) specC[i] = seg[i] * w[i];
    fftBluestein(specC, false);
    // one-sided wie mosqito comp_spectrum: bins 0..n/2-1, *1.42; vollstaendig gespiegelt
    std::vector<std::complex<double>> spec(n);
    for (int k = 0; k < nHalf; ++k) spec[k] = specC[k] * 1.42;
    for (int j = 0; j < nHalf; ++j) spec[nHalf + j] = spec[nHalf - 1 - j];

    std::vector<double> freqAxis(nHalf), barkAxis(nHalf);
    for (int k = 0; k < nHalf; ++k) {
        freqAxis[k] = (k + 1) * fs / n;  // mosqito beschriftet bins 1..n/2
        barkAxis[k] = freq2bark(freqAxis[k]);
    }
    // Ohr-Transfer a0 auf die erste Haelfte
    std::vector<double> a0(n, 0.0);
    for (int k = 0; k < nHalf; ++k)
        a0[k] = std::pow(10.0, 0.05 * earFilter(barkAxis[k]));  // db2amp(ref=1)
    for (int k = 0; k < n; ++k) spec[k] *= a0[k];

    std::vector<double> module(nHalf), specDb(nHalf);
    for (int k = 0; k < nHalf; ++k) {
        module[k] = std::abs(spec[k]);
        specDb[k] = 20.0 * std::log10((module[k] == 0 ? 2e-12 : module[k]) / 2e-5);
    }
    // audible
    std::vector<int> aud;
    for (int k = 0; k < nHalf; ++k)
        if (specDb[k] > ltqRoughness(barkAxis[k])) aud.push_back(k);
    const int nAud = (int)aud.size();
    if (nAud == 0) return 0.0;

    std::vector<double> s2(nAud);
    for (int k = 0; k < nAud; ++k) {
        int ai = aud[k];
        s2[k] = std::min(-24.0 - 230.0 / freqAxis[ai] + 0.2 * specDb[ai], 0.0);
    }
    const int nCh = 47;
    std::vector<double> nZ(nHalf), thresh(nHalf);
    for (int k = 0; k < nHalf; ++k) {
        nZ[k] = k + 1;
        thresh[k] = ltqRoughness(barkAxis[k]);
    }
    std::vector<double> minExcitDb(nCh);
    for (int i = 0; i < nCh; ++i) {
        double zb = bark2freq((i + 1) / 2.0) * n / fs;
        minExcitDb[i] = interpLin(zb, nZ.data(), thresh.data(), nHalf);
    }
    std::vector<int> chLow(nAud), chHigh(nAud);
    for (int k = 0; k < nAud; ++k) {
        chLow[k] = (int)std::floor(2 * barkAxis[aud[k]]) - 1;
        chHigh[k] = (int)std::ceil(2 * barkAxis[aud[k]]) - 1;
    }
    std::vector<std::vector<double>> slopes(nAud, std::vector<double>(nCh, 0.0));
    const double s1 = -27.0;
    for (int k = 0; k < nAud; ++k) {
        double levDb = specDb[aud[k]];
        double b = barkAxis[aud[k]];
        for (int j = 0; j <= chLow[k] && j < nCh; ++j) {
            double sl = s1 * (b - (j + 1) * 0.5) + levDb;
            if (sl > minExcitDb[j]) slopes[k][j] = std::pow(10.0, 0.05 * sl) * 2e-5;
        }
        for (int j = std::max(chHigh[k], 0); j < nCh; ++j) {
            double sl = s2[k] * ((j + 1) * 0.5 - b) + levDb;
            if (sl > minExcitDb[j]) slopes[k][j] = std::pow(10.0, 0.05 * sl) * 2e-5;
        }
    }

    std::vector<std::vector<double>> hBP(nCh, std::vector<double>(n, 0.0));
    std::vector<double> modDepth(nCh, 0.0);
    for (int i = 0; i < nCh; ++i) {
        std::vector<std::complex<double>> exc(n, std::complex<double>(0, 0));
        for (int k = 0; k < nAud; ++k) {
            int ind = aud[k];  // 0-basiert wie mosqito
            double ampl;
            if (chLow[k] == i || chHigh[k] == i) ampl = 1.0;
            else if (chHigh[k] > i) ampl = slopes[k][std::min(i + 1, nCh - 1)] / module[ind];
            else ampl = slopes[k][std::max(i - 1, 0)] / module[ind];
            exc[ind] = ampl * spec[ind];
        }
        fftBluestein(exc, true);
        std::vector<double> tex(n);
        for (int k = 0; k < n; ++k) tex[k] = std::abs(n * exc[k].real());
        double h0 = 0;
        for (double v : tex) h0 += v;
        h0 /= n;
        std::vector<std::complex<double>> espec(n);
        for (int k = 0; k < n; ++k) espec[k] = tex[k] - h0;
        fftBluestein(espec, false);
        for (int k = 0; k < n; ++k) espec[k] *= H[i][k];
        fftBluestein(espec, true);
        double rms = 0;
        for (int k = 0; k < n; ++k) {
            hBP[i][k] = 2.0 * espec[k].real();
            rms += hBP[i][k] * hBP[i][k];
        }
        rms = std::sqrt(rms / n);
        if (h0 > 0) modDepth[i] = std::min(rms / h0, 1.0);
    }
    // Kreuzkorrelation ki (mosqito: nur wenn alle Werte != 0)
    std::vector<double> ki(nCh, 0.0);
    auto corrcoef = [](const std::vector<double>& a, const std::vector<double>& b, int n) {
        double ma = 0, mb = 0;
        for (int i = 0; i < n; ++i) { ma += a[i]; mb += b[i]; }
        ma /= n; mb /= n;
        double sab = 0, saa = 0, sbb = 0;
        for (int i = 0; i < n; ++i) {
            sab += (a[i] - ma) * (b[i] - mb);
            saa += (a[i] - ma) * (a[i] - ma);
            sbb += (b[i] - mb) * (b[i] - mb);
        }
        return (saa > 0 && sbb > 0) ? sab / std::sqrt(saa * sbb) : 0.0;
    };
    for (int i = 0; i < 45; ++i) {
        bool allNz = true;
        for (int k = 0; k < n; ++k)
            if (hBP[i][k] == 0 || hBP[i + 2][k] == 0) allNz = false;
        if (allNz) ki[i] = corrcoef(hBP[i], hBP[i + 2], n);
    }
    std::vector<double> Rspec(nCh, 0.0);
    auto gzi = [](int i) { return gziWeight((i + 1) / 2.0); };
    Rspec[0] = gzi(0) * std::pow(modDepth[0] * ki[0], 2);
    Rspec[1] = gzi(1) * std::pow(modDepth[1] * ki[1], 2);
    for (int i = 2; i < 45; ++i) Rspec[i] = gzi(i) * std::pow(modDepth[i] * ki[i] * ki[i - 2], 2);
    Rspec[45] = gzi(45) * std::pow(modDepth[45] * ki[43], 2);
    Rspec[46] = gzi(46) * std::pow(modDepth[46] * ki[44], 2);
    double R = 0;
    for (double v : Rspec) R += v;
    return 0.25 * R;
}

}  // namespace dw

// R(t) ueber 200-ms-Fenster mit 50% Ueberlappung, p in Pa bei fs (intern 48 kHz)
inline std::vector<double> roughnessDw(const double* p, size_t n, double fs) {
    std::vector<double> p48 = resampleTo48k(p, n, fs);
    const int nperseg = (int)(0.2 * 48000);
    const int noverlap = nperseg / 2;
    std::vector<std::vector<double>> H;
    dw::hWeighting(nperseg, 48000.0, H);
    std::vector<double> R;
    for (size_t off = 0; off + (size_t)nperseg <= p48.size(); off += noverlap)
        R.push_back(dw::roughnessWindow(p48.data() + off, nperseg, 48000.0, H));
    return R;
}

// ---------------------------------------------------------------------------
// Gesamt-Psychoakustik (Torresin-Parameter) auf einem Schalldruck-Signal
// ---------------------------------------------------------------------------

struct PsychoResult {
    double N10 = 0, N50 = 0, N90 = 0;
    double S_acum = 0;       // Sharpness-Mittel (DIN 45692)
    double R_asper = 0;      // Roughness-Mittel (Daniel-Weber)
    double FS_vacil = 0;     // Fluctuation Strength
    std::vector<double> Nseries;
};

inline double percentile(std::vector<double> v, double p) {
    if (v.empty()) return 0.0;
    std::sort(v.begin(), v.end());
    double idx = p / 100.0 * (v.size() - 1);
    size_t lo = (size_t)std::floor(idx), hi = (size_t)std::ceil(idx);
    return v[lo] + (v[hi] - v[lo]) * (idx - lo);
}

inline PsychoResult psychoacoustics(const double* p, size_t n, double fs, bool diffuse = false) {
    PsychoResult r;
    LoudnessTV lv = loudnessZwtv(p, n, fs, diffuse);
    r.Nseries = lv.N;
    r.N10 = percentile(lv.N, 90);   // N10 = 90. Perzentil
    r.N50 = percentile(lv.N, 50);
    r.N90 = percentile(lv.N, 10);
    auto S = sharpnessDin(lv.N, lv.Nspec);
    double sSum = 0;
    for (double v : S) sSum += v;
    r.S_acum = S.empty() ? 0.0 : sSum / S.size();
    auto R = roughnessDw(p, n, fs);
    double rSum = 0;
    for (double v : R) rSum += v;
    r.R_asper = R.empty() ? 0.0 : rSum / R.size();
    r.FS_vacil = fluctuationStrength(lv.N, 500.0);
    return r;
}

}  // namespace ald
