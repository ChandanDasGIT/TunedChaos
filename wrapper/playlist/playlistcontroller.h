#pragma once

#include "backend/library/track/track.h"
#include "backend/playlist/playlist/playlist.h"
#include "wrapper/playlist/playlistmodel.h" // full type needed for the Q_PROPERTY

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

#include <functional>
#include <memory>
#include <optional>
#include <vector>

class PlayerController;
class QJSEngine;
class QQmlEngine;
class SettingsController;

// Playlist logic for QML (`PlaylistController` singleton): the Queue (sorting,
// saving / restoring it between sessions) and what plays next (shuffle /
// repeat / gapless queueing).
//
// Playback runs from the *active list*: the Queue, or - after playFromList()
// - a named playlist's songs (the "context"), which leaves the Queue untouched.
// Library and YouTube songs play as a titled context too (playTitled): a
// Library list (all songs, an album, an artist, a folder) or a YouTube album /
// playlist as is, a single YouTube song as a Mix (YouTube's "up next", topped
// up as it runs out).
// When the Queue ends on a YouTube song, its Mix can follow (setFollowUp).
// count / currentIndex / model / tracks describe the Queue; current* and
// hasNext / upcomingMs describe whatever is playing.
class PlaylistController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(PlaylistModel *model READ model CONSTANT)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int currentIndex READ currentIndex NOTIFY currentChanged)
    Q_PROPERTY(QString currentTitle READ currentTitle NOTIFY currentChanged)
    Q_PROPERTY(QString currentSubtitle READ currentSubtitle NOTIFY currentChanged)
    Q_PROPERTY(QString currentThumbnail READ currentThumbnail NOTIFY currentChanged) // YouTube tracks
    Q_PROPERTY(bool hasNext READ hasNext NOTIFY currentChanged)
    // Length of everything that plays after the current track.
    Q_PROPERTY(qint64 upcomingMs READ upcomingMs NOTIFY currentChanged)
    // Same, for the Queue only (its whole length while a playlist plays).
    Q_PROPERTY(qint64 queueUpcomingMs READ queueUpcomingMs NOTIFY currentChanged)
    Q_PROPERTY(SortColumn sortColumn READ sortColumn NOTIFY sortChanged)
    Q_PROPERTY(bool sortDescending READ sortDescending NOTIFY sortChanged)
    Q_PROPERTY(bool shuffle READ shuffle WRITE setShuffle NOTIFY shuffleChanged)
    Q_PROPERTY(RepeatMode repeatMode READ repeatMode WRITE setRepeatMode NOTIFY repeatModeChanged)
    // true while playing from a named playlist instead of the Queue
    Q_PROPERTY(bool playingFromList READ playingFromList NOTIFY playingFromListChanged)
    // The Library list / YouTube Mix / album playing ("" otherwise, also for named playlists)
    Q_PROPERTY(QString contextTitle READ contextTitle NOTIFY playingFromListChanged)

public:
    // Same order as Playlist::SortColumn. (`Track` here hides the ::Track struct.)
    // Custom = not sorted: the order the tracks were added in.
    enum SortColumn { Title, ArtistAlbum, Track, Duration, Custom };
    Q_ENUM(SortColumn)

    // Same order as Playlist::RepeatMode.
    enum RepeatMode { RepeatOff, RepeatAll, RepeatOne };
    Q_ENUM(RepeatMode)

    PlaylistController(PlayerController *player, SettingsController *settings, QObject *parent);
    ~PlaylistController() override;

    static PlaylistController *create(QQmlEngine *qmlEngine, QJSEngine *jsEngine);

    PlaylistModel *model() const { return m_model.get(); }
    int count() const { return int(m_playlist.size()); }
    int currentIndex() const { return m_playlist.currentIndex(); } // playing row of the Queue, or -1
    QString currentTitle() const;
    QString currentSubtitle() const;
    const ::Track *currentTrack() const; // nullptr when nothing is current
    const ::Track *trackForPath(const QString &path) const;
    // The song that plays after this one ("" = none / not known yet)
    QString nextPath() const;
    QString currentThumbnail() const;
    const std::vector<::Track> &tracks() const { return m_playlist.tracks(); }
    bool hasNext() const;
    qint64 upcomingMs() const { return m_active->upcomingDurationMs(); }
    qint64 queueUpcomingMs() const { return m_playlist.upcomingDurationMs(); }
    bool playingFromList() const { return m_active == &m_context; }
    QString contextTitle() const { return m_active == &m_context ? m_contextTitle : QString(); }
    bool contextEndless() const { return m_active == &m_context && m_contextEndless; } // a Mix
    SortColumn sortColumn() const { return SortColumn(m_playlist.sortColumn()); }
    bool sortDescending() const { return m_playlist.sortDescending(); }
    bool shuffle() const { return m_playlist.shuffle(); }
    void setShuffle(bool shuffle);
    RepeatMode repeatMode() const { return RepeatMode(m_playlist.repeatMode()); }
    void setRepeatMode(RepeatMode mode);

    // Appends tracks to the Queue (each batch ordered album / disc / track),
    // skipping duplicates; returns how many were added. A Queue sorted by a column
    // becomes custom order. Paths of the added tracks go to `addedPaths` if given.
    int addTracks(std::vector<::Track> tracks, std::vector<std::string> *addedPaths = nullptr);
    // If nothing is playing or paused, plays whichever of `paths` comes first in
    // the playlist (used after a folder drop).
    void playFirstIfIdle(const std::vector<std::string> &paths);
    // Adds tracks (e.g. from YouTube) and, if `play`, starts the first of them.
    void addAndPlay(std::vector<::Track> tracks, bool play);
    // Puts `tracks` right after the playing song, in the list being played (the
    // Queue, or the playlist played from; nothing playing: the Queue's top). A
    // song already there is moved instead of added twice.
    void playNext(const std::vector<::Track> &tracks);
    // Puts `tracks` (in this order) at `row` of the Queue (dropped there); a song
    // already in the Queue is moved instead. Returns how many were added.
    int insertTracks(const std::vector<::Track> &tracks, int row);
    // Plays `tracks` (a named playlist) from `startIndex`, without touching the Queue.
    void playFromList(std::vector<::Track> tracks, int startIndex);
    // Songs from `startIndex` (a Library list, YouTube songs), without touching
    // the Queue, shown as `title`. `endless`: when they run out, more are asked
    // for (moreWanted).
    void playTitled(std::vector<::Track> tracks, int startIndex, const QString &title, bool endless);
    // More songs for the endless list playing (those already in it are skipped).
    void extendList(const std::vector<::Track> &tracks);
    // A Mix to go on with once the Queue ends (the answer to moreWanted(.., true)).
    void setFollowUp(std::vector<::Track> tracks, const QString &title);
    // Resuming the last session: the song is loaded paused at `positionMs`.
    // false if the song isn't there.
    bool resumeInQueue(const QString &path, qint64 positionMs);
    bool resumeFromList(std::vector<::Track> tracks, const QString &path, qint64 positionMs);
    bool resumeAlone(const ::Track &track, qint64 positionMs); // in neither (e.g. the Queue was cleared)
    bool resumeTitled(const QString &path, qint64 positionMs, const QString &title, bool endless);
    // A song's tags were edited: the Queue and the list playing show the new ones.
    void updateTrackInfo(const ::Track &track);
    // The playing playlist changed (songs added / removed): keep playing the same song.
    void updateListTracks(std::vector<::Track> tracks);
    void save() const;

    Q_INVOKABLE void playIndex(int index);
    // Removing the playing track moves on to the next one if music is playing,
    // otherwise stops.
    Q_INVOKABLE void removeIndex(int index);
    // Manual reordering (drag handle); the Queue becomes custom order.
    Q_INVOKABLE void moveIndex(int from, int to);
    Q_INVOKABLE void clear();
    Q_INVOKABLE QString pathAt(int index) const;
    Q_INVOKABLE void playPause();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    // Sorts by `column`; the same column again reverses the order.
    Q_INVOKABLE void sortBy(int column);
    // Off -> All -> One -> Off
    Q_INVOKABLE void cycleRepeatMode();

signals:
    void countChanged();
    void currentChanged();
    void sortChanged();
    void shuffleChanged();
    void repeatModeChanged();
    void playingFromListChanged();
    // Running out: what YouTube plays after `seedPath`, please. forQueue: for
    // after the Queue's last song (setFollowUp), else for the list (extendList).
    void moreWanted(const QString &seedPath, bool forQueue);

private:
    // Runs `change` on the playlist and notifies the model / QML about the new current track.
    void changeCurrent(const std::function<void()> &change);
    void loadCurrent(qint64 startMs = 0, bool paused = false);
    const ::Track *detachedTrack() const;
    void placeNext(Playlist &list, const ::Track &track, int placed);
    void queueNext(); // tells the player what to continue with gaplessly
    void checkRunningOut();
    // `load` false: the player already went on to that song by itself.
    void startContext(std::vector<::Track> tracks, int startIndex, const QString &title, bool endless,
                      bool load = true);
    void startFollowUp(bool load);
    void saveTitledContext() const;
    static bool continuesAlbum(const ::Track &from, const ::Track &to);
    void onTrackChanged(const QString &path);
    void onTrackFinished();
    void activateQueue();      // back to playing from the Queue
    void setQueueCustomOrder(); // the Queue is no longer sorted by a column

    static inline PlaylistController *s_instance = nullptr;

    PlayerController *m_player;
    SettingsController *m_settings;
    QString m_storePath;
    Playlist m_playlist;                    // the Queue
    std::unique_ptr<PlaylistModel> m_model; // after m_playlist: destroyed first
    Playlist m_context;                     // the named playlist / YouTube songs being played from
    Playlist *m_active = &m_playlist;
    QString m_contextTitle;      // shown as "Playing from" ("" for named playlists)
    bool m_contextEndless = false; // a Mix: topped up from YouTube
    bool m_moreRequested = false;  // moreWanted sent, no answer yet (or nothing new came)
    bool m_waitingForMore = false; // the music ran out before the answer came
    std::vector<::Track> m_followUp; // the Mix after the Queue's last song
    QString m_followUpTitle;
    QString m_titledStorePath;    // the titled list playing, for resuming it
    // The song that keeps playing after the Queue was cleared (until it ends or is stopped).
    std::optional<::Track> m_detached;
};
