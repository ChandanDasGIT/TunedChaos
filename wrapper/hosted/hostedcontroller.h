#pragma once

#include <QObject>
#include <QString>
#include <QThreadPool>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

#include <functional>
#include <memory>
#include <vector>

class HostedStore;
class PlayerController;
class PlaylistController;
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
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    // Songs: [{ path, title, artist, album, durationMs, thumbnail }]
    // Albums / artists / playlists: [{ id, name, subtitle, count, thumbnail }]
    Q_PROPERTY(QVariantList songs READ songs NOTIFY listsChanged)
    Q_PROPERTY(QVariantList albums READ albums NOTIFY listsChanged)
    Q_PROPERTY(QVariantList artists READ artists NOTIFY listsChanged)
    Q_PROPERTY(QVariantList playlists READ playlists NOTIFY listsChanged)
    // An opened album / artist / playlist
    Q_PROPERTY(bool detailOpen READ detailOpen NOTIFY detailChanged)
    Q_PROPERTY(QString detailTitle READ detailTitle NOTIFY detailChanged)
    Q_PROPERTY(QString detailThumbnail READ detailThumbnail NOTIFY detailChanged)
    Q_PROPERTY(QVariantList detailSongs READ detailSongs NOTIFY detailChanged)

public:
    enum Tab { SongsTab, AlbumsTab, ArtistsTab, PlaylistsTab };
    Q_ENUM(Tab)

    HostedController(PlayerController *player, PlaylistController *playlist, QObject *parent);
    ~HostedController() override;

    static HostedController *create(QQmlEngine *qmlEngine, QJSEngine *jsEngine);

    bool signedIn() const { return !m_accountId.isEmpty(); }
    QString serverName() const { return m_serverName; }
    QString userName() const { return m_userName; }
    bool busy() const { return m_busy > 0; }
    QString error() const { return m_error; }
    QVariantList songs() const { return m_songs; }
    QVariantList albums() const { return m_albums; }
    QVariantList artists() const { return m_artists; }
    QVariantList playlists() const { return m_playlists; }
    bool detailOpen() const { return !m_detailTitle.isEmpty(); }
    QString detailTitle() const { return m_detailTitle; }
    QString detailThumbnail() const { return m_detailThumbnail; }
    QVariantList detailSongs() const { return m_detailSongs; }

    // Jellyfin, with a user name and password (the password isn't kept).
    Q_INVOKABLE void signIn(const QString &serverUrl, const QString &userName, const QString &password);
    Q_INVOKABLE void signOut();
    Q_INVOKABLE void load(int tab);    // the tab's list, the first time it's shown
    Q_INVOKABLE void refresh(int tab); // again from the server
    Q_INVOKABLE void open(int tab, const QString &id, const QString &name, const QString &thumbnail);
    Q_INVOKABLE void closeDetail();
    // `detail`: from the opened album / artist / playlist, else from the Songs tab
    Q_INVOKABLE void play(bool detail, int index);
    Q_INVOKABLE void addToQueue(bool detail, int index);

signals:
    void accountChanged();
    void busyChanged();
    void errorChanged();
    void listsChanged();
    void detailChanged();
    void notice(const QString &text);

private:
    template<typename Work, typename Done>
    void runAsync(Work work, Done done);
    void setError(const QString &error);
    void useAccount();
    ::Track trackOf(const HostedSong &song) const;
    QVariantList toSongList(const std::vector<::Track> &tracks) const;

    static inline HostedController *s_instance = nullptr;

    PlayerController *m_player;
    PlaylistController *m_playlist;
    std::shared_ptr<HostedStore> m_store;

    QString m_accountId, m_serverName, m_userName;
    int m_busy = 0;
    int m_generation = 0; // signing in / out: answers for the account before are dropped
    QString m_error;
    bool m_loaded[4] = {};
    std::vector<::Track> m_songTracks, m_detailTracks;
    QVariantList m_songs, m_albums, m_artists, m_playlists, m_detailSongs;
    QString m_detailTitle, m_detailThumbnail;
    QThreadPool m_pool;
};
