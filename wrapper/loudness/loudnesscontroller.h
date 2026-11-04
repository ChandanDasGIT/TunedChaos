#pragma once

#include <QHash>
#include <QObject>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QThreadPool>
#include <QtQml/qqmlregistration.h>

#include <atomic>
#include <cstdint>
#include <memory>
#include <string>
#include <utility>
#include <vector>

class LocalLibraryController;
class LoudnessStore;
class PlayerController;
class PlaylistController;
class QJSEngine;
class QQmlEngine;
class SettingsController;

// Measures how loud each library song is, in the background
// (`LoudnessController` singleton), so ReplayGain levels songs without
// ReplayGain tags too. Only while ReplayGain is on; one song at a time on a
// low-priority thread, the playing and the next song first. Results are kept
// on disk: a song is measured once (again only if its file changes).
class LoudnessController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // Library songs whose loudness is known (tags or measured), of all of them
    Q_PROPERTY(int doneCount READ doneCount NOTIFY progressChanged)
    Q_PROPERTY(int songCount READ songCount NOTIFY progressChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY progressChanged) // measuring now

public:
    LoudnessController(PlayerController *player, PlaylistController *playlist,
                       LocalLibraryController *library, SettingsController *settings, QObject *parent);
    ~LoudnessController() override;

    static LoudnessController *create(QQmlEngine *qmlEngine, QJSEngine *jsEngine);

    int doneCount() const { return m_doneCount; }
    int songCount() const { return m_songCount; }
    bool busy() const { return !m_inFlight.isEmpty(); }
    // Shared with whoever knows loudness too (music servers' gains)
    std::shared_ptr<LoudnessStore> store() const { return m_store; }

signals:
    void progressChanged();

private:
    using AlbumSongs = std::vector<std::pair<std::string, int64_t>>; // path, length

    bool enabled() const;
    void rebuild();
    void prioritize(const QString &path);
    void processNext();
    void finish(const QString &path);

    static inline LoudnessController *s_instance = nullptr;

    PlayerController *m_player;
    PlaylistController *m_playlist;
    LocalLibraryController *m_library;
    SettingsController *m_settings;
    std::shared_ptr<LoudnessStore> m_store;

    QStringList m_queue;
    QString m_inFlight;
    QSet<QString> m_librarySongs;           // local library songs (counted for progress)
    QHash<QString, QString> m_albumOf;      // song -> its album's key
    QHash<QString, AlbumSongs> m_albums;    // album key -> its songs
    int m_doneCount = 0;
    int m_songCount = 0;
    int m_generation = 0; // rebuilds: an older one's answer is ignored
    int m_unsaved = 0;
    std::atomic<bool> m_stopping{false};
    QThreadPool m_pool;
};
