#include "wrapper/mpris/mprisadaptor.h"

#include "wrapper/files/files.h"
#include "backend/library/metadata/metadata.h"
#include "backend/network/httpclient/httpclient.h"
#include "wrapper/player/playercontroller.h"
#include "wrapper/playlist/playlistcontroller.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDir>
#include <QFile>
#include <QPointer>
#include <QThreadPool>
#include <QStandardPaths>
#include <QUrl>

namespace {

const QString ServiceName = QStringLiteral("org.mpris.MediaPlayer2.tunedchaos");
const QString ObjectPath = QStringLiteral("/org/mpris/MediaPlayer2");
const QString PlayerInterfaceName = QStringLiteral("org.mpris.MediaPlayer2.Player");

} // namespace

// ---------------------------------------------------------------------------
// MprisAdaptor
// ---------------------------------------------------------------------------

MprisAdaptor::MprisAdaptor(PlayerController *player, PlaylistController *playlist, QObject *parent)
    : QObject(parent)
{
    new MprisRootInterface(this);
    new MprisPlayerInterface(this, player, playlist);

    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        qWarning("MPRIS: no D-Bus session bus; media controls are unavailable");
        return;
    }
    if (!bus.registerObject(ObjectPath, this)) {
        qWarning("MPRIS: could not register %s", qPrintable(ObjectPath));
        return;
    }

    // A second running instance gets a unique name, as the spec suggests.
    QString service = ServiceName;
    if (!bus.registerService(service)) {
        service += QStringLiteral(".instance%1").arg(QCoreApplication::applicationPid());
        if (!bus.registerService(service)) {
            qWarning("MPRIS: could not register %s", qPrintable(service));
            return;
        }
    }
    m_service = service;
}

MprisAdaptor::~MprisAdaptor()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!m_service.isEmpty())
        bus.unregisterService(m_service);
    bus.unregisterObject(ObjectPath);
}

// ---------------------------------------------------------------------------
// org.mpris.MediaPlayer2
// ---------------------------------------------------------------------------

MprisRootInterface::MprisRootInterface(MprisAdaptor *parent)
    : QDBusAbstractAdaptor(parent)
    , m_adaptor(parent)
{
}

void MprisRootInterface::Raise()
{
    emit m_adaptor->raiseRequested();
}

void MprisRootInterface::Quit()
{
    emit m_adaptor->quitRequested();
}

// ---------------------------------------------------------------------------
// org.mpris.MediaPlayer2.Player
// ---------------------------------------------------------------------------

MprisPlayerInterface::MprisPlayerInterface(MprisAdaptor *parent, PlayerController *player,
                                           PlaylistController *playlist)
    : QDBusAbstractAdaptor(parent)
    , m_player(player)
    , m_playlist(playlist)
{
    // Several signals usually fire together (e.g. on a track change):
    // collect them into a single PropertiesChanged.
    m_updateTimer.setSingleShot(true);
    m_updateTimer.setInterval(0);
    connect(&m_updateTimer, &QTimer::timeout, this, &MprisPlayerInterface::update);

    const auto schedule = [this] { scheduleUpdate(); };
    connect(m_player, &PlayerController::stateChanged, this, schedule);
    connect(m_player, &PlayerController::sourceChanged, this, schedule);
    connect(m_player, &PlayerController::durationChanged, this, schedule);
    connect(m_player, &PlayerController::volumeChanged, this, schedule);
    connect(m_player, &PlayerController::mutedChanged, this, schedule);
    connect(m_playlist, &PlaylistController::currentChanged, this, schedule);
    connect(m_playlist, &PlaylistController::countChanged, this, schedule);
    connect(m_playlist, &PlaylistController::shuffleChanged, this, schedule);
    connect(m_playlist, &PlaylistController::repeatModeChanged, this, schedule);

    connect(m_player, &PlayerController::seeked, this,
            [this](qint64 ms) { emit Seeked(qlonglong(ms) * 1000); });

    updateArt();
    m_published = snapshot();
}

MprisPlayerInterface::~MprisPlayerInterface()
{
    if (!m_artFile.isEmpty())
        QFile::remove(m_artFile);
}

QString MprisPlayerInterface::playbackStatus() const
{
    switch (m_player->state()) {
    case PlayerController::Playing: return QStringLiteral("Playing");
    case PlayerController::Paused:  return QStringLiteral("Paused");
    case PlayerController::Stopped: break;
    }
    return QStringLiteral("Stopped");
}

QString MprisPlayerInterface::loopStatus() const
{
    switch (m_playlist->repeatMode()) {
    case PlaylistController::RepeatOne: return QStringLiteral("Track");
    case PlaylistController::RepeatAll: return QStringLiteral("Playlist");
    case PlaylistController::RepeatOff: break;
    }
    return QStringLiteral("None");
}

void MprisPlayerInterface::setLoopStatus(const QString &status)
{
    if (status == QLatin1String("Track"))
        m_playlist->setRepeatMode(PlaylistController::RepeatOne);
    else if (status == QLatin1String("Playlist"))
        m_playlist->setRepeatMode(PlaylistController::RepeatAll);
    else if (status == QLatin1String("None"))
        m_playlist->setRepeatMode(PlaylistController::RepeatOff);
}

bool MprisPlayerInterface::shuffle() const
{
    return m_playlist->shuffle();
}

void MprisPlayerInterface::setShuffle(bool shuffle)
{
    m_playlist->setShuffle(shuffle);
}

QVariantMap MprisPlayerInterface::metadata() const
{
    QVariantMap map;
    map.insert(QStringLiteral("mpris:trackid"), QVariant::fromValue(trackId()));

    const QString source = m_player->source();
    if (source.isEmpty())
        return map;

    map.insert(QStringLiteral("xesam:url"), QUrl::fromLocalFile(source).toString());
    if (m_player->duration() > 0)
        map.insert(QStringLiteral("mpris:length"), qlonglong(m_player->duration()) * 1000);
    if (!m_artUrl.isEmpty())
        map.insert(QStringLiteral("mpris:artUrl"), m_artUrl);

    const Track *track = m_playlist->currentTrack();
    if (track && track->path == source.toStdString()) {
        map.insert(QStringLiteral("xesam:title"), QString::fromStdString(track->title));
        if (!track->artist.empty())
            map.insert(QStringLiteral("xesam:artist"),
                       QString::fromStdString(track->artist).split(QStringLiteral(", ")));
        if (!track->album.empty())
            map.insert(QStringLiteral("xesam:album"), QString::fromStdString(track->album));
        if (track->track > 0)
            map.insert(QStringLiteral("xesam:trackNumber"), track->track);
        if (track->disc > 0)
            map.insert(QStringLiteral("xesam:discNumber"), track->disc);
    } else {
        map.insert(QStringLiteral("xesam:title"), m_player->title());
    }
    return map;
}

double MprisPlayerInterface::volume() const
{
    return m_player->muted() ? 0.0 : m_player->volume();
}

void MprisPlayerInterface::setVolume(double volume)
{
    m_player->setMuted(false);
    m_player->setVolume(qBound(0.0, volume, 1.0));
}

qlonglong MprisPlayerInterface::position() const
{
    return qlonglong(m_player->position()) * 1000;
}

bool MprisPlayerInterface::canGoNext() const
{
    return m_playlist->hasNext();
}

bool MprisPlayerInterface::canGoPrevious() const
{
    return m_player->hasTrack();
}

bool MprisPlayerInterface::canPlay() const
{
    return m_player->hasTrack() || m_playlist->count() > 0;
}

bool MprisPlayerInterface::canPause() const
{
    return m_player->hasTrack();
}

bool MprisPlayerInterface::canSeek() const
{
    return m_player->hasTrack() && m_player->duration() > 0;
}

void MprisPlayerInterface::Next()
{
    m_playlist->next();
}

void MprisPlayerInterface::Previous()
{
    m_playlist->previous();
}

void MprisPlayerInterface::Pause()
{
    m_player->pause();
}

void MprisPlayerInterface::PlayPause()
{
    m_playlist->playPause();
}

void MprisPlayerInterface::Stop()
{
    m_player->stop();
}

void MprisPlayerInterface::Play()
{
    if (m_player->hasTrack())
        m_player->play();
    else
        m_playlist->playPause(); // starts the playlist
}

// Relative seek in microseconds; past the end means "next track" (per spec).
void MprisPlayerInterface::Seek(qlonglong offset)
{
    if (!canSeek())
        return;
    const qint64 target = m_player->position() + offset / 1000;
    if (target >= m_player->duration())
        Next();
    else
        m_player->seek(qMax<qint64>(target, 0));
}

void MprisPlayerInterface::SetPosition(const QDBusObjectPath &id, qlonglong position)
{
    const qint64 ms = position / 1000;
    if (!canSeek() || id != trackId() || ms < 0 || ms > m_player->duration())
        return;
    m_player->seek(ms);
}

QDBusObjectPath MprisPlayerInterface::trackId() const
{
    const QString source = m_player->source();
    if (source.isEmpty())
        return QDBusObjectPath(QStringLiteral("/org/mpris/MediaPlayer2/TrackList/NoTrack"));
    return QDBusObjectPath(QStringLiteral("/org/tunedchaos/track/t%1").arg(qHash(source)));
}

QVariantMap MprisPlayerInterface::snapshot() const
{
    return {
        {QStringLiteral("PlaybackStatus"), playbackStatus()},
        {QStringLiteral("LoopStatus"), loopStatus()},
        {QStringLiteral("Shuffle"), shuffle()},
        {QStringLiteral("Metadata"), metadata()},
        {QStringLiteral("Volume"), volume()},
        {QStringLiteral("CanGoNext"), canGoNext()},
        {QStringLiteral("CanGoPrevious"), canGoPrevious()},
        {QStringLiteral("CanPlay"), canPlay()},
        {QStringLiteral("CanPause"), canPause()},
        {QStringLiteral("CanSeek"), canSeek()},
    };
}

void MprisPlayerInterface::scheduleUpdate()
{
    m_updateTimer.start();
}

void MprisPlayerInterface::update()
{
    updateArt();

    const QVariantMap current = snapshot();
    QVariantMap changed;
    for (auto it = current.cbegin(); it != current.cend(); ++it) {
        if (m_published.value(it.key()) != it.value())
            changed.insert(it.key(), it.value());
    }
    m_published = current;
    if (changed.isEmpty())
        return;

    QDBusMessage signal = QDBusMessage::createSignal(
        ObjectPath, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("PropertiesChanged"));
    signal << PlayerInterfaceName << changed << QStringList();
    QDBusConnection::sessionBus().send(signal);
}

// Writes cover bytes to ~/.cache/TunedChaos/cover-<hash>.<ext>; returns the
// file, or "" if there was nothing to write. Safe to call off the main thread.
static QString writeCoverFile(const QString &source, const std::vector<unsigned char> &data)
{
    if (data.empty())
        return {};
    const bool png = data.size() > 4 && data[1] == 'P' && data[2] == 'N' && data[3] == 'G';
    const QString dir = Files::cacheDir();
    QDir().mkpath(dir);
    const QString file = dir + QStringLiteral("/cover-%1.%2")
                                   .arg(qHash(source), 0, 16)
                                   .arg(png ? QStringLiteral("png") : QStringLiteral("jpg"));
    QFile out(file);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)
        || out.write(reinterpret_cast<const char *>(data.data()), qint64(data.size())) <= 0)
        return {};
    return file;
}

// MPRIS wants an image URL, so the current cover is written to
// ~/.cache/TunedChaos/. Each track gets its own file name so clients
// that cache by URL refresh; the previous file is removed.
// Remote covers are downloaded too, never published as web addresses:
// a Jellyfin cover address carries the account's token, and anything
// on the session bus can read MPRIS metadata.
void MprisPlayerInterface::updateArt()
{
    const QString source = m_player->source();
    if (source == m_artSource)
        return;
    m_artSource = source;
    const int generation = ++m_artGeneration;

    if (!m_artFile.isEmpty())
        QFile::remove(m_artFile);
    m_artFile.clear();
    m_artUrl.clear();
    if (source.isEmpty())
        return;

    const Track *track = m_playlist->trackForPath(source);
    const QString thumbnail = track ? QString::fromStdString(track->thumbnailUrl) : QString();
    if (thumbnail.isEmpty()) {
        m_artFile = writeCoverFile(source, Metadata::readCover(source.toStdString()));
        if (!m_artFile.isEmpty())
            m_artUrl = QUrl::fromLocalFile(m_artFile).toString();
        return;
    }

    QPointer<MprisPlayerInterface> self(this);
    QThreadPool::globalInstance()->start([self, source, thumbnail, generation] {
        std::vector<unsigned char> data;
        const HttpResponse response = HttpClient::get(thumbnail.toStdString(), {}, 15000);
        if (response.ok())
            data.assign(response.body.begin(), response.body.end());
        const QString file = writeCoverFile(source, data);
        QMetaObject::invokeMethod(qApp, [self, file, generation] {
            if (!self || generation != self->m_artGeneration) {
                if (!file.isEmpty())
                    QFile::remove(file); // the track changed meanwhile
                return;
            }
            if (file.isEmpty())
                return;
            self->m_artFile = file;
            self->m_artUrl = QUrl::fromLocalFile(file).toString();
            self->scheduleUpdate();
        }, Qt::QueuedConnection);
    });
}
