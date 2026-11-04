#include "wrapper/notifications/notificationcontroller.h"

#include "backend/network/httpclient/httpclient.h"
#include "backend/youtube/streamresolver/streamresolver.h"
#include "wrapper/albumart/covercontroller.h"
#include "wrapper/player/playercontroller.h"
#include "wrapper/playlist/playlistcontroller.h"
#include "wrapper/settings/settingscontroller.h"

#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QStandardPaths>
#include <QThreadPool>
#include <QUrl>

NotificationController::NotificationController(PlayerController *player, PlaylistController *playlist,
                                               SettingsController *settings, QObject *parent)
    : QObject(parent)
    , m_player(player)
    , m_playlist(playlist)
    , m_settings(settings)
{
    connect(m_player, &PlayerController::sourceChanged, this, [this] { m_pending = m_player->hasTrack(); });
    connect(m_player, &PlayerController::positionChanged, this, &NotificationController::onPosition);
}

// Told once the new song is actually playing (not when it is only loaded, e.g. resumed paused).
void NotificationController::onPosition()
{
    if (!m_pending || !m_player->playing())
        return;
    m_pending = false;
    if (m_settings->notificationsEnabled() && QGuiApplication::applicationState() != Qt::ApplicationActive)
        notify();
}

void NotificationController::notify()
{
    const QString title = !m_playlist->currentTitle().isEmpty() ? m_playlist->currentTitle() : m_player->title();
    const QString subtitle = m_playlist->currentSubtitle();
    const QString path = m_player->source();
    const QString thumbnail = m_playlist->currentThumbnail();
    // The cover may need reading or downloading: off the main thread, then the notification.
    QThreadPool::globalInstance()->start([this, title, subtitle, path, thumbnail] {
        const QString cover = saveCover(path, thumbnail);
        QMetaObject::invokeMethod(this, [this, title, subtitle, cover] { send(title, subtitle, cover); },
                                  Qt::QueuedConnection);
    });
}

QString NotificationController::saveCover(const QString &path, const QString &thumbnail)
{
    std::vector<unsigned char> bytes;
    if (thumbnail.startsWith(QLatin1String("https://")) || thumbnail.startsWith(QLatin1String("http://"))) {
        const HttpResponse response = HttpClient::get(thumbnail.toStdString(), {}, 10000);
        if (response.ok())
            bytes.assign(response.body.begin(), response.body.end());
    } else if (!path.isEmpty() && !StreamResolver::isRemote(path.toStdString())) {
        bytes = CoverController::coverBytes(path.toStdString()); // embedded, or found online
    }
    if (bytes.empty())
        return {};
    const bool png = bytes.size() > 4 && bytes[0] == 0x89 && bytes[1] == 'P';
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QDir().mkpath(dir);
    const QString file = dir + (png ? QStringLiteral("/notification-cover.png") : QStringLiteral("/notification-cover.jpg"));
    QFile out(file);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return {};
    out.write(reinterpret_cast<const char *>(bytes.data()), qint64(bytes.size()));
    return file;
}
