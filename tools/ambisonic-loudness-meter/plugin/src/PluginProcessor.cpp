#include "PluginProcessor.h"
#include "PluginEditor.h"

#include <cstring>

AmbisonicLoudnessMeterProcessor::AmbisonicLoudnessMeterProcessor()
    : juce::AudioProcessor(
          BusesProperties()
              .withInput("Input", juce::AudioChannelSet::discreteChannels(16), true)
              .withOutput("Output", juce::AudioChannelSet::discreteChannels(16), true)) {
    auto* p = new juce::AudioParameterChoice(
        juce::ParameterID{"order", 1}, "HOA Order",
        juce::StringArray{"1 (4ch)", "2 (9ch)", "3 (16ch)"}, 0);
    orderParam = p;
    addParameter(p);
    p->addListener(this);
}

AmbisonicLoudnessMeterProcessor::~AmbisonicLoudnessMeterProcessor() {
    if (orderParam != nullptr) orderParam->removeListener(this);
}

bool AmbisonicLoudnessMeterProcessor::isBusesLayoutSupported(
    const BusesLayout& layouts) const {
    auto mainIn = layouts.getMainInputChannelSet();
    auto mainOut = layouts.getMainOutputChannelSet();
    if (mainIn.isDisabled() || mainOut.isDisabled()) return false;
    // diskrete Kanaele, bis zu 16 ((3+1)^2)
    return mainIn == mainOut && mainIn.isDiscreteLayout() &&
           mainIn.size() >= 1 && mainIn.size() <= 16;
}

void AmbisonicLoudnessMeterProcessor::parameterValueChanged(int, float newValue) {
    int order = juce::jlimit(1, 3, (int)std::lround(newValue) + 1);
    pendingOrder.store(order);
}

void AmbisonicLoudnessMeterProcessor::parameterGestureChanged(int, bool) {}

void AmbisonicLoudnessMeterProcessor::applyOrder(int order) {
    const juce::SpinLock::ScopedLockType lock(meterLock);
    meter.prepare(sampleRate_, order);
    meter.reset();
    currentOrder.store(order);
}

void AmbisonicLoudnessMeterProcessor::prepareToPlay(double sampleRate, int samplesPerBlock) {
    sampleRate_ = sampleRate;
    blockSize_ = samplesPerBlock;
    int order = orderParam != nullptr ? orderParam->getIndex() + 1 : 1;
    applyOrder(order);
    int nCh = (order + 1) * (order + 1);
    channelData.assign((size_t)nCh, std::vector<double>((size_t)samplesPerBlock, 0.0));
}

void AmbisonicLoudnessMeterProcessor::releaseResources() {}

void AmbisonicLoudnessMeterProcessor::processBlock(juce::AudioBuffer<float>& buffer,
                                                   juce::MidiBuffer&) {
    int pending = pendingOrder.exchange(-1);
    if (pending > 0 && pending != currentOrder.load()) {
        applyOrder(pending);
        int nCh = (pending + 1) * (pending + 1);
        channelData.assign((size_t)nCh, std::vector<double>((size_t)blockSize_, 0.0));
    }

    const int nCh = (int)channelData.size();
    const int numSamples = buffer.getNumSamples();
    const int avail = juce::jmin(nCh, getTotalNumInputChannels());

    for (int c = 0; c < nCh; ++c) {
        auto& dst = channelData[(size_t)c];
        if (dst.size() < (size_t)numSamples) dst.resize((size_t)numSamples, 0.0);
        if (c < avail)
            for (int i = 0; i < numSamples; ++i)
                dst[(size_t)i] = buffer.getSample(c, i);
        else
            std::fill(dst.begin(), dst.begin() + numSamples, 0.0);
    }
    std::vector<const double*> ptrs((size_t)nCh);
    for (int c = 0; c < nCh; ++c) ptrs[(size_t)c] = channelData[(size_t)c].data();

    {
        const juce::SpinLock::ScopedLockType lock(meterLock);
        meter.process(ptrs.data(), (size_t)numSamples);
        auto r = meter.result();
        snap.integratedLufs = r.integratedLufs;
        snap.maxShortTermLufs = r.maxShortTermLufs;
        snap.maxMomentaryLufs = r.maxMomentaryLufs;
        snap.lra = r.lra;
        snap.truePeakDbtp = r.truePeakDbtp;
        snap.wOnlyLufs = r.wOnlyLufs;
        snap.order = r.order;
        snap.nSpeakers = (int)r.perSpeakerLufs.size();
        for (int s = 0; s < snap.nSpeakers && s < 24; ++s) {
            snap.perSpeakerLufs[(size_t)s] = r.perSpeakerLufs[(size_t)s];
            snap.speakerAz[(size_t)s] = r.layout[(size_t)s].first;
            snap.speakerEl[(size_t)s] = r.layout[(size_t)s].second;
        }
    }

    // Meter-Plugin: Ausgang = Eingang (Through)
    const int outCh = getTotalNumOutputChannels();
    for (int c = avail; c < outCh; ++c)
        buffer.clear(c, 0, numSamples);
}

MeterSnapshot AmbisonicLoudnessMeterProcessor::snapshot() const {
    const juce::SpinLock::ScopedLockType lock(meterLock);
    return snap;
}

void AmbisonicLoudnessMeterProcessor::getStateInformation(juce::MemoryBlock& destData) {
    int idx = orderParam != nullptr ? orderParam->getIndex() : 0;
    destData.append(&idx, sizeof(idx));
}

void AmbisonicLoudnessMeterProcessor::setStateInformation(const void* data, int sizeInBytes) {
    if (data != nullptr && sizeInBytes >= (int)sizeof(int) && orderParam != nullptr) {
        int idx = 0;
        std::memcpy(&idx, data, sizeof(idx));
        *orderParam = juce::jlimit(0, 2, idx);
    }
}

juce::AudioProcessorEditor* AmbisonicLoudnessMeterProcessor::createEditor() {
    return new AmbisonicLoudnessMeterEditor(*this);
}

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter() {
    return new AmbisonicLoudnessMeterProcessor();
}
