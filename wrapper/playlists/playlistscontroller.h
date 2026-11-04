#pragma once

#include "backend/playlist/playlist/playlist.h"
#include "wrapper/playlist/playlistmodel.h" // full type needed for the Q_PROPERTY

#include <QObject>
#include <QString>
#include <QThreadPool>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

#include <functional>
#include <memory>
#include <vector>

class PlayerController;
class PlaylistController;
class PlaylistLibrary;
class QJSEngine;
class QQmlEngine;
class SettingsController;

// The user's named playlists (`PlaylistsController` singleton), next to the
// permanent Queue. Viewing a playlist shows its songs in the left panel;
// playing a song from it plays from that playlist (the Queue is left alone)
// and "pins" it as what is playing. Songs are passed in as maps: { path } for songs already in
// the Queue / the viewed playlist, or YouTube song maps { videoId, ... }.
//
// Naming and deleting need the user's answer: requestNewPlaylist / requestRename
// emit namePrompt(), answered with submitName(); requestDelete emits
// deletePrompt(), answered with confirmDelete().
class PlaylistsController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QVariantList playlists READ playlists NOTIFY playlistsChanged) // [{ id, name, count }]
    Q_PROPERTY(QString viewedId READ viewedId NOTIFY viewChanged)             // "" = the Queue
    Q_PROPERTY(QString viewedName READ viewedName NOTIFY viewChanged)
    Q_PROPERTY(PlaylistModel *viewModel READ viewModel CONSTANT)
    Q_PROPERTY(int viewedCount READ viewedCount NOTIFY viewChanged)
    Q_PROPERTY(qint64 viewedDurationMs READ viewedDurationMs NOTIFY viewChanged)
    // view(playingListId) shows the list being played from (an album, a Mix...),
    // which plays on its own outside the Queue. It can't be edited.
    Q_PROPERTY(QString playingListId READ playingListId CONSTANT)
    Q_PROPERTY(bool viewedEditable READ viewedEditable NOTIFY viewChanged)
    Q_PROPERTY(QString playingFromId READ playingFromId NOTIFY playingFromChanged)
    Q_PROPERTY(QString playingFromName READ playingFromName NOTIFY playingFromChanged)

public:
    PlaylistsController(PlaylistController *queue, PlayerController *player, SettingsController *settings,
                        QObject *parent);
    ~PlaylistsController() override;

    static PlaylistsController *create(QQmlEngine *qmlEngine, QJSEngine *jsEngine);

    // Finds songs that are neither in the Queue nor the viewed playlist (the local library).
    void setTrackLookup(std::function<const ::Track *(const QString &path)> lookup) { m_lookup = std::move(lookup); }

    QVariantList playlists() const;
    QString viewedId() const { return m_viewedId; }
    static QString playingListId() { return QStringLiteral("@playing"); }
    bool viewingPlayingList() const { return m_viewedId == playingListId(); }
    bool viewedEditable() const { return !viewingPlayingList(); }
    QString viewedName() const;
    PlaylistModel *viewModel() const { return m_viewModel.get(); }
    int viewedCount() const { return int(m_view.size()); }
    qint64 viewedDurationMs() const;
    QString playingFromId() const { return m_playingFromId; }
    QString playingFromName() const;
    // Resuming the last session in playlist `id` (false if it or the song is gone).
    bool resumePlaylist(const QString &id, const QString &path, qint64 positionMs);

    // A song's tags were edited: every playlist with it shows the new ones.
    void updateTrackInfo(const ::Track &track);

    Q_INVOKABLE void view(const QString &id); // "" = back to the Queue
    Q_INVOKABLE void playViewed(int index);   // load the viewed playlist into the Queue and play
    Q_INVOKABLE void removeFromViewed(int index);
    Q_INVOKABLE void moveInViewed(int from, int to); // manual reordering
    Q_INVOKABLE void addToPlaylist(const QString &id, const QVariantList &items);
    Q_INVOKABLE void addToQueue(const QVariantList &items);
    // Songs dropped at `row` of playlist `id` ("" = the Queue); songs already
    // there move to that spot. row -1 = the end.
    Q_INVOKABLE void insertItems(const QString &id, const QVariantList &items, int row);
    // Right after the playing song ([{ path }] or YouTube song maps).
    Q_INVOKABLE void playNext(const QVariantList &items);
    // M3U / M3U8 files (path or file:// URL). Import reads the songs in the
    // background into a new playlist (named after the file) and opens it.
    // Export writes playlist `id`, or the Queue when `id` is "".
    Q_INVOKABLE void importM3u(const QString &file);
    Q_INVOKABLE void exportM3u(const QString &id, const QString &file);

    Q_INVOKABLE void requestNewPlaylist(const QVariantList &items = {});
    Q_INVOKABLE void requestRename(const QString &id);
    Q_INVOKABLE void requestDelete(const QString &id);
    Q_INVOKABLE void submitName(const QString &name);
    Q_INVOKABLE void confirmDelete();

signals:
    void playlistsChanged();
    void viewChanged();
    void playingFromChanged();
    void namePrompt(const QString &title, const QString &initialName);
    void deletePrompt(const QString &name);
    void notice(const QString &text);

private:
    std::vector<::Track> tracksFromItems(const QVariantList &items) const;
    void refreshView();
    void updateViewCurrent();
    void setPlayingFrom(const QString &id);
    QString nameOf(const QString &id) const;

    static inline PlaylistsController *s_instance = nullptr;

    PlaylistController *m_queue;
    PlayerController *m_player;
    SettingsController *m_settings;
    std::unique_ptr<PlaylistLibrary> m_library;
    QThreadPool m_pool; // M3U imports (one at a time)

    QString m_viewedId;
    std::function<const ::Track *(const QString &)> m_lookup;
    Playlist m_view; // songs of the viewed playlist, in their own order
    std::unique_ptr<PlaylistModel> m_viewModel; // after m_view: destroyed first
    QString m_playingFromId;

    // What a pending name / delete prompt is for.
    enum class Pending { None, Create, Rename, Delete };
    Pending m_pending = Pending::None;
    QString m_pendingId;
    std::vector<::Track> m_pendingTracks;
};
