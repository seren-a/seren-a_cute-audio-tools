#include "PluginProcessor.h"
#include "PluginEditor.h"

#include <cstring>

namespace {
class PsyWorker : public juce::Thread {
public:
    explicit PsyWorker(AmbisonicLoudnessMeterProcessor& p) : juce::Thread("psy-worker"), proc(p) {}
    void run() override {
        while (!threadShouldExit()) {
            wait(500);
            if (threadShouldExit()) break;
            proc.computePsychoNow();
        }
    }
private:
    AmbisonicLoudnessMeterProcessor& proc;
};
}  // namespace

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
    auto* s = new juce::AudioParameterFloat(
        juce::ParameterID{"splOffset", 1}, "SPL Calibration (dBFS->dB SPL)",
        juce::NormalisableRange<float>(60.0f, 120.0f, 0.1f), 94.0f);
    splOffsetParam = s;
    addParameter(s);
    s->addListener(this);

    // 16 read-only Output-Parameter (Namen = CSV-Spalten, siehe scripts/)
    struct MPDef { const char* name; const char* unit; double lo, hi; };
    static constexpr MPDef kMP[16] = {
        {"integrated_lufs", "LUFS", -120.0, 0.0},
        {"max_shortterm_lufs", "LUFS", -120.0, 0.0},
        {"max_momentary_lufs", "LUFS", -120.0, 0.0},
        {"lra_lu", "LU", 0.0, 60.0},
        {"true_peak_dbtp", "dBTP", -60.0, 12.0},
        {"w_only_lufs", "LUFS", -120.0, 0.0},
        {"l_aeq_db", "dB(A)", 20.0, 140.0},
        {"l_c_minus_l_a_db", "dB", -40.0, 40.0},
        {"l_a10_minus_l_a90_db", "dB", 0.0, 60.0},
        {"n10_sone", "sone", 0.0, 120.0},
        {"n50_sone", "sone", 0.0, 120.0},
        {"n90_sone", "sone", 0.0, 120.0},
        {"n10_minus_n90_sone", "sone", 0.0, 120.0},
        {"sharpness_acum", "acum", 0.0, 6.0},
        {"roughness_asper", "asper", 0.0, 3.0},
        {"fluctuation_strength_vacil", "vacil", 0.0, 1.0},
    };
    for (int i = 0; i < 16; ++i) {
        meterParams[i] = new MeterOutputParameter(kMP[i].name, kMP[i].unit, kMP[i].lo, kMP[i].hi);
        addParameter(meterParams[i]);
    }

    psyWorker = new PsyWorker(*this);
    psyWorker->startThread();
}

void AmbisonicLoudnessMeterProcessor::pushMeterParams(const MeterSnapshot& s) {
    meterParams[0]->setFromDouble(s.integratedLufs);
    meterParams[1]->setFromDouble(s.maxShortTermLufs);
    meterParams[2]->setFromDouble(s.maxMomentaryLufs);
    meterParams[3]->setFromDouble(s.lra);
    meterParams[4]->setFromDouble(s.truePeakDbtp);
    meterParams[5]->setFromDouble(s.wOnlyLufs);
    meterParams[6]->setFromDouble(s.lAeq);
    meterParams[7]->setFromDouble(std::isfinite(s.lCeq) && std::isfinite(s.lAeq) ? s.lCeq - s.lAeq : -40.0);
    meterParams[8]->setFromDouble(std::isfinite(s.lA10) && std::isfinite(s.lA90) ? s.lA10 - s.lA90 : 0.0);
    meterParams[9]->setFromDouble(s.n10);
    meterParams[10]->setFromDouble(s.n50);
    meterParams[11]->setFromDouble(s.n90);
    meterParams[12]->setFromDouble(s.n10 - s.n90);
    meterParams[13]->setFromDouble(s.sharpnessAcum);
    meterParams[14]->setFromDouble(s.roughnessAsper);
    meterParams[15]->setFromDouble(s.fluctStrengthVacil);

    // Host benachrichtigen (VST3 performEdit), aber gedrosselt (~alle 10 Bloecke)
    if ((++notifyCounter_ % 10) == 0)
        for (auto* p : meterParams)
            if (p != nullptr) p->notifyIfDirty();
}

AmbisonicLoudnessMeterProcessor::~AmbisonicLoudnessMeterProcessor() {
    if (psyWorker != nullptr) {
        psyWorker->stopThread(2000);
        delete psyWorker;
    }
    if (orderParam != nullptr) orderParam->removeListener(this);
    if (splOffsetParam != nullptr) splOffsetParam->removeListener(this);
}

bool AmbisonicLoudnessMeterProcessor::isBusesLayoutSupported(
    const BusesLayout& layouts) const {
    auto mainIn = layouts.getMainInputChannelSet();
    auto mainOut = layouts.getMainOutputChannelSet();
    if (mainIn.isDisabled() || mainOut.isDisabled()) return false;
    // bis zu 16 Kanaele ((3+1)^2); Layout egal (diskret ODER 4.0/5.1/... --
    // die HOA-Kanaele liegen auf den ersten nCh Bus-Kanaelen)
    return mainIn.size() == mainOut.size() &&
           mainIn.size() >= 1 && mainIn.size() <= 16;
}

void AmbisonicLoudnessMeterProcessor::parameterValueChanged(int parameterIndex, float) {
    if (parameterIndex == 0 && orderParam != nullptr)
        pendingOrder.store(orderParam->getIndex() + 1);
}

void AmbisonicLoudnessMeterProcessor::computePsychoNow(bool force) {
    const juce::SpinLock::ScopedLockType lock(meterLock);
    meter.setSplOffsetDb(splOffsetParam != nullptr ? splOffsetParam->get() : 94.0f);
    // nur neu rechnen, wenn seit der letzten Berechnung mind. 1 s neues Audio kam
    const size_t bufSize = meter.psyBufferSize();
    if (meter.psyDirty() && (force || bufSize >= lastPsyLen_ + (size_t)sampleRate_)) {
        lastPsyLen_ = bufSize;
        meter.computePsycho();
        auto r = meter.result();
        snap.lAeq = r.lAeq;
        snap.lCeq = r.lCeq;
        snap.lA10 = r.lA10;
        snap.lA90 = r.lA90;
        snap.n10 = r.n10;
        snap.n50 = r.n50;
        snap.n90 = r.n90;
        snap.sharpnessAcum = r.sharpnessAcum;
        snap.roughnessAsper = r.roughnessAsper;
        snap.fluctStrengthVacil = r.fluctStrengthVacil;
        pushMeterParams(snap);
    }
}

void AmbisonicLoudnessMeterProcessor::parameterGestureChanged(int, bool) {}

void AmbisonicLoudnessMeterProcessor::applyOrder(int order) {
    const juce::SpinLock::ScopedLockType lock(meterLock);
    meter.setSplOffsetDb(splOffsetParam != nullptr ? splOffsetParam->get() : 94.0f);
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
    const int avail = std::min({nCh, getTotalNumInputChannels(), buffer.getNumChannels()});

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
        snap.lAeq = r.lAeq;
        snap.lCeq = r.lCeq;
        snap.lA10 = r.lA10;
        snap.lA90 = r.lA90;
        snap.n10 = r.n10;
        snap.n50 = r.n50;
        snap.n90 = r.n90;
        snap.sharpnessAcum = r.sharpnessAcum;
        snap.roughnessAsper = r.roughnessAsper;
        snap.fluctStrengthVacil = r.fluctStrengthVacil;
        snap.order = r.order;
        snap.nSpeakers = (int)r.perSpeakerLufs.size();
        for (int s = 0; s < snap.nSpeakers && s < 24; ++s) {
            snap.perSpeakerLufs[(size_t)s] = r.perSpeakerLufs[(size_t)s];
            snap.speakerAz[(size_t)s] = r.layout[(size_t)s].first;
            snap.speakerEl[(size_t)s] = r.layout[(size_t)s].second;
        }
        pushMeterParams(snap);
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
    float spl = splOffsetParam != nullptr ? splOffsetParam->get() : 94.0f;
    destData.append(&idx, sizeof(idx));
    destData.append(&spl, sizeof(spl));
}

void AmbisonicLoudnessMeterProcessor::setStateInformation(const void* data, int sizeInBytes) {
    if (data == nullptr || sizeInBytes < (int)sizeof(int)) return;
    int idx = 0;
    std::memcpy(&idx, data, sizeof(idx));
    if (orderParam != nullptr)
        *orderParam = juce::jlimit(0, 2, idx);
    if (sizeInBytes >= (int)(sizeof(int) + sizeof(float)) && splOffsetParam != nullptr) {
        float spl = 94.0f;
        std::memcpy(&spl, (const char*)data + sizeof(int), sizeof(spl));
        *splOffsetParam = juce::jlimit(60.0f, 120.0f, spl);
    }
}

juce::AudioProcessorEditor* AmbisonicLoudnessMeterProcessor::createEditor() {
    return new AmbisonicLoudnessMeterEditor(*this);
}

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter() {
    return new AmbisonicLoudnessMeterProcessor();
}
