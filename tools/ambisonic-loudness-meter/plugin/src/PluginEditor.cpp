#include "PluginEditor.h"
#include <array>

// ------------------------------------------------------------- cutiepro
static const std::array<CutieTheme, 12> THEMES {{
    { "matrix", 0xff031007, 0xffb9f2c9, 0xffeafff0, 0xff7de08a, 0xff2a4a2f },
    { "pink",   0xff160a13, 0xffe5c9f2, 0xfff6e7fa, 0xffd286b7, 0xff3d2233 },
    { "aqua",   0xff041014, 0xffa9e6f5, 0xffe2f9ff, 0xff42d9c5, 0xff123a42 },
    { "mint",   0xff03110c, 0xffc2ecd0, 0xffeafff2, 0xff37cb8a, 0xff123526 },
    { "sage",   0xff0d0f08, 0xffe3ebc3, 0xfff6f9e3, 0xffbec975, 0xff2e3320 },
    { "peach",  0xff150d06, 0xffffd9a8, 0xfffff0da, 0xfff58669, 0xff362414 },
    { "rose",   0xff140609, 0xfff7c9d0, 0xffffeef1, 0xfff56e7f, 0xff33191d },
    { "mix",    0xff0b0a0e, 0xffe7e2dc, 0xffffffff, 0xffc3a6cb, 0xff262330 },
    { "rosa",     0xfff9dce8, 0xffa04a72, 0xffc24b82, 0xffc77fa8, 0xffd8b3c8, true },
    { "lilac",    0xffece2f7, 0xff6f4fa3, 0xff5c349b, 0xff9a7fc0, 0xffcbb8e0, true },
    { "peachh",   0xfff9e8d9, 0xffb35435, 0xffcf6038, 0xffd97a52, 0xffe8c4ae, true },
    { "pistazie", 0xffe7f2e4, 0xff3f7a5e, 0xff2c6b4e, 0xff7da88f, 0xffb9d4c0, true },
}};

static const CutieTheme& currentTheme (int idx)
{
    return THEMES[(size_t) juce::jlimit (0, (int) THEMES.size() - 1, idx)];
}

// ----------------------------------------------------------- MeterBar
class MeterBar : public juce::Component
{
public:
    void setLevel (double lufs, double maxLufs)
    {
        level = lufs;
        maxLevel = maxLufs;
        repaint();
    }

    void setColours (juce::Colour fillIn, juce::Colour maxIn, juce::Colour trackIn)
    {
        fill = fillIn;
        maxC = maxIn;
        track = trackIn;
        repaint();
    }

    void paint (juce::Graphics& g) override
    {
        auto r = getLocalBounds().toFloat().reduced (1.0f);
        g.setColour (track);
        g.fillRoundedRectangle (r, 6.0f);
        const double lo = -60.0, hi = 0.0;
        auto fracOf = [&] (double v)
        { return juce::jlimit (0.0, 1.0, (v - lo) / (hi - lo)); };
        auto bar = r;
        bar = bar.removeFromBottom ((float) (fracOf (level) * r.getHeight()));
        g.setColour (fill);
        g.fillRoundedRectangle (bar, 6.0f);
        if (maxLevel > lo)
        {
            auto mr = getLocalBounds().toFloat().reduced (1.0f);
            mr = mr.removeFromBottom ((float) (fracOf (maxLevel) * mr.getHeight()))
                  .removeFromTop (2.0f);
            g.setColour (maxC);
            g.fillRect (mr);
        }
    }

private:
    double level = -70.0, maxLevel = -70.0;
    juce::Colour fill { 0xff42d9c5 }, maxC { 0xfff56e7f }, track { 0xff2a2622 };
};

// ----------------------------------------------------------- Editor
AmbisonicLoudnessMeterAudioProcessorEditor::AmbisonicLoudnessMeterAudioProcessorEditor (
    AmbisonicLoudnessMeterAudioProcessor& p)
    : AudioProcessorEditor (&p), processor (p)
{
    mtBar = std::make_unique<MeterBar>();
    stBar = std::make_unique<MeterBar>();

    for (size_t i = 0; i < THEMES.size(); ++i)
        themeBox.addItem (THEMES[i].name, (int) i + 1);
    themeBox.setJustificationType (juce::Justification::centred);
    themeBox.addListener (this);
    addAndMakeVisible (themeBox);

    allChannelsButton.setClickingTogglesState (true);
    allChannelsButton.addListener (this);
    addAndMakeVisible (allChannelsButton);

    resetButton.addListener (this);
    addAndMakeVisible (resetButton);

    calLabel.setText ("Kalibrierung dBFS->dB SPL:", juce::dontSendNotification);
    calLabel.setJustificationType (juce::Justification::centredRight);
    addAndMakeVisible (calLabel);
    calSlider.setSliderStyle (juce::Slider::LinearHorizontal);
    calSlider.setTextBoxIsEditable (true);
    calSlider.setRange (juce::Range<double> (-40.0, 140.0), 1.0);
    addAndMakeVisible (calSlider);

    for (auto* l : { &lufsValue, &stValue, &mtValue, &tpValue, &lraValue,
                     &n10Value, &n50Value, &laVarValue, &sharpValue, &fsValue,
                     &roughValue, &lcaValue, &laeqValue, &lceqValue })
    {
        l->setJustificationType (juce::Justification::centredRight);
        addAndMakeVisible (*l);
    }

    addAndMakeVisible (*mtBar);
    addAndMakeVisible (*stBar);

    calAttachment = std::make_unique<juce::AudioProcessorValueTreeState::SliderAttachment> (
        processor.apvts, "splOffset", calSlider);
    allChAttachment = std::make_unique<juce::AudioProcessorValueTreeState::ButtonAttachment> (
        processor.apvts, "useAllChannels", allChannelsButton);
    themeAttachment = std::make_unique<juce::AudioProcessorValueTreeState::ComboBoxAttachment> (
        processor.apvts, "theme", themeBox);
    themeBox.onChange = [this] { applyTheme(); };
    applyTheme();
    startTimerHz (20);
    setSize (560, 620);
}

AmbisonicLoudnessMeterAudioProcessorEditor::~AmbisonicLoudnessMeterAudioProcessorEditor() = default;

void AmbisonicLoudnessMeterAudioProcessorEditor::applyTheme()
{
    const auto& th = currentTheme (themeBox.getSelectedItemIndex());
    mtBar->setColours (th.accent, th.flash, th.dim);
    stBar->setColours (th.readout, th.flash, th.dim);
    repaint();
}

void AmbisonicLoudnessMeterAudioProcessorEditor::timerCallback()
{
    const auto& s = processor.lastStats;
    auto fmt = [] (double v, const char* unit, int digits = 1)
    {
        if (v <= -200.0) return juce::String ("--");
        return juce::String (v, digits) + " " + unit;
    };
    lufsValue.setText (fmt (s.integratedLufs, "LUFS"), juce::dontSendNotification);
    stValue.setText (fmt (s.shortTermLufs, "LUFS"), juce::dontSendNotification);
    mtValue.setText (fmt (s.momentaryLufs, "LUFS"), juce::dontSendNotification);
    tpValue.setText (fmt (s.truePeakDbtp, "dBTP"), juce::dontSendNotification);
    lraValue.setText (fmt (s.lra, "LU"), juce::dontSendNotification);
    n10Value.setText (juce::String (s.n10, 2) + " sone", juce::dontSendNotification);
    n50Value.setText (juce::String (s.n50, 2) + " sone", juce::dontSendNotification);
    laVarValue.setText (fmt (s.lA10minus90, "dB"), juce::dontSendNotification);
    sharpValue.setText (juce::String (s.sharpness, 2) + " acum", juce::dontSendNotification);
    fsValue.setText (juce::String (s.fluctuationStrength, 2) + " vacil", juce::dontSendNotification);
    roughValue.setText (juce::String (s.roughness, 2) + " asper", juce::dontSendNotification);
    lcaValue.setText (fmt (s.lCminusA, "dB"), juce::dontSendNotification);
    laeqValue.setText (fmt (s.lAeq, "dB(A)"), juce::dontSendNotification);
    lceqValue.setText (fmt (s.lCeq, "dB(C)"), juce::dontSendNotification);
    mtBar->setLevel (s.momentaryLufs, s.maxMomentary);
    stBar->setLevel (s.shortTermLufs, s.maxShortTerm);

}

void AmbisonicLoudnessMeterAudioProcessorEditor::paint (juce::Graphics& g)
{
    const auto& th = currentTheme (themeBox.getSelectedItemIndex());
    g.fillAll (th.bg);

    const auto panel = juce::Colour (th.bg).withMultipliedBrightness (
        th.light ? 0.97f : 1.4f);

    auto area = getLocalBounds().toFloat().reduced (10.0f);
    auto head = area.removeFromTop (48.0f);
    g.setColour (panel);
    g.fillRoundedRectangle (head, 9.0f);
    g.setColour (th.readout);
    g.setFont (juce::Font (juce::FontOptions { 16.0f, juce::Font::bold }));
    g.drawText ("ambisonic loudness + soundscape meter",
                head.withTrimmedLeft (16.0f), juce::Justification::centredLeft));

    auto col = area;
    auto left = col.removeFromLeft (col.getWidth() * 0.55f);
    auto bsPanel = left.removeFromTop (210.0f);
    g.setColour (panel);
    g.fillRoundedRectangle (bsPanel, 9.0f);
    g.setColour (th.readout);
    g.setFont (juce::Font (juce::FontOptions { 16.0f, juce::Font::bold }));
    g.drawText ("ITU-R BS.1770-5 / EBU R 128",
                bsPanel.withTrimmedLeft (16.0f).withTrimmedTop (8.0f),
                juce::Justification::centredLeft));

    auto scPanel = left;
    g.setColour (panel);
    g.fillRoundedRectangle (scPanel, 9.0f);
    g.setColour (th.readout);
    g.setFont (juce::Font (juce::FontOptions { 16.0f, juce::Font::bold }));
    g.drawText ("Indoor Soundscape (Torresin 2020)",
                scPanel.withTrimmedLeft (16.0f).withTrimmedTop (8.0f),
                juce::Justification::centredLeft));

    auto mtPanel = col.removeFromTop (col.getHeight() / 2.0f);
    g.setColour (panel);
    g.fillRoundedRectangle (mtPanel, 9.0f);
    g.setColour (th.readout);
    g.setFont (juce::Font (juce::FontOptions { 12.0f }));
    g.drawText ("Momentary", mtPanel.withTrimmedLeft (16.0f).withTrimmedTop (8.0f),
                juce::Justification::centredLeft));

    auto stPanel = col;
    g.setColour (panel);
    g.fillRoundedRectangle (stPanel, 9.0f);
    g.setColour (th.readout);
    g.setFont (juce::Font (juce::FontOptions { 12.0f }));
    g.drawText ("Short-Term", stPanel.withTrimmedLeft (16.0f).withTrimmedTop (8.0f),
                juce::Justification::centredLeft));

    g.setColour (th.readout);
    g.setFont (juce::Font (juce::FontOptions { 12.5f }));
    for (auto& [rowRect, name] : rows)
        g.drawText (name, rowRect.withTrimmedRight (132.0f),
                    juce::Justification::centredLeft));
}

void AmbisonicLoudnessMeterAudioProcessorEditor::resized()
{
    auto r = getLocalBounds().reduced (10.0f);

    auto top = r.removeFromTop (48.0f).reduced (8.0f);
    resetButton.setBounds (top.removeFromRight (66.0f));
    themeBox.setBounds (top.removeFromLeft (104.0f));
    top.reduce (8.0f, 0);
    calLabel.setBounds (top.removeFromLeft (168.0f));
    calSlider.setBounds (top.removeFromLeft (110.0f));
    allChannelsButton.setBounds (top);

    auto col = r;
    auto left = col.removeFromLeft ((int) ((float) col.getWidth() * 0.55f));

    auto bs = left.removeFromTop (210.0f).reduced (14.0f, 8.0f);
    bs.removeFromTop (14.0f);
    auto place = [&] (juce::Label& value, const juce::String& name)
    {
        auto rowL = bs.removeFromTop (26.0f);
        rows.push_back ({ rowL, name });
        value.setBounds (rowL.removeFromRight (128.0f));
    };
    rows.clear();
    place (lufsValue, "Integrated");
    place (stValue, "Short-Term");
    place (mtValue, "Momentary");
    place (lraValue, "Loudness Range");
    place (tpValue, "True Peak");

    auto sc = left.reduced (14.0f, 8.0f);
    sc.removeFromTop (14.0f);
    place (laeqValue, "L_Aeq");
    place (lceqValue, "L_Ceq");
    place (lcaValue, "L_C - L_A");
    place (laVarValue, "L_A10 - L_A90");
    place (n10Value, "N10 (sone)");
    place (n50Value, "N50 (sone)");
    place (sharpValue, "Sharpness (acum)");
    place (fsValue, "Fluctuation (vacil)");
    place (roughValue, "Roughness (asper)");

    auto mt = col.removeFromTop (col.getHeight() / 2).reduced (16.0f, 34.0f);
    mtBar->setBounds (mt.removeFromRight (34.0f));
    auto st = col.reduced (16.0f, 34.0f);
    stBar->setBounds (st.removeFromRight (34.0f));
}

void AmbisonicLoudnessMeterAudioProcessorEditor::buttonClicked (juce::Button* b)
{
    if (b == &resetButton)
        processor.resetIntegrated();
}

void AmbisonicLoudnessMeterAudioProcessorEditor::comboBoxChanged (juce::ComboBox*) {}
