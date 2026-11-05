#include "wrapper/hosted/hostedcontroller.h"

#include "backend/hosted/hostedserver/hostedserver.h"
#include "backend/hosted/hostedstore/hostedstore.h"
#include "backend/library/letterindex/letterindex.h"
#include "backend/loudness/loudnessstore/loudnessstore.h"
#include "backend/library/track/track.h"
#include "wrapper/files/files.h"
#include "wrapper/player/playercontroller.h"
#include "wrapper/playlist/playlistcontroller.h"
#include "wrapper/settings/settingscontroller.h"

#include <QJSEngine>

namespace {

constexpr int CoverSize = 300;

QString qs(const std::string &s) { return QString::fromStdString(s); }

QString letterOf(const std::string &name)
{
    return QString::fromStdString(LetterIndex::letterOf(name));
}

HostedServer::Kind kindOf(int tab)
{
    switch (tab) {
    case HostedController::AlbumsTab: return HostedServer::Kind::Albums;
    case HostedController::ArtistsTab: return HostedServer::Kind::Artists;
    case HostedController::GenresTab: return HostedServer::Kind::Genres;
    case HostedController::FoldersTab: return HostedServer::Kind::Folders;
    default: return HostedServer::Kind::Playlists;
    }
}

QString countText(int count)
{
    return count == 1 ? QObject::tr("1 song") : QObject::tr("%1 songs").arg(count);
}

} // namespace

HostedController::HostedController(PlayerController *player, PlaylistController *playlist,
                                   SettingsController *settings, QObject *parent)
    : QObject(parent)
    , m_player(player)
    , m_playlist(playlist)
    , m_settings(settings)
{
    Q_ASSERT(!s_instance);
    s_instance = this;

    m_store = std::make_shared<HostedStore>((Files::configDir() + QStringLiteral("/hosted.tsv")).toStdString());
    m_store->load();
    m_store->save(); // keeps the device id made on first start
    m_player->setHostedStore(m_store);
    m_pool.setMaxThreadCount(2);
    useAccount();

    // Play reports: in order, on their own thread; progress every 10 s while playing
    m_reportPool.setMaxThreadCount(1);
    m_reportTimer.setInterval(10000);
    connect(&m_reportTimer, &QTimer::timeout, this, [this] {
        if (!m_reportPath.isEmpty() && m_reportPlaying)
            reportPlayback(int(HostedServer::PlayEvent::Progress), m_reportPath, m_reportPosition);
    });
    connect(m_player, &PlayerController::sourceChanged, this, &HostedController::followPlayback);
    connect(m_player, &PlayerController::stateChanged, this, &HostedController::followPlayback);
    connect(m_player, &PlayerController::positionChanged, this, [this] {
        if (!m_reportPath.isEmpty() && m_player->source() == m_reportPath)
            m_reportPosition = m_player->position();
    });

    connect(m_settings, &SettingsController::letterGroupsChanged, this, &HostedController::letterTabsChanged);
    connect(m_settings, &SettingsController::hostedSortsChanged, this, &HostedController::letterTabsChanged);
    // A tab sorted differently: loaded again (the server sorts), shown ones at once
    connect(m_settings, &SettingsController::hostedSortsChanged, this, [this] {
        for (int tab = SongsTab; tab <= FoldersTab; ++tab)
            if (m_loaded[tab])
                refresh(tab);
    });
}

HostedController::~HostedController()
{
    if (m_reportStarted)
        reportPlayback(int(HostedServer::PlayEvent::Stopped), m_reportPath, m_reportPosition);
    m_reportPool.waitForDone();
    m_pool.waitForDone(); // no task may post to a destroyed object
    s_instance = nullptr;
}

HostedController *HostedController::create(QQmlEngine *, QJSEngine *)
{
    Q_ASSERT(s_instance);
    QJSEngine::setObjectOwnership(s_instance, QJSEngine::CppOwnership);
    return s_instance;
}

// Work on a worker thread, then `done` with its result here (dropped if the
// account changed meanwhile).
template<typename Work, typename Done>
void HostedController::runAsync(Work work, Done done)
{
    ++m_busy;
    emit busyChanged();
    m_pool.start([this, work, done, generation = m_generation] {
        auto result = work();
        QMetaObject::invokeMethod(this, [this, done, generation, result = std::move(result)] {
            --m_busy;
            emit busyChanged();
            if (generation == m_generation)
                done(result);
        }, Qt::QueuedConnection);
    });
}

void HostedController::setError(const QString &error)
{
    if (error == m_error)
        return;
    m_error = error;
    emit errorChanged();
}

// The first account in the store is the one shown (one server at a time for now).
void HostedController::useAccount()
{
    ++m_generation;
    const std::vector<HostedAccount> accounts = m_store->accounts();
    m_accountId = accounts.empty() ? QString() : qs(accounts.front().id);
    m_serverName = accounts.empty() ? QString() : qs(accounts.front().serverName);
    m_userName = accounts.empty() ? QString() : qs(accounts.front().userName);
    for (bool &loaded : m_loaded)
        loaded = false;
    m_songTracks.clear();
    m_songTracksAll.clear();
    m_albumsAll.clear();
    m_artistsAll.clear();
    m_genresAll.clear();
    m_playlistsAll.clear();
    m_detailTracks.clear();
    m_songs.clear();
    m_albums.clear();
    m_artists.clear();
    m_genres.clear();
    m_playlists.clear();
    m_detailSongs.clear();
    m_detailTitle.clear();
    m_detailThumbnail.clear();
    m_folderTracks.clear();
    m_folderCrumbs.clear();
    m_folderEntries.clear();
    emit accountChanged();
    emit folderChanged();
    emit listsChanged();
    emit detailChanged();
}

::Track HostedController::trackOf(const HostedSong &song) const
{
    ::Track t;
    t.path = HostedPath::make(m_accountId.toStdString(), song.id);
    t.title = song.title;
    t.artist = song.artist;
    t.album = song.album;
    t.disc = song.disc;
    t.track = song.track;
    t.durationMs = song.durationMs;
    t.thumbnailUrl = m_store->coverUrl(m_accountId.toStdString(), song.coverId, CoverSize);
    if (song.hasGain && m_loudness)
        m_loudness->putServerGain(t.path, song.gainDb); // ReplayGain for it
    // (const: the set is a cache of what the server said)
    auto &favorites = const_cast<QSet<QString> &>(m_favorites);
    if (song.favorite)
        favorites.insert(qs(t.path));
    else
        favorites.remove(qs(t.path));
    return t;
}

QVariantList HostedController::toSongList(const std::vector<::Track> &tracks) const
{
    QVariantList out;
    out.reserve(qsizetype(tracks.size()));
    for (const ::Track &t : tracks)
        out.append(QVariantMap{{QStringLiteral("path"), qs(t.path)},
                               {QStringLiteral("title"), qs(t.title)},
                               {QStringLiteral("artist"), qs(t.artist)},
                               {QStringLiteral("album"), qs(t.album)},
                               {QStringLiteral("durationMs"), qint64(t.durationMs)},
                               {QStringLiteral("thumbnail"), qs(t.thumbnailUrl)},
                               {QStringLiteral("favorite"), m_favorites.contains(qs(t.path))},
                               {QStringLiteral("letter"), letterOf(t.title)}});
    return out;
}

void HostedController::signIn(const QString &serverUrl, const QString &userName, const QString &password)
{
    setError({});
    runAsync([store = m_store, url = serverUrl.toStdString(), user = userName.toStdString(),
              password = password.toStdString()] {
                 std::string error;
                 auto account = HostedServer::signIn("jellyfin", url, user, password, store->deviceId(), error);
                 return std::make_pair(account, error);
             },
             [this](const std::pair<std::optional<HostedAccount>, std::string> &result) {
                 if (!result.first) {
                     setError(qs(result.second));
                     return;
                 }
                 for (const HostedAccount &old : m_store->accounts())
                     m_store->remove(old.id); // one server at a time (for now)
                 m_store->add(*result.first);
                 m_store->save();
                 useAccount();
                 load(SongsTab);
             });
}

void HostedController::signOut()
{
    for (const HostedAccount &account : m_store->accounts())
        m_store->remove(account.id);
    m_store->save();
    setError({});
    useAccount();
}

void HostedController::refresh(int tab)
{
    if (tab < SongsTab || tab > FoldersTab)
        return;
    m_loaded[tab] = false;
    load(tab);
}

void HostedController::load(int tab)
{
    if (!signedIn() || tab < SongsTab || tab > FoldersTab || m_loaded[tab])
        return;
    m_loaded[tab] = true;
    if (tab == FoldersTab) {
        loadFolder();
        return;
    }
    const std::optional<HostedAccount> account = m_store->account(m_accountId.toStdString());
    if (!account)
        return;

    const HostedServer::Sort sort = HostedServer::sortFromId(m_settings->hostedSorts().value(tab).toStdString());
    if (tab == SongsTab) {
        runAsync([account = *account, sort] {
                     std::unique_ptr<HostedServer> server = HostedServer::open(account);
                     auto songs = server ? server->songs(sort) : std::nullopt;
                     return std::make_pair(songs, server ? server->lastError() : std::string("Unknown server"));
                 },
                 [this](const std::pair<std::optional<std::vector<HostedSong>>, std::string> &result) {
                     if (!result.first) {
                         m_loaded[SongsTab] = false; // try again next time
                         setError(qs(result.second));
                         return;
                     }
                     setError({});
                     m_songTracksAll.clear();
                     for (const HostedSong &song : *result.first)
                         m_songTracksAll.push_back(trackOf(song));
                     applySearch();
                 });
        return;
    }

    const HostedServer::Kind kind = kindOf(tab);
    runAsync([account = *account, kind, sort] {
                 std::unique_ptr<HostedServer> server = HostedServer::open(account);
                 auto list = server ? server->collections(kind, sort) : std::nullopt;
                 return std::make_pair(list, server ? server->lastError() : std::string("Unknown server"));
             },
             [this, tab](const std::pair<std::optional<std::vector<HostedCollection>>, std::string> &result) {
                 if (!result.first) {
                     m_loaded[tab] = false;
                     setError(qs(result.second));
                     return;
                 }
                 setError({});
                 QVariantList list;
                 for (const HostedCollection &c : *result.first) {
                     QString subtitle = qs(c.subtitle);
                     if (c.songCount > 0)
                         subtitle = subtitle.isEmpty() ? countText(c.songCount)
                                                       : subtitle + QStringLiteral(" · ") + countText(c.songCount);
                     list.append(QVariantMap{
                         {QStringLiteral("id"), qs(c.id)},
                         {QStringLiteral("name"), qs(c.name)},
                         {QStringLiteral("subtitle"), subtitle},
                         {QStringLiteral("count"), c.songCount},
                         {QStringLiteral("letter"), letterOf(c.name)},
                         {QStringLiteral("thumbnail"),
                          qs(m_store->coverUrl(m_accountId.toStdString(), c.coverId, CoverSize))}});
                 }
                 if (tab == PlaylistsTab) // the favourite songs first, as a playlist
                     list.prepend(QVariantMap{{QStringLiteral("id"), QString::fromLatin1(FavoritesId)},
                                              {QStringLiteral("name"), tr("Favourites")},
                                              {QStringLiteral("subtitle"), tr("Songs with a heart")},
                                              {QStringLiteral("count"), 0},
                                              {QStringLiteral("letter"), QStringLiteral("#")},
                                              {QStringLiteral("thumbnail"), QString()}});
                 fullListOf(tab) = list;
                 applySearch();
             });
}

void HostedController::open(int tab, const QString &id, const QString &name, const QString &thumbnail)
{
    const std::optional<HostedAccount> account = m_store->account(m_accountId.toStdString());
    if (!account || tab < AlbumsTab || tab > PlaylistsTab)
        return;
    m_detailTitle = name;
    m_detailThumbnail = thumbnail;
    m_detailKind = tab;
    m_detailId = id;
    m_detailTracks.clear();
    m_detailSongs.clear();
    m_detailEntryIds.clear();
    emit detailChanged();

    const HostedServer::Kind kind = kindOf(tab);
    const bool favorites = id == QLatin1String(FavoritesId);
    runAsync([account = *account, kind, favorites, id = id.toStdString()] {
                 std::unique_ptr<HostedServer> server = HostedServer::open(account);
                 auto songs = !server ? std::nullopt
                            : favorites ? server->favorites(HostedServer::Sort::Name) : server->songsOf(kind, id);
                 return std::make_pair(songs, server ? server->lastError() : std::string("Unknown server"));
             },
             [this, name](const std::pair<std::optional<std::vector<HostedSong>>, std::string> &result) {
                 if (m_detailTitle != name)
                     return; // another one was opened meanwhile
                 if (!result.first) {
                     setError(qs(result.second));
                     return;
                 }
                 setError({});
                 m_detailTracks.clear();
                 m_detailEntryIds.clear();
                 for (const HostedSong &song : *result.first) {
                     m_detailTracks.push_back(trackOf(song));
                     m_detailEntryIds.push_back(song.entryId);
                 }
                 m_detailSongs = toSongList(m_detailTracks);
                 emit detailChanged();
             });
}

void HostedController::closeDetail()
{
    if (m_detailTitle.isEmpty())
        return;
    m_detailTitle.clear();
    m_detailThumbnail.clear();
    m_detailKind = -1;
    m_detailId.clear();
    m_detailTracks.clear();
    m_detailSongs.clear();
    m_detailEntryIds.clear();
    emit detailChanged();
}

const std::vector<::Track> &HostedController::tracksOf(int list) const
{
    return list == DetailList ? m_detailTracks : list == FolderList ? m_folderTracks : m_songTracks;
}

void HostedController::play(int list, int index)
{
    const std::vector<::Track> &tracks = tracksOf(list);
    if (index < 0 || size_t(index) >= tracks.size())
        return;
    QString title = m_serverName.isEmpty() ? tr("Hosted library") : m_serverName;
    if (list == DetailList)
        title = m_detailTitle;
    else if (list == FolderList && !m_folderCrumbs.isEmpty())
        title = m_folderCrumbs.constLast().toMap().value(QStringLiteral("name")).toString();
    m_playlist->playTitled(tracks, index, title, false);
}

void HostedController::addToQueue(int list, int index)
{
    const std::vector<::Track> &tracks = tracksOf(list);
    if (index < 0 || size_t(index) >= tracks.size())
        return;
    m_playlist->addAndPlay({tracks[size_t(index)]}, false);
    emit notice(tr("Added to the queue"));
}

void HostedController::openFolder(const QString &id, const QString &name)
{
    m_folderCrumbs.append(QVariantMap{{QStringLiteral("id"), id}, {QStringLiteral("name"), name}});
    loadFolder();
}

void HostedController::openCrumb(int index)
{
    while (m_folderCrumbs.size() > index + 1)
        m_folderCrumbs.removeLast();
    loadFolder();
}

bool HostedController::folderUp()
{
    if (m_folderCrumbs.isEmpty())
        return false;
    m_folderCrumbs.removeLast();
    loadFolder();
    return true;
}

void HostedController::loadFolder()
{
    const std::optional<HostedAccount> account = m_store->account(m_accountId.toStdString());
    if (!account)
        return;
    const int request = ++m_folderRequest;
    const std::string id = m_folderCrumbs.isEmpty()
        ? std::string() : m_folderCrumbs.constLast().toMap().value(QStringLiteral("id")).toString().toStdString();
    // Shown at once: where it is now; its contents once they come
    m_folderTracks.clear();
    m_folderEntries.clear();
    emit folderChanged();

    const HostedServer::Sort sort = HostedServer::sortFromId(m_settings->hostedSorts().value(FoldersTab).toStdString());
    runAsync([account = *account, id, sort] {
                 std::unique_ptr<HostedServer> server = HostedServer::open(account);
                 auto contents = server ? server->folder(id, sort) : std::nullopt;
                 return std::make_pair(contents, server ? server->lastError() : std::string("Unknown server"));
             },
             [this, request, top = id.empty()](
                 const std::pair<std::optional<HostedServer::FolderContents>, std::string> &result) {
                 if (request != m_folderRequest)
                     return; // another folder was opened meanwhile
                 if (!result.first) {
                     m_loaded[FoldersTab] = false;
                     setError(qs(result.second));
                     return;
                 }
                 setError({});
                 // Only one music library: straight into it
                 if (top && result.first->folders.size() == 1 && result.first->songs.empty()) {
                     const HostedCollection &only = result.first->folders.front();
                     openFolder(qs(only.id), qs(only.name));
                     return;
                 }
                 QVariantList entries;
                 for (const HostedCollection &f : result.first->folders)
                     entries.append(QVariantMap{
                         {QStringLiteral("kind"), QStringLiteral("folder")},
                         {QStringLiteral("id"), qs(f.id)},
                         {QStringLiteral("name"), qs(f.name)},
                         {QStringLiteral("subtitle"), f.songCount > 0 ? tr("%n item(s)", nullptr, f.songCount) : QString()},
                         {QStringLiteral("thumbnail"), QString()}});
                 m_folderTracks.clear();
                 for (const HostedSong &song : result.first->songs)
                     m_folderTracks.push_back(trackOf(song));
                 for (QVariant &song : toSongList(m_folderTracks)) {
                     QVariantMap map = song.toMap();
                     map.insert(QStringLiteral("kind"), QStringLiteral("song"));
                     entries.append(map);
                 }
                 m_folderEntries = entries;
                 emit folderChanged();
             });
}

void HostedController::playFolder()
{
    const std::optional<HostedAccount> account = m_store->account(m_accountId.toStdString());
    if (!account || m_folderCrumbs.isEmpty())
        return;
    const QVariantMap here = m_folderCrumbs.constLast().toMap();
    const QString name = here.value(QStringLiteral("name")).toString();
    runAsync([account = *account, id = here.value(QStringLiteral("id")).toString().toStdString()] {
                 std::unique_ptr<HostedServer> server = HostedServer::open(account);
                 auto songs = server ? server->songsOf(HostedServer::Kind::Folders, id) : std::nullopt;
                 return std::make_pair(songs, server ? server->lastError() : std::string("Unknown server"));
             },
             [this, name](const std::pair<std::optional<std::vector<HostedSong>>, std::string> &result) {
                 if (!result.first) {
                     setError(qs(result.second));
                     return;
                 }
                 std::vector<::Track> tracks;
                 for (const HostedSong &song : *result.first)
                     tracks.push_back(trackOf(song));
                 if (tracks.empty()) {
                     emit notice(tr("No songs in “%1”").arg(name));
                     return;
                 }
                 m_playlist->playTitled(std::move(tracks), 0, name, false);
             });
}

QVariantList &HostedController::listOf(int tab)
{
    switch (tab) {
    case AlbumsTab: return m_albums;
    case ArtistsTab: return m_artists;
    case GenresTab: return m_genres;
    default: return m_playlists;
    }
}

QVariantList HostedController::letterTabs() const
{
    QVariantList shown;
    const QStringList sorts = m_settings->hostedSorts();
    for (int tab = SongsTab; tab <= FoldersTab; ++tab) {
        const QString sort = sorts.value(tab);
        shown << (m_settings->letterGroups() && tab != FoldersTab
                  && (sort == QLatin1String("name") || sort == QLatin1String("nameDesc")));
    }
    return shown;
}

QVariantMap HostedController::letterStarts(int tab) const
{
    const QVariantList &list = tab == SongsTab ? m_songs
                             : tab == AlbumsTab ? m_albums
                             : tab == ArtistsTab ? m_artists
                             : tab == GenresTab ? m_genres : m_playlists;
    QVariantMap starts;
    for (int i = 0; i < list.size(); ++i) {
        const QString letter = list[i].toMap().value(QStringLiteral("letter")).toString();
        if (!starts.contains(letter))
            starts.insert(letter, i);
    }
    return starts;
}

QVariantList &HostedController::fullListOf(int tab)
{
    switch (tab) {
    case AlbumsTab: return m_albumsAll;
    case ArtistsTab: return m_artistsAll;
    case GenresTab: return m_genresAll;
    default: return m_playlistsAll;
    }
}

void HostedController::setSearch(const QString &search)
{
    if (search == m_search)
        return;
    m_search = search;
    emit searchChanged();
    applySearch();
}

// The shown lists: the full ones, filtered by the search (each word in any of the texts)
void HostedController::applySearch()
{
    const QStringList words = m_search.simplified().split(QLatin1Char(' '), Qt::SkipEmptyParts);
    const auto matches = [&words](const QString &text) {
        for (const QString &word : words)
            if (!text.contains(word, Qt::CaseInsensitive))
                return false;
        return true;
    };

    m_songTracks.clear();
    for (const ::Track &t : m_songTracksAll)
        if (words.isEmpty() || matches(qs(t.title + ' ' + t.artist + ' ' + t.album)))
            m_songTracks.push_back(t);
    m_songs = toSongList(m_songTracks);

    for (const int tab : {AlbumsTab, ArtistsTab, GenresTab, PlaylistsTab}) {
        const QVariantList &all = fullListOf(tab);
        QVariantList &shown = listOf(tab);
        shown.clear();
        for (const QVariant &entry : all) {
            const QVariantMap map = entry.toMap();
            if (words.isEmpty() || matches(map.value(QStringLiteral("name")).toString() + QLatin1Char(' ')
                                           + map.value(QStringLiteral("subtitle")).toString()))
                shown.append(entry);
        }
    }
    emit listsChanged();
}

// ---- Favourites and server playlists

void HostedController::refreshFavoriteFlags()
{
    m_songs = toSongList(m_songTracks);
    m_detailSongs = toSongList(m_detailTracks);
    for (QVariant &entry : m_folderEntries) {
        QVariantMap map = entry.toMap();
        if (map.value(QStringLiteral("kind")) == QLatin1String("song")) {
            map.insert(QStringLiteral("favorite"), m_favorites.contains(map.value(QStringLiteral("path")).toString()));
            entry = map;
        }
    }
    emit listsChanged();
    emit detailChanged();
    emit folderChanged();
}

void HostedController::setFavorite(int list, int index, bool favorite)
{
    const std::vector<::Track> &tracks = tracksOf(list);
    const std::optional<HostedAccount> account = m_store->account(m_accountId.toStdString());
    if (!account || index < 0 || size_t(index) >= tracks.size())
        return;
    const QString path = qs(tracks[size_t(index)].path);
    // Shown at once; put back if the server says no
    if (favorite)
        m_favorites.insert(path);
    else
        m_favorites.remove(path);
    refreshFavoriteFlags();
    runAsync([account = *account, id = HostedPath::songId(path.toStdString()), favorite] {
                 std::unique_ptr<HostedServer> server = HostedServer::open(account);
                 const bool ok = server && server->setFavorite(id, favorite);
                 return std::make_pair(ok, server ? server->lastError() : std::string("Unknown server"));
             },
             [this, path, favorite](const std::pair<bool, std::string> &result) {
                 if (result.first) {
                     emit notice(favorite ? tr("Added to your favourites") : tr("Removed from your favourites"));
                     if (m_detailId == QLatin1String(FavoritesId) && !favorite) // the Favourites list shows it no more
                         open(m_detailKind, m_detailId, m_detailTitle, m_detailThumbnail);
                     return;
                 }
                 if (favorite)
                     m_favorites.remove(path);
                 else
                     m_favorites.insert(path);
                 refreshFavoriteFlags();
                 emit notice(tr("Couldn't change the favourite: %1").arg(qs(result.second)));
             });
}

QVariantList HostedController::playlistChoices()
{
    if (!m_loaded[PlaylistsTab])
        load(PlaylistsTab);
    QVariantList out;
    for (const QVariant &entry : m_playlistsAll) {
        const QVariantMap map = entry.toMap();
        if (map.value(QStringLiteral("id")).toString() != QLatin1String(FavoritesId))
            out.append(QVariantMap{{QStringLiteral("id"), map.value(QStringLiteral("id"))},
                                   {QStringLiteral("name"), map.value(QStringLiteral("name"))}});
    }
    return out;
}

void HostedController::addToPlaylist(int list, int index, const QString &playlistId, const QString &playlistName)
{
    const std::vector<::Track> &tracks = tracksOf(list);
    const std::optional<HostedAccount> account = m_store->account(m_accountId.toStdString());
    if (!account || index < 0 || size_t(index) >= tracks.size() || playlistId.isEmpty())
        return;
    runAsync([account = *account, playlist = playlistId.toStdString(),
              id = HostedPath::songId(tracks[size_t(index)].path)] {
                 std::unique_ptr<HostedServer> server = HostedServer::open(account);
                 const bool ok = server && server->addToPlaylist(playlist, {id});
                 return std::make_pair(ok, server ? server->lastError() : std::string("Unknown server"));
             },
             [this, playlistName](const std::pair<bool, std::string> &result) {
                 if (!result.first) {
                     emit notice(tr("Couldn't add it: %1").arg(qs(result.second)));
                     return;
                 }
                 emit notice(tr("Added to %1").arg(playlistName));
                 if (m_loaded[PlaylistsTab])
                     refresh(PlaylistsTab); // its song count
             });
}

void HostedController::addToNewPlaylist(int list, int index, const QString &name)
{
    const std::vector<::Track> &tracks = tracksOf(list);
    const std::optional<HostedAccount> account = m_store->account(m_accountId.toStdString());
    if (!account || index < 0 || size_t(index) >= tracks.size() || name.trimmed().isEmpty())
        return;
    runAsync([account = *account, name = name.trimmed().toStdString(),
              id = HostedPath::songId(tracks[size_t(index)].path)] {
                 std::unique_ptr<HostedServer> server = HostedServer::open(account);
                 const std::string created = server ? server->createPlaylist(name, {id}) : std::string();
                 return std::make_pair(!created.empty(), server ? server->lastError() : std::string("Unknown server"));
             },
             [this, name](const std::pair<bool, std::string> &result) {
                 if (!result.first) {
                     emit notice(tr("Couldn't make the playlist: %1").arg(qs(result.second)));
                     return;
                 }
                 emit notice(tr("Made the playlist %1").arg(name.trimmed()));
                 refresh(PlaylistsTab);
             });
}

void HostedController::removeFromPlaylist(int index)
{
    const std::optional<HostedAccount> account = m_store->account(m_accountId.toStdString());
    if (!account || !detailIsPlaylist() || index < 0 || size_t(index) >= m_detailEntryIds.size()
        || m_detailEntryIds[size_t(index)].empty())
        return;
    runAsync([account = *account, playlist = m_detailId.toStdString(), entry = m_detailEntryIds[size_t(index)]] {
                 std::unique_ptr<HostedServer> server = HostedServer::open(account);
                 const bool ok = server && server->removeFromPlaylist(playlist, {entry});
                 return std::make_pair(ok, server ? server->lastError() : std::string("Unknown server"));
             },
             [this, playlist = m_detailId](const std::pair<bool, std::string> &result) {
                 if (!result.first) {
                     emit notice(tr("Couldn't remove it: %1").arg(qs(result.second)));
                     return;
                 }
                 emit notice(tr("Removed from the playlist"));
                 if (m_detailId == playlist)
                     open(m_detailKind, m_detailId, m_detailTitle, m_detailThumbnail);
                 if (m_loaded[PlaylistsTab])
                     refresh(PlaylistsTab);
             });
}

// ---- Play reports

void HostedController::followPlayback()
{
    const QString path = m_player->source();
    const bool playing = m_player->playing();
    if (path != m_reportPath || (m_reportPath.isEmpty() && HostedPath::is(path.toStdString()))) {
        if (m_reportStarted)
            reportPlayback(int(HostedServer::PlayEvent::Stopped), m_reportPath, m_reportPosition);
        m_reportPath = HostedPath::is(path.toStdString()) ? path : QString();
        m_reportStarted = false;
        m_reportPosition = 0;
    }
    if (m_reportPath.isEmpty()) {
        m_reportTimer.stop();
        return;
    }
    if (!m_reportStarted) {
        if (!playing)
            return; // loaded paused (e.g. the last session): reported once it plays
        m_reportStarted = true;
        m_reportPlaying = true;
        reportPlayback(int(HostedServer::PlayEvent::Started), m_reportPath, m_player->position());
        m_reportTimer.start();
        return;
    }
    if (playing != m_reportPlaying) {
        m_reportPlaying = playing;
        reportPlayback(int(playing ? HostedServer::PlayEvent::Resumed : HostedServer::PlayEvent::Paused), m_reportPath,
                       m_player->position());
    }
}

void HostedController::reportPlayback(int event, const QString &path, qint64 positionMs)
{
    const std::string accountId = HostedPath::accountId(path.toStdString());
    const std::optional<HostedAccount> account = m_store->account(accountId);
    if (!account)
        return;
    m_reportPool.start([account = *account, event, id = HostedPath::songId(path.toStdString()), positionMs] {
        if (std::unique_ptr<HostedServer> server = HostedServer::open(account))
            server->reportPlayback(HostedServer::PlayEvent(event), id, positionMs);
    });
}
