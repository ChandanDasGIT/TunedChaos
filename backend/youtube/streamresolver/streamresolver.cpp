#include "backend/youtube/streamresolver/streamresolver.h"

#include "backend/hosted/hostedserver/hostedserver.h"
#include "backend/hosted/hostedstore/hostedstore.h"

#include "backend/youtube/ytdlp/ytdlp.h"

#include <chrono>
#include <cstdlib>

namespace {

constexpr int64_t SafetyMarginSeconds = 600;     // re-resolve 10 min before expiry
constexpr int64_t FallbackLifetimeSeconds = 3600; // if the address has no "expire="
constexpr int64_t RateLimitPauseSeconds = 120;    // YouTube limiting us: pause prefetching

int64_t nowSeconds()
{
    using namespace std::chrono;
    return duration_cast<seconds>(system_clock::now().time_since_epoch()).count();
}

// googlevideo addresses carry "expire=<unix time>".
int64_t expiryOf(const std::string &url)
{
    const auto pos = url.find("expire=");
    if (pos != std::string::npos) {
        const int64_t value = std::atoll(url.c_str() + pos + 7);
        if (value > 0)
            return value;
    }
    return nowSeconds() + FallbackLifetimeSeconds;
}

} // namespace

StreamResolver::StreamResolver()
    : m_thread(&StreamResolver::run, this)
{
}

StreamResolver::~StreamResolver()
{
    {
        std::lock_guard lock(m_mutex);
        m_quit = true;
    }
    m_changed.notify_all();
    m_thread.join();
}

bool StreamResolver::isYouTube(const std::string &path)
{
    return path.rfind(Prefix, 0) == 0;
}

bool StreamResolver::isHosted(const std::string &path)
{
    return HostedPath::is(path);
}

bool StreamResolver::isRemote(const std::string &path)
{
    return isYouTube(path) || isHosted(path);
}

void StreamResolver::setHostedStore(std::shared_ptr<const HostedStore> store)
{
    std::lock_guard lock(m_mutex);
    m_hosted = std::move(store);
}

std::string StreamResolver::videoId(const std::string &path)
{
    return isYouTube(path) ? path.substr(std::string(Prefix).size()) : std::string();
}

std::string StreamResolver::pathFor(const std::string &videoId)
{
    return Prefix + videoId;
}

std::optional<std::string> StreamResolver::resolve(const std::string &path)
{
    if (isHosted(path)) { // a server's song: its address is known without asking
        std::shared_ptr<const HostedStore> hosted;
        {
            std::lock_guard lock(m_mutex);
            hosted = m_hosted;
        }
        const std::string url = hosted ? hosted->streamUrl(path) : std::string();
        if (url.empty()) {
            std::lock_guard lock(m_mutex);
            m_lastError = "This song's server isn't signed in any more (Library > Hosted library)";
            return std::nullopt;
        }
        return url;
    }
    if (!isYouTube(path))
        return path;
    const std::string id = videoId(path);

    std::string cookies;
    YtDlp::AudioQuality quality;
    {
        std::unique_lock lock(m_mutex);
        // Someone (e.g. a prefetch) is already on it: wait for that result.
        m_changed.wait(lock, [&] { return m_quit || m_resolving.count(id) == 0; });
        if (const auto it = m_cache.find(id);
            it != m_cache.end() && it->second.validUntil - SafetyMarginSeconds > nowSeconds())
            return it->second.url;
        if (m_quit)
            return std::nullopt;
        m_resolving.insert(id);
        cookies = m_cookiesBrowser;
        quality = m_quality;
    }

    const std::optional<std::string> url = YtDlp::streamUrl(id, cookies, quality);

    {
        std::lock_guard lock(m_mutex);
        m_resolving.erase(id);
        if (url) {
            m_cache[id] = {*url, expiryOf(*url)};
        } else {
            m_lastError = YtDlp::lastError();
            if (YtDlp::lastErrorWasRateLimit())
                m_limitedUntil = nowSeconds() + RateLimitPauseSeconds;
        }
    }
    m_changed.notify_all();
    return url;
}

void StreamResolver::prefetch(const std::string &path)
{
    if (!isYouTube(path))
        return;
    {
        std::lock_guard lock(m_mutex);
        m_prefetchQueue.push_back(path);
    }
    m_changed.notify_all();
}

std::string StreamResolver::lastError() const
{
    std::lock_guard lock(m_mutex);
    return m_lastError;
}

void StreamResolver::setCookiesBrowser(const std::string &browser)
{
    std::lock_guard lock(m_mutex);
    if (browser != m_cookiesBrowser) {
        m_cookiesBrowser = browser;
        m_cache.clear(); // addresses may differ when signed in
    }
}

void StreamResolver::setQuality(YtDlp::AudioQuality quality)
{
    std::lock_guard lock(m_mutex);
    if (quality != m_quality) {
        m_quality = quality;
        m_cache.clear(); // the next songs come in the new quality
    }
}

void StreamResolver::run()
{
    for (;;) {
        std::string path;
        {
            std::unique_lock lock(m_mutex);
            m_changed.wait(lock, [this] { return m_quit || !m_prefetchQueue.empty(); });
            if (m_quit)
                return;
            path = std::move(m_prefetchQueue.front());
            m_prefetchQueue.pop_front();
            if (nowSeconds() < m_limitedUntil)
                continue; // the track is resolved when it is played instead
        }
        resolve(path);
    }
}
