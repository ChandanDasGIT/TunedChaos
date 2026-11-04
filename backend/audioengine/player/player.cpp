#include "backend/audioengine/player/player.h"

#include "backend/loudness/loudnessstore/loudnessstore.h"
#include "backend/youtube/streamresolver/streamresolver.h"

#include <algorithm>
#include <cmath>
#include <thread>

namespace {

using namespace std::chrono_literals;

constexpr size_t Channels = Decoder::OutputChannels;
constexpr size_t RingSamples = size_t(1) << 17; // ~1.4 s of stereo at 48 kHz
constexpr auto WakeInterval = 10ms;
constexpr auto PositionInterval = 50ms;
constexpr uint64_t DipFrames = Decoder::OutputRate / 5;       // skip: 0.2 s fade-out ...
constexpr uint64_t SkipRampFrames = Decoder::OutputRate * 3 / 10; // ... and 0.3 s fade-in
constexpr float HalfPi = 1.57079632679f;

// Smooth fade curves (quarter sine / cosine): the music stays clearly audible
// for most of a fade instead of dropping away early.
float fadeOut(float t) { return std::cos(std::min(t, 1.0f) * HalfPi); }
float fadeIn(float t) { return std::sin(std::min(t, 1.0f) * HalfPi); }

} // namespace

Player::Player(std::string appName, Callbacks callbacks, StreamResolver *resolver)
    : m_appName(std::move(appName))
    , m_callbacks(std::move(callbacks))
    , m_resolver(resolver)
    , m_ring(RingSamples)
    , m_thread(&Player::run, this)
{
}

Player::~Player()
{
    post({CommandType::Quit, {}, 0});
    m_thread.join();
}

void Player::load(const std::string &path, int64_t startMs, bool paused)
{
    post({CommandType::Load, path, startMs, paused});
}
void Player::setNext(const std::string &path, int fadeMs) { post({CommandType::SetNext, path, fadeMs}); }
void Player::setSkipFade(bool enabled) { m_skipFade.store(enabled, std::memory_order_relaxed); }
void Player::unload() { post({CommandType::Unload, {}, 0}); }
void Player::setOutputDevice(const std::string &deviceId) { post({CommandType::SetDevice, deviceId, 0}); }
void Player::play() { post({CommandType::Play, {}, 0}); }
void Player::pause() { post({CommandType::Pause, {}, 0}); }
void Player::stop() { post({CommandType::Stop, {}, 0}); }
int64_t Player::bufferMs()
{
    return int64_t(RingSamples / Channels) * 1000 / Decoder::OutputRate;
}

void Player::seek(int64_t positionMs) { post({CommandType::Seek, {}, positionMs}); }
void Player::refreshReplayGain(const std::string &path) { post({CommandType::RefreshGain, path, 0}); }

void Player::setEqualizer(const Equalizer::Gains &gainsDb, bool enabled)
{
    m_equalizer.setGains(gainsDb, enabled);
}

void Player::setReplayGainMode(int mode)
{
    m_replayGainMode.store(std::clamp(mode, 0, 2), std::memory_order_relaxed);
}

void Player::setFadeLevel(float level)
{
    m_fadeLevel.store(std::clamp(level, 0.0f, 1.0f), std::memory_order_relaxed);
}

void Player::setVolume(float volume)
{
    const float v = std::clamp(volume, 0.0f, 1.0f);
    m_gain.store(v * v * v, std::memory_order_relaxed); // cubic: feels linear to the ear
}

void Player::post(Command command)
{
    {
        std::lock_guard lock(m_mutex);
        m_commands.push_back(std::move(command));
    }
    m_wake.notify_one();
}

void Player::run()
{
    if (!m_output.open(m_appName, Decoder::OutputRate, Decoder::OutputChannels,
                       [this](float *dst, size_t frames) { return pull(dst, frames); }))
        reportError(m_output.errorString());

    std::unique_lock lock(m_mutex);
    for (;;) {
        m_wake.wait_for(lock, WakeInterval, [this] { return !m_commands.empty(); });
        std::deque<Command> commands;
        commands.swap(m_commands);
        lock.unlock();

        for (const Command &command : commands) {
            if (command.type == CommandType::Quit) {
                m_output.close();
                m_decoder->close();
                return;
            }
            handle(command);
        }

        fillBuffer();
        applyTransitions();
        checkFinished();
        reportPosition(false);

        lock.lock();
    }
}

void Player::handle(const Command &command)
{
    switch (command.type) {
    case CommandType::Load: {
        const bool fade = m_skipFade.load(std::memory_order_relaxed) && m_state == State::Playing;
        if (fade)
            dipOut();
        m_output.setActive(false);
        m_transitions.clear();
        m_nextPath.clear();
        m_rampFrames = m_rampPos = 0;
        m_currentPath = command.path;
        if (!openPath(command.path)) {
            m_dipMuted.store(false, std::memory_order_relaxed);
            setDuration(0);
            resetTimeline(0);
            setState(State::Stopped);
            reportPosition(true);
            return;
        }
        setDuration(m_decoder->durationMs());
        // Resuming: start where the listener left off (from the start if that fails).
        int64_t start = std::max<int64_t>(command.ms, 0);
        if (m_durationMs > 0)
            start = std::min(start, m_durationMs);
        if (start > 0 && m_decoder->seek(start))
            m_decodedFrames = uint64_t(start) * Decoder::OutputRate / 1000;
        else
            start = 0;
        resetTimeline(start);
        if (fade && !command.paused) {
            m_rampFrames = SkipRampFrames;
            m_rampPos = 0;
        }
        fillBuffer(); // prefill so playback starts without an underrun
        m_dipMuted.store(false, std::memory_order_relaxed);
        if (command.paused) {
            setState(State::Paused); // the output starts on Play
        } else {
            m_output.setActive(true);
            setState(State::Playing);
        }
        reportPosition(true);
        break;
    }

    case CommandType::SetNext:
        // Ignored once the next track is already in the buffer.
        if (m_transitions.empty()) {
            m_nextPath = command.path;
            m_nextFadeMs = int(command.ms);
            if (m_resolver)
                m_resolver->prefetch(command.path); // stream address ready before it is needed
        }
        break;

    case CommandType::Unload:
        m_output.setActive(false);
        m_transitions.clear();
        m_nextPath.clear();
        m_rampFrames = m_rampPos = 0;
        m_currentPath.clear();
        m_decoder->close();
        setDuration(0);
        resetTimeline(0);
        setState(State::Stopped);
        reportPosition(true);
        break;

    case CommandType::SetDevice:
        m_output.setDevice(command.path);
        break;

    case CommandType::Play:
        if (!m_decoder->isOpen() || m_state == State::Playing)
            return;
        m_output.setActive(true);
        setState(State::Playing);
        break;

    case CommandType::Pause:
        if (m_state != State::Playing)
            return;
        m_output.setActive(false);
        setState(State::Paused);
        reportPosition(true);
        break;

    case CommandType::Stop:
        if (m_decoder->isOpen())
            rewind();
        break;

    case CommandType::Seek: {
        if (!m_decoder->isOpen() || !restoreCurrentDecoder())
            return;
        int64_t ms = std::max<int64_t>(command.ms, 0);
        if (m_durationMs > 0)
            ms = std::min(ms, m_durationMs);
        if (!m_decoder->seek(ms)) {
            reportError(m_decoder->errorString());
            return;
        }
        resetTimeline(ms);
        m_decodedFrames = uint64_t(ms) * Decoder::OutputRate / 1000;
        reportPosition(true);
        break;
    }

    case CommandType::RefreshGain:
        if (command.path == m_decodingPath && !StreamResolver::isRemote(command.path)) {
            m_decodingGain = replayGainFor(command.path);
            constexpr uint64_t EaseFrames = Decoder::OutputRate; // a second
            m_gainStep = (float(replayGainFactor()) - m_gainFactor) / float(EaseFrames);
            m_gainRampLeft = m_gainStep != 0.0f ? EaseFrames : 0;
        }
        break;

    case CommandType::Quit:
        break;
    }
}

// If the queued track was already opened (but is not heard yet), reopen the
// current one so it can be seeked; the queued track stays queued.
bool Player::restoreCurrentDecoder()
{
    if (m_transitions.empty())
        return true;

    m_nextPath = m_transitions.front().path;
    m_transitions.clear();
    m_rampFrames = m_rampPos = 0; // that was the next track's fade-in
    return openPath(m_currentPath);
}

bool Player::openNext()
{
    const uint64_t boundary = m_ring.writeIndex();
    const std::string path = std::move(m_nextPath);
    const int fadeMs = m_nextFadeMs;
    m_nextPath.clear();

    if (!openPath(path)) {
        // Keep the current track seekable; it simply ends as if nothing was queued.
        openPath(m_currentPath);
        m_decoderDone = true;
        return false;
    }

    m_transitions.push_back({boundary, path, m_decoder->durationMs()});
    m_decoderDone = false;
    // It starts from silence and comes up (the previous track faded out).
    m_rampFrames = uint64_t(std::max(fadeMs, 0)) * Decoder::OutputRate / 1000;
    m_rampPos = 0;
    return true;
}

bool Player::openPath(Decoder &decoder, const std::string &path)
{
    if (&decoder == m_decoder.get()) {
        m_decodedFrames = 0;
        // (YouTube songs have no tags and aren't measured; servers may give theirs: the store has it.)
        m_decodingGain = StreamResolver::isYouTube(path) ? ReplayGain{} : replayGainFor(path);
        m_decodingPath = path;
        m_gainFactor = float(replayGainFactor()); // a new file starts at its own level
        m_gainRampLeft = 0;
    }
    std::optional<std::string> source = path;
    if (m_resolver && StreamResolver::isRemote(path)) {
        source = m_resolver->resolve(path);
        if (!source) {
            decoder.close();
            const std::string reason = m_resolver->lastError();
            reportError(reason.empty() ? "Couldn't get the YouTube stream (is yt-dlp installed and up to date?)"
                                       : reason);
            return false;
        }
    }
    if (!decoder.open(*source)) {
        reportError(decoder.errorString());
        return false;
    }
    return true;
}

void Player::rewind()
{
    m_output.setActive(false);
    restoreCurrentDecoder();
    m_decoder->seek(0);
    resetTimeline(0);
    m_decodedFrames = 0;
    setState(State::Stopped);
    reportPosition(true);
}

void Player::resetTimeline(int64_t ms)
{
    m_pending.clear();
    m_pendingOffset = 0;
    m_decoderDone = false;
    m_baseIndex = m_ring.writeIndex();
    m_ring.discardUntil(m_baseIndex);
    m_baseMs = ms;
}

void Player::fillBuffer()
{
    if (!m_decoder->isOpen())
        return;

    for (;;) {
        if (m_pendingOffset < m_pending.size()) {
            // Keep whole frames together: write an even number of samples.
            const size_t space = m_ring.writable() / Channels * Channels;
            const size_t count = std::min(m_pending.size() - m_pendingOffset, space);
            m_pendingOffset += m_ring.write(m_pending.data() + m_pendingOffset, count);
            if (m_pendingOffset < m_pending.size())
                return; // ring is full
        }

        if (m_decoderDone) {
            // Current file fully buffered: continue with the queued one, if any.
            if (m_nextPath.empty() || !openNext())
                return;
            continue;
        }

        m_pending.clear();
        m_pendingOffset = 0;
        const bool more = m_decoder->decode(m_pending);
        m_decodedFrames += m_pending.size() / Channels;
        applyReplayGain(m_pending);
        applyRampIn(m_pending);
        applyFadeOut(m_pending);

        if (!more) {
            if (!m_decoder->errorString().empty())
                reportError(m_decoder->errorString());
            m_decoderDone = true;
            m_endIndex = m_ring.writeIndex() + m_pending.size();
        }
    }
}

// A track with a fade queued after it: its last fade-length goes down to silence
// (the chunk just decoded ends at m_decodedFrames). Short or endless tracks
// don't fade.
void Player::applyFadeOut(std::vector<float> &chunk)
{
    if (m_nextPath.empty() || m_nextFadeMs <= 0)
        return;
    const int64_t duration = m_decoder->durationMs();
    if (duration <= 0 || duration < 3 * int64_t(m_nextFadeMs))
        return;
    const uint64_t fadeFrames = uint64_t(m_nextFadeMs) * Decoder::OutputRate / 1000;
    const uint64_t totalFrames = uint64_t(duration) * Decoder::OutputRate / 1000;
    const size_t frames = chunk.size() / Channels;
    const uint64_t first = m_decodedFrames - frames; // of this chunk
    if (first + frames + fadeFrames < totalFrames)
        return; // not there yet
    for (size_t f = 0; f < frames; ++f) {
        const uint64_t frame = first + f;
        const uint64_t left = frame < totalFrames ? totalFrames - frame : 0;
        if (left >= fadeFrames)
            continue;
        const float gain = fadeOut(1.0f - float(left) / float(fadeFrames));
        for (size_t c = 0; c < Channels; ++c)
            chunk[f * Channels + c] *= gain;
    }
}

void Player::setLoudnessStore(std::shared_ptr<const LoudnessStore> store)
{
    std::lock_guard lock(m_loudnessMutex);
    m_loudness = std::move(store);
}

ReplayGain Player::replayGainFor(const std::string &path)
{
    const ReplayGain tags = StreamResolver::isHosted(path) ? ReplayGain{} : Metadata::readReplayGain(path);
    if (tags.hasTrack || tags.hasAlbum)
        return tags;
    std::shared_ptr<const LoudnessStore> store;
    {
        std::lock_guard lock(m_loudnessMutex);
        store = m_loudness;
    }
    if (store)
        if (const auto measured = store->replayGain(path))
            return *measured;
    return tags;
}

// The file's ReplayGain in the current mode (never past its peak: no clipping).
double Player::replayGainFactor() const
{
    const int mode = m_replayGainMode.load(std::memory_order_relaxed);
    const ReplayGain &g = m_decodingGain;
    const bool album = mode == 2 && g.hasAlbum;
    if (mode == 0 || (!album && !g.hasTrack))
        return 1.0;
    const double peak = album ? g.albumPeak : g.trackPeak;
    double factor = std::pow(10.0, (album ? g.albumGainDb : g.trackGainDb) / 20.0);
    if (peak > 0)
        factor = std::min(factor, 1.0 / peak);
    return factor;
}

// Turned up or down by the file's ReplayGain; a gain that arrived while the
// file plays (just measured) is eased in.
void Player::applyReplayGain(std::vector<float> &chunk)
{
    if (m_gainRampLeft == 0) {
        m_gainFactor = float(replayGainFactor()); // (a mode change applies at once)
        if (m_gainFactor == 1.0f)
            return;
        for (float &sample : chunk)
            sample *= m_gainFactor;
        return;
    }
    const size_t frames = chunk.size() / Channels;
    for (size_t f = 0; f < frames; ++f) {
        if (m_gainRampLeft > 0) {
            m_gainFactor += m_gainStep;
            if (--m_gainRampLeft == 0)
                m_gainFactor = float(replayGainFactor());
        }
        for (size_t c = 0; c < Channels; ++c)
            chunk[f * Channels + c] *= m_gainFactor;
    }
}

void Player::applyRampIn(std::vector<float> &chunk)
{
    if (m_rampPos >= m_rampFrames)
        return;
    const size_t frames = chunk.size() / Channels;
    for (size_t f = 0; f < frames && m_rampPos < m_rampFrames; ++f, ++m_rampPos) {
        const float gain = fadeIn(float(m_rampPos) / float(m_rampFrames));
        for (size_t c = 0; c < Channels; ++c)
            chunk[f * Channels + c] *= gain;
    }
}

// Asks the realtime thread to fade the output out, and waits until it has
// (bounded: the device may not be pulling at all).
void Player::dipOut()
{
    m_dipRemaining.store(int(DipFrames), std::memory_order_relaxed);
    const auto deadline = std::chrono::steady_clock::now() + 400ms;
    while (m_dipRemaining.load(std::memory_order_relaxed) > 0 && std::chrono::steady_clock::now() < deadline)
        std::this_thread::sleep_for(5ms);
    m_dipRemaining.store(0, std::memory_order_relaxed);
    m_dipMuted.store(true, std::memory_order_relaxed);
}

// Playback has reached a queued track: it becomes the current one.
void Player::applyTransitions()
{
    while (!m_transitions.empty() && m_ring.readIndex() >= m_transitions.front().index) {
        const Transition transition = std::move(m_transitions.front());
        m_transitions.pop_front();

        m_currentPath = transition.path;
        m_baseIndex = transition.index;
        m_baseMs = 0;
        setDuration(transition.durationMs);
        if (m_callbacks.trackChanged)
            m_callbacks.trackChanged(transition.path);
        reportPosition(true);
    }
}

void Player::checkFinished()
{
    if (m_state != State::Playing || !m_decoderDone || !m_transitions.empty()
        || m_ring.readIndex() < m_endIndex)
        return;

    rewind();
    if (m_callbacks.trackFinished)
        m_callbacks.trackFinished();
}

void Player::reportPosition(bool force)
{
    const auto now = std::chrono::steady_clock::now();
    if (!force && (m_state != State::Playing || now - m_lastReport < PositionInterval))
        return;
    m_lastReport = now;

    const int64_t position = currentPositionMs();
    if (position == m_lastPositionMs)
        return;
    m_lastPositionMs = position;
    if (m_callbacks.positionChanged)
        m_callbacks.positionChanged(position);
}

int64_t Player::currentPositionMs() const
{
    const uint64_t read = m_ring.readIndex();
    int64_t ms = m_baseMs;
    if (read > m_baseIndex)
        ms += int64_t((read - m_baseIndex) / Channels * 1000 / Decoder::OutputRate);
    return m_durationMs > 0 ? std::min(ms, m_durationMs) : ms;
}

void Player::setState(State state)
{
    if (state == m_state)
        return;
    m_state = state;
    if (m_callbacks.stateChanged)
        m_callbacks.stateChanged(state);
}

void Player::setDuration(int64_t ms)
{
    m_durationMs = ms;
    if (m_callbacks.durationChanged)
        m_callbacks.durationChanged(ms);
}

void Player::reportError(const std::string &message)
{
    if (m_callbacks.error)
        m_callbacks.error(message);
}

size_t Player::pull(float *dst, size_t frames)
{
    const size_t got = m_ring.read(dst, frames * Channels) / Channels;
    if (m_dipMuted.load(std::memory_order_relaxed)) {
        std::fill(dst, dst + got * Channels, 0.0f);
        return got;
    }
    if (int remaining = m_dipRemaining.load(std::memory_order_relaxed); remaining > 0) {
        // Skip: fade out over DipFrames, then silence until the new track starts.
        for (size_t f = 0; f < got; ++f) {
            const float gain = remaining > 0 ? fadeOut(1.0f - float(remaining) / float(DipFrames)) : 0.0f;
            for (size_t c = 0; c < Channels; ++c)
                dst[f * Channels + c] *= gain;
            if (remaining > 0)
                --remaining;
        }
        if (remaining == 0)
            m_dipMuted.store(true, std::memory_order_relaxed);
        m_dipRemaining.store(remaining, std::memory_order_relaxed);
    }
    m_equalizer.process(dst, got);
    m_spectrum.push(dst, got); // what is heard, equalizer included
    const float gain = m_gain.load(std::memory_order_relaxed) * m_fadeLevel.load(std::memory_order_relaxed);
    if (gain != 1.0f) {
        for (size_t i = 0; i < got * Channels; ++i)
            dst[i] *= gain;
    }
    return got;
}
