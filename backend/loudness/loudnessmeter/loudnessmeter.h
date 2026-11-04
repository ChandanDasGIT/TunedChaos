#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <vector>

// How loud a song is, the way ReplayGain 2 measures it.
struct Loudness
{
    double lufs = 0; // integrated loudness (EBU R128 / ITU-R BS.1770)
    double peak = 0; // highest sample, 1.0 = full scale
};

// Integrated loudness of interleaved stereo float audio at 48 kHz (what the
// Decoder gives): K-weighting, 400 ms blocks every 100 ms, absolute gate at
// -70 LUFS and relative gate 10 LU below.
class LoudnessMeter
{
public:
    static constexpr int Rate = 48000;
    static constexpr int Channels = 2;
    // ReplayGain 2's reference loudness: gain = ReferenceLufs - lufs.
    static constexpr double ReferenceLufs = -18.0;

    LoudnessMeter();

    void add(const float *samples, size_t count); // `count` samples (frames * Channels)
    void add(const std::vector<float> &samples) { add(samples.data(), samples.size()); }

    // Empty for silence or audio shorter than one block.
    std::optional<Loudness> result() const;

    // Decodes the whole file and measures it (empty if it can't be read, or is silent).
    // `stop` (optional) is checked now and then: true gives up early.
    static std::optional<Loudness> measureFile(const std::filesystem::path &path,
                                               const std::atomic<bool> *stop = nullptr);

    // A whole album's loudness from its songs' (each weighted by its length).
    static Loudness combine(const std::vector<std::pair<Loudness, int64_t /*durationMs*/>> &songs);

private:
    struct Biquad
    {
        double b0, b1, b2, a1, a2;
        double z1[Channels]{}, z2[Channels]{};
        double run(int channel, double x);
    };

    static constexpr size_t SegmentFrames = Rate / 10; // 100 ms
    static constexpr int SegmentsPerBlock = 4;         // 400 ms blocks, 75 % overlap

    Biquad m_shelf, m_highPass;
    double m_segmentSum = 0;  // weighted squares in the current 100 ms
    size_t m_segmentFrames = 0;
    size_t m_channel = 0;     // next sample's channel
    std::vector<double> m_segments; // finished 100 ms sums
    std::vector<double> m_blocks;   // mean square of every 400 ms block
    double m_peak = 0;
};
