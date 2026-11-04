#pragma once

#include "backend/audioengine/audiooutput/audiooutput.h"
#include "backend/audioengine/decoder/decoder.h"
#include "backend/audioengine/equalizer/equalizer.h"
#include "backend/audioengine/ringbuffer/ringbuffer.h"
#include "backend/audioengine/spectrum/spectrum.h"
#include "backend/library/metadata/metadata.h"

class LoudnessStore;
class StreamResolver;

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

// Playback engine.
//
// Owns a worker thread that decodes into a ring buffer, which the audio
// output drains from its realtime thread. Public methods are thread-safe and
// return immediately; callbacks are invoked from the worker thread.
//
// Gapless: a track queued with setNext() is opened as soon as the current one
// has been fully decoded and is appended to the same buffer, so there is no
// gap. trackChanged() fires when playback actually reaches it. Once the next
// track has started decoding (about a buffer's length before the end) it is
// locked in and further setNext() calls are ignored until it plays.
//
// Fade: setNext() with a fade length plays the current track to its end with
// its volume going down over that long, and starts the next one (gaplessly,
// from its start) with its volume coming up over that long. Nothing overlaps
// or is cut. With setSkipFade(true), load() while playing fades the old track
// out briefly and the new one in, instead of cutting.
//
// Paths are files, or YouTube tracks ("ytmusic:<id>") which the optional
// StreamResolver turns into stream addresses; the path stays the track's
// identity in every callback.
class Player
{
public:
    enum class State { Stopped, Playing, Paused };

    struct Callbacks
    {
        std::function<void(State)> stateChanged;
        std::function<void(int64_t ms)> positionChanged;
        std::function<void(int64_t ms)> durationChanged;
        std::function<void(const std::string &path)> trackChanged; // gapless switch to the queued track
        std::function<void()> trackFinished; // reached the end with nothing queued
        std::function<void(const std::string &)> error;
    };

    Player(std::string appName, Callbacks callbacks, StreamResolver *resolver = nullptr);

    static int64_t bufferMs(); // how much decoded audio the ring buffer holds
    ~Player();

    Player(const Player &) = delete;
    Player &operator=(const Player &) = delete;

    // Opens the file and starts playing (or stays paused) at `startMs`; clears the queued track.
    void load(const std::string &path, int64_t startMs = 0, bool paused = false);
    // Track to continue with when the current one ends; empty clears.
    // fadeMs = 0: gapless; otherwise this track fades out and that one in, each over that long.
    void setNext(const std::string &path, int fadeMs = 0);
    void setSkipFade(bool enabled); // short fade instead of a cut when switching tracks
    void unload(); // stop and close the current file
    void setOutputDevice(const std::string &deviceId); // "" = system default
    void play();
    void pause();
    void stop();
    void seek(int64_t positionMs);
    void setVolume(float volume); // 0..1, perceptual
    void setFadeLevel(float level); // 0..1 on top of the volume (the sleep timer fading out)
    // ReplayGain: 0 off, 1 track, 2 album (album songs without album values use their track values).
    void setReplayGainMode(int mode);
    // Measured loudness for files without ReplayGain tags (shared with whoever measures).
    void setLoudnessStore(std::shared_ptr<const LoudnessStore> store);
    // That file's loudness was just measured: if it is the one being decoded,
    // its gain is looked up again and eased in (about a second).
    void refreshReplayGain(const std::string &path);
    void setEqualizer(const Equalizer::Gains &gainsDb, bool enabled); // takes effect at once

    // What is being played, for the visualizer (before volume is applied).
    SpectrumAnalyzer &spectrum() { return m_spectrum; }

private:
    enum class CommandType { Load, SetNext, Unload, SetDevice, Play, Pause, Stop, Seek, RefreshGain, Quit };

    struct Command
    {
        CommandType type;
        std::string path;
        int64_t ms = 0;
        bool paused = false; // Load: stay paused once opened
    };

    // A queued track that is already in the ring buffer, starting at `index`.
    struct Transition
    {
        uint64_t index;
        std::string path;
        int64_t durationMs;
    };

    void post(Command command);
    void run();
    void handle(const Command &command);

    bool restoreCurrentDecoder();        // undo an opened-but-unheard next track
    bool openNext();                     // current track fully decoded: continue with the queued one
    void rewind();                       // back to 0, output inactive, state Stopped
    void resetTimeline(int64_t ms);      // drop buffered audio, position restarts at ms
    void fillBuffer();
    void applyTransitions();
    void checkFinished();
    void reportPosition(bool force);
    int64_t currentPositionMs() const;
    void setState(State state);
    void setDuration(int64_t ms);
    bool openPath(Decoder &decoder, const std::string &path); // file or resolved stream
    bool openPath(const std::string &path) { return openPath(*m_decoder, path); }

    // Fades
    void applyFadeOut(std::vector<float> &chunk); // the end of a track, when the next one fades in
    void applyRampIn(std::vector<float> &chunk);  // fade-in after a skip / at the start of a track
    void applyReplayGain(std::vector<float> &chunk); // the decoding file's ReplayGain
    ReplayGain replayGainFor(const std::string &path); // its tags, else its measured loudness
    double replayGainFactor() const; // m_decodingGain in the current mode, as a multiplier
    void dipOut();                                // skip: fade what is playing out, then mute
    void reportError(const std::string &message);

    size_t pull(float *dst, size_t frames); // realtime thread

    const std::string m_appName;
    const Callbacks m_callbacks;
    StreamResolver *const m_resolver;

    // Worker thread state
    std::unique_ptr<Decoder> m_decoder = std::make_unique<Decoder>();
    AudioOutput m_output;
    State m_state = State::Stopped;
    std::string m_currentPath;           // track being heard
    std::string m_nextPath;              // queued, not opened yet
    std::deque<Transition> m_transitions; // opened, not heard yet
    std::vector<float> m_pending;
    size_t m_pendingOffset = 0;
    bool m_decoderDone = false;
    uint64_t m_endIndex = 0;   // ring index where the decoder's file ends (valid once m_decoderDone)
    uint64_t m_baseIndex = 0;  // ring index that corresponds to m_baseMs
    int64_t m_baseMs = 0;
    int64_t m_durationMs = 0;
    int64_t m_lastPositionMs = -1;
    std::chrono::steady_clock::time_point m_lastReport;
    uint64_t m_decodedFrames = 0; // of the current decoder's file

    // Fades (worker thread)
    int m_nextFadeMs = 0;                     // for m_nextPath
    uint64_t m_rampFrames = 0, m_rampPos = 0; // fade-in still to apply
    ReplayGain m_decodingGain;                // of the file being decoded
    std::string m_decodingPath;               // that file
    float m_gainFactor = 1.0f;                // applied now (eases towards the target)
    float m_gainStep = 0.0f;                  // per frame, while easing
    uint64_t m_gainRampLeft = 0;              // frames of easing left
    std::atomic<int> m_replayGainMode{0};
    std::mutex m_loudnessMutex;
    std::shared_ptr<const LoudnessStore> m_loudness;

    // Shared with the realtime thread
    RingBuffer m_ring;
    std::atomic<float> m_gain{1.0f};
    std::atomic<float> m_fadeLevel{1.0f};
    std::atomic<bool> m_skipFade{false};
    std::atomic<int> m_dipRemaining{0}; // frames of fade-out left (skip)
    std::atomic<bool> m_dipMuted{false};  // fade-out done: silence until the new track
    Equalizer m_equalizer{Decoder::OutputRate, Decoder::OutputChannels};
    SpectrumAnalyzer m_spectrum{Decoder::OutputRate};

    // Command queue
    std::mutex m_mutex;
    std::condition_variable m_wake;
    std::deque<Command> m_commands;

    std::thread m_thread; // last member: starts after everything above exists
};
