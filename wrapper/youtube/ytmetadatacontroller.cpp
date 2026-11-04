#include "wrapper/youtube/ytmetadatacontroller.h"

#include "wrapper/files/files.h"
#include "backend/library/metadata/metadata.h"
#include "backend/library/track/track.h"
#include "backend/youtube/ytmatcher/ytmatcher.h"
#include "backend/youtube/streamresolver/streamresolver.h"
#include "backend/youtube/ytmetadatastore/ytmetadatastore.h"
#include "wrapper/player/playercontroller.h"
#include "wrapper/playlist/playlistcontroller.h"
#include "wrapper/settings/settingscontroller.h"

#include <QFileInfo>
#include <QJSEngine>
#include <QStandardPaths>

namespace {

// Gentle on YouTube: one lookup per interval, backing off while it fails.
constexpr int IntervalMs = 2000;
constexpr int MaxIntervalMs = 60000;

} // namespace

YtMetadataController::YtMetadataController(PlaylistController *playlist, PlayerController *player,
                                           SettingsController *settings, QObject *parent)
    : QObject(parent)
    , m_playlist(playlist)
    , m_player(player)
    , m_settings(settings)
{
    Q_ASSERT(!s_instance);
    s_instance = this;

    const QString file = Files::cacheDir()
                         + QStringLiteral("/ytmeta.tsv");
    m_store = std::make_unique<YtMetadataStore>(file.toStdString());
    m_store->load();

    m_pool.setMaxThreadCount(1);
    m_timer.setInterval(IntervalMs);
    connect(&m_timer, &QTimer::timeout, this, &YtMetadataController::processNext);

    connect(m_playlist, &PlaylistController::countChanged, this, &YtMetadataController::rebuildQueue);
    connect(m_player, &PlayerController::sourceChanged, this,
            [this] { prioritize(m_player->source()); });
    connect(m_settings, &SettingsController::ytBackgroundLookupChanged, this, [this] {
        emit enabledChanged();
        rebuildQueue();
    });

    rebuildQueue();
}

YtMetadataController::~YtMetadataController()
{
    m_timer.stop();
    m_pool.waitForDone(); // no task may post to a destroyed object
    m_store->save();
    s_instance = nullptr;
}

YtMetadataController *YtMetadataController::create(QQmlEngine *, QJSEngine *)
{
    Q_ASSERT(s_instance);
    QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
    return s_instance;
}

// A file on disk (not a YouTube "ytmusic:" source).
bool YtMetadataController::isLocal(const QString &path)
{
    return !path.isEmpty() && !StreamResolver::isRemote(path.toStdString());
}

bool YtMetadataController::enabled() const
{
    return m_settings->ytBackgroundLookup();
}

QVariantMap YtMetadataController::infoFor(const QString &path) const
{
    if (path.isEmpty())
        return {};

    // A YouTube track *is* the YouTube Music song: nothing to look up.
    if (const ::Track *track = m_playlist->trackForPath(path); track && !track->videoId.empty()) {
        return {
            {QStringLiteral("state"), QStringLiteral("matched")},
            {QStringLiteral("title"), QString::fromStdString(track->title)},
            {QStringLiteral("artists"), QString::fromStdString(track->artist)},
            {QStringLiteral("album"), QString::fromStdString(track->album)},
            {QStringLiteral("year"), QString()},
            {QStringLiteral("duration"), qint64(track->durationMs)},
            {QStringLiteral("url"), QString::fromStdString(YtMusicClient::watchUrl(track->videoId))},
            {QStringLiteral("thumbnail"), QString::fromStdString(track->thumbnailUrl)},
        };
    }

    if (const YtMetadataEntry *entry = m_store->find(path.toStdString())) {
        if (!entry->matched)
            return {{QStringLiteral("state"), QStringLiteral("nomatch")}};

        const YtSong &song = entry->song;
        QStringList artists;
        for (const std::string &artist : song.artists)
            artists << QString::fromStdString(artist);
        return {
            {QStringLiteral("state"), QStringLiteral("matched")},
            {QStringLiteral("close"), entry->close},
            {QStringLiteral("title"), QString::fromStdString(song.title)},
            {QStringLiteral("artists"), artists.join(QStringLiteral(", "))},
            {QStringLiteral("album"), QString::fromStdString(song.album)},
            {QStringLiteral("year"), QString::fromStdString(song.year)},
            {QStringLiteral("duration"), qint64(song.durationMs)},
            {QStringLiteral("url"), QString::fromStdString(YtMusicClient::watchUrl(song.videoId))},
            {QStringLiteral("thumbnail"), QString::fromStdString(song.thumbnailUrl)},
        };
    }

    if (!enabled())
        return {{QStringLiteral("state"), QStringLiteral("off")}};
    if (m_failed.contains(path) && m_inFlight != path)
        return {{QStringLiteral("state"), QStringLiteral("error")}};
    return {{QStringLiteral("state"), QStringLiteral("pending")}};
}

void YtMetadataController::prioritize(const QString &path)
{
    if (!isLocal(path) || !enabled() || path == m_inFlight || m_store->find(path.toStdString()))
        return;
    if (const ::Track *track = m_playlist->trackForPath(path); track && !track->videoId.empty())
        return; // a YouTube track
    m_queue.removeAll(path);
    m_queue.prepend(path);
    m_failed.remove(path);
    if (!m_timer.isActive())
        m_timer.start();
    if (m_inFlight.isEmpty())
        QTimer::singleShot(0, this, &YtMetadataController::processNext); // right away
}

// Every Queue track never looked up, the playing one first (even when it is
// not in the Queue). (In-memory check
// only: whether a stored result still fits the file is checked when it is shown
// or played, via prioritize().)
void YtMetadataController::rebuildQueue()
{
    m_queue.clear();
    if (!enabled()) {
        m_timer.stop();
        return;
    }

    for (const ::Track &track : m_playlist->tracks()) {
        const QString path = QString::fromStdString(track.path);
        if (track.videoId.empty() && path != m_inFlight && !m_store->contains(track.path))
            m_queue.append(path);
    }
    const QString playing = m_player->source();
    if (m_queue.removeAll(playing) > 0
        || (isLocal(playing) && playing != m_inFlight && !m_store->contains(playing.toStdString())))
        m_queue.prepend(playing);

    if (!m_queue.isEmpty() && !m_timer.isActive())
        m_timer.start();
}

void YtMetadataController::processNext()
{
    if (!m_inFlight.isEmpty())
        return;
    if (!enabled() || m_queue.isEmpty()) {
        m_timer.stop();
        return;
    }

    const QString path = m_queue.takeFirst();
    // Its tags: from the Queue or the list being played, else the library, else
    // read from the file on the worker. The file may be gone by now.
    const ::Track *known = m_playlist->trackForPath(path);
    if (!known && m_lookup)
        known = m_lookup(path);
    if ((known && !known->videoId.empty()) || (!known && !QFileInfo::exists(path))) {
        QTimer::singleShot(0, this, &YtMetadataController::processNext);
        return;
    }
    const ::Track tags = known ? *known : ::Track{};

    m_inFlight = path;
    emit infoChanged(path); // "pending" again if it had failed before

    m_pool.start([this, path, tags, read = !known] {
        const ::Track local = read ? Metadata::read(path.toStdString()) : tags;
        YtMetadataEntry entry;
        bool answered = false;
        if (const auto results = YtMusicClient::searchSongs(YtMatcher::searchQuery(local))) {
            answered = true;
            bool close = false;
            if (auto song = YtMatcher::bestMatch(local, *results, &close)) {
                if (const auto year = YtMusicClient::albumYear(song->albumId))
                    song->year = *year; // a missing year is not worth failing for
                entry.matched = true;
                entry.close = close;
                entry.song = std::move(*song);
            }
        }
        QMetaObject::invokeMethod(this, [this, path, answered, entry] { finish(path, answered, entry); },
                                  Qt::QueuedConnection);
    });
}

void YtMetadataController::finish(const QString &path, bool answered, const YtMetadataEntry &entry)
{
    m_inFlight.clear();

    if (answered) {
        m_failed.remove(path);
        m_consecutiveFailures = 0;
        m_store->put(path.toStdString(), entry);
        if (++m_unsaved >= 10) {
            m_store->save();
            m_unsaved = 0;
        }
    } else {
        // Offline or YouTube trouble: keep it for later and slow down.
        m_failed.insert(path);
        m_queue.append(path);
        ++m_consecutiveFailures;
    }
    m_timer.setInterval(qMin(IntervalMs << qMin(m_consecutiveFailures, 5), MaxIntervalMs));
    emit infoChanged(path);
}
