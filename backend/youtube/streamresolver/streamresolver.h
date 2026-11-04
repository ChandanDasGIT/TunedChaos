#pragma once

#include "backend/youtube/ytdlp/ytdlp.h"

#include <memory>

#include <condition_variable>
#include <cstdint>
#include <deque>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <thread>
#include <unordered_map>

class HostedStore;

// Turns playlist paths of YouTube tracks ("ytmusic:<videoId>") into direct
// audio stream addresses (via yt-dlp). Addresses are cached until shortly
// before they expire. prefetch() resolves in the background so the next track
// is ready for a gapless switch. Thread-safe.
class StreamResolver
{
public:
    static constexpr const char *Prefix = "ytmusic:";

    StreamResolver();
    ~StreamResolver();

    StreamResolver(const StreamResolver &) = delete;
    StreamResolver &operator=(const StreamResolver &) = delete;

    static bool isYouTube(const std::string &path);
    static bool isHosted(const std::string &path); // a music server's song ("hosted:...")
    static bool isRemote(const std::string &path); // not a file on this device: YouTube or a server
    // Where "hosted:" songs stream from (the servers signed in to).
    void setHostedStore(std::shared_ptr<const HostedStore> store);
    static std::string videoId(const std::string &path);
    static std::string pathFor(const std::string &videoId);

    // Blocking. Local paths come back unchanged.
    std::optional<std::string> resolve(const std::string &path);
    void prefetch(const std::string &path);

    void setCookiesBrowser(const std::string &browser);
    void setQuality(YtDlp::AudioQuality quality); // for the songs resolved from now on

    // Why the last resolve failed, in plain words ("" = no failure yet).
    std::string lastError() const;

private:
    void run();

    struct Cached
    {
        std::string url;
        int64_t validUntil; // unix seconds
    };

    mutable std::mutex m_mutex;
    std::condition_variable m_changed;
    std::unordered_map<std::string, Cached> m_cache; // videoId -> stream
    std::set<std::string> m_resolving;               // videoIds being resolved right now
    std::deque<std::string> m_prefetchQueue;
    std::string m_cookiesBrowser;
    std::shared_ptr<const HostedStore> m_hosted;
    YtDlp::AudioQuality m_quality = YtDlp::AudioQuality::Best;
    std::string m_lastError;
    int64_t m_limitedUntil = 0; // unix seconds: no background prefetches before this
    bool m_quit = false;
    std::thread m_thread; // last member: starts after everything above exists
};
