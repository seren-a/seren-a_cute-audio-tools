#pragma once

#include <array>
#include <cmath>
#include <complex>
#include <cstdint>
#include <deque>
#include <memory>
#include <algorithm>
#include <vector>

namespace meterdsp
{

inline constexpr double kPi = 3.14159265358979323846;

namespace detail
{

// Kompakte Radix-2-FFT (real, in-place, interleaved re/im)
class RealFFT
{
public:
    explicit RealFFT (int order) : n (1u << order), order_ (order)
    {
        tables.reserve ((size_t) order);
        for (int o = 1; o <= order; ++o)
        {
            const size_t m = (size_t) 1 << o;
            std::vector<double> cosT (m / 2), sinT (m / 2);
            for (size_t i = 0; i < m / 2; ++i)
            {
                cosT[i] = std::cos (-2.0 * kPi * (double) i / (double) m);
                sinT[i] = std::sin (-2.0 * kPi * (double) i / (double) m);
            }
            tables.push_back ({ std::move (cosT), std::move (sinT) });
        }
    }

    int getOrder() const { return order_; }
    size_t getSize() const { return n; }

    // data: 2*n Werte (interleaved), nur die ersten n/2 Bins sind gueltig
    void performRealOnlyForwardTransform (double* data, bool) const
    {
        bitReverse (data);
        for (int o = 1; o <= order_; ++o)
        {
            const size_t m = (size_t) 1 << o;
            const auto& cosT = tables[(size_t) o - 1].first;
            const auto& sinT = tables[(size_t) o - 1].second;
            for (size_t i = 0; i < n; i += m)
                for (size_t j = 0; j < m / 2; ++j)
                {
                    const double wr = cosT[j], wi = sinT[j];
                    const double xr = data[2 * (i + j + m / 2)];
                    const double xi = data[2 * (i + j + m / 2) + 1];
                    const double yr = xr * wr - xi * wi;
                    const double yi = xr * wi + xi * wr;
                    const size_t a = 2 * (i + j), b = 2 * (i + j + m / 2);
                    const double ar = data[a], ai = data[a + 1];
                    data[b] = ar - yr; data[b + 1] = ai - yi;
                    data[a] = ar + yr; data[a + 1] = ai + yi;
                }
        }
    }

public:
    void bitReverse (double* data) const
    {
        for (size_t i = 1, j = 0; i < n; ++i)
        {
            size_t bit = n >> 1;
            for (; j & bit; bit >>= 1) j ^= bit;
            j ^= bit;
            if (i < j)
            {
                std::swap (data[2 * i], data[2 * j]);
                std::swap (data[2 * i + 1], data[2 * j + 1]);
            }
        }
    }

    size_t n;
    int order_;
    std::vector<std::pair<std::vector<double>, std::vector<double>>> tables;
};

} // namespace detail

} // namespace meterdsp

/* =====================================================================
 * MeterDSP: Echtzeit-Loudness- und Soundscape-Messung
 *
 * Exakt nach Norm implementiert:
 *  - K-Filter (BS.1770 Annex 1, RBJ-Design fuer beliebige Abtastraten)
 *  - Gated Integrated / Short-Term / Momentary Loudness (BS.1770, EBU R128)
 *  - Loudness Range LRA (EBU Tech 3342)
 *  - True Peak dBTP (4x Oversampling, BS.1770 Annex 2)
 *  - A-/C-Bewertung (IEC 61672, Analogprototyp + Bilinear-Transformation)
 *  - Statistische Pegel L_A10/L_A90 (125-ms-Bloecke, Gating -70 dBFS)
 *
 * Dokumentierte Naeherungen (Referenz: Python-Modul mit mosqito):
 *  - Zwicker-Lautheit N (spektrale Naeherung nach Zwicker/Fastl,
 *    20 Bark-Baender, vereinfachte Hoerschwelle)
 *  - Sharpness S (gewichtetes erstes Moment der spezifischen Lautheit)
 *  - Fluctuation Strength (Modulationstiefe der Lautheitszeitfunktion)
 *  - Roughness (Huellkurvenmodulation, Peak bei ~70 Hz)
 * ===================================================================== */

namespace meterdsp
{

// ---------------------------------------------------------------- Biquad
struct Biquad
{
    double b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0;
    double x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;

    void reset() { x1 = x2 = y1 = y2 = 0.0; }

    inline double process (double x) noexcept
    {
        const double y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        x2 = x1; x1 = x;
        y2 = y1; y1 = y;
        return y;
    }
};

// RBJ Cookbook
inline Biquad highShelf (double fs, double fc, double gainDb, double q)
{
    const double A  = std::pow (10.0, gainDb / 40.0);
    const double w0 = 2.0 * kPi * fc / fs;
    const double cw = std::cos (w0), sw = std::sin (w0);
    const double alpha = sw / (2.0 * q);
    const double sq = 2.0 * std::sqrt (A) * alpha;
    Biquad bq;
    bq.b0 = A * ((A + 1.0) + (A - 1.0) * cw + sq);
    bq.b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cw);
    bq.b2 = A * ((A + 1.0) + (A - 1.0) * cw - sq);
    const double a0 = (A + 1.0) - (A - 1.0) * cw + sq;
    bq.a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cw);
    bq.a2 = (A + 1.0) - (A - 1.0) * cw - sq;
    bq.b0 /= a0; bq.b1 /= a0; bq.b2 /= a0; bq.a1 /= a0; bq.a2 /= a0;
    return bq;
}

inline Biquad highPass (double fs, double fc, double q)
{
    const double w0 = 2.0 * kPi * fc / fs;
    const double cw = std::cos (w0), sw = std::sin (w0);
    const double alpha = sw / (2.0 * q);
    Biquad bq;
    bq.b0 = (1.0 + cw) / 2.0;
    bq.b1 = -(1.0 + cw);
    bq.b2 = (1.0 + cw) / 2.0;
    const double a0 = 1.0 + alpha;
    bq.a1 = -2.0 * cw;
    bq.a2 = 1.0 - alpha;
    bq.b0 /= a0; bq.b1 /= a0; bq.b2 /= a0; bq.a1 /= a0; bq.a2 /= a0;
    return bq;
}


// ================================================================ Kern
class MeterCore
{
public:
    struct Stats
    {
        double integratedLufs = -70.0;
        double momentaryLufs  = -70.0;
        double shortTermLufs = -70.0;
        double maxShortTerm   = -70.0;
        double maxMomentary   = -70.0;
        double lra = 0.0;
        double truePeakDbtp = -120.0;
        double lAeq = -120.0, lCeq = -120.0, lCminusA = 0.0;
        double lA10 = -120.0, lA90 = -120.0, lA10minus90 = 0.0;
        double n10 = 0.0, n50 = 0.0, n90 = 0.0, n10minus90 = 0.0;
        double sharpness = 0.0;
        double fluctuationStrength = 0.0;
        double roughness = 0.0;
        double rmsDbfs = -120.0;
    };

    void prepare (double sampleRate, int numChannels, int maxBlockSize)
    {
        fs = sampleRate;
        nch = numChannels;
        kFilters.assign ((size_t) nch, {});
        if (std::abs (fs - 48000.0) < 0.5)
        {
            Biquad s1, s2;
            s1.b0 = 1.53512485958697; s1.b1 = -2.69169618940638; s1.b2 = 1.19839281085285;
            s1.a1 = -1.69065929318241; s1.a2 = 0.73248077421585;
            s2.b0 = 1.0; s2.b1 = -2.0; s2.b2 = 1.0;
            s2.a1 = -1.99004745483398; s2.a2 = 0.99007225036621;
            for (auto& pair : kFilters) { pair.first = s1; pair.second = s2; }
        }
        else
        {
            for (auto& pair : kFilters)
            {
                pair.first = highShelf (fs, 1681.974450, 3.999843854, 0.7071752369);
                pair.second = highPass (fs, 38.135470876, 0.5003270375);
            }
        }
        aWeight = makeWeighting (fs, true);
        cWeight = makeWeighting (fs, false);

        // True-Peak-4x-Oversampling: Fenster-Sinc
        designOversamplingFir();

        blockLen = (int) std::llround (fs * 0.4);
        hopLen   = (int) std::llround (fs * 0.1);
        laBlockLen = (int) std::llround (fs * 0.125);
        hopPos = 0;
        laHopPos = 0;
        blockSums.assign ((size_t) nch, 0.0);
        laSum = 0.0;
        laBlockLevels.clear();
        loudnessBlocks.clear();   // (meanSquare je Kanal) pro Block
        momentaryHistory.clear();
        shortTermHistory.clear();

        nSeries.clear();
        envSeries.clear();
        envBuf.clear();
        truePeak = 0.0;
        fft = std::make_unique<detail::RealFFT> (13); // 8192
        fftData.assign (2 * fft->getSize(), 0.0);
        fftCountdown = 0;
        monoBuf.assign ((size_t) maxBlockSize, 0.0);

        ready = true;
    }

    void reset()
    {
        for (auto& pair : kFilters) { pair.first.reset(); pair.second.reset(); }
        aWeight.reset(); cWeight.reset(); peakFilter.reset();
        blockSums.assign ((size_t) nch, 0.0);
        laSum = 0.0;
        loudnessBlocks.clear();
        laBlockLevels.clear();
        momentaryHistory.clear();
        shortTermHistory.clear();

        nSeries.clear();
        envSeries.clear();
        envBuf.clear();
        truePeak = 0.0;
    }

    // Eingang: Mono-Signal (W oder Summe), alle Kanäle für BS.1770
    void processBlock (const float* const* channelData, int numSamples,
                       int monoChannel, double splOffsetDb)
    {
        if (! ready) return;
        // ---- True Peak (4x Interpolation, BS.1770 Annex 2) ----
        const float* mono = channelData[monoChannel];
        for (int i = 0; i < numSamples; ++i)
        {
            const double x = (double) mono[i];
            for (int ph = 0; ph < 4; ++ph)
            {
                double y = 0.0;
                for (size_t k = 0; k < ntaps; ++k)
                {
                    const size_t idx = (firHistPos + k) % ntaps;
                    y += firHist[idx] * fir[(size_t) ph][k];
                }
                const double pk = std::abs (y);
                if (pk > truePeak) truePeak = pk;
            }
            firHist[firHistPos] = x;
            firHistPos = (firHistPos + 1) % ntaps;
        }

        // ---- BS.1770: K-Filter + Blocksummen ----
        for (int c = 0; c < nch; ++c)
        {
            double sum = blockSums[(size_t) c];
            auto& kf = kFilters[(size_t) c];
            for (int i = 0; i < numSamples; ++i)
            {
                const double y = kf.second.process (kf.first.process ((double) channelData[c][i]));
                sum += y * y;
            }
            blockSums[(size_t) c] = sum;
        }
        hopPos += numSamples;
        if (hopPos >= hopLen)
        {
            const size_t samplesInBlock = (size_t) hopPos;
            std::vector<double> ms ((size_t) nch);
            for (int c = 0; c < nch; ++c)
            {
                ms[(size_t) c] = blockSums[(size_t) c] / (double) samplesInBlock;
                blockSums[(size_t) c] = 0.0;
            }
            hopPos = 0;
            loudnessBlocks.push_back (ms);
            if (loudnessBlocks.size() > (size_t) std::max (4, blockLen / hopLen * 4))
                loudnessBlocks.pop_front();
        }

        // ---- A-Bewertung (Mono) fuer L_Aeq / Perzentile ----
        double laSumLocal = 0.0;
        for (int i = 0; i < numSamples; ++i)
        {
            const double y = aWeight.process ((double) mono[i]) * aGain;
            laSumLocal += y * y;
            aRmsAccum += y * y; ++aRmsCount;
            cRmsAccum += std::pow (cWeight.process ((double) mono[i]) * cGain, 2.0);
            ++cRmsCount;
        }
        laSum += laSumLocal;
        laHopPos += numSamples;
        if (laHopPos >= laBlockLen / 4) // ~31 ms Hops fuer 125-ms-Bloecke
        {
            const double lvl = 10.0 * std::log10 (std::max (laSum / (double) laHopPos, 1e-24));
            laBlockLevels.push_back (lvl + splOffsetDb);
            if (laBlockLevels.size() > 4000) laBlockLevels.pop_front();
            laSum = 0.0; laHopPos = 0;
        }

        // ---- Spektrum fuer Zwicker/Sharpness (Mono, alle 50 ms) ----
        for (int i = 0; i < numSamples; ++i)
        {
            envBuf.push_back ((double) mono[i]);
            if (envBuf.size() > monoBuf.capacity())
                envBuf.erase (envBuf.begin(), envBuf.end() - monoBuf.capacity());
        }
        fftCountdown += numSamples;
        if (fftCountdown >= (int) std::llround (fs * 0.05))
        {
            fftCountdown = 0;
            psychoacousticTick (mono, numSamples, splOffsetDb);
        }

        // ---- Momentary/Short-Term aus Blockliste ----
        updateLoudnessWindows();
    }

    Stats getStats (double splOffsetDb)
    {
        Stats s;
        s.truePeakDbtp = 20.0 * std::log10 (std::max (truePeak, 1e-12));
        s.integratedLufs = gatedLoudness (loudnessBlocks, 400.0);
        s.momentaryLufs = momentaryNow;
        s.shortTermLufs = shortTermNow;
        s.maxMomentary = maxMomentary;
        s.maxShortTerm = maxShortTerm;
        s.lra = computeLra();
        if (aRmsCount > 0)
            s.lAeq = 10.0 * std::log10 (std::max (aRmsAccum / (double) aRmsCount, 1e-24)) + splOffsetDb;
        if (cRmsCount > 0)
            s.lCeq = 10.0 * std::log10 (std::max (cRmsAccum / (double) cRmsCount, 1e-24)) + splOffsetDb;
        s.lCminusA = s.lCeq - s.lAeq;
        computeLevelPercentiles (s, splOffsetDb);
        computeLoudnessPercentiles (s);
        s.sharpness = sharpnessNow;
        s.fluctuationStrength = fsNow;
        s.roughness = roughnessNow;
        return s;
    }

    void resetIntegrated()
    {
        loudnessBlocks.clear();
        momentaryHistory.clear();
        shortTermHistory.clear();
        maxMomentary = -70.0; maxShortTerm = -70.0;
        nSeries.clear(); laBlockLevels.clear();
        aRmsAccum = 0; aRmsCount = 0; cRmsAccum = 0; cRmsCount = 0;
    }

public:
    // ------------------------------------------------ Hilfsstrukturen
private:
    struct CascadeFilter
    {
        std::vector<Biquad> sections;
        double gain = 1.0;
        void reset() { for (auto& b : sections) b.reset(); }
        inline double process (double x)
        {
            for (auto& bq : sections) x = bq.process (x);
            return x * gain;
        }
    };

    static CascadeFilter makeWeighting (double fsRate, bool isA)
    {
        // IEC 61672 Analogprototyp, exakte Bilinear-Transformation:
        // Polstelle s=-w  ->  z^-1 = (2fs + w) / (2fs - w)
        const double f1 = 20.598997, f2 = 107.65265, f3 = 737.86223, f4 = 12194.217;
        const double pi = kPi;
        std::vector<double> polesA = { -2*pi*f1, -2*pi*f1, -2*pi*f2, -2*pi*f3, -2*pi*f4, -2*pi*f4 };
        std::vector<double> polesC = { -2*pi*f1, -2*pi*f1, -2*pi*f4, -2*pi*f4 };
        auto& poles = isA ? polesA : polesC;
        const int nZeroPairs = isA ? 2 : 1;  // doppelte Nullstelle bei z^-1=1
        CascadeFilter cf;
        const double k = 2.0 * fsRate;
        for (size_t i = 0; i < poles.size(); i += 2)
        {
            const double p0 = poles[i];
            const double p1 = (i + 1 < poles.size()) ? poles[i + 1] : p0;
            const double z0 = (k + p0) / (k - p0);
            const double z1 = (k + p1) / (k - p1);
            Biquad bq;
            // Nenner: (1 - z0 z^-1)(1 - z1 z^-1)
            bq.a1 = -(z0 + z1);
            bq.a2 = z0 * z1;
            // Zaehler: Nullstellen bei z^-1 = 1
            if ((int) (i / 2) < nZeroPairs)
            {
                bq.b0 = 1.0; bq.b1 = -2.0; bq.b2 = 1.0;
            }
            else
            {
                bq.b0 = 1.0; bq.b1 = 0.0; bq.b2 = 0.0;
            }
            cf.sections.push_back (bq);
        }
        // exakte Normierung: Durchlass bei 1 kHz messen (digital)
        const int N = 8192;
        std::vector<double> in ((size_t) N), out ((size_t) N);
        for (int i = 0; i < N; ++i)
            in[(size_t) i] = std::sin (2.0 * kPi * 1000.0 * i / fsRate);
        for (int i = 0; i < N; ++i)
        {
            double y = in[(size_t) i];
            for (auto& bq : cf.sections) y = bq.process (y);
            out[(size_t) i] = y;
        }
        const size_t skip = (size_t) (N / 2);
        double po = 0.0, pr = 0.0;
        for (size_t i = skip; i < (size_t) N; ++i)
        {
            po += out[i] * out[i];
            pr += in[i] * in[i];
        }
        cf.gain = std::sqrt (pr / std::max (po, 1e-30));
        return cf;
    }

    void designOversamplingFir()
    {
        // 4 Phasen einer fensterbelegten Sinc-Interpolation (4x)
        fir.assign (4, std::vector<double> (ntaps, 0.0));
        for (int ph = 0; ph < 4; ++ph)
        {
            for (size_t i = 0; i < ntaps; ++i)
            {
                const double m = 4.0 * (double) ((long long) i - (long long) (ntaps / 2)) + (double) ph;
                double sinc = (m == 0.0) ? 1.0 : std::sin (kPi * m / 4.0) / (kPi * m / 4.0);
                const double w = 0.54 - 0.46 * std::cos (2.0 * kPi * i / (double) (ntaps - 1));
                fir[(size_t) ph][i] = sinc * w;
            }
        }
        firHist.assign (ntaps, 0.0);
        firHistPos = 0;
    }

    double gatedLoudness (const std::deque<std::vector<double>>& blocks, double)
    {
        if (blocks.empty()) return -70.0;
        // Blocklautheiten
        std::vector<double> z;
        z.reserve (blocks.size());
        for (auto& ms : blocks)
        {
            double sum = 0.0;
            for (double v : ms) sum += v;
            z.push_back (sum);
        }
        double maxZ = 0.0;
        for (double v : z) maxZ = std::max (maxZ, v);
        if (maxZ <= 0.0) return -70.0;
        const double relThresh = -0.691 + 10.0 * std::log10 (maxZ) - 10.0;
        double acc = 0.0; int cnt = 0;
        for (double v : z)
        {
            const double l = -0.691 + 10.0 * std::log10 (std::max (v, 1e-24));
            if (l > -70.0 && l > relThresh) { acc += v; ++cnt; }
        }
        if (cnt == 0) return -70.0;
        return -0.691 + 10.0 * std::log10 (acc / (double) cnt);
    }

    void updateLoudnessWindows()
    {
        // Momentary: letzte 400 ms der Bloecke (100-ms-Hop)
        double momentary = gatedLoudness (loudnessBlocks, 400.0);
        momentaryNow = momentary;
        if (momentary > -70.0)
        {
            momentaryHistory.push_back (momentary);
            if (momentaryHistory.size() > 600) momentaryHistory.pop_front();
            maxMomentary = std::max (maxMomentary, momentary);
        }
        // Short-Term: 3 s => wir berechnen aus Blockliste mit 1-s-Hop
        stCounter++;
        if (stCounter >= 10) // 10 * 100 ms = 1 s
        {
            stCounter = 0;
            double st = gatedLoudness (loudnessBlocks, 3000.0);
            shortTermNow = st;
            if (st > -70.0)
            {
                shortTermHistory.push_back (st);
                if (shortTermHistory.size() > 3600) shortTermHistory.pop_front();
            }
        }
    }

    double computeLra()
    {
        std::vector<double> st (shortTermHistory.begin(), shortTermHistory.end());
        std::vector<double> gated;
        for (double v : st) if (v > -70.0) gated.push_back (v);
        if (gated.empty()) return 0.0;
        double mean = 0.0;
        for (double v : gated) mean += v;
        mean /= (double) gated.size();
        std::vector<double> rel;
        for (double v : gated) if (v > mean - 20.0) rel.push_back (v);
        if (rel.empty()) return 0.0;
        std::sort (rel.begin(), rel.end());
        const size_t n = rel.size();
        const double lo = rel[std::min (n - 1, (size_t) std::floor (0.10 * n))];
        const double hi = rel[std::min (n - 1, (size_t) std::ceil (0.95 * n) - 1)];
        return hi - lo;
    }

    void computeLevelPercentiles (Stats& s, double splOffsetDb)
    {
        std::vector<double> lv (laBlockLevels.begin(), laBlockLevels.end());
        const double floorDb = splOffsetDb - 70.0;
        std::vector<double> gated;
        for (double v : lv) if (v > floorDb) gated.push_back (v);
        if (gated.empty()) return;
        std::sort (gated.begin(), gated.end());
        const size_t n = gated.size();
        s.lA90 = gated[std::min (n - 1, (size_t) std::floor (0.10 * n))];
        s.lA10 = gated[std::min (n - 1, (size_t) std::ceil (0.90 * n) - 1)];
        s.lA10minus90 = s.lA10 - s.lA90;
    }

    void computeLoudnessPercentiles (Stats& s)
    {
        if (nSeries.empty()) return;
        std::vector<double> v (nSeries.begin(), nSeries.end());
        std::sort (v.begin(), v.end());
        const size_t n = v.size();
        auto pct = [&] (double p) { return v[std::min (n - 1, (size_t) std::floor (p / 100.0 * n))]; };
        s.n10 = pct (90.0); s.n50 = pct (50.0); s.n90 = pct (10.0);
        s.n10minus90 = s.n10 - s.n90;
    }

    // ------------------------------------------- Psychoakustik (Naeherung)
    void psychoacousticTick (const float* mono, int numSamples, double splOffsetDb)
    {
        // Huellkurve fuer Roughness
        double env = 0.0;
        for (int i = 0; i < numSamples; ++i)
            env = std::max (std::abs ((double) mono[i]), env * 0.999);
        envSeries.push_back (env);
        if (envSeries.size() > 4000) envSeries.pop_front();

        // Spektrum
        const size_t N = fft->getSize();
        std::fill (fftData.begin(), fftData.end(), 0.0);
        const size_t avail = std::min (N, envBuf.size());
        const size_t start = envBuf.size() - avail;
        double w2sum = 0.0;
        for (size_t i = 0; i < N; ++i)
        {
            const double s = i < avail ? envBuf[start + i] : 0.0;
            const double w = 0.5 - 0.5 * std::cos (2.0 * kPi * (double) i / (double) N);
            fftData[2 * i] = s * w;
            w2sum += w * w;
        }
        if (envBuf.size() > N * 4) envBuf.erase (envBuf.begin(), envBuf.begin() + (envBuf.size() - N * 2));
        fft->performRealOnlyForwardTransform (fftData.data(), true);
        const double wCorr = w2sum / (double) N;
        const double pRef = 2e-5 * std::pow (10.0, splOffsetDb / 20.0);
        const double binHz = fs / (double) N;

        // 20 Bark-Baender, Kanten numerisch invertiert (z -> f)
        auto barkOf = [] (double f)
        {
            return 13.0 * std::atan (0.00076 * f) + 3.5 * std::atan (f * f / 56250000.0);
        };
        auto freqOfBark = [&] (double z)
        {
            double lo = 20.0, hi = 20000.0;
            for (int it = 0; it < 60; ++it)
            {
                const double mid = 0.5 * (lo + hi);
                if (barkOf (mid) < z) lo = mid; else hi = mid;
            }
            return 0.5 * (lo + hi);
        };
        // Hoerschwelle in dB SPL je Band (Naeherung an ISO 532-1)
        static const std::array<double, 20> thrDb {{
            23.0, 15.0, 8.0, 5.0, 3.0, 2.0, 2.0, 2.5, 3.0, 4.0,
            5.0, 6.0, 8.0, 10.0, 13.0, 17.0, 22.0, 28.0, 35.0, 43.0
        }};
        double nTotal = 0.0, sharpAcc = 0.0;
        std::vector<double> specN (20, 0.0);
        for (size_t bi = 0; bi < 20; ++bi)
        {
            const double zc = (double) bi + 0.5;
            const double f0 = freqOfBark (zc - 0.5);
            const double f1 = freqOfBark (zc + 0.5);
            const size_t i0 = (size_t) std::max (1.0, std::floor (f0 / binHz));
            const size_t i1 = (size_t) std::max ((double) i0 + 1.0, std::ceil (f1 / binHz));
            double energy = 0.0;
            for (size_t kk = i0; kk < i1 && kk < N / 2; ++kk)
            {
                const double re = fftData[2 * kk], im = fftData[2 * kk + 1];
                energy += (re * re + im * im) / (double) N / wCorr;
            }
            const double bandRms = std::sqrt (energy);
            const double bandPa = bandRms * pRef;
            const double bandDb = 20.0 * std::log10 (std::max (bandPa, 1e-12) / 2e-5);
            double np = 0.0;
            if (bandDb > thrDb[bi])
                np = 0.08 * std::pow (std::pow (10.0, (bandDb - thrDb[bi]) / 10.0), 0.23);
            specN[bi] = np;
            nTotal += np;
            sharpAcc += np * zc;
        }
        const double nSone = nTotal;
        nSeries.push_back (nSone);
        if (nSeries.size() > 4000) nSeries.pop_front();
        sharpnessNow = nSone > 0.01 ? 0.11 * sharpAcc / nSone : 0.0;

        // Fluctuation Strength aus N(t)
        if (nSeries.size() >= 64)
        {
            const size_t M = nSeries.size();
            const double fsN = 20.0; // 50-ms-Hop => 20 Hz
            std::vector<double> buf (M);
            for (size_t i = 0; i < M; ++i)
                buf[i] = std::max (nSeries[i], 1e-6) * (0.5 - 0.5 * std::cos (2.0 * kPi * i / (M - 1)));
            std::vector<double> sp (2 * M, 0.0);
            for (size_t i = 0; i < M; ++i) sp[2 * i] = buf[i];
            ensureFft (fsFft, (int) std::log2 (M));
            fsFft->performRealOnlyForwardTransform (sp.data(), true);
            double best = 0.0, bestHz = 4.0;
            for (size_t k = 1; k < M / 2; ++k)
            {
                const double hz = (double) k * fsN / (double) M;
                if (hz < 0.5 || hz > 30.0) continue;
                const double mag = std::sqrt (sp[2 * k] * sp[2 * k] + sp[2 * k + 1] * sp[2 * k + 1]);
                if (mag > best) { best = mag; bestHz = hz; }
            }
            double nMin = 1e9, nMax = 0.0;
            for (double v : nSeries) { nMin = std::min (nMin, v); nMax = std::max (nMax, v); }
            const double dl = 10.0 * std::log10 (std::max (nMax, 1e-6)) - 10.0 * std::log10 (std::max (nMin, 1e-6));
            const double w = bestHz < 4.0 ? bestHz / 4.0 : 4.0 / bestHz;
            fsNow = 0.008 * std::max (dl, 0.0) * w;
        }

        // Roughness (Huellkurvenmodulation, Naeherung)
        if (envSeries.size() >= 512)
        {
            const size_t M = 512;
            std::vector<double> sp (2 * M, 0.0);
            const double eMean = [&]
            {
                double s = 0.0;
                for (double v : envSeries) s += v;
                return s / (double) envSeries.size();
            }();
            for (size_t i = 0; i < M; ++i)
            {
                const size_t idx = envSeries.size() - M + i;
                const double v = std::max (envSeries[idx] - eMean, 0.0);
                sp[2 * i] = v * (0.5 - 0.5 * std::cos (2.0 * kPi * i / (M - 1)));
            }
            ensureFft (roughFft, 9);
            roughFft->performRealOnlyForwardTransform (sp.data(), true);
            const double hopSec = 0.05;
            double mod15 = 0.0, modTotal = 0.0;
            for (size_t k = 1; k < M / 2; ++k)
            {
                const double hz = (double) k / (double) M / hopSec;
                const double mag = std::sqrt (sp[2 * k] * sp[2 * k] + sp[2 * k + 1] * sp[2 * k + 1]);
                modTotal += mag;
                if (hz >= 15.0 && hz <= 300.0) mod15 += mag;
            }
            double m = modTotal > 0.0 ? mod15 / modTotal : 0.0;
            m = std::min (m, 1.0);
            roughnessNow = 0.3 * m * (1.0 + m);
        }
    }

    // ------------------------------------------------------- Mitglieder
    bool ready = false;
    double fs = 48000.0;
    int nch = 1;
    std::vector<std::pair<Biquad, Biquad>> kFilters;
    CascadeFilter aWeight, cWeight;
    double aGain = 1.0, cGain = 1.0;
    Biquad peakFilter;
    static constexpr size_t ntaps = 33;
    std::vector<std::vector<double>> fir;
    std::vector<double> firHist;
    size_t firHistPos = 0;
    double truePeak = 0.0;

    int blockLen = 0, hopLen = 0, hopPos = 0;
    int laBlockLen = 0, laHopPos = 0;
    std::vector<double> blockSums;
    double laSum = 0.0;
    double aRmsAccum = 0.0; uint64_t aRmsCount = 0;
    double cRmsAccum = 0.0; uint64_t cRmsCount = 0;

    std::deque<std::vector<double>> loudnessBlocks;
    std::deque<double> laBlockLevels;
    std::deque<double> momentaryHistory, shortTermHistory, nSeries, envSeries;
    std::vector<double> envBuf, monoBuf;
    double momentaryNow = -70.0, shortTermNow = -70.0;
    double maxMomentary = -70.0, maxShortTerm = -70.0;
    int stCounter = 0;
    double sharpnessNow = 0.0, fsNow = 0.0, roughnessNow = 0.0;

    std::unique_ptr<detail::RealFFT> fft;
    std::unique_ptr<detail::RealFFT> fsFft, roughFft;
    std::vector<double> fftData;
    int fftCountdown = 0;

    void ensureFft (std::unique_ptr<detail::RealFFT>& slot, int order)
    {
        if (slot == nullptr || slot->getOrder() != order)
            slot = std::make_unique<detail::RealFFT> (order);
    }
};

} // namespace meterdsp
