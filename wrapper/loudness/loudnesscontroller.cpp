#include "wrapper/loudness/loudnesscontroller.h"

#include "backend/library/metadata/metadata.h"
#include "backend/library/track/track.h"
#include "backend/loudness/loudnessmeter/loudnessmeter.h"
#include "backend/loudness/loudnessstore/loudnessstore.h"
#include "wrapper/files/files.h"
#include "wrapper/locallibrary/locallibrarycontroller.h"
#include "wrapper/player/playercontroller.h"
#include "wrapper/playlist/playlistcontroller.h"
#include "wrapper/settings/settingscontroller.h"

#include <QFileInfo>
#include <QJSEngine>
#include <QThread>
#include <QTimer>

namespace {

constexpr int SaveEvery = 10; // results written to disk every so many (and on exit)

bool isLocal(const QString &path)
{
    return !path.isEmpty() && !path.startsWith(QStringLiteral("ytmusic:"));
}

} // namespace

LoudnessController::LoudnessController(PlayerController *player, PlaylistController *playlist,
                                       LocalLibraryController *library, SettingsController *settings,
                                       QObject *parent)
    : QObject(parent)
    , m_player(player)
    , m_playlist(playlist)
    , m_library(library)
    , m_settings(settings)
{
    Q_ASSERT(!s_instance);
    s_instance = this;

    // (Data, not cache: measuring everything again would cost battery.)
    m_store = std::make_shared<LoudnessStore>((Files::dataDir() + QStringLiteral("/loudness.tsv")).toStdString());
    m_store->load();
    m_player->setLoudnessStore(m_store);

    m_pool.setMaxThreadCount(1);
    m_pool.setThreadPriority(QThread::LowestPriority); // never in the way of playing or the UI

    connect(m_library, &LocalLibraryController::contentsChanged, this, &LoudnessController::rebuild);
    connect(m_settings, &SettingsController::replayGainChanged, this, &LoudnessController::rebuild);
    connect(m_player, &PlayerController::sourceChanged, this, [this] {
        // The next song first (the playing one already has its gain), then the playing one
        prioritize(m_playlist->nextPath());
        prioritize(m_player->source());
    });

    QTimer::singleShot(0, this, &LoudnessController::rebuild); // once the app is up
}

LoudnessController::~LoudnessController()
{
    m_stopping = true; // a measurement under way gives up
    m_pool.waitForDone();
    m_store->save();
    s_instance = nullptr;
}

LoudnessController *LoudnessController::create(QQmlEngine *, QJSEngine *)
{
    Q_ASSERT(s_instance);
    QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
    return s_instance;
}

bool LoudnessController::enabled() const
{
    return m_settings->replayGain() != 0;
}

// Every library song not known yet, in library order. Which ones still fit the
// file on disk is checked on the worker (a file check per song).
void LoudnessController::rebuild()
{
    const int generation = ++m_generation;
    m_queue.clear();
    m_librarySongs.clear();
    m_albumOf.clear();
    m_albums.clear();

    QStringList paths;
    for (const ::Track &track : m_library->tracks()) {
        const QString path = QString::fromStdString(track.path);
        if (!track.videoId.empty() || !isLocal(path))
            continue;
        paths << path;
        m_librarySongs.insert(path);
        if (track.album.empty())
            continue;
        // An album: its name and its album artist (else the song's artist)
        const std::string &by = track.albumArtist.empty() ? track.artist : track.albumArtist;
        const QString key = QString::fromStdString(by + '\x1f' + track.album);
        m_albumOf.insert(path, key);
        m_albums[key].emplace_back(track.path, track.durationMs);
    }
    m_songCount = int(paths.size());
    if (!enabled()) {
        m_doneCount = 0;
        emit progressChanged();
        return;
    }

    m_pool.start([this, generation, paths, store = m_store] {
        QStringList todo;
        for (const QString &path : paths)
            if (store->kind(path.toStdString()) == LoudnessStore::Kind::Unknown)
                todo << path;
        QMetaObject::invokeMethod(this, [this, generation, todo = std::move(todo)]() mutable {
            if (generation != m_generation || !enabled())
                return;
            todo.removeAll(m_inFlight); // being measured: counted when it's done
            m_doneCount = m_songCount - int(todo.size());
            const QStringList first = m_queue; // asked for meanwhile: still first
            m_queue = todo;
            for (auto it = first.crbegin(); it != first.crend(); ++it) {
                m_queue.removeAll(*it);
                m_queue.prepend(*it);
            }
            emit progressChanged();
            processNext();
        }, Qt::QueuedConnection);
    });
}

void LoudnessController::prioritize(const QString &path)
{
    if (!enabled() || !isLocal(path) || path == m_inFlight || m_store->contains(path.toStdString()))
        return;
    m_queue.removeAll(path);
    m_queue.prepend(path);
    processNext();
}

void LoudnessController::processNext()
{
    if (!m_inFlight.isEmpty() || !enabled())
        return;
    QString path;
    while (!m_queue.isEmpty() && path.isEmpty()) {
        path = m_queue.takeFirst();
        if (!QFileInfo::exists(path))
            path.clear(); // gone meanwhile
    }
    if (path.isEmpty())
        return;

    m_inFlight = path;
    emit progressChanged();
    const AlbumSongs album = m_albums.value(m_albumOf.value(path));
    m_pool.start([this, path, album, store = m_store] {
        const std::string file = path.toStdString();
        if (store->kind(file) == LoudnessStore::Kind::Unknown) {
            const ReplayGain tags = Metadata::readReplayGain(file);
            if (tags.hasTrack || tags.hasAlbum) {
                store->putTagged(file);
            } else if (const auto loudness = LoudnessMeter::measureFile(file, &m_stopping)) {
                store->putMeasured(file, *loudness);
            } else if (!m_stopping) {
                store->putFailed(file);
            }
        }
        if (!album.empty() && !m_stopping)
            store->updateAlbum(album); // the album's own level, once all its songs are measured
        QMetaObject::invokeMethod(this, [this, path] { finish(path); }, Qt::QueuedConnection);
    });
}

void LoudnessController::finish(const QString &path)
{
    m_inFlight.clear();
    if (m_librarySongs.contains(path))
        m_doneCount = qMin(m_doneCount + 1, m_songCount);
    if (++m_unsaved >= SaveEvery || m_queue.isEmpty()) {
        m_store->save();
        m_unsaved = 0;
    }
    emit progressChanged();
    m_player->loudnessMeasured(path);
    processNext();
}
