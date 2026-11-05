#pragma once

#include <QObject>
#include <QSet>
#include <QString>
#include <QTimer>
#include <QThreadPool>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

#include <functional>
#include <memory>
#include <vector>

class HostedStore;
class LoudnessStore;
class PlayerController;
class PlaylistController;
class SettingsController;
class QJSEngine;
class QQmlEngine;
struct HostedSong;
struct Track;

// Library > Hosted library (`HostedController` singleton): signing in to a
// music server (Jellyfin for now) and browsing its songs, albums, artists and
// playlists. Its songs play like any other (paths "hosted:<account>:<id>").
// One server at a time for now; the store can hold more.
class HostedController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool signedIn READ signedIn NOTIFY accountChanged)
    Q_PROPERTY(QString serverName READ serverName NOTIFY accountChanged)
    Q_PROPERTY(QString userName READ userName NOTIFY accountChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    // Filters the Songs, Albums, Artists, Genres and Playlists tabs (every word must match)
    Q_PROPERTY(QString search READ search WRITE setSearch NOTIFY searchChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    // Songs: [{ path, title, artist, album, durationMs, thumbnail }]
    // Albums / artists / playlists: [{ id, name, subtitle, count, thumbnail }]
    Q_PROPERTY(QVariantList songs READ songs NOTIFY listsChanged)
    Q_PROPERTY(QVariantList albums READ albums NOTIFY listsChanged)
    Q_PROPERTY(QVariantList artists READ artists NOTIFY listsChanged)
    Q_PROPERTY(QVariantList genres READ genres NOTIFY listsChanged)
    Q_PROPERTY(QVariantList playlists READ playlists NOTIFY listsChanged)
    // An opened album / artist / playlist
    Q_PROPERTY(bool detailOpen READ detailOpen NOTIFY detailChanged)
    Q_PROPERTY(QString detailTitle READ detailTitle NOTIFY detailChanged)
    Q_PROPERTY(QString detailThumbnail READ detailThumbnail NOTIFY detailChanged)
    Q_PROPERTY(QVariantList detailSongs READ detailSongs NOTIFY detailChanged)
    // The opened one is a server playlist (its songs can be removed from it)
    Q_PROPERTY(bool detailIsPlaylist READ detailIsPlaylist NOTIFY detailChanged)
    // Folders tab: where it is ([{ id, name }], the music libraries first; [] = the top),
    // and what's in that folder: its folders [{ kind: "folder", id, name, subtitle }]
    // first, then its songs [{ kind: "song", path, title, ... }]
    Q_PROPERTY(QVariantList folderCrumbs READ folderCrumbs NOTIFY folderChanged)
    Q_PROPERTY(QVariantList folderEntries READ folderEntries NOTIFY folderChanged)
    Q_PROPERTY(bool folderHasSongs READ folderHasSongs NOTIFY folderChanged)
    // Letter groups per tab (Settings > Library on, the tab sorted by name; not Folders).
    // Songs and lists carry a "letter".
    Q_PROPERTY(QVariantList letterTabs READ letterTabs NOTIFY letterTabsChanged)
    // letterStarts() of every tab, kept up to date (for the grids)
    Q_PROPERTY(QVariantList allLetterStarts READ allLetterStarts NOTIFY listsChanged)

public:
    enum Tab { SongsTab, AlbumsTab, ArtistsTab, GenresTab, PlaylistsTab, FoldersTab };
    Q_ENUM(Tab)
    enum List { SongsList, DetailList, FolderList }; // where a song is played from
    Q_ENUM(List)

    HostedController(PlayerController *player, PlaylistController *playlist, SettingsController *settings,
                     QObject *parent);
    ~HostedController() override;

    static HostedController *create(QQmlEngine *qmlEngine, QJSEngine *jsEngine);
    // Where the gains servers measure go (ReplayGain for their songs)
    void setLoudnessStore(std::shared_ptr<LoudnessStore> store) { m_loudness = std::move(store); }

    bool signedIn() const { return !m_accountId.isEmpty(); }
    QString serverName() const { return m_serverName; }
    QString userName() const { return m_userName; }
    bool busy() const { return m_busy > 0; }
    QString error() const { return m_error; }
    QString search() const { return m_search; }
    void setSearch(const QString &search);
    QVariantList songs() const { return m_songs; }
    QVariantList albums() const { return m_albums; }
    QVariantList artists() const { return m_artists; }
    QVariantList genres() const { return m_genres; }
    QVariantList letterTabs() const;
    // Where each letter starts in a tab's list: { "A": 0, "B": 12, ... }
    Q_INVOKABLE QVariantMap letterStarts(int tab) const;
    QVariantList allLetterStarts() const
    {
        QVariantList out;
        for (int tab = SongsTab; tab <= FoldersTab; ++tab)
            out.append(letterStarts(tab));
        return out;
    }
    QVariantList playlists() const { return m_playlists; }
    bool detailOpen() const { return !m_detailTitle.isEmpty(); }
    QString detailTitle() const { return m_detailTitle; }
    QString detailThumbnail() const { return m_detailThumbnail; }
    QVariantList detailSongs() const { return m_detailSongs; }
    bool detailIsPlaylist() const { return m_detailKind == PlaylistsTab && m_detailId != QLatin1String(FavoritesId); }
    QVariantList folderCrumbs() const { return m_folderCrumbs; }
    QVariantList folderEntries() const { return m_folderEntries; }
    bool folderHasSongs() const { return !m_folderTracks.empty(); }

    // Jellyfin, with a user name and password (the password isn't kept).
    Q_INVOKABLE void signIn(const QString &serverUrl, const QString &userName, const QString &password);
    Q_INVOKABLE void signOut();
    Q_INVOKABLE void load(int tab);    // the tab's list, the first time it's shown
    Q_INVOKABLE void refresh(int tab); // again from the server
    Q_INVOKABLE void open(int tab, const QString &id, const QString &name, const QString &thumbnail);
    Q_INVOKABLE void closeDetail();
    // `list`: List; for FolderList, `index` counts the folder's songs only
    Q_INVOKABLE void play(int list, int index);
    Q_INVOKABLE void addToQueue(int list, int index);
    // Folders tab
    Q_INVOKABLE void openFolder(const QString &id, const QString &name);
    Q_INVOKABLE void openCrumb(int index); // -1: the top (the music libraries)
    Q_INVOKABLE bool folderUp();          // false: already at the top
    Q_INVOKABLE void playFolder();        // every song under the open folder, subfolders too
    // A song of a list (as for play): favourite on the server or not
    Q_INVOKABLE void setFavorite(int list, int index, bool favorite);
    // ... to a server playlist (`playlistId` from the Playlists tab), or to a new one
    Q_INVOKABLE void addToPlaylist(int list, int index, const QString &playlistId, const QString &playlistName);
    Q_INVOKABLE void addToNewPlaylist(int list, int index, const QString &name);
    // From the opened playlist (DetailList)
    Q_INVOKABLE void removeFromPlaylist(int index);
    // The server playlists to add to: [{ id, name }] (loads them if needed)
    Q_INVOKABLE QVariantList playlistChoices();
    // The Favourites list's id in the Playlists tab
    static constexpr const char *FavoritesId = "@favorites";

signals:
    void accountChanged();
    void searchChanged();
    void busyChanged();
    void errorChanged();
    void listsChanged();
    void detailChanged();
    void folderChanged();
    void letterTabsChanged();
    void notice(const QString &text);

private:
    template<typename Work, typename Done>
    void runAsync(Work work, Done done);
    void setError(const QString &error);
    void useAccount();
    ::Track trackOf(const HostedSong &song) const;
    QVariantList toSongList(const std::vector<::Track> &tracks) const;
    void loadFolder(); // what's in the folder of m_folderCrumbs' end (the top if none)
    const std::vector<::Track> &tracksOf(int list) const;
    void refreshFavoriteFlags(); // the song lists' "favorite" after a change
    // Play reports to the server of the song playing (in order, on their own thread)
    void reportPlayback(int event, const QString &path, qint64 positionMs);
    void followPlayback();
    QString m_reportPath;    // the hosted song reported as playing ("" = none)
    bool m_reportPlaying = false;
    bool m_reportStarted = false; // Started was sent for m_reportPath
    qint64 m_reportPosition = 0;
    QTimer m_reportTimer;
    QThreadPool m_reportPool;
    QSet<QString> m_favorites; // paths of favourite songs
    int m_detailKind = -1;     // the opened one's tab, and its id
    QString m_detailId;
    std::vector<std::string> m_detailEntryIds; // playlist entries, as detailSongs

    static inline HostedController *s_instance = nullptr;

    PlayerController *m_player;
    PlaylistController *m_playlist;
    SettingsController *m_settings;
    std::shared_ptr<HostedStore> m_store;
    std::shared_ptr<LoudnessStore> m_loudness;

    QString m_accountId, m_serverName, m_userName;
    int m_busy = 0;
    int m_generation = 0; // signing in / out: answers for the account before are dropped
    QString m_error;
    bool m_loaded[6] = {};
    std::vector<::Track> m_songTracks, m_detailTracks, m_folderTracks;
    QVariantList m_folderCrumbs, m_folderEntries;
    int m_folderRequest = 0; // the folder asked for last (older answers are dropped)
    QVariantList m_songs, m_albums, m_artists, m_genres, m_playlists, m_detailSongs;
    QVariantList &listOf(int tab); // a tab's list of albums / artists / genres / playlists (shown)
    QVariantList &fullListOf(int tab); // the same, before the search
    void applySearch();
    QString m_search;
    std::vector<::Track> m_songTracksAll;
    QVariantList m_albumsAll, m_artistsAll, m_genresAll, m_playlistsAll;
    QString m_detailTitle, m_detailThumbnail;
    QThreadPool m_pool;
};
