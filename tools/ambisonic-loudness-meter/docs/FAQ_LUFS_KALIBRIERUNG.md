# FAQ: LUFS-Berechnung mit Ambisonics & Kalibrierung

(Stand: PR `vibe/ambisonic-loudness-meter-finish`)

## 1. Vorgehen: Loudness-Metering in LUFS mit Ambisonics (BS.1770-5 / EBU R128)

BS.1770 ist für **Lautsprecher-Feeds** definiert, nicht für Szenen (Ambisonics).
Deshalb:

1. **Dekodieren:** B-Format/HOA → virtuelle Lautsprecher (bei uns max-rE
   Energy-Decoding, default-Layout je Ordnung: 11 virtuelle LS bei 1OA).
2. **Kanalgewichte:** G = 1.0 für L/C/R, **G = 1.41** für Surround (60–120°) und
   Elevation > 5°.
3. **K-weighting** pro Kanal (High-Shelf + High-Pass), dann Energiesumme:
   `L = −0.691 + 10·log10( Σ Gᵢ·zᵢ )`
4. **Gating fürs Integrated:** 400-ms-Blöcke, 75 % Überlappung, absolutes Gate
   −70 LUFS, relatives Gate −10 LU unter dem ungegateten Mittel.
5. **Kennwerte:** Integrated (ganzes Programm), max Short-Term (3 s), max
   Momentary (400 ms), **LRA** (10/95-Perzentile der 3-s-Werte), **True Peak**
   (4× Oversampling, dBTP).
6. **Zielwerte EBU R128:** −23 LUFS ±0.5 LU, True Peak ≤ −1 dBTP (ATSC: −24 LUFS).

**Ambisonics-Sonderfall:** Die **W-only-Direktschätzung** (0. Ordnung, skaliert
mit 2·√π ≈ +11 dB) ist layout-unabhängig und laut AES-Paper („Loudness
Perception of Scene-Based Audio across Loudspeaker Configurations and HOA
Orders“) eine gute Näherung der decodierten Lautheit. Das Plugin zeigt beides
(decodierte LUFS + W-only).

**Psychoakustik (Torresin et al. 2020) immer auf W** (Omni am Aufnahmeort):
L_Aeq, N10/N50/N90 (sone), Sharpness, Roughness, FS, L_C−L_A, L_A10−L_A90.

## 2. Wie viel Prozent hat W an der LUFS-Messung? (3OA)

In der decodierten LUFS wird W nicht separat gewichtet — die Decodierung mischt
W in jeden virtuellen Lautsprecher. In der **SH-Ebene** trägt W (ACN 0, SN3D)
bei einer Schallquelle (ebene Welle) und in einem ideal diffussen Feld exakt

```
W-Anteil = 1 / (N+1)²   der Gesamtenergie des Schallfelds
```

| Ordnung | Kanäle | W-Anteil |
|---|---|---|
| 1OA | 4 | 25,00 % |
| 2OA | 9 | 11,11 % |
| **3OA** | **16** | **6,25 %** |

(numerisch verifiziert: plane wave 3OA, SN3D → 6,2500 %)

Die LUFS summiert allerdings die **decodierten LS-Feeds** mit G-Gewichten, nicht
die SH-Kanäle direkt — bei einer Quelle aus LS-Richtung landet nach max-rE der
Großteil der Energie in diesem LS. Die 2√π-Skalierung der W-only-Anzeige
kompensiert genau diesen Ordnungs-/Layout-Unterschied.

**Plugin-Umfang:** HOA Order 1–3 (bis 16 Kanäle, ACN/SN3D). Die
Torresin-BFormat-Dateien sind **1OA (4 Kanäle)**. Das Kalibrier-WAV ist plain
Stereo (kein Ambisonics).

## 3. Kalibrierung: SPL Cal (dBFS → dB SPL)

LUFS ist relativ zu 0 dBFS. Der SPL-Cal-Wert ist der Offset:

```
angezeigter dB SPL = LUFS + SPL Cal
```

- **Default 94 dB** = Konvention „0 dBFS = 1 Pa = 94 dB SPL“ (Mess-Recorder,
  WAV in Pa). Sind die Aufnahmen so kalibriert (z. B. AMBEO VR), sind
  L_Aeq/sone echte Szenen-Werte.
- **N10/N50/N90 (sone) und L_Aeq sind absolut** — ohne korrekte Kalibrierung
  nicht aussagekräftig. LUFS, LRA, L_C−L_A, TP sind davon nur verschoben.
- **Faustregel:** 1 dB Aufnahmefehler = 1 dB Fehler in allen absoluten Werten.

### Variante A (empfohlen, EBU R128): −23 LUFS = 83 dB SPL(C)
1. Kalibrierdatei: 1 kHz-Sinus, −23 dBFS RMS, 60 s
   (`scripts/make_calibration_signal.py`, fertiges File
   `examples/calibration_1kHz_-23dBFS_60s.wav`, oder EBU Tech 3341 von
   tech.ebu.ch/publications/tech3341).
2. In REAPER auf Monitor-Out, Loop, Fader 0 dB.
3. SPL-Meter an der Messposition (dort wo das Ambisonic-Mic stand):
   **C-Bewertung, Slow, Leq, 30–60 s mitteln**; Monitor-Gain so, dass
   **83 dB SPL(C)** angezeigt werden (EBU Tech 3343 Reference Listening Level).
4. Plugin: **SPL Cal = 83 + 23 = 106 dB**.
5. Kontrolle: Kalibrierfile durchs Plugin → Integrated ≈ −23 LUFS,
   L_Aeq ≈ 83 dB(A).

### Variante B: Direktmessung
1 kHz-Sinus bei −20 dBFS abspielen, Meter liest X dB SPL(C) → **SPL Cal = X + 20**
(SMPTE RP 200: −20 dBFS = 83 dB SPL(C) → 103).

### Pro Item?
**Nein** — Kalibrierung gehört zur Wiedergabekette (DAW → Interface → Monitore
→ Raum), einmal pro Session. Wird mit dem REAPER-Projekt gespeichert (HOA
Order + SPL Cal im Plugin-State). Pro-Item-Offset nur bei unterschiedlicher
Aufnahme-Verstärkung der Files. Batch: `--spl-offset` pro Lauf.

Unbekannte Aufnahme-Kalibrierung (z. B. Torresin): nur relativ vergleichen oder
gegen einen bekannten Wert der Studie kalibrieren.

## 4. Siehe auch

- `docs/SPL_KALIBRIERUNG.md` — ausführliches How-To mit Checkliste
- `README.md` — Parameter-Tabelle (Torresin et al. 2020)
