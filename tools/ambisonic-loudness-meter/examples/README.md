# Torresin-Ergebnisse (Beispiel-Messung)

`torresin_results.csv` enthält die Messungen der 7 BFormat-Ambix-Dateien
(First Order, ACN/SN3D, 48 kHz, 60 s, PCM_24) aus der Torresin-Arbeit zu
Indoor-Soundscapes: Fan, Garden, Light_traffic, Music, Pedestrian_area,
Siren, TV.

Gemessen mit dem C++-DSP-Kern des Plugins (`plugin/src/dsp/`, identisch zum
Python-Kern `src/ambisonic_loudness.py`).

## Spalten

- BS.1770: `integrated_lufs`, `max_shortterm_lufs`, `max_momentary_lufs`,
  `lra_lu`, `true_peak_dbtp`, `w_only_lufs`
- dB-SPL (angenommene Kalibrierung 94 dB, siehe `spl_calibration_db`):
  `l_aeq_db_spl`, `l_ceq_db_spl`, `l_c_minus_l_a_db`, `l_a10_db`, `l_a90_db`,
  `l_a10_minus_l_a90_db`
- Psychoakustik (mosqito-Port): `n10_sone`, `n50_sone`, `n90_sone`,
  `n10_minus_n90_sone`, `sharpness_acum`, `roughness_asper`,
  `fluctuation_strength_vacil`
- Richtung der max-rE-Decodierung: `dir_max_az_deg`, `dir_max_el_deg`,
  `dir_max_lufs`

## Hinweise

- Die absoluten dB-SPL-Werte setzen eine 94-dB-Kalibrierung voraus; die
  wahre Kalibrierung der Aufnahmen ist unbekannt. Relative Vergleiche
  zwischen den Szenen sind aussagekräftig.
- `dir_max_az_deg` landet bei allen Dateien bei 60° — Artefakt der
  max-rE-Decodierung mit G = 1.41 (tritt im Python-Kern identisch auf).
