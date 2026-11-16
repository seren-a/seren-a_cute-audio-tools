#include "PluginEditor.h"

static juce::String fmtLufs(double v) {
    if (v <= -70.0 || !std::isfinite(v)) return "--";
    return juce::String(v, 1) + " LUFS";
}
static juce::String fmtDb(double v, const char* unit) {
    if (!std::isfinite(v)) return "--";
    return juce::String(v, 1) + " " + unit;
}
static juce::String fmtVal(double v, const char* unit, int digits = 2) {
    if (!std::isfinite(v)) return "--";
    return juce::String(v, digits) + " " + unit;
}

// ---------------------------------------------------------------------------

void DirectionMeter::paint(juce::Graphics& g) {
    auto bounds = getLocalBounds().toFloat().reduced(4.0f);
    g.fillAll(juce::Colour(0xff1e1e24));
    if (snap.nSpeakers <= 0) return;

    double lo = -60.0, hi = 0.0;
    for (int s = 0; s < snap.nSpeakers; ++s) {
        hi = std::max(hi, snap.perSpeakerLufs[(size_t)s]);
        lo = std::min(lo, snap.perSpeakerLufs[(size_t)s]);
    }
    if (hi - lo < 1.0) hi = lo + 1.0;
    // Fensterskala: mindestens 30 LU Spanne
    double bottom = std::min(lo, hi - 30.0);

    const float n = (float)snap.nSpeakers;
    const float bw = bounds.getWidth() / n;
    g.setFont(9.0f);
    for (int s = 0; s < snap.nSpeakers; ++s) {
        double v = snap.perSpeakerLufs[(size_t)s];
        float frac = juce::jlimit(0.0f, 1.0f, (float)((v - bottom) / (hi - bottom)));
        float h = frac * (bounds.getHeight() - 16.0f);
        float x = bounds.getX() + s * bw;
        float y = bounds.getY() + bounds.getHeight() - 16.0f - h;
        bool surround = std::abs(snap.speakerAz[(size_t)s]) >= 60.0 &&
                        std::abs(snap.speakerAz[(size_t)s]) <= 120.0 &&
                        std::abs(snap.speakerEl[(size_t)s]) <= 5.0;
        g.setColour(surround ? juce::Colour(0xffd080a0) : juce::Colour(0xff80c0ff));
        g.fillRect(x + 1.0f, y, bw - 2.0f, h);
        if (s % 2 == 0) {
            g.setColour(juce::Colours::grey);
            g.drawText(juce::String(snap.speakerAz[(size_t)s], 0) + "°",
                       x - bw, bounds.getY() + bounds.getHeight() - 14.0f, 2 * bw, 12.0f,
                       juce::Justification::centred, false);
        }
    }
    g.setColour(juce::Colours::grey);
    g.setFont(10.0f);
    g.drawText("Richtungs-Loudness (virtuelle Lautsprecher, LUFS)",
               bounds.getX(), bounds.getY(), bounds.getWidth(), 12.0f,
               juce::Justification::left, false);
}

// ---------------------------------------------------------------------------

static const char* kCellNames[] = {
    "Integrated", "Max Short-Term (3s)", "Max Momentary (400ms)", "LRA",
    "True Peak", "W-only (0. Ord.)",
    "L_Aeq", "L_C - L_A", "L_A10 - L_A90",
    "N10", "N50", "N90", "N10 - N90",
    "Sharpness S", "Roughness R", "Fluct. FS"
};
static_assert(std::size(kCellNames) == 16);

// Mouseover-Texte (Index wie kCellNames)
static const char* kCellTips[] = {
    "Integrated Loudness (ITU-R BS.1770-5): K-bewertete Gesamtlautheit, 400-ms-Bloecke mit 75% Ueberlappung, absolutes (-70 LUFS) und relatives (-10 LU) Gating. Einheit LUFS, bezogen auf digital full scale.",
    "Max Short-Term (3 s): lautestes 3-Sekunden-Fenster (BS.1770-5), ungefenstert.",
    "Max Momentary (400 ms): lautestes 400-ms-Fenster (BS.1770-5).",
    "Loudness Range LRA (EBU Tech 3342): Abstand zwischen 10%- und 95%-Perzentil der Short-Term-Loudness (3 s) in LU. Gross bei stark schwankenden Szenen (z. B. Sirene).",
    "True Peak (dBTP): Spitzenpegel nach 4x-Oversampling (BS.1770-5), genauer als der Sample-Peak.",
    "Loudness des W-Kanals allein (0. Ordnung, skaliert mit 2*sqrt(pi)) in LUFS - Direktschaetzung ohne Decoding auf virtuelle Lautsprecher.",
    "Gesamtlautheit L_Aeq in dB(A) (A-Bewertung nach IEC 61672). Absoluter dB-SPL-Wert haengt von der SPL-Kalibrierung ab (Slider oben); ohne bekannte Aufnahme-Kalibrierung nur relativ vergleichen.",
    "Spektrale Differenz L_C - L_A in dB: positiv = basslastig/dumpf, negativ = hoehenreich/scharf. Torresin et al. (2020), Spektrum-Praediktor.",
    "Variabilitaet L_A10 - L_A90 in dB: Differenz der statistischen Pegel (125-ms-Bloecke, A-bewertet). Torresin: Content korreliert positiv mit L_A10 - L_A90.",
    "Lautheits-Perzentil N10 in sone (ISO 532-1 Zwicker, zeitvariabel): Lautheit der lautesten 10% der Zeit. Torresin: Comfort korreliert negativ mit N10. Berechnet auf W ueber gleitendes 5-s-Fenster.",
    "Median-Lautheit N50 in sone (ISO 532-1 Zwicker, zeitvariabel), 50%-Perzentil.",
    "Lautheits-Perzentil N90 in sone: Grundlautheit, die 90% der Zeit ueberschritten wird.",
    "Lautheits-Variabilitaet N10 - N90 in sone: Perzentildifferenz der zeitvariablen Lautheit - wie stark die Szene 'atmet'.",
    "Sharpness S in acum (DIN 45692): spektrale Schaerfe, vor allem 2-5 kHz. Torresin: Familiarity korreliert negativ mit S.",
    "Roughness R in asper (Daniel-Weber, mosqito): Rauigkeit durch Amplitudenmodulation 20-300 Hz, Maximum bei ~70 Hz.",
    "Fluctuation Strength FS in vacil (Zwicker/Fastl): Schwankungsstaerke der Lautheit, Maximum bei ~4 Hz Modulation - 'Wummern' vs. 'Zischen'."
};
static_assert(std::size(kCellTips) == 16);

AmbisonicLoudnessMeterEditor::AmbisonicLoudnessMeterEditor(AmbisonicLoudnessMeterProcessor& p)
    : juce::AudioProcessorEditor(&p), proc(p) {
    auto* orderParam = dynamic_cast<juce::AudioParameterChoice*>(proc.getOrderParameter());

    orderLabel.setText("HOA Order:", juce::dontSendNotification);
    orderBox.addItemList(juce::StringArray{"1 (4ch)", "2 (9ch)", "3 (16ch)"}, 1);
    if (orderParam != nullptr) orderBox.setSelectedItemIndex(orderParam->getIndex(), juce::dontSendNotification);
    orderBox.onChange = [this, orderParam] {
        if (orderParam != nullptr) *orderParam = orderBox.getSelectedItemIndex();
    };
    addAndMakeVisible(orderLabel);
    addAndMakeVisible(orderBox);
    if (orderParam != nullptr) orderParam->addListener(this);

    auto* splParam = dynamic_cast<juce::AudioParameterFloat*>(proc.getSplOffsetParameter());
    splLabel.setText("SPL Cal [dB]:", juce::dontSendNotification);
    splLabel.setColour(juce::Label::textColourId, juce::Colours::lightgrey);
    splSlider.setRange(60.0, 120.0, 0.1);
    splSlider.setValue(splParam != nullptr ? (double)splParam->get() : 94.0, juce::dontSendNotification);
    splSlider.onValueChange = [splParam, this] {
        if (splParam != nullptr)
            splParam->setValueNotifyingHost(splParam->getNormalisableRange().convertTo0to1((float)splSlider.getValue()));
    };
    addAndMakeVisible(splLabel);
    addAndMakeVisible(splSlider);
    if (splParam != nullptr) splParam->addListener(this);

    orderBox.setTooltip("HOA-Ordnung des B-Formats (ACN/SN3D): 1 = 4 Kanaele, 2 = 9, 3 = 16. "
                        "Die ersten nCh Bus-Kanaele werden als B-Format interpretiert.");
    orderLabel.setTooltip(orderBox.getTooltip());
    splSlider.setTooltip("SPL-Kalibrierung: dB SPL, die 0 dBFS entsprechen. Default 94 dB = 1 Pa "
                         "(Mess-Recorder-Konvention). Nur wenn die Aufnahme kalibriert ist, sind die "
                         "dB-SPL-Werte absolut; sonst nur relativ vergleichen.");
    splLabel.setTooltip(splSlider.getTooltip());

    for (int i = 0; i < kNumCells; ++i) {
        cellName[(size_t)i].setText(kCellNames[i], juce::dontSendNotification);
        cellName[(size_t)i].setColour(juce::Label::textColourId, juce::Colours::lightgrey);
        cellName[(size_t)i].setFont(juce::Font(juce::FontOptions{10.0f}));
        cellVal[(size_t)i].setColour(juce::Label::textColourId, juce::Colour(0xff80ffc0));
        cellVal[(size_t)i].setFont(juce::Font(juce::FontOptions{14.0f}));
        cellName[(size_t)i].setTooltip(kCellTips[i]);
        cellVal[(size_t)i].setTooltip(kCellTips[i]);
        addAndMakeVisible(cellName[(size_t)i]);
        addAndMakeVisible(cellVal[(size_t)i]);
    }

    addAndMakeVisible(dirMeter);
    setSize(760, 560);
    startTimerHz(10);
    updateLabels();
}

AmbisonicLoudnessMeterEditor::~AmbisonicLoudnessMeterEditor() {
    stopTimer();
    if (auto* p = dynamic_cast<juce::AudioParameterChoice*>(proc.getOrderParameter()))
        p->removeListener(this);
    if (auto* p = dynamic_cast<juce::AudioParameterFloat*>(proc.getSplOffsetParameter()))
        p->removeListener(this);
}

void AmbisonicLoudnessMeterEditor::parameterValueChanged(int parameterIndex, float newValue) {
    if (parameterIndex == 0) {
        auto* p = dynamic_cast<juce::AudioParameterChoice*>(proc.getOrderParameter());
        if (p != nullptr) orderBox.setSelectedItemIndex(p->getIndex(), juce::dontSendNotification);
    } else if (parameterIndex == 1) {
        auto* p = dynamic_cast<juce::AudioParameterFloat*>(proc.getSplOffsetParameter());
        if (p != nullptr)
            splSlider.setValue((double)p->get(), juce::dontSendNotification);
    }
    (void)newValue;
}

void AmbisonicLoudnessMeterEditor::parameterGestureChanged(int, bool) {}

void AmbisonicLoudnessMeterEditor::updateLabels() {
    auto s = proc.snapshot();
    cellVal[0].setText(fmtLufs(s.integratedLufs), juce::dontSendNotification);
    cellVal[1].setText(fmtLufs(s.maxShortTermLufs), juce::dontSendNotification);
    cellVal[2].setText(fmtLufs(s.maxMomentaryLufs), juce::dontSendNotification);
    cellVal[3].setText(std::isfinite(s.lra) ? juce::String(s.lra, 1) + " LU" : "--",
                       juce::dontSendNotification);
    cellVal[4].setText(fmtDb(s.truePeakDbtp, "dBTP"), juce::dontSendNotification);
    cellVal[5].setText(fmtLufs(s.wOnlyLufs), juce::dontSendNotification);
    cellVal[6].setText(fmtDb(s.lAeq, "dB(A)"), juce::dontSendNotification);
    cellVal[7].setText(std::isfinite(s.lCeq) && std::isfinite(s.lAeq)
                           ? juce::String(s.lCeq - s.lAeq, 1) + " dB" : "--",
                       juce::dontSendNotification);
    cellVal[8].setText(std::isfinite(s.lA10) && std::isfinite(s.lA90)
                           ? juce::String(s.lA10 - s.lA90, 1) + " dB" : "--",
                       juce::dontSendNotification);
    cellVal[9].setText(fmtVal(s.n10, "sone"), juce::dontSendNotification);
    cellVal[10].setText(fmtVal(s.n50, "sone"), juce::dontSendNotification);
    cellVal[11].setText(fmtVal(s.n90, "sone"), juce::dontSendNotification);
    cellVal[12].setText(fmtVal(s.n10 - s.n90, "sone"), juce::dontSendNotification);
    cellVal[13].setText(fmtVal(s.sharpnessAcum, "acum"), juce::dontSendNotification);
    cellVal[14].setText(fmtVal(s.roughnessAsper, "asper"), juce::dontSendNotification);
    cellVal[15].setText(fmtVal(s.fluctStrengthVacil, "vacil"), juce::dontSendNotification);
    dirMeter.setSnapshot(s);
}

void AmbisonicLoudnessMeterEditor::timerCallback() { updateLabels(); }

void AmbisonicLoudnessMeterEditor::paint(juce::Graphics& g) {
    g.fillAll(juce::Colour(0xff14141a));
    g.setColour(juce::Colours::white);
    g.setFont(juce::Font(juce::FontOptions{16.0f, juce::Font::bold}));
    g.drawText("Ambisonic Loudness Meter (BS.1770-5 / EBU R 128 + Torresin 2020)",
               8, 6, getWidth() - 16, 20, juce::Justification::left, false);
}

void AmbisonicLoudnessMeterEditor::resized() {
    auto area = getLocalBounds().reduced(8);
    area.removeFromTop(26);  // Titel
    auto top = area.removeFromTop(30);
    orderLabel.setBounds(top.removeFromLeft(70));
    orderBox.setBounds(top.removeFromLeft(100));
    splLabel.setBounds(top.removeFromLeft(90));
    splSlider.setBounds(top.removeFromLeft(160));

    // 4x4-Raster, jede Metrik eigene Zelle (Name klein grau, Wert gross gruen)
    constexpr int cols = 4;
    constexpr int rows = (kNumCells + cols - 1) / cols;
    constexpr float cellH = 46.0f;
    auto grid = area.removeFromTop(cellH * rows);
    const float cw = grid.getWidth() / cols;
    for (int i = 0; i < kNumCells; ++i) {
        juce::Rectangle<float> cell(grid.getX() + (i % cols) * cw,
                                    grid.getY() + (i / cols) * cellH, cw, cellH);
        cell.reduce(3.0f, 2.0f);
        cellName[(size_t)i].setBounds(cell.removeFromTop(14.0f).toNearestInt());
        cellVal[(size_t)i].setBounds(cell.toNearestInt());
    }

    dirMeter.setBounds(area);
}
