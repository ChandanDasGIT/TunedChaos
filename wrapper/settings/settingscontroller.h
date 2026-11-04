#pragma once

#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

#include <memory>

class QJSEngine;
class QQmlEngine;
class Settings;

// Persistent user settings (`SettingsController` singleton), stored in
// ~/.config/TunedChaos/settings.conf. Changes are saved shortly after
// they happen (debounced) and on exit.
class SettingsController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(qreal volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool playlistPinned READ playlistPinned WRITE setPlaylistPinned NOTIFY playlistPinnedChanged)
    // The YouTube and Library panels share the right-hand column: pinning one unpins the other.
    Q_PROPERTY(bool youtubePanelPinned READ youtubePanelPinned WRITE setYoutubePanelPinned NOTIFY youtubePanelPinnedChanged)
    Q_PROPERTY(bool libraryPanelPinned READ libraryPanelPinned WRITE setLibraryPanelPinned NOTIFY libraryPanelPinnedChanged)
    // Home, YouTube Music and the Library share a column: at most one of them is pinned.
    Q_PROPERTY(bool homePanelPinned READ homePanelPinned WRITE setHomePanelPinned NOTIFY homePanelPinnedChanged)
    Q_PROPERTY(int artistAlbumWidth READ artistAlbumWidth WRITE setArtistAlbumWidth NOTIFY columnWidthsChanged)
    Q_PROPERTY(int trackWidth READ trackWidth WRITE setTrackWidth NOTIFY columnWidthsChanged)
    Q_PROPERTY(int durationWidth READ durationWidth WRITE setDurationWidth NOTIFY columnWidthsChanged)

    // Playback
    Q_PROPERTY(bool restorePlaylist READ restorePlaylist WRITE setRestorePlaylist NOTIFY restorePlaylistChanged)
    Q_PROPERTY(bool backgroundPlayback READ backgroundPlayback WRITE setBackgroundPlayback NOTIFY backgroundPlaybackChanged)
    // The private listening history (kept on this computer only)
    Q_PROPERTY(bool historyEnabled READ historyEnabled WRITE setHistoryEnabled NOTIFY historyChanged)
    // ReplayGain: 0 off, 1 track, 2 album
    Q_PROPERTY(int replayGain READ replayGain WRITE setReplayGain NOTIFY replayGainChanged)
    // A desktop notification when the song changes (while the window isn't in front)
    Q_PROPERTY(bool notificationsEnabled READ notificationsEnabled WRITE setNotificationsEnabled NOTIFY notificationsEnabledChanged)
    Q_PROPERTY(bool historyYouTube READ historyYouTube WRITE setHistoryYouTube NOTIFY historyChanged)
    Q_PROPERTY(QString themeMode READ themeMode WRITE setThemeMode NOTIFY themeModeChanged)
    // The player's cover: 60 (%, a square) .. 100 (reaches the screen's edges)
    Q_PROPERTY(int coverSize READ coverSize WRITE setCoverSize NOTIFY coverSizeChanged)
    // The seek bar while playing: "wave" (all of it flows) or "dot" (only around the dot)
    Q_PROPERTY(QString seekbarStyle READ seekbarStyle WRITE setSeekbarStyle NOTIFY seekbarStyleChanged)
    // The bottom bar's toy seek bar: its own choice of the same (phones)
    Q_PROPERTY(QString fidgetStyle READ fidgetStyle WRITE setFidgetStyle NOTIFY seekbarStyleChanged)
    Q_PROPERTY(QString fidgetThumb READ fidgetThumb WRITE setFidgetThumb NOTIFY seekbarThumbChanged)
    // The seek bar's thumb: "circle", "ring", "pill", "diamond", "heart", "star", "note", "disc",
    // "play" or "arrow"
    Q_PROPERTY(QString seekbarThumb READ seekbarThumb WRITE setSeekbarThumb NOTIFY seekbarThumbChanged)
    Q_PROPERTY(bool resumeSession READ resumeSession WRITE setResumeSession NOTIFY resumeSessionChanged)
    Q_PROPERTY(int volumeStep READ volumeStep WRITE setVolumeStep NOTIFY volumeStepChanged)
    Q_PROPERTY(bool showRemainingTime READ showRemainingTime WRITE setShowRemainingTime NOTIFY showRemainingTimeChanged)
    // Seconds the end of a song overlaps the next one (0 = gapless)
    Q_PROPERTY(int fadeSeconds READ fadeSeconds WRITE setFadeSeconds NOTIFY fadeSecondsChanged)
    // Lyrics: [{ id, name, enabled }] in the order they are tried
    Q_PROPERTY(QVariantList lyricsSources READ lyricsSources NOTIFY lyricsSourcesChanged)
    Q_PROPERTY(bool lyricsSyncedByDefault READ lyricsSyncedByDefault WRITE setLyricsSyncedByDefault NOTIFY lyricsSyncedByDefaultChanged)
    // Lyrics in English letters (romanized, same language) instead of their own script
    Q_PROPERTY(bool lyricsLatinScript READ lyricsLatinScript WRITE setLyricsLatinScript NOTIFY lyricsLatinScriptChanged)
    // Android: look for a new version of the app at startup, and the version "Skip this version" hides.
    Q_PROPERTY(bool appUpdateCheck READ appUpdateCheck WRITE setAppUpdateCheck NOTIFY appUpdateCheckChanged)
    Q_PROPERTY(QString appUpdateSkipped READ appUpdateSkipped WRITE setAppUpdateSkipped NOTIFY appUpdateSkippedChanged)
    // YouTube
    Q_PROPERTY(bool ytBackgroundLookup READ ytBackgroundLookup WRITE setYtBackgroundLookup NOTIFY ytBackgroundLookupChanged)
    // After a YouTube song / album / playlist: keep going with YouTube's "up next" (a Mix).
    Q_PROPERTY(bool ytAutoplay READ ytAutoplay WRITE setYtAutoplay NOTIFY ytAutoplayChanged)
    // When the Queue ends on a YouTube song: continue with its Mix.
    Q_PROPERTY(bool ytQueueMix READ ytQueueMix WRITE setYtQueueMix NOTIFY ytQueueMixChanged)
    // Playing a list (album, artist, playlist, YouTube...) adds it to the end of the Queue
    // instead of playing it on its own, out of sight; a Mix after it grows the Queue too.
    Q_PROPERTY(bool listsToQueue READ listsToQueue WRITE setListsToQueue NOTIFY listsToQueueChanged)
    // YouTube Music searches you used, newest first (kept on this computer only).
    Q_PROPERTY(QStringList ytSearchHistory READ ytSearchHistory NOTIFY ytSearchHistoryChanged)
    Q_PROPERTY(YtQuality ytQuality READ ytQuality WRITE setYtQuality NOTIFY ytQualityChanged)
    // 10-band equalizer: on / off, dB per band (31 Hz ... 16 kHz), and the preset
    // they came from ("custom" once a slider is moved).
    Q_PROPERTY(bool eqEnabled READ eqEnabled WRITE setEqEnabled NOTIFY eqChanged)
    Q_PROPERTY(QList<qreal> eqGains READ eqGains NOTIFY eqChanged)
    Q_PROPERTY(QString eqPreset READ eqPreset NOTIFY eqChanged)
    // Browser whose YouTube session yt-dlp reads ("" = not signed in)
    Q_PROPERTY(QString ytCookiesBrowser READ ytCookiesBrowser WRITE setYtCookiesBrowser NOTIFY ytCookiesBrowserChanged)
    // Album art for songs without one: look it up online for the playing song;
    // sources [{ id, name, enabled }] (all asked, the largest image wins)
    Q_PROPERTY(bool coversOnline READ coversOnline WRITE setCoversOnline NOTIFY coversOnlineChanged)
    Q_PROPERTY(QVariantList coverSources READ coverSources NOTIFY coverSourcesChanged)
    // Local library: folders scanned for music, and folders left out of them
    Q_PROPERTY(QStringList libraryFolders READ libraryFolders NOTIFY libraryFoldersChanged)
    Q_PROPERTY(QStringList libraryExcluded READ libraryExcluded NOTIFY libraryExcludedChanged)
    // The bottom bar (phones): its panels in order, and the ones turned off
    Q_PROPERTY(QStringList panelOrder READ panelOrder NOTIFY panelsChanged)
    Q_PROPERTY(QStringList hiddenPanels READ hiddenPanels NOTIFY panelsChanged)
    // Thin lines between the bottom bar's icons
    Q_PROPERTY(bool navDividers READ navDividers WRITE setNavDividers NOTIFY navDividersChanged)
    // What opens at start: "player", "youtube", "queue", "home" or "library"
    Q_PROPERTY(QString startPanel READ startPanel WRITE setStartPanel NOTIFY startPanelChanged)
    // Phones: the panel in the player's place ("player", or a bottom-bar panel)
    Q_PROPERTY(QString defaultPanel READ defaultPanel WRITE setDefaultPanel NOTIFY defaultPanelChanged)
    // The Library's Songs tab: "title", "titleDesc", "newest", "oldest", "modifiedNew",
    // "modifiedOld", "artist" or "album"
    Q_PROPERTY(QString librarySort READ librarySort WRITE setLibrarySort NOTIFY librarySortChanged)
    // Library lists sorted by name get letter headers (# A..Z), tap one to jump to a letter
    Q_PROPERTY(bool letterGroups READ letterGroups WRITE setLetterGroups NOTIFY letterGroupsChanged)
    // Albums: "name", "nameDesc", "newest", "oldest", "modifiedNew", "modifiedOld", "artist" or "mostSongs"
    Q_PROPERTY(QString albumSort READ albumSort WRITE setAlbumSort NOTIFY librarySortChanged)
    // Artists: "name", "nameDesc", "mostSongs" or "fewestSongs"
    Q_PROPERTY(QString artistSort READ artistSort WRITE setArtistSort NOTIFY librarySortChanged)
    // Genres: as Artists
    Q_PROPERTY(QString genreSort READ genreSort WRITE setGenreSort NOTIFY librarySortChanged)
    // Folders: "name", "nameDesc", "mostSongs", "fewestSongs", "modifiedNew" or "modifiedOld"
    Q_PROPERTY(QString folderSort READ folderSort WRITE setFolderSort NOTIFY librarySortChanged)
    // Appearance: 0 = plain dark theme, 1 = full cover color
    Q_PROPERTY(qreal coverTintStrength READ coverTintStrength WRITE setCoverTintStrength NOTIFY coverTintStrengthChanged)
    // Interface size (1 = 100%), applied at the next start; activeInterfaceScale: this run's
    Q_PROPERTY(qreal interfaceScale READ interfaceScale WRITE setInterfaceScale NOTIFY interfaceScaleChanged)
    Q_PROPERTY(qreal activeInterfaceScale READ activeInterfaceScale CONSTANT)
    // Visualizer under the volume bar; style: 0 = bars, 1 = mirrored bars, 2 = wave
    Q_PROPERTY(bool visualizerEnabled READ visualizerEnabled WRITE setVisualizerEnabled NOTIFY visualizerEnabledChanged)
    Q_PROPERTY(int visualizerStyle READ visualizerStyle WRITE setVisualizerStyle NOTIFY visualizerStyleChanged)

public:
    // YouTube audio quality. Auto: Best, but Lowest on a metered connection.
    enum YtQuality { YtAuto, YtBest, YtLowest };
    Q_ENUM(YtQuality)

    // No default argument: QML must use create(), not construct its own instance.
    explicit SettingsController(QObject *parent);
    ~SettingsController() override;

    static SettingsController *create(QQmlEngine *qmlEngine, QJSEngine *jsEngine);

    qreal volume() const;
    void setVolume(qreal volume);
    bool playlistPinned() const;
    void setPlaylistPinned(bool pinned);
    bool youtubePanelPinned() const;
    void setYoutubePanelPinned(bool pinned);
    bool libraryPanelPinned() const;
    bool homePanelPinned() const;
    void setHomePanelPinned(bool pinned);
    void setLibraryPanelPinned(bool pinned);
    int artistAlbumWidth() const;
    void setArtistAlbumWidth(int width);
    int trackWidth() const;
    void setTrackWidth(int width);
    int durationWidth() const;
    void setDurationWidth(int width);

    bool restorePlaylist() const;    // load the last playlist on startup
    void setRestorePlaylist(bool restore);
    bool backgroundPlayback() const; // closing the window keeps the music playing
    bool notificationsEnabled() const;
    void setNotificationsEnabled(bool enabled);
    int replayGain() const;
    void setReplayGain(int mode);
    bool historyEnabled() const;
    void setHistoryEnabled(bool enabled);
    bool historyYouTube() const; // YouTube Music songs are recorded too
    void setHistoryYouTube(bool enabled);
    void setBackgroundPlayback(bool enabled);
    QString themeMode() const; // "system" (follow the desktop), "dark" (default) or "light"
    void setThemeMode(const QString &mode);
    int coverSize() const;
    void setCoverSize(int size);
    QString seekbarStyle() const;
    void setSeekbarStyle(const QString &style);
    QString fidgetStyle() const;
    void setFidgetStyle(const QString &style);
    QString fidgetThumb() const;
    void setFidgetThumb(const QString &thumb);
    QString seekbarThumb() const;
    void setSeekbarThumb(const QString &thumb);
    bool resumeSession() const; // reopen on the last song, paused where it was
    void setResumeSession(bool resume);

    // The last session (SessionController): song, position, length, and the
    // list it played from ("queue" or a playlist id).
    QString sessionPath() const;
    qint64 sessionPosition() const;
    qint64 sessionDuration() const;
    QString sessionList() const;
    void setSession(const QString &path, qint64 positionMs, qint64 durationMs, const QString &list);
    QString outputDevice() const;    // "" = system default; applied by main()
    void setOutputDevice(const QString &deviceId);
    int volumeStep() const;          // percent per mouse-wheel notch
    void setVolumeStep(int step);
    bool showRemainingTime() const;
    int fadeSeconds() const;
    void setFadeSeconds(int seconds);
    void setShowRemainingTime(bool show);
    QVariantList lyricsSources() const;
    Q_INVOKABLE void moveLyricsSource(int index, int delta);
    Q_INVOKABLE void setLyricsSourceEnabled(int index, bool enabled);
    QStringList enabledLyricsSourceIds() const; // in the order they should be tried
    bool lyricsSyncedByDefault() const;
    void setLyricsSyncedByDefault(bool synced);
    bool lyricsLatinScript() const;
    void setLyricsLatinScript(bool latin);
    bool ytBackgroundLookup() const;
    QString ytCookiesBrowser() const;
    void setYtCookiesBrowser(const QString &browser);
    void setYtBackgroundLookup(bool enabled);
    bool ytAutoplay() const;
    void setYtAutoplay(bool enabled);
    bool appUpdateCheck() const;
    void setAppUpdateCheck(bool enabled);
    QString appUpdateSkipped() const;
    void setAppUpdateSkipped(const QString &version);
    bool ytQueueMix() const;
    void setYtQueueMix(bool enabled);
    bool listsToQueue() const;
    void setListsToQueue(bool enabled);
    bool eqEnabled() const;
    void setEqEnabled(bool enabled);
    QList<qreal> eqGains() const;
    QString eqPreset() const;
    Q_INVOKABLE void setEqGain(int band, qreal db);                          // the preset becomes "custom"
    Q_INVOKABLE void setEqPreset(const QString &preset, const QList<qreal> &gains);
    YtQuality ytQuality() const;
    void setYtQuality(YtQuality quality);
    QStringList ytSearchHistory() const;
    Q_INVOKABLE void rememberYtSearch(const QString &query); // to the top (once)
    Q_INVOKABLE void forgetYtSearch(const QString &query);
    Q_INVOKABLE void clearYtSearchHistory();
    bool coversOnline() const;
    void setCoversOnline(bool online);
    QVariantList coverSources() const;
    Q_INVOKABLE void setCoverSourceEnabled(const QString &id, bool enabled);
    QStringList enabledCoverSourceIds() const;
    QStringList libraryFolders() const;
    QStringList libraryExcluded() const;
    bool navDividers() const;
    void setNavDividers(bool on);
    QStringList panelOrder() const;
    QStringList hiddenPanels() const;
    Q_INVOKABLE void movePanel(int index, int delta);
    Q_INVOKABLE void setPanelHidden(const QString &panel, bool hidden);
    QString startPanel() const;
    void setStartPanel(const QString &panel);
    QString defaultPanel() const;
    void setDefaultPanel(const QString &panel);
    QString librarySort() const;
    bool letterGroups() const;
    void setLetterGroups(bool enabled);
    void setLibrarySort(const QString &sort);
    QString albumSort() const;
    void setAlbumSort(const QString &sort);
    QString artistSort() const;
    void setArtistSort(const QString &sort);
    QString genreSort() const;
    void setGenreSort(const QString &sort);
    QString folderSort() const;
    void setFolderSort(const QString &sort);
    // Local paths or file:// URLs; return false if it was already there.
    Q_INVOKABLE bool addLibraryFolder(const QString &folder);
    Q_INVOKABLE void removeLibraryFolder(const QString &folder);
    Q_INVOKABLE bool addLibraryExcluded(const QString &folder);
    Q_INVOKABLE void removeLibraryExcluded(const QString &folder);
    qreal coverTintStrength() const;
    void setCoverTintStrength(qreal strength);
    qreal interfaceScale() const;
    void setInterfaceScale(qreal scale);
    qreal activeInterfaceScale() const { return m_activeInterfaceScale; }
    void setActiveInterfaceScale(qreal scale) { m_activeInterfaceScale = scale; }
    // The saved interface size, read before the app starts (Qt scales the whole UI by it).
    static qreal storedInterfaceScale();
    // Writes the settings file now (before a restart).
    void flush();
    // Quits and starts the app again (main does it: restartRequested).
    Q_INVOKABLE void restartApp() { emit restartRequested(); }
    bool visualizerEnabled() const;
    void setVisualizerEnabled(bool enabled);
    int visualizerStyle() const;
    void setVisualizerStyle(int style);

    // Used by PlaylistController (values of Playlist::SortColumn).
    int sortColumn() const;
    bool sortDescending() const;
    void setSort(int column, bool descending);
    bool shuffle() const;
    void setShuffle(bool shuffle);
    int repeatMode() const; // values of Playlist::RepeatMode
    void setRepeatMode(int mode);

signals:
    void volumeChanged();
    void playlistPinnedChanged();
    void youtubePanelPinnedChanged();
    void libraryPanelPinnedChanged();
    void homePanelPinnedChanged();
    void columnWidthsChanged();
    void volumeStepChanged();
    void restorePlaylistChanged();
    void backgroundPlaybackChanged();
    void historyChanged();
    void replayGainChanged();
    void notificationsEnabledChanged();
    void themeModeChanged();
    void coverSizeChanged();
    void seekbarStyleChanged();
    void seekbarThumbChanged();
    void resumeSessionChanged();
    void showRemainingTimeChanged();
    void fadeSecondsChanged();
    void lyricsSourcesChanged();
    void lyricsSyncedByDefaultChanged();
    void lyricsLatinScriptChanged();
    void ytBackgroundLookupChanged();
    void ytAutoplayChanged();
    void appUpdateCheckChanged();
    void appUpdateSkippedChanged();
    void ytQueueMixChanged();
    void listsToQueueChanged();
    void ytSearchHistoryChanged();
    void ytQualityChanged();
    void eqChanged();
    void ytCookiesBrowserChanged();
    void coverTintStrengthChanged();
    void interfaceScaleChanged();
    void restartRequested();
    void coversOnlineChanged();
    void coverSourcesChanged();
    void libraryFoldersChanged();
    void libraryExcludedChanged();
    void librarySortChanged();
    void letterGroupsChanged();
    void panelsChanged();
    void navDividersChanged();
    void startPanelChanged();
    void defaultPanelChanged();
    void visualizerEnabledChanged();
    void visualizerStyleChanged();

private:
    void setWidth(const char *key, int width, int min, int max);
    QStringList pathList(const char *key) const;
    void setPathList(const char *key, const QStringList &paths);
    QString sortValue(const char *key, const QStringList &allowed) const; // (the first one is the default)
    void setSortValue(const char *key, const QStringList &allowed, const QString &sort);
    void scheduleSave();

    struct LyricsSource
    {
        QString id;
        bool enabled;
    };
    QList<LyricsSource> lyricsSourceList() const;
    void storeLyricsSources(const QList<LyricsSource> &sources);

    static inline SettingsController *s_instance = nullptr;

    std::unique_ptr<Settings> m_settings;
    qreal m_activeInterfaceScale = 1.0;
    QTimer m_saveTimer;
};
