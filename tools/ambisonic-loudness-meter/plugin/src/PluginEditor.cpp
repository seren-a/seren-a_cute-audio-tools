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

    addAndMakeVisible(dirMeter);
    setSize(560, 380);
    startTimerHz(10);
    updateLabels();
}

AmbisonicLoudnessMeterEditor::~AmbisonicLoudnessMeterEditor() {
    stopTimer();
    if (auto* p = dynamic_cast<juce::AudioParameterChoice*>(proc.getOrderParameter()))
        p->removeListener(this);
}

void AmbisonicLoudnessMeterEditor::parameterValueChanged(int, float newValue) {
    int idx = juce::jlimit(0, 2, (int)std::lround(newValue));
    orderBox.setSelectedItemIndex(idx, juce::dontSendNotification);
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
    orderBox.setBounds(top.removeFromLeft(110));

    auto row = area.removeFromTop(22);
    integratedLbl.setBounds(row.removeFromLeft(150));
    integratedVal.setBounds(row.removeFromLeft(110));
    stLbl.setBounds(row.removeFromLeft(150));
    stVal.setBounds(row.removeFromLeft(110));

    row = area.removeFromTop(22);
    mLbl.setBounds(row.removeFromLeft(150));
    mVal.setBounds(row.removeFromLeft(110));
    lraLbl.setBounds(row.removeFromLeft(150));
    lraVal.setBounds(row.removeFromLeft(110));

    row = area.removeFromTop(22);
    tpLbl.setBounds(row.removeFromLeft(150));
    tpVal.setBounds(row.removeFromLeft(110));
    wOnlyLbl.setBounds(row.removeFromLeft(150));
    wOnlyVal.setBounds(row.removeFromLeft(110));

    dirMeter.setBounds(area);
}
