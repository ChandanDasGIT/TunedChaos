#pragma once

#include "backend/library/metadata/metadata.h"
#include "backend/loudness/loudnessmeter/loudnessmeter.h"

#include <cstdint>
#include <filesystem>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

// Disk cache (tab-separated text) of measured loudness for local files that
// have no ReplayGain tags, and of the gains music servers give for their songs
// (Kind::Server). Files that do have tags are only noted, so they aren't read
// again. A file's entry is ignored once the file changes (size / modification
// time). Thread-safe: the player reads it while the scanner writes.
class LoudnessStore
{
public:
    enum class Kind { Unknown, Tagged, Measured, Failed, Server };

    explicit LoudnessStore(std::filesystem::path file);

    void load();
    bool save() const;

    // Cheap: is there any record for this path (no file checks)?
    bool contains(const std::string &path) const;
    // What is known about the file as it is on disk now.
    Kind kind(const std::string &path) const;

    void putTagged(const std::string &path);
    void putMeasured(const std::string &path, const Loudness &loudness);
    void putFailed(const std::string &path); // unreadable or silent: not tried again
    // A music server's song (not a file here): the gain the server measured.
    void putServerGain(const std::string &path, double gainDb);

    // Gives every song of one album its album values, once all of them are
    // measured (false otherwise). songs: path and length.
    bool updateAlbum(const std::vector<std::pair<std::string, int64_t /*durationMs*/>> &songs);

    // The measured values as ReplayGain (nothing for tagged / unmeasured files).
    std::optional<ReplayGain> replayGain(const std::string &path) const;

private:
    struct Entry
    {
        Kind kind = Kind::Unknown;
        int64_t fileSize = 0, fileTime = 0;
        Loudness track;
        bool hasAlbum = false;
        Loudness album;
    };

    void put(const std::string &path, Entry entry);
    const Entry *findLocked(const std::string &path) const; // still fits the file on disk

    std::filesystem::path m_file;
    mutable std::mutex m_mutex;
    std::unordered_map<std::string, Entry> m_entries;
};
