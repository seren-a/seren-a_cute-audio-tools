#include "PluginProcessor.h"
#include "PluginEditor.h"

AmbisonicLoudnessMeterAudioProcessor::AmbisonicLoudnessMeterAudioProcessor()
    : AudioProcessor (BusesProperties()
                          .withInput ("Input", juce::AudioChannelSet::ambisonic (1), true)
                          .withOutput ("Output", juce::AudioChannelSet::ambisonic (1), true))
{
}

juce::AudioProcessorValueTreeState::ParameterLayout
AmbisonicLoudnessMeterAudioProcessor::createParameterLayout()
{
    using P = juce::AudioParameterFloat;
    juce::AudioProcessorValueTreeState::ParameterLayout layout;
    layout.add (std::make_unique<P> (juce::ParameterID { "splOffset", 1 },
                                     "Kalibrierung dBFS->dB SPL",
                                     -40.0f, 140.0f, 94.0f));
    layout.add (std::make_unique<juce::AudioParameterBool> (
        juce::ParameterID { "useAllChannels", 1 }, "Alle Kanaele (statt W)", false));
    layout.add (std::make_unique<juce::AudioParameterInt> (
        juce::ParameterID { "theme", 1 }, "Theme", 0, 11, 1));
    return layout;
}

bool AmbisonicLoudnessMeterAudioProcessor::isBusesLayoutSupported (const BusesLayout& layouts) const
{
    const auto& in = layouts.getMainInputChannelSet();
    const auto& out = layouts.getMainOutputChannelSet();
    if (in == out && in == juce::AudioChannelSet::ambisonic (0)) return true;
    if (in == out && in == juce::AudioChannelSet::ambisonic (1)) return true;
    if (in == out && in == juce::AudioChannelSet::ambisonic (2)) return true;
    if (in == out && in == juce::AudioChannelSet::ambisonic (3)) return true;
    if (in == out && in == juce::AudioChannelSet::stereo()) return true;
    if (in == out && in == juce::AudioChannelSet::mono()) return true;
    return false;
}

void AmbisonicLoudnessMeterAudioProcessor::prepareToPlay (double sampleRate, int samplesPerBlock)
{
    const int nchIn = getTotalNumInputChannels();
    core.prepare (sampleRate, nchIn, samplesPerBlock);
    core.reset();
}

void AmbisonicLoudnessMeterAudioProcessor::processBlock (juce::AudioBuffer<float>& buffer,
                                                         juce::MidiBuffer&)
{
    const int n = buffer.getNumSamples();
    const int nchIn = buffer.getNumChannels();

    splOffsetDb = apvts.getRawParameterValue ("splOffset")->load();
    useAllChannels = apvts.getRawParameterValue ("useAllChannels")->load() > 0.5f;
    themeIndex = (int) apvts.getRawParameterValue ("theme")->load();

    // Psychoakustik und ggf. BS.1770 beziehen sich auf W (Kanal 0, omni);
    // im Modus "Alle Kanaele" misst BS.1770 die Originalkanalfuehrungen.
    std::vector<const float*> ptrs ((size_t) nchIn);
    for (int c = 0; c < nchIn; ++c)
        ptrs[(size_t) c] = useAllChannels.load()
                               ? buffer.getReadPointer (c)
                               : buffer.getReadPointer (0);
    core.processBlock (ptrs.data(), n, 0, splOffsetDb.load());

    lastStats = core.getStats (splOffsetDb.load());
}

void AmbisonicLoudnessMeterAudioProcessor::resetIntegrated()
{
    core.resetIntegrated();
}

juce::AudioProcessorEditor* AmbisonicLoudnessMeterAudioProcessor::createEditor()
{
    return new AmbisonicLoudnessMeterAudioProcessorEditor (*this);
}

void AmbisonicLoudnessMeterAudioProcessor::getStateInformation (juce::MemoryBlock& destData)
{
    juce::MemoryOutputStream (destData, false).writeString (
        apvts.copyState().toXmlString());
}

void AmbisonicLoudnessMeterAudioProcessor::setStateInformation (const void* data, int sizeInBytes)
{
    const auto xml = juce::XmlDocument::parse (
        juce::String::createStringFromData (data, sizeInBytes));
    if (xml != nullptr)
        if (const auto newTree = juce::ValueTree::fromXml (*xml); newTree.isValid())
            apvts.replaceState (newTree);
}

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
{
    return new AmbisonicLoudnessMeterAudioProcessor();
}
