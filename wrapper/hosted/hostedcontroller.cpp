#include "wrapper/hosted/hostedcontroller.h"

#include "backend/hosted/hostedserver/hostedserver.h"
#include "backend/hosted/hostedstore/hostedstore.h"
#include "backend/library/track/track.h"
#include "wrapper/files/files.h"
#include "wrapper/player/playercontroller.h"
#include "wrapper/playlist/playlistcontroller.h"
#include "wrapper/settings/settingscontroller.h"

#include <QJSEngine>

namespace {

constexpr int CoverSize = 300;

QString qs(const std::string &s) { return QString::fromStdString(s); }

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

    // A tab sorted differently: loaded again (the server sorts), shown ones at once
    connect(m_settings, &SettingsController::hostedSortsChanged, this, [this] {
        for (int tab = SongsTab; tab <= FoldersTab; ++tab)
            if (m_loaded[tab])
                refresh(tab);
    });
}

HostedController::~HostedController()
{
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
    m_detailTracks.clear();
    m_songs.clear();
    m_albums.clear();
    m_artists.clear();
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
                               {QStringLiteral("thumbnail"), qs(t.thumbnailUrl)}});
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
                     m_songTracks.clear();
                     for (const HostedSong &song : *result.first)
                         m_songTracks.push_back(trackOf(song));
                     m_songs = toSongList(m_songTracks);
                     emit listsChanged();
                 });
        return;
    }

    const auto kind = tab == AlbumsTab ? HostedServer::Kind::Albums
                    : tab == ArtistsTab ? HostedServer::Kind::Artists : HostedServer::Kind::Playlists;
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
                         {QStringLiteral("thumbnail"),
                          qs(m_store->coverUrl(m_accountId.toStdString(), c.coverId, CoverSize))}});
                 }
                 (tab == AlbumsTab ? m_albums : tab == ArtistsTab ? m_artists : m_playlists) = list;
                 emit listsChanged();
             });
}

void HostedController::open(int tab, const QString &id, const QString &name, const QString &thumbnail)
{
    const std::optional<HostedAccount> account = m_store->account(m_accountId.toStdString());
    if (!account || tab < AlbumsTab || tab > PlaylistsTab)
        return;
    m_detailTitle = name;
    m_detailThumbnail = thumbnail;
    m_detailTracks.clear();
    m_detailSongs.clear();
    emit detailChanged();

    const auto kind = tab == AlbumsTab ? HostedServer::Kind::Albums
                    : tab == ArtistsTab ? HostedServer::Kind::Artists : HostedServer::Kind::Playlists;
    runAsync([account = *account, kind, id = id.toStdString()] {
                 std::unique_ptr<HostedServer> server = HostedServer::open(account);
                 auto songs = server ? server->songsOf(kind, id) : std::nullopt;
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
                 for (const HostedSong &song : *result.first)
                     m_detailTracks.push_back(trackOf(song));
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
    m_detailTracks.clear();
    m_detailSongs.clear();
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
