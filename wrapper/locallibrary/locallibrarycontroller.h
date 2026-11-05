#pragma once

#include "backend/library/track/track.h"
#include "wrapper/locallibrary/librarysongsmodel.h" // full type needed for the Q_PROPERTY

#include <QObject>
#include <QString>
#include <QThreadPool>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

#include <atomic>
#include <memory>
#include <unordered_map>
#include <vector>

class MusicLibrary;
class PlaylistController;
class PlaylistsController;
class QJSEngine;
class QQmlEngine;
class SettingsController;
class YtMetadataController;

// The local music library (`LocalLibraryController` singleton): every song in
// the folders the user added (Settings keeps the folders and the excluded
// ones), as Songs / Albums / Artists. Refreshed in the background on startup,
// when the folders change, and on request; only new or changed files are read.
// Playing a song adds it to the end of the Queue (unless it is already there)
// and plays it from the Queue.
class LocalLibraryController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(LibrarySongsModel *songs READ songs CONSTANT)              // Songs tab (search applied)
    Q_PROPERTY(LibrarySongsModel *detailSongs READ detailSongs CONSTANT)  // the opened album / artist
    Q_PROPERTY(QString search READ search WRITE setSearch NOTIFY searchChanged)
    Q_PROPERTY(int songCount READ songCount NOTIFY contentsChanged)       // whole library
    // Albums / Artists tabs (search and sort applied)
    Q_PROPERTY(QVariantList albums READ albums NOTIFY shownChanged)       // [{ key, album, artist, coverPath, count }]
    Q_PROPERTY(QVariantList artists READ artists NOTIFY shownChanged)     // [{ name, count }]
    Q_PROPERTY(QVariantList genres READ genres NOTIFY shownChanged)       // [{ name, count }]
    // Letter groups shown per tab (Settings > Library on, and the tab sorted by name).
    // Albums / artists / genres carry "letter" too, songs a "letter" role.
    Q_PROPERTY(bool songLetters READ songLetters NOTIFY lettersChanged)
    Q_PROPERTY(bool albumLetters READ albumLetters NOTIFY lettersChanged)
    // letterStarts() of the Songs, Albums, Artists and Genres tabs, kept up to date (for the grids)
    Q_PROPERTY(QVariantList allLetterStarts READ allLetterStarts NOTIFY shownChanged)
    Q_PROPERTY(bool artistLetters READ artistLetters NOTIFY lettersChanged)
    Q_PROPERTY(bool genreLetters READ genreLetters NOTIFY lettersChanged)
    // Songs in no genre (they aren't in `genres`)
    Q_PROPERTY(int songsWithoutGenre READ songsWithoutGenre NOTIFY contentsChanged)
    // Albums by when their newest song was added, newest first (as albums, + addedAt)
    Q_PROPERTY(QVariantList recentlyAdded READ recentlyAdded NOTIFY contentsChanged)
    Q_PROPERTY(bool loaded READ loaded NOTIFY contentsChanged)            // index read (startup)
    Q_PROPERTY(bool scanning READ scanning NOTIFY scanChanged)
    Q_PROPERTY(int scanDone READ scanDone NOTIFY scanChanged)
    Q_PROPERTY(int scanTotal READ scanTotal NOTIFY scanChanged)
    // 0 = none, 1 = album, 2 = artist, 3 = genre
    Q_PROPERTY(int detailKind READ detailKind NOTIFY detailChanged)
    Q_PROPERTY(QString detailTitle READ detailTitle NOTIFY detailChanged)
    Q_PROPERTY(QString detailSubtitle READ detailSubtitle NOTIFY detailChanged)
    Q_PROPERTY(QString detailCoverPath READ detailCoverPath NOTIFY detailChanged)

    // Folders tab, browsed like a file manager. folder "" = the music folders.
    Q_PROPERTY(QString folder READ folder NOTIFY folderChanged)
    Q_PROPERTY(QString folderTitle READ folderTitle NOTIFY folderChanged)
    Q_PROPERTY(QVariantList folderCrumbs READ folderCrumbs NOTIFY folderChanged)   // [{ name, path }] for the path bar
    Q_PROPERTY(QVariantList subfolders READ subfolders NOTIFY folderChanged)       // [{ name, path, count, location }]
    Q_PROPERTY(LibrarySongsModel *folderSongs READ folderSongs CONSTANT)           // songs right in the folder

public:
    LocalLibraryController(PlaylistController *queue, PlaylistsController *playlists, YtMetadataController *ytMetadata,
                           SettingsController *settings, QObject *parent);
    ~LocalLibraryController() override;

    static LocalLibraryController *create(QQmlEngine *qmlEngine, QJSEngine *jsEngine);

    LibrarySongsModel *songs() const { return m_songs.get(); }
    bool songLetters() const;
    bool albumLetters() const;
    bool artistLetters() const;
    bool genreLetters() const;
    // Where each letter starts in a tab's list (0 songs, 2 artists, 3 genres): { "A": 0, "B": 12, ... }
    Q_INVOKABLE QVariantMap letterStarts(int tab) const;
    QVariantList allLetterStarts() const
    {
        return {letterStarts(0), letterStarts(1), letterStarts(2), letterStarts(3)};
    }
    LibrarySongsModel *detailSongs() const { return m_detail.get(); }
    QString search() const { return m_search; }
    void setSearch(const QString &search);
    int songCount() const { return int(m_tracks.size()); }
    QVariantList albums() const { return m_shownAlbums; }
    QVariantList artists() const { return m_shownArtists; }
    QVariantList genres() const { return m_shownGenres; }
    int songsWithoutGenre() const { return m_songsWithoutGenre; }
    QVariantList recentlyAdded() const { return m_recentlyAdded; }
    bool loaded() const { return m_loaded; }
    bool scanning() const { return m_scanning; }
    int scanDone() const { return m_scanDone; }
    int scanTotal() const { return m_scanTotal; }
    int detailKind() const { return m_detailKind; }
    QString detailTitle() const { return m_detailTitle; }
    QString detailSubtitle() const { return m_detailSubtitle; }
    QString detailCoverPath() const { return m_detailCoverPath; }
    QString folder() const { return m_folder; }
    QString folderTitle() const;
    QVariantList folderCrumbs() const;
    QVariantList subfolders() const { return m_subfolders; }
    LibrarySongsModel *folderSongs() const { return m_folderSongs.get(); }

    // A library song by path (nullptr if it is not in the library).
    const Track *trackForPath(const QString &path) const;
    const std::vector<Track> &tracks() const { return m_tracks; } // the whole library

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void addFolder(const QString &folder); // path or file:// URL
    Q_INVOKABLE void removeFolder(const QString &folder);

    Q_INVOKABLE void showAlbum(const QString &key);
    Q_INVOKABLE void showArtist(const QString &name);
    Q_INVOKABLE void showGenre(const QString &name);
    Q_INVOKABLE void closeDetail();

    Q_INVOKABLE void openFolder(const QString &path); // "" = back to the music folders
    Q_INVOKABLE void folderUp();
    Q_INVOKABLE void playFolder();       // everything in the open folder, subfolders too
    Q_INVOKABLE void addFolderToQueue(); // same, to the Queue

    // The lists songs are shown in (`list` below).
    enum List { SongsList, DetailList, FolderList }; // Songs tab, opened album / artist, open folder
    Q_ENUM(List)

    // index -1 = all. play(): that list from the song (the first one for -1),
    // leaving the Queue alone.
    Q_INVOKABLE void play(int list, int index);
    Q_INVOKABLE void addToQueue(int list, int index);
    Q_INVOKABLE QVariantList items(int list, int index) const; // [{ path }] for the playlist menus
    Q_INVOKABLE QVariantList albumItems(const QString &key) const;  // [{ path }] in disc / track order
    Q_INVOKABLE void playAlbumOf(const QString &path);              // that song's album, from its first track
    Q_INVOKABLE void playAlbum(const QString &key);

    // Tag editing (local files): { title, artist, album, albumArtist, track, disc, year,
    // genre }, empty if the file can't be read. Saving runs in the background, then the
    // library, the Queue and the playlists show the new tags; tagsSaved / notice tell how it went.
    Q_INVOKABLE QVariantMap tagsOf(const QString &path) const;
    Q_INVOKABLE void saveTags(const QString &path, const QVariantMap &tags);
    Q_INVOKABLE QVariantList folderItems(const QString &path) const; // [{ path }], subfolders too, in file order

signals:
    void searchChanged();
    void contentsChanged();
    void shownChanged();
    void scanChanged();
    void detailChanged();
    void folderChanged();
    void lettersChanged();
    void notice(const QString &text);
    void tagsSaved(const QString &path, bool ok);

private:
    void startRefresh(bool loadIndexFirst);
    void setTracks(std::vector<Track> tracks);
    void applySearch();
    void rebuildDetail();
    void rebuildFolder();
    std::vector<Track> listFor(int list) const;
    std::vector<Track> folderTracks(const QString &folder, bool withSubfolders) const; // in file order

    static inline LocalLibraryController *s_instance = nullptr;

    PlaylistController *const m_queue;
    PlaylistsController *const m_playlists;
    YtMetadataController *const m_ytMetadata;
    SettingsController *const m_settings;
    std::shared_ptr<MusicLibrary> m_library; // used by the worker only
    QThreadPool m_pool;                      // one worker
    std::shared_ptr<std::atomic<bool>> m_cancel;
    bool m_refreshAgain = false;

    std::vector<Track> m_tracks; // sorted by title
    std::unordered_map<std::string, size_t> m_byPath;
    std::unique_ptr<LibrarySongsModel> m_songs;
    std::unique_ptr<LibrarySongsModel> m_detail;
    std::unique_ptr<LibrarySongsModel> m_folderSongs;
    QString m_folder;
    QVariantList m_subfolders;
    QString m_search;
    QVariantList m_albums;  // the whole library, by name
    QVariantList m_artists; // same
    QVariantList m_genres;  // same
    int m_songsWithoutGenre = 0;
    QVariantList m_shownAlbums;
    QVariantList m_shownArtists;
    QVariantList m_shownGenres;
    QVariantList m_recentlyAdded;
    bool m_loaded = false;
    bool m_scanning = false;
    int m_scanDone = 0;
    int m_scanTotal = 0;

    int m_detailKind = 0;
    QString m_detailKey; // album key or artist name
    QString m_detailTitle;
    QString m_detailSubtitle;
    QString m_detailCoverPath;
};
