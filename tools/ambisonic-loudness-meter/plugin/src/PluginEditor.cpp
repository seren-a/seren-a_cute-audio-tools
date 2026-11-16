#include "PluginEditor.h"

static juce::String fmtLufs(double v) {
    if (v <= -70.0 || !std::isfinite(v)) return "--";
    return juce::String(v, 1) + " LUFS";
}
static juce::String fmtDb(double v, const char* unit) {
    if (!std::isfinite(v)) return "--";
    return juce::String(v, 1) + " " + unit;
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

    auto makeRow = [this](juce::Label& name, juce::Label& val, const juce::String& text) {
        name.setText(text, juce::dontSendNotification);
        name.setColour(juce::Label::textColourId, juce::Colours::lightgrey);
        val.setColour(juce::Label::textColourId, juce::Colour(0xff80ffc0));
        val.setFont(juce::Font(juce::FontOptions{14.0f}));
        addAndMakeVisible(name);
        addAndMakeVisible(val);
    };
    makeRow(integratedLbl, integratedVal, "Integrated:");
    makeRow(stLbl, stVal, "Max Short-Term (3s):");
    makeRow(mLbl, mVal, "Max Momentary (400ms):");
    makeRow(lraLbl, lraVal, "LRA:");
    makeRow(tpLbl, tpVal, "True Peak:");
    makeRow(wOnlyLbl, wOnlyVal, "W-only (0. Ord.):");
    makeRow(laeqLbl, laeqVal, "L_Aeq (W):");
    makeRow(lcaLbl, lcaVal, "L_C - L_A:");
    makeRow(laVarLbl, laVarVal, "L_A10 - L_A90:");
    makeRow(nLbl, nVal, "N10 / N90 (W):");
    makeRow(sharpLbl, sharpVal, "Sharpness S:");
    makeRow(roughLbl, roughVal, "Roughness R:");
    makeRow(fsLbl, fsVal, "Fluct. FS:");

    addAndMakeVisible(dirMeter);
    setSize(640, 460);
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
    integratedVal.setText(fmtLufs(s.integratedLufs), juce::dontSendNotification);
    stVal.setText(fmtLufs(s.maxShortTermLufs), juce::dontSendNotification);
    mVal.setText(fmtLufs(s.maxMomentaryLufs), juce::dontSendNotification);
    lraVal.setText(std::isfinite(s.lra) ? juce::String(s.lra, 1) + " LU" : "--",
                   juce::dontSendNotification);
    tpVal.setText(fmtDb(s.truePeakDbtp, "dBTP"), juce::dontSendNotification);
    wOnlyVal.setText(fmtLufs(s.wOnlyLufs), juce::dontSendNotification);
    laeqVal.setText(fmtDb(s.lAeq, "dB(A)"), juce::dontSendNotification);
    lcaVal.setText(std::isfinite(s.lCeq) && std::isfinite(s.lAeq)
                       ? juce::String(s.lCeq - s.lAeq, 1) + " dB" : "--",
                   juce::dontSendNotification);
    laVarVal.setText(std::isfinite(s.lA10) && std::isfinite(s.lA90)
                         ? juce::String(s.lA10 - s.lA90, 1) + " dB" : "--",
                     juce::dontSendNotification);
    nVal.setText(juce::String(s.n10, 2) + " / " + juce::String(s.n90, 2) + " sone",
                 juce::dontSendNotification);
    sharpVal.setText(juce::String(s.sharpnessAcum, 2) + " acum", juce::dontSendNotification);
    roughVal.setText(juce::String(s.roughnessAsper, 2) + " asper", juce::dontSendNotification);
    fsVal.setText(juce::String(s.fluctStrengthVacil, 2) + " vacil", juce::dontSendNotification);
    dirMeter.setSnapshot(s);
}

void AmbisonicLoudnessMeterEditor::timerCallback() { updateLabels(); }

void AmbisonicLoudnessMeterEditor::paint(juce::Graphics& g) {
    g.fillAll(juce::Colour(0xff14141a));
    g.setColour(juce::Colours::white);
    g.setFont(juce::Font(juce::FontOptions{16.0f, juce::Font::bold}));
    g.drawText("Ambisonic Loudness Meter (BS.1770-5 / EBU R 128)",
               8, 6, getWidth() - 16, 20, juce::Justification::left, false);
}

void AmbisonicLoudnessMeterEditor::resized() {
    auto area = getLocalBounds().reduced(8);
    area.removeFromTop(26);  // Titel
    auto top = area.removeFromTop(30);
    orderLabel.setBounds(top.removeFromLeft(70));
    orderBox.setBounds(top.removeFromLeft(100));
    splLabel.setBounds(top.removeFromLeft(90));
    splSlider.setBounds(top.removeFromLeft(120));

    auto row = area.removeFromTop(22);
    integratedLbl.setBounds(row.removeFromLeft(150));
    integratedVal.setBounds(row.removeFromLeft(100));
    stLbl.setBounds(row.removeFromLeft(150));
    stVal.setBounds(row.removeFromLeft(100));

    row = area.removeFromTop(22);
    mLbl.setBounds(row.removeFromLeft(150));
    mVal.setBounds(row.removeFromLeft(100));
    lraLbl.setBounds(row.removeFromLeft(150));
    lraVal.setBounds(row.removeFromLeft(100));

    row = area.removeFromTop(22);
    tpLbl.setBounds(row.removeFromLeft(150));
    tpVal.setBounds(row.removeFromLeft(100));
    wOnlyLbl.setBounds(row.removeFromLeft(150));
    wOnlyVal.setBounds(row.removeFromLeft(100));

    row = area.removeFromTop(22);
    laeqLbl.setBounds(row.removeFromLeft(150));
    laeqVal.setBounds(row.removeFromLeft(100));
    lcaLbl.setBounds(row.removeFromLeft(150));
    lcaVal.setBounds(row.removeFromLeft(100));

    row = area.removeFromTop(22);
    laVarLbl.setBounds(row.removeFromLeft(150));
    laVarVal.setBounds(row.removeFromLeft(100));
    nLbl.setBounds(row.removeFromLeft(150));
    nVal.setBounds(row.removeFromLeft(100));

    row = area.removeFromTop(22);
    sharpLbl.setBounds(row.removeFromLeft(150));
    sharpVal.setBounds(row.removeFromLeft(100));
    roughLbl.setBounds(row.removeFromLeft(150));
    roughVal.setBounds(row.removeFromLeft(100));

    row = area.removeFromTop(22);
    fsLbl.setBounds(row.removeFromLeft(150));
    fsVal.setBounds(row.removeFromLeft(100));

    dirMeter.setBounds(area);
}
