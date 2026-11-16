// DspTests.cpp -- Referenztests fuer den JUCE-unabhaengigen DSP-Kern.
// Validiert gegen dieselben Normreferenzen wie die pytest-Suite des
// Python-Kerns (BS.1770: -23 dBFS => -23 LUFS; IEC 61672: -19.1 dB bei
// 100 Hz; True Peak; LRA; max-rE-Richtung; Richtungsinvarianz).
//
// Build (ohne JUCE):  clang++ -std=c++17 -O2 -I. DspTests.cpp -o dsp_tests

#include <cmath>
#include <cstdio>
#include <vector>

#include "AmbisonicDsp.h"

using namespace ald;

static int failures = 0;
static int checks = 0;

#define CHECK(cond)                                                        \
    do {                                                                   \
        ++checks;                                                          \
        if (!(cond)) {                                                     \
            ++failures;                                                    \
            std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);   \
        }                                                                  \
    } while (0)

#define CHECK_NEAR(val, ref, tol)                                          \
    do {                                                                   \
        ++checks;                                                          \
        double v_ = (val), r_ = (ref), t_ = (tol);                         \
        if (std::abs(v_ - r_) > t_) {                                      \
            ++failures;                                                    \
            std::printf("FAIL %s:%d: %s = %f, erwartet %f +/- %f\n",      \
                        __FILE__, __LINE__, #val, v_, r_, t_);             \
        }                                                                  \
    } while (0)

static constexpr double FS = 48000.0;

static std::vector<double> sine(double dbfs, double seconds, double freq = 1000.0) {
    double amp = std::pow(10.0, dbfs / 20.0);
    size_t n = (size_t)(FS * seconds);
    std::vector<double> s(n);
    for (size_t i = 0; i < n; ++i) s[i] = amp * std::sin(2 * kPi * freq * i / FS);
    return s;
}

static void testKFilter48kCoefficients() {
    // Bei 48 kHz muessen die publizierten BS.1770-Koeffizienten herauskommen
    Biquad shelf = bilinearBiquad(1.5848647011308554, 18886.914378028901, 112594507.26979087,
                                  1.0, 15004.846526655718, 112594507.26978998, FS);
    Biquad hpf = bilinearBiquad(1.0049948987146884, 0.0, 0.0,
                                1.0, 478.91221140842475, 57414.259358626012, FS);
    CHECK_NEAR(shelf.b0, 1.53512485958697, 1e-9);
    CHECK_NEAR(shelf.b1, -2.69169618940638, 1e-9);
    CHECK_NEAR(shelf.b2, 1.19839281085285, 1e-9);
    CHECK_NEAR(shelf.a1, -1.69065929318241, 1e-9);
    CHECK_NEAR(shelf.a2, 0.73248077421585, 1e-9);
    CHECK_NEAR(hpf.b0, 1.0, 1e-9);
    CHECK_NEAR(hpf.b1, -2.0, 1e-9);
    CHECK_NEAR(hpf.b2, 1.0, 1e-9);
    CHECK_NEAR(hpf.a1, -1.99004745483398, 1e-9);
    CHECK_NEAR(hpf.a2, 0.99007225036621, 1e-9);
}

static void testStereoReference() {
    auto s = sine(-23.0, 20.0);
    Bs1770Meter m;
    m.prepare(FS, 2, {1.0, 1.0});
    const double* p[2] = {s.data(), s.data()};
    m.process(p, s.size());
    CHECK_NEAR(m.integrated(), -23.0, 0.1);
}

static void testSurroundGain() {
    auto s = sine(-23.0, 20.0);
    Bs1770Meter front, sur;
    front.prepare(FS, 1, {1.0});
    sur.prepare(FS, 1, {std::pow(10.0, 3.01 / 10.0)});
    const double* p = s.data();
    front.process(&p, s.size());
    sur.process(&p, s.size());
    CHECK_NEAR(sur.integrated() - front.integrated(), 3.01, 0.1);
}

static void testRelativeGating() {
    // 10 s laut (-23), 10 s leise (-60): leiser Teil darf nicht mitgerechnet werden
    auto loud = sine(-23.0, 10.0), quiet = sine(-60.0, 10.0);
    std::vector<double> x(loud.size() + quiet.size());
    std::copy(loud.begin(), loud.end(), x.begin());
    std::copy(quiet.begin(), quiet.end(), x.begin() + loud.size());
    Bs1770Meter m;
    m.prepare(FS, 2, {1.0, 1.0});
    const double* p[2] = {x.data(), x.data()};
    m.process(p, x.size());
    CHECK_NEAR(m.integrated(), -23.0, 0.5);
}

static void testLraTwoLevels() {
    // Wechsel zwischen -30 und -10 dBFS alle 5 s -> LRA ~ 20 LU
    std::vector<double> x;
    for (int b = 0; b < 4; ++b) {
        auto part = (b % 2 == 0) ? sine(-30.0, 5.0) : sine(-10.0, 5.0);
        x.insert(x.end(), part.begin(), part.end());
    }
    Bs1770Meter m;
    m.prepare(FS, 1, {1.0});
    const double* p[1] = {x.data()};
    m.process(p, x.size());
    CHECK_NEAR(m.loudnessRange(), 20.0, 3.0);
}

static void testTruePeak() {
    auto s = sine(-3.0, 1.0);
    TruePeak tp;
    tp.prepare(FS, 4);
    for (double v : s) tp.process(v);
    double dbtp = tp.dbtp();
    CHECK(dbtp > -3.1 && dbtp < -2.4);
    // Vollaussteuerung: True Peak ~ 0 dBTP
    auto fs1 = sine(0.0, 1.0);
    TruePeak tp2;
    tp2.prepare(FS, 4);
    for (double v : fs1) tp2.process(v);
    CHECK(tp2.dbtp() > -0.2 && tp2.dbtp() < 0.2);
}

static void testWeighting() {
    auto s1k = sine(-6.0, 2.0, 1000.0);
    auto s100 = sine(-6.0, 2.0, 100.0);
    auto wa = Weighting::create(FS, true);
    double pIn = 0, pOut = 0;
    for (double v : s1k) { double y = wa.process(v); pIn += v * v; pOut += y * y; }
    CHECK_NEAR(10.0 * std::log10(pOut / pIn), 0.0, 0.5);
    pIn = pOut = 0;
    for (double v : s1k) { double y = wa.process(v); pIn += v * v; pOut += y * y; }
    double g1k = 10.0 * std::log10(pOut / pIn);
    pIn = pOut = 0;
    for (double v : s100) { double y = wa.process(v); pIn += v * v; pOut += y * y; }
    double g100 = 10.0 * std::log10(pOut / pIn);
    CHECK_NEAR(g100 - g1k, -19.1, 1.5);
}

static void testShFirstOrder() {
    auto y0 = sphericalHarmonics(0.0, 0.0, 1);
    CHECK(y0.size() == 4);
    CHECK_NEAR(y0[0], 1.0 / (2.0 * std::sqrt(kPi)), 1e-12);
}

static void testDecodeDirection() {
    int order = 1, nCh = 4;
    auto sig = sine(-20.0, 5.0);
    auto b = encodePlaneWave(sig.data(), sig.size(), 90.0, 0.0, order);
    std::vector<std::pair<double, double>> layout = {{-90, 0}, {0, 0}, {90, 0}, {180, 0}};
    auto spk = energyDecode(b, nCh, sig.size(), layout, order);
    int argmax = 0;
    double best = -1;
    for (int s = 0; s < 4; ++s) {
        double e = 0;
        for (double v : spk[s]) e += v * v;
        if (e > best) { best = e; argmax = s; }
    }
    CHECK(argmax == 2);
}

static void testDirectionInvariance() {
    auto sig = sine(-23.0, 10.0);
    double vals[4];
    const double azs[4] = {0.0, 45.0, 90.0, 135.0};
    for (int k = 0; k < 4; ++k) {
        auto b = encodePlaneWave(sig.data(), sig.size(), azs[k], 0.0, 3);
        int nCh = 16;
        std::vector<const double*> ptrs(nCh);
        for (int c = 0; c < nCh; ++c) ptrs[c] = &b[(size_t)c * sig.size()];
        AmbisonicMeter m;
        m.prepare(FS, 3);
        const size_t block = 4800;
        std::vector<std::vector<double>> blocks(nCh, std::vector<double>(block));
        for (size_t off = 0; off < sig.size(); off += block) {
            size_t n = std::min(block, sig.size() - off);
            for (int c = 0; c < nCh; ++c)
                std::copy(b.begin() + (size_t)c * sig.size() + off,
                          b.begin() + (size_t)c * sig.size() + off + n, blocks[c].begin());
            std::vector<const double*> bp(nCh);
            for (int c = 0; c < nCh; ++c) bp[c] = blocks[c].data();
            m.process(bp.data(), n);
        }
        vals[k] = m.result().integratedLufs;
    }
    double mn = *std::min_element(vals, vals + 4), mx = *std::max_element(vals, vals + 4);
    CHECK(mx - mn < 1.5);
}

static void testMeasureAmbisonics() {
    auto sig = sine(-23.0, 10.0);
    auto b = encodePlaneWave(sig.data(), sig.size(), 30.0, 0.0, 1);
    int nCh = 4;
    std::vector<const double*> ptrs(nCh);
    for (int c = 0; c < nCh; ++c) ptrs[c] = &b[(size_t)c * sig.size()];
    AmbisonicMeter m;
    m.prepare(FS, 1);
    const size_t block = 4800;
    std::vector<std::vector<double>> blocks(nCh, std::vector<double>(block));
    for (size_t off = 0; off < sig.size(); off += block) {
        size_t n = std::min(block, sig.size() - off);
        for (int c = 0; c < nCh; ++c)
            std::copy(b.begin() + (size_t)c * sig.size() + off,
                      b.begin() + (size_t)c * sig.size() + off + n, blocks[c].begin());
        std::vector<const double*> bp(nCh);
        for (int c = 0; c < nCh; ++c) bp[c] = blocks[c].data();
        m.process(bp.data(), n);
    }
    auto r = m.result();
    CHECK(r.order == 1 && r.nChannels == 4);
    CHECK(std::abs(r.integratedLufs - r.wOnlyLufs) < 2.5);
    CHECK(r.perSpeakerLufs.size() == 11);
    CHECK(std::isfinite(r.lra) && r.lra >= 0.0);
    CHECK(std::isfinite(r.truePeakDbtp));
}

static void testAcnOrder() {
    CHECK(acnOrder(4) == 1);
    CHECK(acnOrder(9) == 2);
    CHECK(acnOrder(16) == 3);
    CHECK(acnOrder(5) == -1);
}

int main() {
    testKFilter48kCoefficients();
    testStereoReference();
    testSurroundGain();
    testRelativeGating();
    testLraTwoLevels();
    testTruePeak();
    testWeighting();
    testShFirstOrder();
    testDecodeDirection();
    testDirectionInvariance();
    testMeasureAmbisonics();
    testAcnOrder();
    std::printf("%d Checks, %d Fehler\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
