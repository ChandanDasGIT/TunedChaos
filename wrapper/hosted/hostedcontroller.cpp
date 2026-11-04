#include "wrapper/hosted/hostedcontroller.h"

#include "backend/hosted/hostedserver/hostedserver.h"
#include "backend/hosted/hostedstore/hostedstore.h"
#include "backend/library/track/track.h"
#include "wrapper/files/files.h"
#include "wrapper/player/playercontroller.h"
#include "wrapper/playlist/playlistcontroller.h"

#include <QJSEngine>

namespace {

constexpr int CoverSize = 300;

QString qs(const std::string &s) { return QString::fromStdString(s); }

QString countText(int count)
{
    return count == 1 ? QObject::tr("1 song") : QObject::tr("%1 songs").arg(count);
}

} // namespace

HostedController::HostedController(PlayerController *player, PlaylistController *playlist, QObject *parent)
    : QObject(parent)
    , m_player(player)
    , m_playlist(playlist)
{
    Q_ASSERT(!s_instance);
    s_instance = this;

    m_store = std::make_shared<HostedStore>((Files::configDir() + QStringLiteral("/hosted.tsv")).toStdString());
    m_store->load();
    m_store->save(); // keeps the device id made on first start
    m_player->setHostedStore(m_store);
    m_pool.setMaxThreadCount(2);
    useAccount();
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
    emit accountChanged();
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
    if (tab < SongsTab || tab > PlaylistsTab)
        return;
    m_loaded[tab] = false;
    load(tab);
}

void HostedController::load(int tab)
{
    if (!signedIn() || tab < SongsTab || tab > PlaylistsTab || m_loaded[tab])
        return;
    m_loaded[tab] = true;
    const std::optional<HostedAccount> account = m_store->account(m_accountId.toStdString());
    if (!account)
        return;

    if (tab == SongsTab) {
        runAsync([account = *account] {
                     std::unique_ptr<HostedServer> server = HostedServer::open(account);
                     auto songs = server ? server->songs() : std::nullopt;
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
    runAsync([account = *account, kind] {
                 std::unique_ptr<HostedServer> server = HostedServer::open(account);
                 auto list = server ? server->collections(kind) : std::nullopt;
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

void HostedController::play(bool detail, int index)
{
    const std::vector<::Track> &tracks = detail ? m_detailTracks : m_songTracks;
    if (index < 0 || size_t(index) >= tracks.size())
        return;
    const QString title = detail ? m_detailTitle : (m_serverName.isEmpty() ? tr("Hosted library") : m_serverName);
    m_playlist->playTitled(tracks, index, title, false);
}

void HostedController::addToQueue(bool detail, int index)
{
    const std::vector<::Track> &tracks = detail ? m_detailTracks : m_songTracks;
    if (index < 0 || size_t(index) >= tracks.size())
        return;
    m_playlist->addAndPlay({tracks[size_t(index)]}, false);
    emit notice(tr("Added to the queue"));
}
