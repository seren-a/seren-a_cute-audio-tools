// PsyTests.cpp -- validiert die portierte Psychoakustik (Psychoacoustics.h)
// gegen mosqito-Referenzwerte. Signale + Referenzen kommen aus psy_gen.py:
//   usage: psy_tests <psy_signals.bin> <psy_ref.txt>
//
// Build: clang++ -std=c++17 -O2 -I. PsyTests.cpp -o psy_tests

#include <cmath>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

#include "Psychoacoustics.h"

using namespace ald;

static int failures = 0, checks = 0;

static void checkClose(const char* what, double got, double ref, double relTol, double absTol) {
    ++checks;
    double diff = std::abs(got - ref);
    double tol = std::max(absTol, relTol * std::abs(ref));
    if (!(diff <= tol)) {
        ++failures;
        std::printf("FAIL %-28s got=%.6f ref=%.6f (diff=%.4g, tol=%.4g)\n", what, got, ref, diff, tol);
    } else {
        std::printf("ok   %-28s got=%.6f ref=%.6f\n", what, got, ref);
    }
}

int main(int argc, char** argv) {
    if (argc < 3) {
        std::printf("usage: %s psy_signals.bin psy_ref.txt\n", argv[0]);
        return 2;
    }
    std::ifstream fb(argv[1], std::ios::binary);
    std::map<std::string, std::vector<double>> sigs;
    std::map<std::string, size_t> order;
    // Reihenfolge der Signale wie in psy_gen.py
    const char* names[] = {"sine1k_60dB", "am1k_70Hz_60dB", "noise_60dB",
                           "chirp1k5k_60dB", "sine100_60dB"};
    for (auto* nm : names) {
        int64_t n = 0;
        fb.read((char*)&n, sizeof(n));
        std::vector<double> s(n);
        fb.read((char*)s.data(), n * sizeof(double));
        sigs[nm] = std::move(s);
    }
    std::ifstream fr(argv[2]);
    std::map<std::string, std::map<std::string, double>> ref;
    std::string line;
    while (std::getline(fr, line)) {
        std::istringstream ss(line);
        std::string name;
        ss >> name;
        std::string tok;
        while (ss >> tok) {
            auto eq = tok.find('=');
            ref[name][tok.substr(0, eq)] = std::stod(tok.substr(eq + 1));
        }
    }

    for (auto* nm : names) {
        auto& p = sigs[nm];
        auto& R = ref[nm];
        std::printf("--- %s ---\n", nm);
        PsychoResult r = psychoacoustics(p.data(), p.size(), 48000.0);
        checkClose("N10", r.N10, R["N10"], 0.03, 0.05);
        checkClose("N50", r.N50, R["N50"], 0.03, 0.05);
        checkClose("N90", r.N90, R["N90"], 0.03, 0.05);
        checkClose("S_acum", r.S_acum, R["S"], 0.10, 0.05);
        checkClose("R_asper", r.R_asper, R["R"], 0.15, 0.05);
        checkClose("FS_vacil", r.FS_vacil, R["FS"], 0.25, 0.03);
    }
    std::printf("%d Checks, %d Fehler\n", checks, failures);
    return failures ? 1 : 0;
}
