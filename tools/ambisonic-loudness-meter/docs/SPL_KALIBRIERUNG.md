# SPL-Kalibrierung im Ambisonic Loudness Meter (dBFS → dB SPL)

## Was der „SPL Cal"-Regler tut

LUFS ist **relativ** zu digital full scale (0 dBFS). Der SPL-Cal-Wert ist der
Offset, der daraus absolute Schalldruckpegel macht:

```
angezeigter dB SPL  =  LUFS + SPL Cal
```

Default **94 dB** = Konvention „0 dBFS = 1 Pa = 94 dB SPL" (üblich bei
Mess-Recordern, die WAV direkt in Pa schreiben).

**Wichtig:** N10/N50/N90 (sone, ISO 532-1) und L_Aeq in dB(A) sind *absolute*
Größen — ohne korrekte Kalibrierung sind sie nicht aussagekräftig.
LUFS, LRA, L_C−L_A, True Peak sind davon nur verschoben (relativ bleibt relativ).

## Variante A (empfohlen): Monitoring auf EBU-Referenz kalibrieren

Ziel: **−23 LUFS werden zu 83 dB SPL(C)** (EBU Tech 3343, Reference Listening
Level). Daraus folgt direkt der Plugin-Wert:

```
SPL Cal = 83 + 23 = 106 dB
```

### Vorgehen

1. **Kalibrierdatei** erzeugen: 1 kHz-Sinus, −23 dBFS RMS, 60 s — z. B. mit
   `python3 scripts/make_calibration_signal.py calibration.wav`
   (fertiges File: `examples/calibration_1kHz_-23dBFS_60s.wav`),
   oder offizielles EBU-Tech-3341-Alignment-Signal von tech.ebu.ch,
   oder in REAPER Item → *Normalize* auf −23 LUFS.
2. **Abspielen** (Loop), Fader auf 0 dB.
3. **Messung mit echtem SPL-Meter** (Klasse 2 reicht):
   - Position = Hör-/Messposition (dort, wo das Ambisonic-Mic stand),
   - **C-Bewertung, Slow**, Leq-Anzeige,
   - **30–60 s mitteln** (bei Sinus reichen wenige Sekunden).
4. Monitor-Gain so einstellen, dass das Meter **83 dB SPL(C)** zeigt.
5. Im Plugin **SPL Cal = 106** einstellen. Der Wert wird jetzt mit dem
   REAPER-Projekt gespeichert (HOA Order + SPL Cal im Plugin-State).
6. **Kontrolle:** Kalibrierdatei durch das Plugin spielen → Integrated ≈
   −23 LUFS, L_Aeq ≈ 83 dB(A) (1-kHz-Sinus: A ≈ C ≈ K, ±0,5 dB ok).

## Variante B: direkt über Sinus messen

1 kHz-Sinus bei −20 dBFS abspielen, Meter liest X dB SPL(C) → **SPL Cal = X + 20**
(SMPTE RP 200: −20 dBFS = 83 dB SPL(C) → SPL Cal = 103).

## Muss das für jedes Item neu passieren?

**Nein.** Die Kalibrierung gehört zur *Wiedergabekette*
(DAW → Interface → Monitore → Raum), nicht zum einzelnen Item. Einmal pro
Session messen, dann gilt der Wert für alle Items — im Plugin wird er mit dem
Projekt gespeichert, in der Batch-Analyse als `--spl-offset` pro Lauf.

Pro-Item-Offsets brauchst du nur, wenn die **Aufnahmen** selbst unter-
schiedliche Verstärkung haben (z. B. Auto-Gain pro File). Das ist bei den
Torresin-Dateien nicht der Fall.

## Besonderheit Aufnahmen (z. B. Torresin-BFormat)

Für die absoluten Werte zählt die **Aufnahme-Kalibrierung**, nicht die
Monitor-Kalibrierung: Sind die WAVs kalibriert (0 dBFS = 1 Pa, z. B.
AMBEO VR + Recorder mit bekannter Empfindlichkeit), ist **SPL Cal = 94**
korrekt und L_Aeq/N10… sind echte Szenen-Werte in dB SPL / sone.
Ist die Aufnahme-Kalibrierung unbekannt: nur relativ vergleichen, oder gegen
einen bekannten Wert aus der Studie kalibrieren (z. B. berichtetes L_Aeq einer
Szene → Offset so verschieben, dass es passt). Faustregel: 1 dB Aufnahmefehler
= 1 dB Fehler in allen absoluten Werten.

## Schnell-Checkliste

- [ ] Kalibrier-Sinus (−23 dBFS bzw. −23 LUFS) einmal durch die Kette
- [ ] SPL-Meter: C, Slow, Leq, 30–60 s, an der Messposition
- [ ] Monitor so pegeln, dass 83 dB SPL(C) (EBU) angezeigt werden
- [ ] Plugin: SPL Cal = **106** (bzw. X + 20 bei Direktmessung)
- [ ] Kontrolle im Plugin: Integrated ≈ −23 LUFS, L_Aeq ≈ 83 dB(A)
- [ ] Aufnahmen kalibriert? Dann Cal = 94 lassen und echte SPL/sone ablesen
