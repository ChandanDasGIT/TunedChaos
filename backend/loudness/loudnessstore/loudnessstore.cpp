#include "backend/loudness/loudnessstore/loudnessstore.h"

#include "backend/storage/tsv/tsv.h"

#include <fstream>
#include <locale>
#include <sstream>
#include <system_error>

namespace fs = std::filesystem;

namespace {

constexpr const char *Header = "TunedChaos loudness v1";
constexpr size_t FieldCount = 9;

bool fileStamp(const std::string &path, int64_t &size, int64_t &time)
{
    std::error_code ec;
    const auto bytes = fs::file_size(path, ec);
    if (ec)
        return false;
    const auto written = fs::last_write_time(path, ec);
    if (ec)
        return false;
    size = int64_t(bytes);
    time = int64_t(written.time_since_epoch().count());
    return true;
}

char kindCode(LoudnessStore::Kind kind)
{
    switch (kind) {
    case LoudnessStore::Kind::Tagged: return 't';
    case LoudnessStore::Kind::Measured: return 'm';
    case LoudnessStore::Kind::Failed: return 'f';
    case LoudnessStore::Kind::Unknown: break;
    }
    return '?';
}

LoudnessStore::Kind kindFromCode(const std::string &code)
{
    if (code == "t")
        return LoudnessStore::Kind::Tagged;
    if (code == "m")
        return LoudnessStore::Kind::Measured;
    if (code == "f")
        return LoudnessStore::Kind::Failed;
    return LoudnessStore::Kind::Unknown;
}

// Always with a '.' (strtod follows the system's language; from_chars for
// doubles is missing from older Android NDKs).
double toDouble(const std::string &s)
{
    std::istringstream in(s);
    in.imbue(std::locale::classic());
    double value = 0;
    in >> value;
    return value;
}

} // namespace

LoudnessStore::LoudnessStore(fs::path file)
    : m_file(std::move(file))
{
}

void LoudnessStore::load()
{
    std::lock_guard lock(m_mutex);
    m_entries.clear();
    std::ifstream in(m_file);
    std::string line;
    if (!in || !std::getline(in, line) || line != Header)
        return;
    while (std::getline(in, line)) {
        const std::vector<std::string> f = tsv::split(line);
        if (f.size() != FieldCount)
            continue;
        Entry entry;
        entry.kind = kindFromCode(f[1]);
        if (entry.kind == Kind::Unknown)
            continue;
        entry.fileSize = tsv::toNumber<int64_t>(f[2]);
        entry.fileTime = tsv::toNumber<int64_t>(f[3]);
        entry.track = {toDouble(f[4]), toDouble(f[5])};
        entry.hasAlbum = !f[6].empty();
        entry.album = {toDouble(f[6]), toDouble(f[7])};
        m_entries[tsv::unescape(f[0])] = entry;
    }
}

bool LoudnessStore::save() const
{
    std::error_code ec;
    fs::create_directories(m_file.parent_path(), ec);
    const fs::path temp = m_file.string() + ".tmp";
    {
        std::lock_guard lock(m_mutex);
        std::ofstream out(temp, std::ios::trunc);
        if (!out)
            return false;
        out.imbue(std::locale::classic());
        out.precision(4);
        out << std::fixed << Header << '\n';
        for (const auto &[path, e] : m_entries) {
            out << tsv::escape(path) << '\t' << kindCode(e.kind) << '\t' << e.fileSize << '\t' << e.fileTime
                << '\t' << e.track.lufs << '\t' << e.track.peak << '\t';
            if (e.hasAlbum)
                out << e.album.lufs << '\t' << e.album.peak;
            else
                out << '\t';
            out << '\t' << '\n'; // (a spare field for later)
        }
        if (!out)
            return false;
    }
    fs::rename(temp, m_file, ec);
    return !ec;
}

bool LoudnessStore::contains(const std::string &path) const
{
    std::lock_guard lock(m_mutex);
    return m_entries.count(path) != 0;
}

const LoudnessStore::Entry *LoudnessStore::findLocked(const std::string &path) const
{
    const auto it = m_entries.find(path);
    if (it == m_entries.end())
        return nullptr;
    int64_t size = 0, time = 0;
    if (!fileStamp(path, size, time) || size != it->second.fileSize || time != it->second.fileTime)
        return nullptr; // the file changed since
    return &it->second;
}

LoudnessStore::Kind LoudnessStore::kind(const std::string &path) const
{
    std::lock_guard lock(m_mutex);
    const Entry *entry = findLocked(path);
    return entry ? entry->kind : Kind::Unknown;
}

void LoudnessStore::put(const std::string &path, Entry entry)
{
    fileStamp(path, entry.fileSize, entry.fileTime);
    std::lock_guard lock(m_mutex);
    m_entries[path] = entry;
}

void LoudnessStore::putTagged(const std::string &path)
{
    Entry entry;
    entry.kind = Kind::Tagged;
    put(path, entry);
}

void LoudnessStore::putFailed(const std::string &path)
{
    Entry entry;
    entry.kind = Kind::Failed;
    put(path, entry);
}

void LoudnessStore::putMeasured(const std::string &path, const Loudness &loudness)
{
    Entry entry;
    entry.kind = Kind::Measured;
    entry.track = loudness;
    put(path, entry);
}

bool LoudnessStore::updateAlbum(const std::vector<std::pair<std::string, int64_t>> &songs)
{
    std::lock_guard lock(m_mutex);
    std::vector<std::pair<Loudness, int64_t>> measured;
    for (const auto &[path, durationMs] : songs) {
        const Entry *entry = findLocked(path);
        if (!entry || entry->kind == Kind::Unknown)
            return false; // not all measured yet
        if (entry->kind == Kind::Measured)
            measured.emplace_back(entry->track, durationMs);
    }
    if (measured.empty())
        return false;
    const Loudness album = LoudnessMeter::combine(measured);
    for (const auto &[path, durationMs] : songs) {
        Entry &entry = m_entries[path];
        if (entry.kind != Kind::Measured)
            continue;
        entry.hasAlbum = true;
        entry.album = album;
    }
    return true;
}

std::optional<ReplayGain> LoudnessStore::replayGain(const std::string &path) const
{
    std::lock_guard lock(m_mutex);
    const Entry *entry = findLocked(path);
    if (!entry || entry->kind != Kind::Measured)
        return std::nullopt;
    ReplayGain gain;
    gain.hasTrack = true;
    gain.trackGainDb = LoudnessMeter::ReferenceLufs - entry->track.lufs;
    gain.trackPeak = entry->track.peak;
    if (entry->hasAlbum) {
        gain.hasAlbum = true;
        gain.albumGainDb = LoudnessMeter::ReferenceLufs - entry->album.lufs;
        gain.albumPeak = entry->album.peak;
    }
    return gain;
}
