#pragma once

#include <QDBusAbstractAdaptor>
#include <QDBusObjectPath>
#include <QGuiApplication>
#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QVariantMap>

class PlayerController;
class PlaylistController;

// MPRIS 2 (https://specifications.freedesktop.org/mpris-spec/latest/):
// lets desktop media controls, the lock screen, media keys and playerctl see
// and control the player. Registers as org.mpris.MediaPlayer2.tunedchaos
// on the session bus; the two interfaces below are exported on its object.
class MprisAdaptor : public QObject
{
    Q_OBJECT

public:
    MprisAdaptor(PlayerController *player, PlaylistController *playlist, QObject *parent);
    ~MprisAdaptor() override;

    bool isRegistered() const { return !m_service.isEmpty(); }

signals:
    void raiseRequested(); // a client asked to bring the window to the front
    void quitRequested();  // a client asked the app to quit

private:
    QString m_service;
};

// org.mpris.MediaPlayer2: the application itself.
class MprisRootInterface : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2")

    Q_PROPERTY(bool CanQuit READ canQuit CONSTANT)
    Q_PROPERTY(bool CanRaise READ canRaise CONSTANT)
    Q_PROPERTY(bool CanSetFullscreen READ canSetFullscreen CONSTANT)
    Q_PROPERTY(bool Fullscreen READ fullscreen CONSTANT)
    Q_PROPERTY(bool HasTrackList READ hasTrackList CONSTANT)
    Q_PROPERTY(QString Identity READ identity CONSTANT)
    Q_PROPERTY(QString DesktopEntry READ desktopEntry CONSTANT)
    Q_PROPERTY(QStringList SupportedUriSchemes READ supportedUriSchemes CONSTANT)
    Q_PROPERTY(QStringList SupportedMimeTypes READ supportedMimeTypes CONSTANT)

public:
    explicit MprisRootInterface(MprisAdaptor *parent);

    bool canQuit() const { return true; }
    bool canRaise() const { return true; }
    bool canSetFullscreen() const { return false; }
    bool fullscreen() const { return false; }
    bool hasTrackList() const { return false; }
    QString identity() const { return QStringLiteral("Tuned Chaos"); }
    QString desktopEntry() const { return QGuiApplication::desktopFileName(); }
    // OpenUri is not supported, so both lists are empty (as the spec asks).
    QStringList supportedUriSchemes() const { return {}; }
    QStringList supportedMimeTypes() const { return {}; }

public slots:
    void Raise();
    void Quit();

private:
    MprisAdaptor *m_adaptor;
};

// org.mpris.MediaPlayer2.Player: playback state and controls.
class MprisPlayerInterface : public QDBusAbstractAdaptor
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2.Player")

    Q_PROPERTY(QString PlaybackStatus READ playbackStatus)
    Q_PROPERTY(QString LoopStatus READ loopStatus WRITE setLoopStatus)
    Q_PROPERTY(double Rate READ rate WRITE setRate)
    Q_PROPERTY(bool Shuffle READ shuffle WRITE setShuffle)
    Q_PROPERTY(QVariantMap Metadata READ metadata)
    Q_PROPERTY(double Volume READ volume WRITE setVolume)
    Q_PROPERTY(qlonglong Position READ position)
    Q_PROPERTY(double MinimumRate READ rate CONSTANT)
    Q_PROPERTY(double MaximumRate READ rate CONSTANT)
    Q_PROPERTY(bool CanGoNext READ canGoNext)
    Q_PROPERTY(bool CanGoPrevious READ canGoPrevious)
    Q_PROPERTY(bool CanPlay READ canPlay)
    Q_PROPERTY(bool CanPause READ canPause)
    Q_PROPERTY(bool CanSeek READ canSeek)
    Q_PROPERTY(bool CanControl READ canControl CONSTANT)

public:
    MprisPlayerInterface(MprisAdaptor *parent, PlayerController *player, PlaylistController *playlist);
    ~MprisPlayerInterface() override;

    QString playbackStatus() const;
    QString loopStatus() const;
    void setLoopStatus(const QString &status);
    double rate() const { return 1.0; }
    void setRate(double) {} // only 1.0 is supported
    bool shuffle() const;
    void setShuffle(bool shuffle);
    QVariantMap metadata() const;
    double volume() const;
    void setVolume(double volume);
    qlonglong position() const; // microseconds
    bool canGoNext() const;
    bool canGoPrevious() const;
    bool canPlay() const;
    bool canPause() const;
    bool canSeek() const;
    bool canControl() const { return true; }

public slots:
    void Next();
    void Previous();
    void Pause();
    void PlayPause();
    void Stop();
    void Play();
    void Seek(qlonglong offset);
    void SetPosition(const QDBusObjectPath &trackId, qlonglong position);
    void OpenUri(const QString &) {} // not supported

signals:
    void Seeked(qlonglong position);

private:
    QDBusObjectPath trackId() const;
    QVariantMap snapshot() const; // every property except Position
    void scheduleUpdate();
    void update();                // emits PropertiesChanged for what changed
    void updateArt();             // writes the cover to the cache dir for mpris:artUrl

    PlayerController *m_player;
    PlaylistController *m_playlist;
    QTimer m_updateTimer;
    QVariantMap m_published;
    QString m_artSource; // audio file the cached cover belongs to
    QString m_artFile;
    QString m_artUrl;
    int m_artGeneration = 0; // bumped per track; stale cover downloads are dropped
};
