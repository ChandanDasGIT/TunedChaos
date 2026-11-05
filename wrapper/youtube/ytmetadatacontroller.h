#pragma once

#include <QObject>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QThreadPool>
#include <QTimer>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include <functional>
#include <memory>

class PlayerController;
class PlaylistController;
class QJSEngine;
class QQmlEngine;
class SettingsController;
class YtMetadataStore;
struct Track;
struct YtMetadataEntry;

// Looks up local tracks on YouTube Music in the background
// (`YtMetadataController` singleton): the Queue's tracks, plus any song that is
// played or whose details are opened (from the Library or a playlist). One
// track every couple of seconds, the playing track first, results cached on
// disk. Turned off in Settings stops it.
class YtMetadataController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool enabled READ enabled NOTIFY enabledChanged)

public:
    YtMetadataController(PlaylistController *playlist, PlayerController *player,
                         SettingsController *settings, QObject *parent);
    ~YtMetadataController() override;

    static YtMetadataController *create(QQmlEngine *qmlEngine, QJSEngine *jsEngine);

    bool enabled() const;

    // Finds a library song by path (set by LocalLibraryController; empty = none).
    void setTrackLookup(std::function<const ::Track *(const QString &path)> lookup) { m_lookup = std::move(lookup); }

    // { state: "matched" | "nomatch" | "pending" | "error" | "off",
    //   title, artists, album, year, duration (ms), url, thumbnail }
    Q_INVOKABLE QVariantMap infoFor(const QString &path) const;
    // Look this one up next (e.g. its details window is open).
    Q_INVOKABLE void prioritize(const QString &path);
    // The YouTube Music song already found for this local file ("": not looked up / no match).
    QString cachedVideoId(const QString &path) const;

signals:
    void enabledChanged();
    void infoChanged(const QString &path);

private:
    void rebuildQueue();
    void processNext();
    void finish(const QString &path, bool answered, const YtMetadataEntry &entry);
    static bool isLocal(const QString &path);

    static inline YtMetadataController *s_instance = nullptr;

    PlaylistController *m_playlist;
    PlayerController *m_player;
    SettingsController *m_settings;
    std::unique_ptr<YtMetadataStore> m_store;
    std::function<const ::Track *(const QString &path)> m_lookup;

    QStringList m_queue;
    QString m_inFlight;
    QSet<QString> m_failed; // no answer this session (offline / API trouble)
    int m_consecutiveFailures = 0;
    int m_unsaved = 0; // results not written to disk yet (saved every 10 and on exit)
    QTimer m_timer;
    QThreadPool m_pool;
};
