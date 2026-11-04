#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QString>
#include <QThreadPool>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include <memory>

class LoudnessStore;
class Player;
class SpectrumAnalyzer;
class StreamResolver;
class QJSEngine;
class QQmlEngine;

// Exposes the backend Player to QML as the `PlayerController` singleton.
// Backend callbacks arrive on the player thread and are queued onto the GUI thread.
class PlayerController : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(State state READ state NOTIFY stateChanged)
    Q_PROPERTY(bool playing READ playing NOTIFY stateChanged)
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(qreal volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool muted READ muted WRITE setMuted NOTIFY mutedChanged)
    Q_PROPERTY(bool hasTrack READ hasTrack NOTIFY sourceChanged)
    Q_PROPERTY(QString source READ source NOTIFY sourceChanged)
    Q_PROPERTY(QString title READ title NOTIFY sourceChanged)
    Q_PROPERTY(QString errorString READ errorString NOTIFY errorStringChanged)
    // e.g. "44.1 kHz · 941 kbps · FLAC"; empty until known
    Q_PROPERTY(QString qualityText READ qualityText NOTIFY qualityTextChanged)
    // The song playing, for the audio pipeline: { codec, sampleRate, bitsPerSample, channels,
    // bitrate, stream, outputRate, gainSource, gainTrackDb, gainAlbumDb } (local files only:
    // gainSource "tags" | "measured" | "pending" (not measured yet) | "failed"; gains when known)
    Q_PROPERTY(QVariantMap sourceInfo READ sourceInfo NOTIFY sourceInfoChanged)
    // Audio outputs: [{ id, name }]; id "" = system default (always first)
    Q_PROPERTY(QVariantList outputDevices READ outputDevices NOTIFY outputDevicesChanged)
    Q_PROPERTY(QString outputDevice READ outputDevice WRITE setOutputDevice NOTIFY outputDeviceChanged)

public:
    enum State { Stopped, Playing, Paused };
    Q_ENUM(State)

    // No default argument: otherwise QML would construct its own instance
    // instead of calling create().
    explicit PlayerController(QObject *parent);
    ~PlayerController() override;

    // QML singleton factory: returns the instance created in main().
    static PlayerController *create(QQmlEngine *qmlEngine, QJSEngine *jsEngine);

    // Measured loudness for songs without ReplayGain tags (LoudnessController's)
    void setLoudnessStore(std::shared_ptr<const LoudnessStore> store);
    // That song's loudness was just measured: if it is playing, its gain is
    // eased in and its details are read again.
    void loudnessMeasured(const QString &path);

    State state() const { return m_state; }
    bool playing() const { return m_state == Playing; }
    QVariantMap sourceInfo() const { return m_sourceInfo; }
    qint64 position() const { return m_position; }
    qint64 duration() const { return m_duration; }
    qreal volume() const { return m_volume; }
    void setVolume(qreal volume);
    bool muted() const { return m_muted; }
    void setMuted(bool muted);
    bool hasTrack() const { return !m_source.isEmpty(); }
    QString source() const { return m_source; }
    QString title() const;
    QString errorString() const { return m_errorString; }
    QString qualityText() const { return m_qualityText; }
    QVariantList outputDevices() const { return m_outputDevices; }
    QString outputDevice() const { return m_outputDevice; }
    void setOutputDevice(const QString &deviceId);

    Q_INVOKABLE void load(const QString &path);
    // Loads `path` paused at `positionMs` (resuming the last session).
    void loadPaused(const QString &path, qint64 positionMs);
    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void togglePlayPause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void seek(qint64 positionMs);
    // Stop and forget the current file (nothing playing afterwards).
    Q_INVOKABLE void unload();

    // Track to continue with when the current one ends (empty clears);
    // fadeMs = 0: gapless; otherwise this track fades out and that one in.
    void setNext(const QString &path, int fadeMs = 0);
    // Short fade instead of a cut when switching tracks (Next, Previous, ...).
    void setSkipFade(bool enabled);

    // Re-reads the list of audio outputs (in the background).
    Q_INVOKABLE void refreshOutputDevices();

    // Browser whose YouTube session yt-dlp may use ("" = none).
    void setYtCookiesBrowser(const QString &browser);
    void setYtLowestQuality(bool lowest); // smallest YouTube streams (else the best ones)
    void setEqualizer(const QList<qreal> &gainsDb, bool enabled); // 10 bands, 31 Hz first
    void setFadeLevel(qreal level); // 0..1 on top of the volume (not saved, not shown)
    void setReplayGainMode(int mode); // 0 off, 1 track, 2 album

    // Analysis of what is being played (for VisualizerController).
    SpectrumAnalyzer &spectrum();

signals:
    void stateChanged();
    void positionChanged();
    void durationChanged();
    void volumeChanged();
    void mutedChanged();
    void sourceChanged();
    void errorStringChanged();
    void qualityTextChanged();
    void sourceInfoChanged();
    void outputDevicesChanged();
    void outputDeviceChanged();
    void trackFinished();
    void trackChanged(const QString &path); // gapless switch to the queued track
    void seeked(qint64 positionMs);         // the user jumped to a new position

private:
    void setState(State state);
    void setPosition(qint64 position);
    void setDuration(qint64 duration);
    void setErrorString(const QString &error);
    void applyVolume();
    void updateQuality();

    static inline PlayerController *s_instance = nullptr;

    State m_state = Stopped;
    static constexpr qint64 SeekArrivedMs = 2000; // this close to the target: the seek is done
    static constexpr qint64 SeekPatienceMs = 3000;

    qint64 m_position = 0;
    qint64 m_seekTarget = -1; // -1: no seek under way
    QVariantMap m_sourceInfo;
    QElapsedTimer m_seekClock;
    qint64 m_duration = 0;
    qreal m_volume = 0.8;
    bool m_muted = false;
    QString m_source;
    QString m_errorString;
    QString m_qualityText;
    int m_qualityGeneration = 0;
    QVariantList m_outputDevices;
    QString m_outputDevice;
    QThreadPool m_probePool;

    std::unique_ptr<StreamResolver> m_resolver; // before m_player: outlives it
    std::unique_ptr<Player> m_player;
    std::shared_ptr<const LoudnessStore> m_loudness;
};
