// Referenz-Tests fuer MeterDSP (gleiche Werte wie die Python-pytests):
//  - Stereo-1-kHz-Sinus bei -23 dBFS => Integrated ~-23 LUFS (BS.1770)
//  - A-Bewertung: 100 Hz gegenueber 1 kHz ~-19.1 dB (IEC 61672)
//  - Zwicker-Naeherung: 1 kHz @ 60 dB SPL => ~4 sone
//  - True Peak ueberschreitet Sample-Peak
#include "../src/MeterDSP.h"
#include <cstdio>
#include <random>
#include <cmath>

using namespace meterdsp;

static int failures = 0;

static void check (const char* name, double value, double expected, double tol)
{
    const bool ok = std::abs (value - expected) <= tol;
    std::printf ("%s %s: %.3f (erwartet %.3f +- %.3f)\n",
                 ok ? "PASS" : "FAIL", name, value, expected, tol);
    if (! ok) ++failures;
}

static std::vector<float> sine (double dbfs, double seconds, double freq,
                                double fs, double modHz = 0.0,
                                double modDepth = 0.0)
{
    const size_t n = (size_t) std::llround (fs * seconds);
    std::vector<float> s (n);
    const double amp = std::pow (10.0, dbfs / 20.0);
    for (size_t i = 0; i < n; ++i)
    {
        const double t = (double) i / fs;
        double m = 1.0;
        if (modHz > 0.0)
            m = 1.0 - modDepth + modDepth * (0.5 + 0.5 * std::sin (2.0 * kPi * modHz * t));
        s[i] = (float) (amp * m * std::sin (2.0 * kPi * freq * t));
    }
    return s;
}

int main()
{
    const double fs = 48000.0;

    // ---- Test 1: Stereo-Referenz -23 LUFS ----
    {
        MeterCore core;
        core.prepare (fs, 2, 512);
        auto s = sine (-23.0, 20.0, 1000.0, fs);

        for (size_t off = 0; off < s.size(); off += 512)
        {
            const float* c[2] = { s.data() + off, s.data() + off };
            core.processBlock (c, (int) std::min ((size_t) 512, s.size() - off), 0, 94.0);
        }
        const auto st = core.getStats (94.0);
        check ("Integrated LUFS", st.integratedLufs, -23.0, 0.2);
    }

    // ---- Test 2: A-Bewertung ueber L_Aeq-Differenz ----
    {
        MeterCore core1, core2;
        core1.prepare (fs, 1, 512);
        core2.prepare (fs, 1, 512);
        auto s1k = sine (-23.0, 4.0, 1000.0, fs);
        auto s100 = sine (-23.0, 4.0, 100.0, fs);
        for (size_t off = 0; off < s1k.size(); off += 512)
        {
            const float* c1[1] = { s1k.data() + off };
            const float* c2[1] = { s100.data() + off };
            const int n = (int) std::min ((size_t) 512, s1k.size() - off);
            core1.processBlock (c1, n, 0, 94.0);
            core2.processBlock (c2, n, 0, 94.0);
        }
        const double diff = core1.getStats (94.0).lAeq - core2.getStats (94.0).lAeq;
        check ("A-Bewertung 100Hz rel. 1kHz", diff, 19.1, 1.5);
    }

    // ---- Test 3: Zwicker-Naeherung 4 sone @ 60 dB SPL ----
    {
        MeterCore core;
        core.prepare (fs, 1, 512);
        // RMS-normiert: 0 dBFS RMS = 60 dB SPL
        auto s = sine (20.0 * std::log10 (std::sqrt (2.0)), 6.0, 1000.0, fs);
        for (size_t off = 0; off < s.size(); off += 512)
        {
            const float* c[1] = { s.data() + off };
            core.processBlock (c, (int) std::min ((size_t) 512, s.size() - off), 0, 60.0);
        }
        const auto st = core.getStats (60.0);
        std::printf ("Zwicker N50: %.2f sone (Referenz ~4)\n", st.n50);
        check ("Zwicker N50", st.n50, 4.0, 2.5);
    }

    // ---- Test 4: True Peak > Sample-Peak ----
    {
        MeterCore core;
        core.prepare (fs, 1, 512);
        auto s = sine (-3.0, 1.0, 1000.0, fs);
        for (size_t off = 0; off < s.size(); off += 512)
        {
            const float* c[1] = { s.data() + off };
            core.processBlock (c, (int) std::min ((size_t) 512, s.size() - off), 0, 94.0);
        }
        const auto st = core.getStats (94.0);
        check ("True Peak dBTP", st.truePeakDbtp, -2.8, 0.6);
    }

    // ---- Test 5: AM-moduliertes Signal: groessere Pegelvariabilitaet ----
    {
        MeterCore coreAM, coreConst;
        coreAM.prepare (fs, 1, 512);
        coreConst.prepare (fs, 1, 512);
        auto am = sine (-20.0, 12.0, 1000.0, fs, 0.5, 0.5);
        auto cst = sine (-20.0, 12.0, 1000.0, fs);
        for (size_t off = 0; off < am.size(); off += 512)
        {
            const float* c1[1] = { am.data() + off };
            const float* c2[1] = { cst.data() + off };
            const int n = (int) std::min ((size_t) 512, am.size() - off);
            coreAM.processBlock (c1, n, 0, 94.0);
            coreConst.processBlock (c2, n, 0, 94.0);
        }
        const double vAM = coreAM.getStats (94.0).lA10minus90;
        const double vConst = coreConst.getStats (94.0).lA10minus90;
        std::printf ("L_A10-L_A90: AM %.2f dB vs konstant %.2f dB\n", vAM, vConst);
        check ("Variabilitaet AM > konstant", vAM > vConst ? 1.0 : 0.0, 1.0, 0.001);
    }

    std::printf ("\n%s (%d Fehler)\n", failures == 0 ? "ALLE TESTS BESTANDEN" : "FEHLER", failures);
    return failures == 0 ? 0 : 1;
}
