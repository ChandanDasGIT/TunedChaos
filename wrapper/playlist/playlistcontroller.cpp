#include "wrapper/playlist/playlistcontroller.h"

#include "wrapper/files/files.h"
#include "backend/playlist/playliststore/playliststore.h"
#include "backend/youtube/streamresolver/streamresolver.h"
#include "wrapper/player/playercontroller.h"
#include "wrapper/settings/settingscontroller.h"

#include <QJSEngine>

#include <algorithm>
#include <QStandardPaths>

namespace {

// "Previous" restarts the track instead when it has played longer than this.
constexpr qint64 RestartThresholdMs = 3000;

Playlist::SortColumn toBackend(int column)
{
    return Playlist::SortColumn(qBound(0, column, int(Playlist::SortColumn::Custom)));
}

Playlist::RepeatMode toBackendRepeat(int mode)
{
    return Playlist::RepeatMode(qBound(0, mode, int(Playlist::RepeatMode::One)));
}

} // namespace

PlaylistController::PlaylistController(PlayerController *player, SettingsController *settings,
                                       QObject *parent)
    : QObject(parent)
    , m_player(player)
    , m_settings(settings)
    , m_model(std::make_unique<PlaylistModel>(m_playlist, nullptr))
{
    Q_ASSERT(!s_instance);
    s_instance = this;
    QJSEngine::setObjectOwnership(m_model.get(), QJSEngine::CppOwnership);

    m_storePath = Files::dataDir()
                  + QStringLiteral("/playlist.tsv");
    m_titledStorePath = Files::dataDir()
                         + QStringLiteral("/playing-list.tsv");

    // Restore the last session (before QML exists, so no model signals are needed).
    m_playlist.sort(toBackend(m_settings->sortColumn()), m_settings->sortDescending());
    for (Playlist *list : {&m_playlist, &m_context}) {
        list->setRepeatMode(toBackendRepeat(m_settings->repeatMode()));
        list->setShuffle(m_settings->shuffle());
    }
    m_context.sort(Playlist::SortColumn::Custom, false);
    if (m_settings->restorePlaylist())
        m_playlist.setTracks(PlaylistStore::load(m_storePath.toStdString()));

    connect(m_player, &PlayerController::trackChanged, this, &PlaylistController::onTrackChanged);
    connect(m_player, &PlayerController::trackFinished, this, &PlaylistController::onTrackFinished);
    // The song kept from a cleared Queue was stopped or replaced: forget it.
    connect(m_player, &PlayerController::sourceChanged, this, [this] {
        if (m_detached && !detachedTrack()) {
            m_detached.reset();
            emit currentChanged();
        }
    });
    connect(m_settings, &SettingsController::fadeSecondsChanged, this, &PlaylistController::queueNext);
}

PlaylistController::~PlaylistController()
{
    save();
    s_instance = nullptr;
}

PlaylistController *PlaylistController::create(QQmlEngine *, QJSEngine *)
{
    Q_ASSERT(s_instance);
    QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
    return s_instance;
}

const ::Track *PlaylistController::currentTrack() const
{
    const int i = m_active->currentIndex();
    if (i >= 0)
        return &m_active->at(size_t(i));
    return detachedTrack();
}

// The song still playing from a cleared Queue, if it is still the one loaded.
const ::Track *PlaylistController::detachedTrack() const
{
    const bool playing = m_detached && m_active == &m_playlist
                         && m_player->source() == QString::fromStdString(m_detached->path);
    return playing ? &*m_detached : nullptr;
}

QString PlaylistController::currentTitle() const
{
    const ::Track *track = currentTrack();
    return track ? QString::fromStdString(track->title) : QString();
}

QString PlaylistController::currentSubtitle() const
{
    const ::Track *track = currentTrack();
    return track ? PlaylistModel::artistAlbum(*track) : QString();
}

QString PlaylistController::currentThumbnail() const
{
    const ::Track *track = currentTrack();
    return track ? QString::fromStdString(track->thumbnailUrl) : QString();
}

// Queue first, then the playlist being played from.
const ::Track *PlaylistController::trackForPath(const QString &path) const
{
    for (const Playlist *list : {&m_playlist, &m_context}) {
        const int index = list->indexOf(path.toStdString());
        if (index >= 0)
            return &list->at(size_t(index));
    }
    if (const ::Track *detached = detachedTrack(); detached && detached->path == path.toStdString())
        return detached;
    return nullptr;
}

void PlaylistController::addAndPlay(std::vector<::Track> tracks, bool play)
{
    if (tracks.empty())
        return;
    const std::string first = tracks.front().path;
    addTracks(std::move(tracks));
    save();
    if (play)
        playIndex(m_playlist.indexOf(first));
}

void PlaylistController::playNext(const std::vector<::Track> &tracks)
{
    if (tracks.empty())
        return;
    if (m_active == &m_playlist)
        setQueueCustomOrder(); // songs are placed by hand now
    int placed = 0;
    for (const ::Track &track : tracks) {
        placeNext(*m_active, track, placed);
        ++placed;
    }
    if (m_active == &m_playlist) {
        emit countChanged();
        save();
    }
    emit currentChanged(); // hasNext / upcoming changed
    queueNext();
}

// Moves (or adds) `track` to the slot `placed` songs after the playing one.
// The Queue goes through its model so the view follows; the playlist being
// played from is only a copy for playback (the saved playlist is unchanged).
void PlaylistController::placeNext(Playlist &list, const ::Track &track, int placed)
{
    const bool viaModel = &list == &m_playlist;
    const int current = list.currentIndex();
    int existing = list.indexOf(track.path);
    if (existing >= 0 && existing == current)
        return; // the playing song itself
    if (existing < 0) {
        if (viaModel)
            m_model->appendTrack(track);
        else
            list.append(track);
        existing = list.indexOf(track.path);
        if (existing < 0)
            return;
    }
    // Where it ends up once taken out of its old slot.
    const int target = (existing < current ? current : current + 1) + placed;
    if (target == existing || target >= int(list.size()))
        return;
    if (viaModel)
        m_model->moveTrack(existing, target);
    else
        list.move(size_t(existing), size_t(target));
}

void PlaylistController::playFromList(std::vector<::Track> tracks, int startIndex)
{
    startContext(std::move(tracks), startIndex, QString(), false);
}

void PlaylistController::playTitled(std::vector<::Track> tracks, int startIndex, const QString &title, bool endless)
{
    startContext(std::move(tracks), startIndex, title, endless);
    saveTitledContext();
}

void PlaylistController::startContext(std::vector<::Track> tracks, int startIndex, const QString &title, bool endless,
                                      bool load)
{
    if (startIndex < 0 || size_t(startIndex) >= tracks.size())
        return;

    // The Queue stops showing a playing row; it is otherwise untouched.
    const int previousQueueRow = m_playlist.currentIndex();
    m_playlist.deselect();
    m_model->refreshCurrent(previousQueueRow);

    m_context.setTracks(std::move(tracks));
    m_context.select(startIndex);
    m_contextTitle = title;
    m_contextEndless = endless;
    m_moreRequested = false;
    m_waitingForMore = false;
    m_followUp.clear();
    m_active = &m_context;
    emit playingFromListChanged(); // also when only the title changed
    emit currentChanged();
    if (load)
        loadCurrent();
    else
        queueNext();
}

void PlaylistController::extendList(const std::vector<::Track> &tracks)
{
    if (m_active != &m_context || !m_contextEndless)
        return;
    int added = 0;
    for (const ::Track &track : tracks) {
        if (m_context.indexOf(track.path) < 0) {
            m_context.append(track);
            ++added;
        }
    }
    if (added == 0)
        return; // nothing new: don't keep asking
    m_moreRequested = false;
    saveTitledContext();
    emit currentChanged(); // hasNext / upcoming changed
    if (m_waitingForMore) {
        m_waitingForMore = false;
        next();
    } else {
        queueNext();
    }
}

void PlaylistController::setFollowUp(std::vector<::Track> tracks, const QString &title)
{
    if (m_active != &m_playlist || tracks.empty())
        return;
    m_followUp = std::move(tracks);
    m_followUpTitle = title;
    if (m_waitingForMore) {
        startFollowUp(true);
        return;
    }
    emit currentChanged(); // hasNext
    queueNext();
}

// The Queue is over: its Mix takes over (`load` false: already playing its first song).
void PlaylistController::startFollowUp(bool load)
{
    std::vector<::Track> tracks = std::move(m_followUp);
    m_followUp.clear();
    startContext(std::move(tracks), 0, m_followUpTitle, true, load);
    saveTitledContext();
}

void PlaylistController::saveTitledContext() const
{
    if (m_active == &m_context && !m_contextTitle.isEmpty())
        PlaylistStore::save(m_titledStorePath.toStdString(), m_context.tracks());
}

bool PlaylistController::hasNext() const
{
    return m_active->nextIndex() >= 0 || (m_active == &m_playlist && !m_followUp.empty());
}

void PlaylistController::updateTrackInfo(const ::Track &track)
{
    const int row = m_playlist.updateTrack(track);
    m_model->refreshRow(row);
    const int inList = m_context.updateTrack(track);
    if (row >= 0)
        save();
    if (row >= 0 || inList >= 0)
        emit currentChanged(); // the playing song's title may have changed
}

void PlaylistController::updateListTracks(std::vector<::Track> tracks)
{
    const ::Track *current = m_context.currentIndex() >= 0 ? &m_context.at(size_t(m_context.currentIndex())) : nullptr;
    const std::string currentPath = current ? current->path : std::string();

    m_context.setTracks(std::move(tracks));
    if (const int index = m_context.indexOf(currentPath); index >= 0)
        m_context.select(index);
    if (m_active == &m_context) {
        emit currentChanged();
        queueNext();
    }
}

void PlaylistController::activateQueue()
{
    m_waitingForMore = false;
    if (m_active == &m_playlist)
        return;
    m_context.deselect();
    m_active = &m_playlist;
    m_contextTitle.clear();
    m_contextEndless = false;
    m_moreRequested = false;
    emit playingFromListChanged();
}

void PlaylistController::setShuffle(bool shuffle)
{
    if (shuffle == m_playlist.shuffle())
        return;
    m_playlist.setShuffle(shuffle);
    m_context.setShuffle(shuffle);
    m_settings->setShuffle(shuffle);
    emit shuffleChanged();
    emit currentChanged(); // hasNext
    queueNext();
}

void PlaylistController::setRepeatMode(RepeatMode mode)
{
    if (mode == repeatMode())
        return;
    m_playlist.setRepeatMode(toBackendRepeat(mode));
    m_context.setRepeatMode(toBackendRepeat(mode));
    m_settings->setRepeatMode(int(mode));
    emit repeatModeChanged();
    emit currentChanged(); // hasNext
    queueNext();
}

void PlaylistController::cycleRepeatMode()
{
    setRepeatMode(RepeatMode((int(repeatMode()) + 1) % 3));
}

int PlaylistController::addTracks(std::vector<::Track> tracks, std::vector<std::string> *addedPaths)
{
    // The batch in album / disc / track order, then appended after the last song.
    Playlist batch;
    batch.setTracks(std::move(tracks)); // default sort: album, disc, track

    int added = 0;
    for (const ::Track &track : batch.tracks()) {
        if (m_model->appendTrack(track)) {
            ++added;
            if (addedPaths)
                addedPaths->push_back(track.path);
        }
    }

    if (added > 0) {
        setQueueCustomOrder();
        emit countChanged();
        emit currentChanged(); // hasNext may have changed
        queueNext();           // e.g. the last track was playing and now there is a next one
    }
    return added;
}

int PlaylistController::insertTracks(const std::vector<::Track> &tracks, int row)
{
    if (tracks.empty())
        return 0;
    setQueueCustomOrder(); // songs are placed by hand now
    int at = std::clamp(row, 0, count());
    int added = 0;
    for (const ::Track &track : tracks) {
        const int existing = m_playlist.indexOf(track.path);
        if (existing < 0) {
            if (m_model->insertTrack(at, track)) {
                ++added;
                ++at;
            }
            continue;
        }
        // Where it ends up once taken out of its old slot.
        const int target = existing < at ? at - 1 : at;
        m_model->moveTrack(existing, target);
        at = target + 1;
    }
    emit countChanged();
    emit currentChanged(); // hasNext / upcoming changed
    queueNext();
    save();
    return added;
}

void PlaylistController::setQueueCustomOrder()
{
    if (m_playlist.sortColumn() == Playlist::SortColumn::Custom)
        return;
    m_playlist.sort(Playlist::SortColumn::Custom, false); // keeps the current order
    m_settings->setSort(int(Playlist::SortColumn::Custom), false);
    emit sortChanged();
}

void PlaylistController::playFirstIfIdle(const std::vector<std::string> &paths)
{
    if (m_player->state() != PlayerController::Stopped)
        return; // playing or paused: don't interrupt

    int first = -1;
    for (const std::string &path : paths) {
        const int index = m_playlist.indexOf(path);
        if (index >= 0 && (first < 0 || index < first))
            first = index;
    }
    if (first >= 0)
        playIndex(first);
}

void PlaylistController::save() const
{
    PlaylistStore::save(m_storePath.toStdString(), m_playlist.tracks());
}

void PlaylistController::playIndex(int index)
{
    if (index < 0 || index >= count())
        return;
    activateQueue();
    changeCurrent([&] { m_playlist.select(index); });
    loadCurrent();
}

void PlaylistController::removeIndex(int index)
{
    if (index < 0 || index >= count())
        return;

    // Only the Queue's playing row counts here (while playing from a playlist, there is none).
    const bool removingCurrent = m_active == &m_playlist && index == m_playlist.currentIndex();
    QString continueWith;
    if (removingCurrent && m_player->playing()) {
        const int next = m_playlist.nextIndex();
        if (next >= 0 && next != index)
            continueWith = pathAt(next);
    }

    m_model->removeTrack(index);
    emit countChanged();

    if (!removingCurrent) {
        emit currentChanged(); // hasNext may have changed
        queueNext();
    } else if (!continueWith.isEmpty()) {
        playIndex(m_playlist.indexOf(continueWith.toStdString()));
    } else {
        m_player->unload();
        emit currentChanged();
    }
    save();
}

void PlaylistController::moveIndex(int from, int to)
{
    if (from < 0 || to < 0 || from >= count() || to >= count() || from == to)
        return;
    setQueueCustomOrder();
    m_model->moveTrack(from, to);
    emit currentChanged(); // hasNext / upcoming may have changed
    queueNext();
    save();
}

void PlaylistController::clear()
{
    if (count() == 0)
        return;
    // The playing song keeps playing (also from the Queue); nothing follows it.
    if (m_active == &m_playlist) {
        if (const ::Track *track = currentTrack(); track && m_player->hasTrack())
            m_detached = *track;
        m_player->setNext(QString());
    }
    m_model->clear();
    emit countChanged();
    emit currentChanged();
    save();
}

QString PlaylistController::pathAt(int index) const
{
    return index >= 0 && index < count() ? QString::fromStdString(m_playlist.at(size_t(index)).path)
                                         : QString();
}

void PlaylistController::playPause()
{
    if (m_player->hasTrack())
        m_player->togglePlayPause();
    else if (m_active->currentIndex() >= 0)
        loadCurrent();
    else if (count() > 0)
        playIndex(0);
}

void PlaylistController::next()
{
    if (m_active->nextIndex() < 0) {
        if (m_active == &m_playlist && !m_followUp.empty())
            startFollowUp(true);
        return;
    }
    changeCurrent([&] { m_active->goNext(); });
    loadCurrent();
}

void PlaylistController::previous()
{
    if (m_active->previousIndex() < 0 || m_player->position() > RestartThresholdMs) {
        m_player->seek(0);
        return;
    }
    changeCurrent([&] { m_active->goPrevious(); });
    loadCurrent();
}

void PlaylistController::sortBy(int column)
{
    const Playlist::SortColumn sortColumn = toBackend(column);
    const bool descending = sortColumn == m_playlist.sortColumn() ? !m_playlist.sortDescending() : false;

    m_model->sortBy(sortColumn, descending);
    m_settings->setSort(int(sortColumn), descending);
    emit sortChanged();
    emit currentChanged();
    queueNext();
    save();
}

void PlaylistController::changeCurrent(const std::function<void()> &change)
{
    const int previousQueueRow = m_playlist.currentIndex();
    change();
    m_model->refreshCurrent(previousQueueRow);
    emit currentChanged();
}

void PlaylistController::loadCurrent(qint64 startMs, bool paused)
{
    const ::Track *track = currentTrack();
    if (!track || track == detachedTrack())
        return;
    m_detached.reset();
    if (paused)
        m_player->loadPaused(QString::fromStdString(track->path), startMs);
    else
        m_player->load(QString::fromStdString(track->path));
    queueNext();
}

bool PlaylistController::resumeInQueue(const QString &path, qint64 positionMs)
{
    const int index = m_playlist.indexOf(path.toStdString());
    if (index < 0)
        return false;
    activateQueue();
    changeCurrent([&] { m_playlist.select(index); });
    loadCurrent(positionMs, true);
    return true;
}

bool PlaylistController::resumeFromList(std::vector<::Track> tracks, const QString &path, qint64 positionMs)
{
    // As playFromList(), but loaded paused at the saved position.
    const bool found = std::any_of(tracks.begin(), tracks.end(),
                                   [&](const ::Track &track) { return track.path == path.toStdString(); });
    if (!found)
        return false;
    const int previousQueueRow = m_playlist.currentIndex();
    m_playlist.deselect();
    m_model->refreshCurrent(previousQueueRow);
    m_context.setTracks(std::move(tracks));
    m_context.select(m_context.indexOf(path.toStdString()));
    m_contextTitle.clear();
    m_contextEndless = false;
    m_moreRequested = false;
    m_active = &m_context;
    emit playingFromListChanged();
    emit currentChanged();
    loadCurrent(positionMs, true);
    return true;
}

bool PlaylistController::resumeTitled(const QString &path, qint64 positionMs, const QString &title, bool endless)
{
    std::vector<::Track> tracks = PlaylistStore::load(m_titledStorePath.toStdString());
    const auto it = std::find_if(tracks.begin(), tracks.end(),
                                 [&](const ::Track &track) { return track.path == path.toStdString(); });
    if (it == tracks.end() || title.isEmpty())
        return false;
    const int index = int(it - tracks.begin());
    startContext(std::move(tracks), index, title, endless, false);
    loadCurrent(positionMs, true);
    return true;
}

bool PlaylistController::resumeAlone(const ::Track &track, qint64 positionMs)
{
    if (track.path.empty())
        return false;
    activateQueue();
    m_detached = track; // shown as the current song, like after clearing the Queue
    m_player->loadPaused(QString::fromStdString(track.path), positionMs);
    emit currentChanged();
    return true;
}

QString PlaylistController::nextPath() const
{
    if (m_active->currentIndex() < 0)
        return {};
    if (const int next = m_active->nextIndex(); next >= 0)
        return QString::fromStdString(m_active->at(size_t(next)).path);
    if (m_active == &m_playlist && !m_followUp.empty())
        return QString::fromStdString(m_followUp.front().path);
    return {};
}

void PlaylistController::queueNext()
{
    const int current = m_active->currentIndex();
    if (!m_player->hasTrack() || current < 0)
        return;
    checkRunningOut();

    const int next = m_active->repeatMode() == Playlist::RepeatMode::One ? current : m_active->nextIndex();
    const ::Track &from = m_active->at(size_t(current));
    // The Queue ends here: on into its Mix, if one is waiting.
    const ::Track *to = next >= 0 ? &m_active->at(size_t(next))
                      : m_active == &m_playlist && !m_followUp.empty() ? &m_followUp.front()
                                                                         : nullptr;
    if (!to) {
        m_player->setNext(QString());
        return;
    }
    m_player->setNext(QString::fromStdString(to->path), continuesAlbum(from, *to) ? 0 : m_settings->fadeSeconds() * 1000);
}

// Near the end of a Mix (or of the Queue, on a YouTube song): asks once for
// what YouTube plays next.
void PlaylistController::checkRunningOut()
{
    const int current = m_active->currentIndex();
    if (current < 0 || m_active->repeatMode() == Playlist::RepeatMode::One)
        return;
    QString seed;
    if (m_active == &m_context) {
        const int left = int(m_context.size()) - 1 - current;
        const bool nearEnd = m_context.shuffle() ? m_context.nextIndex() < 0 : left <= 2;
        if (!m_contextEndless || m_moreRequested || !nearEnd)
            return;
        // The Mix goes on from where the list ends (an album: its last song).
        seed = QString::fromStdString(m_context.at(m_context.size() - 1).path);
    } else {
        if (m_playlist.nextIndex() >= 0) { // more Queue to come (again)
            m_followUp.clear();
            m_moreRequested = false;
            return;
        }
        const ::Track &track = m_playlist.at(size_t(current));
        if (!m_settings->ytQueueMix() || m_moreRequested || !m_followUp.empty()
            || !StreamResolver::isYouTube(track.path))
            return;
        seed = QString::fromStdString(track.path);
    }
    m_moreRequested = true;
    emit moreWanted(seed, m_active == &m_playlist);
}

// The next track follows straight on in the same album (live or concept albums
// run songs into each other): play those gaplessly, never fade them.
bool PlaylistController::continuesAlbum(const ::Track &from, const ::Track &to)
{
    return !from.album.empty() && from.album == to.album && from.disc == to.disc && from.track > 0
           && to.track == from.track + 1;
}

// The player continued gaplessly with the queued track.
void PlaylistController::onTrackChanged(const QString &path)
{
    if (m_active == &m_playlist && !m_followUp.empty() && path.toStdString() == m_followUp.front().path) {
        startFollowUp(false); // the Queue ended and the player went on into its Mix
        return;
    }
    changeCurrent([&] { m_active->follow(path.toStdString()); });
    queueNext();
}

// Reached the end with nothing queued (or the queued file failed to open).
void PlaylistController::onTrackFinished()
{
    if (m_active->repeatMode() == Playlist::RepeatMode::One && m_active->currentIndex() >= 0)
        loadCurrent();
    else if (m_active->nextIndex() >= 0 || (m_active == &m_playlist && !m_followUp.empty()))
        next();
    else if (m_moreRequested)
        m_waitingForMore = true; // more songs are on the way: they start playing when they come
}
