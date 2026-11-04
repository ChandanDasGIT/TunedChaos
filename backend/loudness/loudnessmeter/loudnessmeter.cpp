#include "backend/loudness/loudnessmeter/loudnessmeter.h"

#include "backend/audioengine/decoder/decoder.h"

#include <algorithm>
#include <cmath>

static_assert(Decoder::OutputRate == LoudnessMeter::Rate && Decoder::OutputChannels == LoudnessMeter::Channels,
              "the meter's filters are made for the decoder's output");

namespace {

constexpr double AbsoluteGateLufs = -70.0;
constexpr double RelativeGateLu = -10.0;

double toLufs(double meanSquare) { return -0.691 + 10.0 * std::log10(meanSquare); }
double fromLufs(double lufs) { return std::pow(10.0, (lufs + 0.691) / 10.0); }

} // namespace

double LoudnessMeter::Biquad::run(int channel, double x)
{
    // Transposed direct form II
    const double y = b0 * x + z1[channel];
    z1[channel] = b1 * x - a1 * y + z2[channel];
    z2[channel] = b2 * x - a2 * y;
    return y;
}

// BS.1770's K-weighting at 48 kHz: a high shelf (the head) and a high pass.
LoudnessMeter::LoudnessMeter()
    : m_shelf{1.53512485958697, -2.69169618940638, 1.19839281085285, -1.69065929318241, 0.73248077421585}
    , m_highPass{1.0, -2.0, 1.0, -1.99004745483398, 0.99007225036621}
{
}

void LoudnessMeter::add(const float *samples, size_t count)
{
    for (size_t i = 0; i < count; ++i) {
        const double x = samples[i];
        m_peak = std::max(m_peak, std::abs(x));
        const double k = m_highPass.run(int(m_channel), m_shelf.run(int(m_channel), x));
        m_segmentSum += k * k; // left and right both weigh 1.0
        if (++m_channel < Channels)
            continue;
        m_channel = 0;
        if (++m_segmentFrames < SegmentFrames)
            continue;
        m_segments.push_back(m_segmentSum);
        m_segmentSum = 0;
        m_segmentFrames = 0;
        if (m_segments.size() >= SegmentsPerBlock) {
            double sum = 0;
            for (size_t s = m_segments.size() - SegmentsPerBlock; s < m_segments.size(); ++s)
                sum += m_segments[s];
            m_blocks.push_back(sum / double(SegmentFrames * SegmentsPerBlock));
        }
    }
}

std::optional<Loudness> LoudnessMeter::result() const
{
    // Blocks above the absolute gate, then those within 10 LU of their average.
    const double absolute = fromLufs(AbsoluteGateLufs);
    double sum = 0;
    size_t count = 0;
    for (double block : m_blocks)
        if (block > absolute) {
            sum += block;
            ++count;
        }
    if (count == 0)
        return std::nullopt;
    const double relative = fromLufs(toLufs(sum / double(count)) + RelativeGateLu);
    double gatedSum = 0;
    size_t gatedCount = 0;
    for (double block : m_blocks)
        if (block > absolute && block > relative) {
            gatedSum += block;
            ++gatedCount;
        }
    if (gatedCount == 0)
        return std::nullopt;
    return Loudness{toLufs(gatedSum / double(gatedCount)), m_peak};
}

std::optional<Loudness> LoudnessMeter::measureFile(const std::filesystem::path &path,
                                                  const std::atomic<bool> *stop)
{
    Decoder decoder;
    if (!decoder.open(path.string()))
        return std::nullopt;
    LoudnessMeter meter;
    std::vector<float> chunk;
    for (;;) {
        if (stop && stop->load(std::memory_order_relaxed))
            return std::nullopt;
        chunk.clear();
        const bool more = decoder.decode(chunk);
        meter.add(chunk);
        if (!more)
            break;
    }
    if (!decoder.errorString().empty())
        return std::nullopt; // a broken file: don't trust a partial measurement
    return meter.result();
}

Loudness LoudnessMeter::combine(const std::vector<std::pair<Loudness, int64_t>> &songs)
{
    // Energy average, weighted by length (close to measuring the album as one piece).
    double energy = 0, total = 0;
    Loudness album;
    for (const auto &[song, durationMs] : songs) {
        const double weight = double(std::max<int64_t>(durationMs, 1));
        energy += fromLufs(song.lufs) * weight;
        total += weight;
        album.peak = std::max(album.peak, song.peak);
    }
    album.lufs = total > 0 ? toLufs(energy / total) : 0;
    return album;
}
