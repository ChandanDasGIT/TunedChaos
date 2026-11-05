#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QThreadPool>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include <memory>

class LinkLibrary;
struct Track;
class PlaylistController;
class QJSEngine;
class QQmlEngine;
class SettingsController;
class YtDlpManager;
class YtMetadataController;

// Everything the YouTube Music panel shows and does (`YouTubeController`
// singleton). Songs are passed to QML as maps:
//   { videoId, title, artists, album, duration (ms), thumbnail }
// Network / yt-dlp work runs on worker threads; results arrive as property
// changes. `notice(text)` carries short messages for the panel's toast.
class YouTubeController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool available READ available NOTIFY availabilityChanged) // yt-dlp installed
    Q_PROPERTY(QString ytDlpVersion READ ytDlpVersion NOTIFY availabilityChanged)
    // Which copy runs ("app", "bundled", "system"), the last update check in words,
    // a check / download going on, and whether this build may update yt-dlp
    Q_PROPERTY(QString ytDlpSource READ ytDlpSource NOTIFY availabilityChanged)
    Q_PROPERTY(QString ytDlpStatus READ ytDlpStatus NOTIFY availabilityChanged)
    Q_PROPERTY(bool ytDlpBusy READ ytDlpBusy NOTIFY availabilityChanged)
    Q_PROPERTY(bool ytDlpCanUpdate READ ytDlpCanUpdate CONSTANT)
    Q_PROPERTY(bool signedIn READ signedIn NOTIFY signedInChanged)

    Q_PROPERTY(QVariantList searchResults READ searchResults NOTIFY searchChanged)
    Q_PROPERTY(bool searching READ searching NOTIFY searchChanged)
    Q_PROPERTY(QString searchError READ searchError NOTIFY searchChanged)
    // "songs" (searchResults), "albums" or "artists" (searchCards: { browseId, title, subtitle, thumbnail })
    Q_PROPERTY(QString searchKind READ searchKind NOTIFY searchChanged)
    Q_PROPERTY(QVariantList searchCards READ searchCards NOTIFY searchChanged)

    // [{ title, items: [{ browseId, title, subtitle, thumbnail }] }]
    Q_PROPERTY(QVariantList homeShelves READ homeShelves NOTIFY homeChanged)
    Q_PROPERTY(bool homeLoading READ homeLoading NOTIFY homeChanged)
    Q_PROPERTY(QString homeError READ homeError NOTIFY homeChanged)

    Q_PROPERTY(bool collectionOpen READ collectionOpen NOTIFY collectionChanged)
    Q_PROPERTY(QString collectionTitle READ collectionTitle NOTIFY collectionChanged)
    Q_PROPERTY(QVariantList collectionSongs READ collectionSongs NOTIFY collectionChanged)
    Q_PROPERTY(bool collectionLoading READ collectionLoading NOTIFY collectionChanged)
    Q_PROPERTY(QString collectionError READ collectionError NOTIFY collectionChanged)

    // An artist's page: top songs and shelves of cards (albums, singles, similar artists)
    Q_PROPERTY(bool artistOpen READ artistOpen NOTIFY artistChanged)
    Q_PROPERTY(QString artistName READ artistName NOTIFY artistChanged)
    Q_PROPERTY(QString artistThumbnail READ artistThumbnail NOTIFY artistChanged)
    Q_PROPERTY(QVariantList artistSongs READ artistSongs NOTIFY artistChanged)
    Q_PROPERTY(QVariantList artistShelves READ artistShelves NOTIFY artistChanged)
    Q_PROPERTY(bool artistLoading READ artistLoading NOTIFY artistChanged)
    Q_PROPERTY(QString artistError READ artistError NOTIFY artistChanged)

    Q_PROPERTY(QVariantList librarySongs READ librarySongs NOTIFY libraryChanged)
    Q_PROPERTY(bool libraryLoading READ libraryLoading NOTIFY libraryChanged)
    Q_PROPERTY(QString libraryError READ libraryError NOTIFY libraryChanged)

    Q_PROPERTY(QVariantList savedSongs READ savedSongs NOTIFY savedChanged)
    Q_PROPERTY(bool addingLink READ addingLink NOTIFY savedChanged)

public:
    YouTubeController(PlaylistController *playlist, SettingsController *settings, QObject *parent);
    // For local songs' YouTube Music matches (autoplay after them)
    void setMetadata(YtMetadataController *metadata) { m_metadata = metadata; }
    ~YouTubeController() override;

    static YouTubeController *create(QQmlEngine *qmlEngine, QJSEngine *jsEngine);

    // A song map (see above) as a playlist track ("ytmusic:<id>").
    static ::Track trackFromSong(const QVariantMap &song);

    bool available() const;
    QString ytDlpVersion() const;
    QString ytDlpSource() const;
    QString ytDlpStatus() const;
    bool ytDlpBusy() const;
    bool ytDlpCanUpdate() const;
    Q_INVOKABLE void updateYtDlp();
    bool signedIn() const;

    QVariantList searchResults() const { return m_searchResults; }
    bool searching() const { return m_searching; }
    QString searchError() const { return m_searchError; }
    QString searchKind() const { return m_searchKind; }
    QVariantList searchCards() const { return m_searchCards; }
    QVariantList homeShelves() const { return m_homeShelves; }
    bool homeLoading() const { return m_homeLoading; }
    QString homeError() const { return m_homeError; }
    bool collectionOpen() const { return m_collectionOpen; }
    QString collectionTitle() const { return m_collectionTitle; }
    QVariantList collectionSongs() const { return m_collectionSongs; }
    bool collectionLoading() const { return m_collectionLoading; }
    QString collectionError() const { return m_collectionError; }
    bool artistOpen() const { return m_artistOpen; }
    QString artistName() const { return m_artistName; }
    QString artistThumbnail() const { return m_artistThumbnail; }
    QVariantList artistSongs() const { return m_artistSongs; }
    QVariantList artistShelves() const { return m_artistShelves; }
    bool artistLoading() const { return m_artistLoading; }
    QString artistError() const { return m_artistError; }
    QVariantList librarySongs() const { return m_librarySongs; }
    bool libraryLoading() const { return m_libraryLoading; }
    QString libraryError() const { return m_libraryError; }
    QVariantList savedSongs() const;
    bool addingLink() const { return m_addingLink; }

    // kind: "songs", "albums" or "artists"
    Q_INVOKABLE void search(const QString &query, const QString &kind = QStringLiteral("songs"));
    Q_INVOKABLE void loadHome();
    Q_INVOKABLE void openCollection(const QString &browseId, const QString &title);
    Q_INVOKABLE void closeCollection();
    // A playlist / album's songs without opening it (e.g. dropped on the
    // Queue): collectionFetched(browseId, songs) once they arrive.
    Q_INVOKABLE void fetchCollection(const QString &browseId, const QString &title);
    Q_INVOKABLE void openArtist(const QString &browseId, const QString &name);
    Q_INVOKABLE void closeArtist();
    Q_INVOKABLE void loadLibrary();

    // Playing never adds to the Queue: a song plays as a Mix (YouTube's "up
    // next" after it, if autoplay is on), a list (album, playlist...) as is.
    Q_INVOKABLE void play(const QVariantMap &song);
    Q_INVOKABLE void playList(const QVariantList &songs, int index, const QString &title);
    Q_INVOKABLE void enqueue(const QVariantMap &song);    // add to the Queue
    Q_INVOKABLE void save(const QVariantMap &song);       // add to Saved
    Q_INVOKABLE void addLink(const QString &url);         // video or playlist link -> Saved
    Q_INVOKABLE void removeSaved(int index);

signals:
    void availabilityChanged();
    void signedInChanged();
    void searchChanged();
    void homeChanged();
    void collectionChanged();
    void collectionFetched(const QString &browseId, const QVariantList &songs);
    void artistChanged();
    void libraryChanged();
    void savedChanged();
    void notice(const QString &text);

private:
    template<typename Work, typename Done>
    void runAsync(Work work, Done done);

    static inline YouTubeController *s_instance = nullptr;

    void fetchMore(const QString &seedPath, bool followUp);

    PlaylistController *m_playlist;
    YtMetadataController *m_metadata = nullptr;
    SettingsController *m_settings;
    std::unique_ptr<LinkLibrary> m_links;

    YtDlpManager *m_ytDlp;

    QVariantList m_searchResults;
    bool m_searching = false;
    QString m_searchError;
    int m_searchGeneration = 0;
    QString m_searchKind = QStringLiteral("songs");
    QVariantList m_searchCards;

    QVariantList m_homeShelves;
    bool m_homeLoading = false;
    QString m_homeError;

    bool m_collectionOpen = false;
    QString m_collectionTitle;
    QVariantList m_collectionSongs;
    bool m_collectionLoading = false;
    QString m_collectionError;
    int m_collectionGeneration = 0;

    bool m_artistOpen = false;
    QString m_artistName;
    QString m_artistThumbnail;
    QVariantList m_artistSongs;
    QVariantList m_artistShelves;
    bool m_artistLoading = false;
    QString m_artistError;
    int m_artistGeneration = 0;

    QVariantList m_librarySongs;
    bool m_libraryLoading = false;
    QString m_libraryError;

    bool m_addingLink = false;

    QThreadPool m_pool;
};
