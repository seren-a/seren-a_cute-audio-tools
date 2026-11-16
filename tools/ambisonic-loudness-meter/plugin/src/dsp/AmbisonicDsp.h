// AmbisonicDsp.h -- JUCE-unabhaengiger DSP-Kern des ambisonic-loudness-meter.
//
// C++-Portierung des Python-Referenzkerns (src/ambisonic_loudness.py):
//   - K-Filter (BS.1770-5): analoge Prototypen per Bilinear-Transformation
//     fuer beliebige Sampleraten; bei 48 kHz exakt die publizierten Koeffizienten
//   - A-/C-Bewertung (IEC 61672-1) via Bilinear-Transform
//   - BS.1770-Gating (Integrated/Short-Term/Momentary/LRA), True Peak (4x)
//   - Ambisonics ACN/SN3D: SH, Plane-Wave-Encoding, Energy-Decoding (max-rE)
//
// Nur C++17-Standardbibliothek, damit der Kern ohne JUCE testbar ist
// (siehe DspTests.cpp: validiert gegen die pytest-Referenzwerte).

#pragma once

#include <algorithm>
#include <cmath>
#include <complex>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace ald {

constexpr double kPi = 3.14159265358979323846;

// ---------------------------------------------------------------------------
// Biquad + Bilinear-Transformation eines analogen Biquad-Abschnitts
// ---------------------------------------------------------------------------

struct Biquad {
    double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
    double x1 = 0, x2 = 0, y1 = 0, y2 = 0;

    void reset() { x1 = x2 = y1 = y2 = 0; }

    inline double process(double x) {
        double y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        x2 = x1; x1 = x;
        y2 = y1; y1 = y;
        return y;
    }

    void processBlock(double* x, size_t n) {
        for (size_t i = 0; i < n; ++i) x[i] = process(x[i]);
    }
};

// H(s) = (n2 s^2 + n1 s + n0) / (d2 s^2 + d1 s + d0), s = 2 fs (1 - z^-1)/(1 + z^-1)
inline Biquad bilinearBiquad(double n2, double n1, double n0,
                             double d2, double d1, double d0, double fs) {
    const double k = 2.0 * fs;
    const double nb0 = n2 * k * k + n1 * k + n0;
    const double nb1 = -2.0 * n2 * k * k + 2.0 * n0;
    const double nb2 = n2 * k * k - n1 * k + n0;
    const double da0 = d2 * k * k + d1 * k + d0;
    const double da1 = -2.0 * d2 * k * k + 2.0 * d0;
    const double da2 = d2 * k * k - d1 * k + d0;
    Biquad bq;
    bq.b0 = nb0 / da0; bq.b1 = nb1 / da0; bq.b2 = nb2 / da0;
    bq.a1 = da1 / da0; bq.a2 = da2 / da0;
    return bq;
}

// ---------------------------------------------------------------------------
// K-Filter (BS.1770-5 Annex 1). Analoge Prototypen per inverser Bilinear-
// Transformation aus den publizierten 48-kHz-Koeffizienten gewonnen
// (Roundtrip bei 48 kHz exakt).
// ---------------------------------------------------------------------------

struct KFilter {
    Biquad shelf, hpf;  // stage 1: high shelf +4 dB, stage 2: high pass

    static KFilter create(double fs) {
        KFilter kf;
        // stage 1 (high shelf): num/den in s
        kf.shelf = bilinearBiquad(1.5848647011308554, 18886.914378028901, 112594507.26979087,
                                  1.0, 15004.846526655718, 112594507.26978998, fs);
        // stage 2 (high pass)
        kf.hpf = bilinearBiquad(1.0049948987146884, 0.0, 0.0,
                                1.0, 478.91221140842475, 57414.259358626012, fs);
        return kf;
    }

    void reset() { shelf.reset(); hpf.reset(); }

    inline double process(double x) { return hpf.process(shelf.process(x)); }

    void processBlock(double* x, size_t n) {
        for (size_t i = 0; i < n; ++i) x[i] = process(x[i]);
    }
};

// ---------------------------------------------------------------------------
// A-/C-Bewertung (IEC 61672-1), analoge Prototypen wie im Python-Referenzcode
// ---------------------------------------------------------------------------

struct Weighting {
    std::vector<Biquad> sections;
    double gain = 1.0;  // Normalisierung auf 0 dB bei 1 kHz

    static Weighting create(double fs, bool aWeighting) {
        const double f1 = 20.598997, f2 = 107.65265, f3 = 737.86223, f4 = 12194.217;
        const double w1 = 2 * kPi * f1, w2 = 2 * kPi * f2;
        const double w3 = 2 * kPi * f3, w4 = 2 * kPi * f4;
        Weighting w;
        if (aWeighting) {
            // H(s) = w4^2 s^4 / ((s+w1)^2 (s+w2)(s+w3) (s+w4)^2)
            w.sections.push_back(bilinearBiquad(1, 0, 0, 1, 2 * w1, w1 * w1, fs));
            w.sections.push_back(bilinearBiquad(0, 0, 1, 1, w2 + w3, w2 * w3, fs));
            w.sections.push_back(bilinearBiquad(1, 0, 0, 1, 2 * w4, w4 * w4, fs));
        } else {
            // H(s) = w4^2 s^2 / ((s+w1)^2 (s+w4)^2)
            w.sections.push_back(bilinearBiquad(1, 0, 0, 1, 2 * w1, w1 * w1, fs));
            w.sections.push_back(bilinearBiquad(0, 0, 1, 1, 2 * w4, w4 * w4, fs));
        }
        // Normierung auf 0 dB bei 1 kHz: H(s) = w4^2 s^n / den(s), die
        // Sektionen oben enthalten den Faktor w4^2 nicht, daher hier nur
        // |s^n / den(j 2 pi 1000)| bilden.
        const std::complex<double> jw(0.0, 2 * kPi * 1000.0);
        auto pole = [](double p, std::complex<double> s) { return s + p; };
        std::complex<double> h;
        if (aWeighting) {
            h = std::pow(jw, 4) / (std::pow(pole(w1, jw), 2) * pole(w2, jw) * pole(w3, jw) * std::pow(pole(w4, jw), 2));
        } else {
            h = std::pow(jw, 2) / (std::pow(pole(w1, jw), 2) * std::pow(pole(w4, jw), 2));
        }
        w.gain = 1.0 / std::abs(h);  // 0 dB bei 1 kHz (w4^2 hebt sich gegen die Sektionen auf)
        return w;
    }

    void reset() { for (auto& s : sections) s.reset(); }

    inline double process(double x) {
        double y = x;
        for (auto& s : sections) y = s.process(y);
        return y * gain;
    }
};

// ---------------------------------------------------------------------------
// BS.1770-5 Gating-Meter (400-ms-Bloecke, 100-ms-Hop; Short-Term 3 s/1 s)
// ---------------------------------------------------------------------------

class Bs1770Meter {
public:
    void prepare(double fs, int nCh, const std::vector<double>& gains) {
        fs_ = fs;
        nCh_ = nCh;
        gains_ = gains;
        kFilters_.assign(nCh, KFilter::create(fs));
        blockN_ = (size_t)llround(fs * 0.400);
        hopN_ = (size_t)llround(fs * 0.100);
        stN_ = (size_t)llround(fs * 3.000);
        stHopN_ = (size_t)llround(fs * 1.000);
        reset();
    }

    void reset() {
        for (auto& k : kFilters_) k.reset();
        buf_.assign(nCh_, std::vector<double>(blockN_, 0.0));
        sumsq_.assign(nCh_, 0.0);
        pos_ = 0; filled_ = false; sinceHop_ = 0;
        stBuf_.assign(nCh_, std::vector<double>(stN_, 0.0));
        stSumsq_.assign(nCh_, 0.0);
        stPos_ = 0; stFilled_ = false; stSinceHop_ = 0;
        zBlocks_.clear();
        stValues_.clear();
    }

    // x: nCh Zeiger auf je n Samples (ungefiltert)
    void process(const double* const* x, size_t n) {
        for (size_t i = 0; i < n; ++i) {
            for (int c = 0; c < nCh_; ++c) {
                double y = kFilters_[c].process(x[c][i]);
                double& s = sumsq_[c];
                if (filled_) s -= buf_[c][pos_] * buf_[c][pos_];
                s += y * y;
                buf_[c][pos_] = y;

                double& ss = stSumsq_[c];
                if (stFilled_) ss -= stBuf_[c][stPos_] * stBuf_[c][stPos_];
                ss += y * y;
                stBuf_[c][stPos_] = y;
            }
            pos_ = (pos_ + 1) % blockN_;
            stPos_ = (stPos_ + 1) % stN_;
            if (!filled_ && pos_ == 0) filled_ = true;
            if (!stFilled_ && stPos_ == 0) stFilled_ = true;

            if (filled_ && ++sinceHop_ >= hopN_) {
                sinceHop_ = 0;
                double z = 0;
                for (int c = 0; c < nCh_; ++c) z += gains_[c] * sumsq_[c] / (double)blockN_;
                zBlocks_.push_back(z);
            }
            if (stFilled_ && ++stSinceHop_ >= stHopN_) {
                stSinceHop_ = 0;
                double z = 0;
                for (int c = 0; c < nCh_; ++c) z += gains_[c] * stSumsq_[c] / (double)stN_;
                double lufs = -0.691 + 10.0 * std::log10(std::max(z, 1e-15));
                stValues_.push_back(lufs);
                if (stValues_.size() > 36000) stValues_.erase(stValues_.begin());
            }
        }
    }

    static double lufsOf(double z) { return -0.691 + 10.0 * std::log10(std::max(z, 1e-15)); }

    // zweistufiges Gating nach BS.1770-5
    double integrated() const {
        if (zBlocks_.empty()) return -HUGE_VAL;
        std::vector<double> lufs(zBlocks_.size());
        for (size_t i = 0; i < zBlocks_.size(); ++i) lufs[i] = lufsOf(zBlocks_[i]);
        double sumAbs = 0; size_t nAbs = 0;
        for (double l : lufs)
            if (l > -70.0) { sumAbs += std::pow(10.0, (l + 0.691) / 10.0); ++nAbs; }
        if (nAbs == 0) return -HUGE_VAL;
        double ungated = lufsOf(sumAbs / nAbs);
        double rel = ungated - 10.0;
        double sum = 0; size_t n = 0;
        for (size_t i = 0; i < lufs.size(); ++i)
            if (lufs[i] > -70.0 && lufs[i] > rel) { sum += zBlocks_[i]; ++n; }
        if (n == 0) { sum = sumAbs; n = nAbs; }
        return lufsOf(sum / n);
    }

    double maxMomentary() const {
        double m = -HUGE_VAL;
        for (double z : zBlocks_) m = std::max(m, lufsOf(z));
        return m;
    }

    double maxShortTerm() const {
        double m = -HUGE_VAL;
        for (double l : stValues_) m = std::max(m, l);
        return m;
    }

    // LRA nach EBU Tech 3342
    double loudnessRange() const {
        std::vector<double> st;
        for (double l : stValues_) if (l > -70.0) st.push_back(l);
        if (st.empty()) return 0.0;
        double sum = 0;
        for (double l : st) sum += std::pow(10.0, (l + 0.691) / 10.0);
        double rel = 10.0 * std::log10(sum / st.size()) - 0.691 - 20.0;
        std::vector<double> kept;
        for (double l : st) if (l > rel) kept.push_back(l);
        if (kept.empty()) return 0.0;
        std::sort(kept.begin(), kept.end());
        auto pct = [&](double p) {
            double idx = p / 100.0 * (kept.size() - 1);
            size_t lo = (size_t)std::floor(idx), hi = (size_t)std::ceil(idx);
            return kept[lo] + (kept[hi] - kept[lo]) * (idx - lo);
        };
        return pct(95.0) - pct(10.0);
    }

    const std::vector<double>& shortTermSeries() const { return stValues_; }

private:
    double fs_ = 48000;
    int nCh_ = 0;
    std::vector<double> gains_;
    std::vector<KFilter> kFilters_;
    size_t blockN_ = 0, hopN_ = 0, stN_ = 0, stHopN_ = 0;
    std::vector<std::vector<double>> buf_, stBuf_;
    std::vector<double> sumsq_, stSumsq_;
    size_t pos_ = 0, stPos_ = 0, sinceHop_ = 0, stSinceHop_ = 0;
    bool filled_ = false, stFilled_ = false;
    std::vector<double> zBlocks_, stValues_;
};

// ---------------------------------------------------------------------------
// True Peak (4x Oversampling, windowed-sinc FIR, polyphasig)
// ---------------------------------------------------------------------------

class TruePeak {
public:
    void prepare(double fs, int oversample = 4) {
        fs_ = fs; os_ = oversample;
        const int M = 64;  // FIR-Laenge (gerade, os-teilig)
        const double beta = 8.0;
        auto besselI0 = [](double x) {
            double sum = 1, term = 1, y = x * x / 4;
            for (int k = 1; k < 60; ++k) {
                term *= y / (k * k);
                sum += term;
                if (term < 1e-18 * sum) break;
            }
            return sum;
        };
        const double fc = 0.5 / os_ * 0.97;  // Grenzfrequenz (rel. zur os-Rate)
        std::vector<double> h(M);
        double dc = 0;
        for (int i = 0; i < M; ++i) {
            double t = i - (M - 1) / 2.0;
            double sinc = (std::abs(t) < 1e-12) ? 1.0 : std::sin(2 * kPi * fc * t) / (kPi * t);
            double r = 2.0 * i / (M - 1.0) - 1.0;
            double w = besselI0(beta * std::sqrt(std::max(0.0, 1 - r * r))) / besselI0(beta);
            h[i] = 2 * fc * sinc * w;
            dc += h[i];
        }
        // Upsampling um os_: Passband-Gain muss os_ sein (Zero-Stuffing skaliert 1/os_)
        for (int i = 0; i < M; ++i) h[i] *= os_ / dc;
        // polyphase: h_p[i] = h[p + os*i]
        taps_.assign(os_, std::vector<double>(M / os_, 0.0));
        for (int p = 0; p < os_; ++p)
            for (int i = 0; i < M / os_; ++i) taps_[p][i] = h[p + os_ * i];
        hist_.assign(M / os_, 0.0);
        pos_ = 0;
        peak_ = 0;
    }

    void reset() { std::fill(hist_.begin(), hist_.end(), 0.0); pos_ = 0; peak_ = 0; }

    inline void process(double x) {
        hist_[pos_] = x;
        for (int p = 0; p < os_; ++p) {
            const auto& tp = taps_[p];
            double y = 0;
            size_t idx = pos_;
            for (size_t i = 0; i < tp.size(); ++i) {
                y += tp[i] * hist_[idx];
                if (idx == 0) idx = hist_.size() - 1; else --idx;
            }
            peak_ = std::max(peak_, std::abs(y));
        }
        if (++pos_ >= hist_.size()) pos_ = 0;
    }

    double dbtp() const { return 20.0 * std::log10(peak_ + 1e-15); }

private:
    double fs_ = 48000;
    int os_ = 4;
    std::vector<std::vector<double>> taps_;
    std::vector<double> hist_;
    size_t pos_ = 0;
    double peak_ = 0;
};

// ---------------------------------------------------------------------------
// Ambisonics: SH (ACN/SN3D), Encoding, Energy-Decoding (max-rE)
// ---------------------------------------------------------------------------

inline int acnOrder(int nCh) {
    int n = (int)llround(std::sqrt((double)nCh)) - 1;
    if ((n + 1) * (n + 1) != nCh) return -1;
    return n;
}

// Assoziierte Legendre-Funktion P_l^m(x) OHNE Condon-Shortley-Phase
// (entspricht (-1)^m * scipy lpmv(m, l, x), wie im Python-Referenzcode)
inline double legendreP(int l, int m, double x) {
    double pmm = 1.0;
    if (m > 0) {
        double somx2 = std::sqrt(std::max(0.0, 1.0 - x * x));
        double fact = 1.0;
        for (int i = 1; i <= m; ++i) {
            pmm *= fact * somx2;   // (2m-1)!! (1-x^2)^(m/2), ohne (-1)^m
            fact += 2.0;
        }
    }
    if (l == m) return pmm;
    double pmmp1 = x * (2 * m + 1) * pmm;
    if (l == m + 1) return pmmp1;
    double pll = 0;
    for (int ll = m + 2; ll <= l; ++ll) {
        pll = ((2 * ll - 1) * x * pmmp1 - (ll + m - 1) * pmm) / (ll - m);
        pmm = pmmp1;
        pmmp1 = pll;
    }
    return pll;
}

inline double factorialRatio(int l, int m) {
    // (l-m)! / (l+m)!
    return std::exp(std::lgamma(l - m + 1.0) - std::lgamma(l + m + 1.0));
}

// Realwertige SH in ACN/SN3D, Laenge (order+1)^2, ACN-Reihenfolge m = -l..l
inline std::vector<double> sphericalHarmonics(double azimuthDeg, double elevationDeg, int order) {
    const double az = azimuthDeg * kPi / 180.0;
    const double x = std::sin(elevationDeg * kPi / 180.0);
    std::vector<double> out;
    out.reserve((order + 1) * (order + 1));
    for (int l = 0; l <= order; ++l) {
        for (int m = -l; m <= l; ++m) {
            double norm = std::sqrt((2.0 * l + 1.0) / (4.0 * kPi) * factorialRatio(l, std::abs(m)));
            double plm = legendreP(l, std::abs(m), x);  // ohne CS-Phase wie Python
            double val;
            if (m > 0) val = norm * plm * std::cos(m * az) / std::sqrt(2.0);
            else if (m < 0) val = norm * plm * std::sin(-m * az) / std::sqrt(2.0);
            else val = norm * plm;
            out.push_back(val);
        }
    }
    return out;
}

inline std::vector<double> encodePlaneWave(const double* signal, size_t n,
                                           double azimuthDeg, double elevationDeg, int order) {
    auto y = sphericalHarmonics(azimuthDeg, elevationDeg, order);
    std::vector<double> out(y.size() * n);
    for (size_t c = 0; c < y.size(); ++c)
        for (size_t i = 0; i < n; ++i) out[c * n + i] = y[c] * signal[i];
    return out;
}

// Virtuelle Lautsprecher: Horizontal-Ring + Layer oben/unten (wie Python)
inline std::vector<std::pair<double, double>> defaultLayout(int order) {
    std::vector<std::pair<double, double>> layout;
    for (int az = -150; az < 180; az += 30) layout.push_back({(double)az, 0.0});
    if (order >= 2) {
        for (double az : {0.0, 90.0, 180.0, -90.0}) layout.push_back({az, 45.0});
        for (double az : {0.0, 90.0, 180.0, -90.0}) layout.push_back({az, -45.0});
    }
    if (order >= 3) {
        layout.push_back({0.0, 90.0});
        layout.push_back({0.0, -90.0});
    }
    return layout;
}

inline double channelGain(double azimuthDeg, double elevationDeg) {
    const double g141 = std::pow(10.0, 3.01 / 10.0);
    if (std::abs(elevationDeg) > 5.0) return g141;
    if (std::abs(azimuthDeg) >= 60.0 && std::abs(azimuthDeg) <= 120.0) return g141;
    return 1.0;
}

// Energy-Decoding (max-rE): b ist (nCh x n), Rueckgabe (nSpk x n)
inline std::vector<std::vector<double>> energyDecode(const std::vector<double>& b, int nCh, size_t n,
                                                      const std::vector<std::pair<double, double>>& layout,
                                                      int order) {
    std::vector<double> w(order + 1, 0.0);
    const double alpha = kPi / (2.0 * order + 2.0);
    for (int l = 0; l <= order; ++l)
        w[l] = (l > 0) ? std::sqrt(2.0 / kPi) * std::sin((l + 1) * alpha) / ((l + 1) * alpha) : 1.0;

    const int nSpk = (int)layout.size();
    const int nSh = (order + 1) * (order + 1);
    // SH-Matrix + Order-Band-Gewichtung
    std::vector<std::vector<double>> dec(nSpk, std::vector<double>(nSh, 0.0));
    int idx = 0;
    for (int l = 0; l <= order; ++l) {
        for (int s = 0; s < nSpk; ++s) {
            auto y = sphericalHarmonics(layout[s].first, layout[s].second, order);
            for (int j = 0; j < 2 * l + 1; ++j) dec[s][idx + j] = y[idx + j] * w[l];
        }
        idx += 2 * l + 1;
    }
    // Zeilen normieren
    for (int s = 0; s < nSpk; ++s) {
        double e = 0;
        for (double v : dec[s]) e += v * v;
        e = std::sqrt(e);
        if (e > 0) for (double& v : dec[s]) v /= e;
    }
    // Mittlere Energie ueber eine Kugel-Rasterung normieren
    double meanEnergy = 0;
    int nDirs = 0;
    for (int az = 0; az < 360; az += 15) {
        for (int el = -90; el <= 90; el += 15) {
            auto y = sphericalHarmonics(az, el, order);
            double e = 0;
            for (int s = 0; s < nSpk; ++s) {
                double d = 0;
                for (int c = 0; c < nSh; ++c) d += dec[s][c] * y[c];
                e += d * d;
            }
            meanEnergy += e;
            ++nDirs;
        }
    }
    meanEnergy /= nDirs;
    if (meanEnergy > 0) {
        double f = 1.0 / std::sqrt(meanEnergy);
        for (auto& row : dec) for (double& v : row) v *= f;
    }
    // dec @ b
    std::vector<std::vector<double>> out(nSpk, std::vector<double>(n, 0.0));
    for (int s = 0; s < nSpk; ++s)
        for (int c = 0; c < nCh; ++c) {
            double d = dec[s][c];
            if (d == 0) continue;
            const double* src = &b[(size_t)c * n];
            for (size_t i = 0; i < n; ++i) out[s][i] += d * src[i];
        }
    return out;
}

// ---------------------------------------------------------------------------
// Gesamt-Meter: B-Format-Block -> alle Parameter (BS.1770-5)
// ---------------------------------------------------------------------------

struct AmbisonicResult {
    int order = 0;
    int nChannels = 0;
    double integratedLufs = -HUGE_VAL;
    double maxShortTermLufs = -HUGE_VAL;
    double maxMomentaryLufs = -HUGE_VAL;
    double lra = 0;
    double truePeakDbtp = -HUGE_VAL;
    double wOnlyLufs = -HUGE_VAL;
    std::vector<double> perSpeakerLufs;
    std::vector<std::pair<double, double>> layout;
};

class AmbisonicMeter {
public:
    void prepare(double fs, int order) {
        fs_ = fs;
        order_ = order;
        nCh_ = (order + 1) * (order + 1);
        layout_ = defaultLayout(order);
        gains_.resize(layout_.size());
        for (size_t i = 0; i < layout_.size(); ++i)
            gains_[i] = channelGain(layout_[i].first, layout_[i].second);
        meter_.prepare(fs, (int)layout_.size(), gains_);
        wMeter_.prepare(fs, 1, {1.0});
        spkMeters_.assign(layout_.size(), Bs1770Meter{});
        for (auto& m : spkMeters_) m.prepare(fs, 1, {1.0});  // Gain separat appliziert
        tp_.prepare(fs, 4);
        work_.assign(nCh_, 0.0);
    }

    void reset() {
        meter_.reset();
        wMeter_.reset();
        for (auto& m : spkMeters_) m.reset();
        tp_.reset();
    }

    // b: nCh Zeiger auf je n Samples (B-Format, ACN/SN3D)
    void process(const double* const* b, size_t n) {
        // Energy-Decode auf virtuelle Lautsprecher
        std::vector<double> flat((size_t)nCh_ * n);
        for (int c = 0; c < nCh_; ++c)
            std::copy(b[c], b[c] + n, flat.begin() + (size_t)c * n);
        auto spk = energyDecode(flat, nCh_, n, layout_, order_);

        std::vector<const double*> spkPtrs(spk.size());
        for (size_t s = 0; s < spk.size(); ++s) spkPtrs[s] = spk[s].data();
        meter_.process(spkPtrs.data(), n);

        // W-only (0. Ordnungskoeffizient, skaliert mit 2 sqrt(pi))
        work_.resize(n);
        const double wScale = 2.0 * std::sqrt(kPi);
        for (size_t i = 0; i < n; ++i) work_[i] = wScale * b[0][i];
        const double* wPtr = work_.data();
        wMeter_.process(&wPtr, n);

        // pro virtuellem Lautsprecher (mit G-Gewicht)
        for (size_t s = 0; s < spk.size(); ++s) {
            for (size_t i = 0; i < n; ++i) work_[i] = std::sqrt(gains_[s]) * spk[s][i];
            const double* p = work_.data();
            spkMeters_[s].process(&p, n);
        }

        // True Peak ueber die dekodierten virtuellen Lautsprecher
        for (size_t s = 0; s < spk.size(); ++s)
            for (size_t i = 0; i < n; ++i) tp_.process(spk[s][i]);
    }

    AmbisonicResult result() const {
        AmbisonicResult r;
        r.order = order_;
        r.nChannels = nCh_;
        r.integratedLufs = meter_.integrated();
        r.maxShortTermLufs = meter_.maxShortTerm();
        r.maxMomentaryLufs = meter_.maxMomentary();
        r.lra = meter_.loudnessRange();
        r.truePeakDbtp = tp_.dbtp();
        r.wOnlyLufs = wMeter_.integrated();
        r.layout = layout_;
        r.perSpeakerLufs.resize(layout_.size());
        for (size_t s = 0; s < layout_.size(); ++s)
            r.perSpeakerLufs[s] = spkMeters_[s].integrated();
        return r;
    }

    const Bs1770Meter& meter() const { return meter_; }

private:
    double fs_ = 48000;
    int order_ = 1;
    int nCh_ = 4;
    std::vector<std::pair<double, double>> layout_;
    std::vector<double> gains_;
    Bs1770Meter meter_, wMeter_;
    std::vector<Bs1770Meter> spkMeters_;
    TruePeak tp_;
    std::vector<double> work_;
};

}  // namespace ald
