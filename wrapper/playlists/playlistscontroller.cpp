#include "wrapper/playlists/playlistscontroller.h"

#include "wrapper/files/files.h"
#include "backend/playlist/m3u/m3u.h"
#include "backend/playlist/playlistlibrary/playlistlibrary.h"
#include "wrapper/player/playercontroller.h"
#include "wrapper/playlist/playlistcontroller.h"
#include "wrapper/settings/settingscontroller.h"
#include "wrapper/youtube/youtubecontroller.h"

#include <QFileInfo>
#include <QJSEngine>
#include <QStandardPaths>
#include <QUrl>

#include <algorithm>

PlaylistsController::PlaylistsController(PlaylistController *queue, PlayerController *player,
                                         SettingsController *settings, QObject *parent)
    : QObject(parent)
    , m_queue(queue)
    , m_player(player)
    , m_settings(settings)
    , m_viewModel(std::make_unique<PlaylistModel>(m_view, nullptr))
{
    Q_ASSERT(!s_instance);
    s_instance = this;
    QJSEngine::setObjectOwnership(m_viewModel.get(), QJSEngine::CppOwnership);
    m_view.sort(Playlist::SortColumn::Custom, false);

    const QString dir = Files::dataDir()
                        + QStringLiteral("/playlists");
    m_library = std::make_unique<PlaylistLibrary>(dir.toStdString());
    m_pool.setMaxThreadCount(1);
    m_library->load();

    connect(m_player, &PlayerController::sourceChanged, this, &PlaylistsController::updateViewCurrent);
    connect(m_queue, &PlaylistController::playingFromListChanged, this, [this] {
        if (!m_queue->playingFromList() || !m_queue->contextTitle().isEmpty())
            setPlayingFrom({}); // a Queue song, or YouTube songs, were played
    });
    // The list being played from is shown: it follows (more Mix songs; it ended: back to the Queue).
    connect(m_queue, &PlaylistController::contextTracksChanged, this, [this] {
        if (viewingPlayingList())
            refreshView();
    });
    connect(m_queue, &PlaylistController::playingFromListChanged, this, [this] {
        if (viewingPlayingList())
            view(playingListId()); // (back to the Queue when none plays any more)
    });
}

PlaylistsController::~PlaylistsController()
{
    m_pool.waitForDone(); // no import may post to a destroyed object
    s_instance = nullptr;
}

PlaylistsController *PlaylistsController::create(QQmlEngine *, QJSEngine *)
{
    Q_ASSERT(s_instance);
    QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
    return s_instance;
}

QVariantList PlaylistsController::playlists() const
{
    QVariantList list;
    for (const PlaylistLibrary::Entry &entry : m_library->playlists()) {
        list.append(QVariantMap{
            {QStringLiteral("id"), QString::fromStdString(entry.id)},
            {QStringLiteral("name"), QString::fromStdString(entry.name)},
            {QStringLiteral("count"), int(entry.tracks.size())},
        });
    }
    return list;
}

QString PlaylistsController::nameOf(const QString &id) const
{
    const PlaylistLibrary::Entry *entry = m_library->find(id.toStdString());
    return entry ? QString::fromStdString(entry->name) : QString();
}

QString PlaylistsController::viewedName() const
{
    return viewingPlayingList() ? m_queue->contextTitle() : nameOf(m_viewedId);
}

QString PlaylistsController::playingFromName() const
{
    return nameOf(m_playingFromId);
}

qint64 PlaylistsController::viewedDurationMs() const
{
    qint64 total = 0;
    for (const ::Track &track : m_view.tracks())
        total += track.durationMs;
    return total;
}

void PlaylistsController::view(const QString &id)
{
    if (id == playingListId())
        m_viewedId = m_queue->contextTitle().isEmpty() ? QString() : id; // only while one plays
    else
        m_viewedId = m_library->find(id.toStdString()) ? id : QString();
    refreshView();
}

void PlaylistsController::updateTrackInfo(const ::Track &track)
{
    if (!m_library->updateTrack(track))
        return;
    refreshView();
    emit playlistsChanged();
}

void PlaylistsController::refreshView()
{
    // The playing playlist changed too: playback follows (same song keeps playing).
    if (!m_playingFromId.isEmpty() && m_playingFromId == m_viewedId)
        if (const PlaylistLibrary::Entry *playing = m_library->find(m_playingFromId.toStdString()))
            m_queue->updateListTracks(playing->tracks);

    if (viewingPlayingList()) {
        m_viewModel->setTracks(m_queue->contextTracks());
    } else {
        const PlaylistLibrary::Entry *entry = m_library->find(m_viewedId.toStdString());
        m_viewModel->setTracks(entry ? entry->tracks : std::vector<::Track>{});
    }
    updateViewCurrent();
    emit viewChanged();
}

// Marks the playing song in the viewed playlist.
void PlaylistsController::updateViewCurrent()
{
    const int previous = m_view.currentIndex();
    const int index = m_view.indexOf(m_player->source().toStdString());
    if (index >= 0)
        m_view.select(index);
    else
        m_view.deselect();
    m_viewModel->refreshCurrent(previous);
}

void PlaylistsController::playViewed(int index)
{
    if (viewingPlayingList()) {
        m_queue->playContextIndex(index);
        return;
    }
    const PlaylistLibrary::Entry *entry = m_library->find(m_viewedId.toStdString());
    if (!entry || index < 0 || size_t(index) >= entry->tracks.size())
        return;
    m_queue->playFromList(entry->tracks, index); // the Queue stays as it is
    setPlayingFrom(m_viewedId);
}

bool PlaylistsController::resumePlaylist(const QString &id, const QString &path, qint64 positionMs)
{
    const PlaylistLibrary::Entry *entry = m_library->find(id.toStdString());
    if (!entry || !m_queue->resumeFromList(entry->tracks, path, positionMs))
        return false;
    setPlayingFrom(id);
    return true;
}

void PlaylistsController::removeFromViewed(int index)
{
    if (m_viewedId.isEmpty() || viewingPlayingList())
        return;
    m_library->removeTrack(m_viewedId.toStdString(), size_t(index));
    refreshView();
    emit playlistsChanged(); // counts
}

void PlaylistsController::moveInViewed(int from, int to)
{
    if (m_viewedId.isEmpty() || viewingPlayingList() || from == to)
        return;
    m_library->moveTrack(m_viewedId.toStdString(), size_t(from), size_t(to));
    m_viewModel->moveTrack(from, to); // animated, unlike a full refresh
    if (m_viewedId == m_playingFromId)
        if (const PlaylistLibrary::Entry *playing = m_library->find(m_playingFromId.toStdString()))
            m_queue->updateListTracks(playing->tracks);
}

void PlaylistsController::addToPlaylist(const QString &id, const QVariantList &items)
{
    const std::vector<::Track> tracks = tracksFromItems(items);
    const int added = m_library->addTracks(id.toStdString(), tracks);
    if (id == m_viewedId)
        refreshView();
    else if (id == m_playingFromId)
        if (const PlaylistLibrary::Entry *playing = m_library->find(id.toStdString()))
            m_queue->updateListTracks(playing->tracks);
    emit playlistsChanged();
    if (added == 0)
        emit notice(tr("Already in “%1”").arg(nameOf(id)));
    else
        emit notice(added == 1 ? tr("Added to “%1”").arg(nameOf(id))
                               : tr("Added %1 songs to “%2”").arg(added).arg(nameOf(id)));
}

void PlaylistsController::addToQueue(const QVariantList &items)
{
    std::vector<::Track> tracks = tracksFromItems(items);
    if (tracks.empty())
        return;
    const size_t count = tracks.size();
    m_queue->addAndPlay(std::move(tracks), false);
    emit notice(count == 1 ? tr("Added to the queue") : tr("Added %1 songs to the queue").arg(count));
}

void PlaylistsController::insertItems(const QString &id, const QVariantList &items, int row)
{
    const std::vector<::Track> tracks = tracksFromItems(items);
    if (tracks.empty())
        return;
    int added = 0;
    if (id.isEmpty()) {
        added = m_queue->insertTracks(tracks, row < 0 ? m_queue->count() : row);
    } else {
        const PlaylistLibrary::Entry *entry = m_library->find(id.toStdString());
        if (!entry)
            return;
        added = m_library->insertTracks(id.toStdString(), tracks, row < 0 ? entry->tracks.size() : size_t(row));
        if (id == m_viewedId)
            refreshView();
        else if (id == m_playingFromId)
            if (const PlaylistLibrary::Entry *playing = m_library->find(id.toStdString()))
                m_queue->updateListTracks(playing->tracks);
        emit playlistsChanged();
    }
    const QString where = id.isEmpty() ? tr("the Queue") : QStringLiteral("“%1”").arg(nameOf(id));
    if (added == 0)
        emit notice(tr("Moved in %1").arg(where));
    else
        emit notice(added == 1 ? tr("Added to %1").arg(where) : tr("Added %1 songs to %2").arg(added).arg(where));
}

void PlaylistsController::playNext(const QVariantList &items)
{
    const std::vector<::Track> tracks = tracksFromItems(items);
    if (tracks.empty())
        return;
    m_queue->playNext(tracks);
    emit notice(tracks.size() == 1 ? tr("Plays next") : tr("%1 songs play next").arg(tracks.size()));
}

namespace {

QString songCount(size_t n)
{
    return n == 1 ? QObject::tr("1 song") : QObject::tr("%1 songs").arg(n);
}

QString localPath(const QString &file)
{
    return file.startsWith(QStringLiteral("file:")) ? QUrl(file).toLocalFile() : file;
}

} // namespace

void PlaylistsController::importM3u(const QString &file)
{
    const QString path = localPath(file);
    emit notice(tr("Importing “%1”…").arg(QFileInfo(path).fileName()));
    m_pool.start([this, path] {
        M3u::Result result = M3u::read(path.toStdString());
        QMetaObject::invokeMethod(this, [this, path, result = std::move(result)] {
            if (!result.ok) {
                emit notice(tr("Couldn't read “%1”").arg(QFileInfo(path).fileName()));
                return;
            }
            if (result.tracks.empty()) {
                emit notice(tr("No songs found in “%1”").arg(QFileInfo(path).fileName()));
                return;
            }
            // Named after the file; "Name (2)" if that name is taken.
            const QString base = QFileInfo(path).completeBaseName();
            QString name = base;
            for (int n = 2; std::any_of(m_library->playlists().begin(), m_library->playlists().end(),
                                        [&](const PlaylistLibrary::Entry &e) { return QString::fromStdString(e.name) == name; });
                 ++n)
                name = QStringLiteral("%1 (%2)").arg(base).arg(n);
            const std::string id = m_library->create(name.toStdString());
            m_library->addTracks(id, result.tracks);
            emit playlistsChanged();
            view(QString::fromStdString(id));

            QString text = tr("Imported %1 into “%2”").arg(songCount(result.tracks.size()), name);
            if (result.missing > 0)
                text += tr(" · %1 not found").arg(result.missing);
            emit notice(text);
        }, Qt::QueuedConnection);
    });
}

void PlaylistsController::exportM3u(const QString &id, const QString &file)
{
    QString path = localPath(file);
    if (!path.endsWith(QStringLiteral(".m3u8"), Qt::CaseInsensitive)
        && !path.endsWith(QStringLiteral(".m3u"), Qt::CaseInsensitive))
        path += QStringLiteral(".m3u8");
    const PlaylistLibrary::Entry *entry = id.isEmpty() ? nullptr : m_library->find(id.toStdString());
    if (!id.isEmpty() && !entry)
        return;
    const std::vector<::Track> &tracks = entry ? entry->tracks : m_queue->tracks();
    if (M3u::write(path.toStdString(), tracks))
        emit notice(tr("Exported %1 to “%2”").arg(songCount(tracks.size()), QFileInfo(path).fileName()));
    else
        emit notice(tr("Couldn't write “%1”").arg(QFileInfo(path).fileName()));
}

void PlaylistsController::requestNewPlaylist(const QVariantList &items)
{
    m_pending = Pending::Create;
    m_pendingTracks = tracksFromItems(items);
    emit namePrompt(tr("New playlist"), tr("My playlist"));
}

void PlaylistsController::requestRename(const QString &id)
{
    if (!m_library->find(id.toStdString()))
        return;
    m_pending = Pending::Rename;
    m_pendingId = id;
    emit namePrompt(tr("Rename playlist"), nameOf(id));
}

void PlaylistsController::requestDelete(const QString &id)
{
    if (!m_library->find(id.toStdString()))
        return;
    m_pending = Pending::Delete;
    m_pendingId = id;
    emit deletePrompt(nameOf(id));
}

void PlaylistsController::submitName(const QString &name)
{
    const QString trimmed = name.trimmed();
    const Pending pending = std::exchange(m_pending, Pending::None);
    if (trimmed.isEmpty())
        return;

    if (pending == Pending::Create) {
        const std::string id = m_library->create(trimmed.toStdString());
        if (!m_pendingTracks.empty())
            m_library->addTracks(id, m_pendingTracks);
        m_pendingTracks.clear();
        emit playlistsChanged();
        emit notice(tr("Created “%1”").arg(trimmed));
        view(QString::fromStdString(id));
    } else if (pending == Pending::Rename) {
        m_library->rename(m_pendingId.toStdString(), trimmed.toStdString());
        emit playlistsChanged();
        emit viewChanged();
        emit playingFromChanged();
    }
}

void PlaylistsController::confirmDelete()
{
    if (std::exchange(m_pending, Pending::None) != Pending::Delete)
        return;
    const QString name = nameOf(m_pendingId);
    m_library->remove(m_pendingId.toStdString());
    if (m_pendingId == m_playingFromId)
        setPlayingFrom({});
    if (m_pendingId == m_viewedId)
        view({});
    emit playlistsChanged();
    emit notice(tr("Deleted “%1”").arg(name));
}

std::vector<::Track> PlaylistsController::tracksFromItems(const QVariantList &items) const
{
    std::vector<::Track> tracks;
    for (const QVariant &item : items) {
        const QVariantMap map = item.toMap();
        const QString path = map.value(QStringLiteral("path")).toString();
        if (!path.isEmpty()) {
            if (const ::Track *track = m_queue->trackForPath(path)) {
                tracks.push_back(*track);
            } else if (const int index = m_view.indexOf(path.toStdString()); index >= 0) {
                tracks.push_back(m_view.at(size_t(index)));
            } else if (const ::Track *found = m_lookup ? m_lookup(path) : nullptr) {
                tracks.push_back(*found);
            }
        } else if (!map.value(QStringLiteral("videoId")).toString().isEmpty()) {
            tracks.push_back(YouTubeController::trackFromSong(map));
        }
    }
    return tracks;
}

void PlaylistsController::setPlayingFrom(const QString &id)
{
    if (id == m_playingFromId)
        return;
    m_playingFromId = id;
    emit playingFromChanged();
}
