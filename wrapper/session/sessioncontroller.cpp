#include "wrapper/session/sessioncontroller.h"

#include "backend/library/metadata/metadata.h"
#include "backend/youtube/streamresolver/streamresolver.h"
#include "wrapper/player/playercontroller.h"
#include "wrapper/playlist/playlistcontroller.h"
#include "wrapper/playlists/playlistscontroller.h"
#include "wrapper/settings/settingscontroller.h"

#include <QCoreApplication>
#include <QFileInfo>

namespace {

constexpr int SaveIntervalMs = 15000;
// Stopped this close to the end: start the song over instead.
constexpr qint64 NearEndMs = 5000;

} // namespace

SessionController::SessionController(PlayerController *player, PlaylistController *playlist,
                                     PlaylistsController *playlists, SettingsController *settings, QObject *parent)
    : QObject(parent)
    , m_player(player)
    , m_playlist(playlist)
    , m_playlists(playlists)
    , m_settings(settings)
{
    m_timer.setInterval(SaveIntervalMs);
    connect(&m_timer, &QTimer::timeout, this, &SessionController::save);
    connect(m_player, &PlayerController::sourceChanged, this, &SessionController::save);
    connect(m_player, &PlayerController::stateChanged, this, [this] {
        if (m_player->playing())
            m_timer.start();
        else
            m_timer.stop();
        save(); // e.g. paused: remember exactly where
    });
    connect(qApp, &QCoreApplication::aboutToQuit, this, &SessionController::save);
}

void SessionController::save()
{
    const QString path = m_player->source();
    // A titled list playing (Library list, YouTube Mix / album): "list:mix:<title>" / "list:list:<title>".
    const QString list = path.isEmpty() ? QString()
                       : !m_playlist->contextTitle().isEmpty()
                           ? QStringLiteral("list:%1:%2").arg(m_playlist->contextEndless() ? QStringLiteral("mix")
                                                                                              : QStringLiteral("list"),
                                                                 m_playlist->contextTitle())
                       : m_playlist->playingFromList() ? m_playlists->playingFromId()
                                                       : QStringLiteral("queue");
    m_settings->setSession(path, path.isEmpty() ? 0 : m_player->position(), m_player->duration(), list);
}

void SessionController::restore()
{
    const QString path = m_settings->sessionPath();
    if (!m_settings->resumeSession() || path.isEmpty())
        return;
    qint64 position = m_settings->sessionPosition();
    const qint64 duration = m_settings->sessionDuration();
    if (position < 0 || (duration > 0 && position > duration - NearEndMs))
        position = 0;

    const QString list = m_settings->sessionList();
    if (list.startsWith(QLatin1String("list:"))
        && m_playlist->resumeTitled(path, position, list.section(QLatin1Char(':'), 2),
                                     list.section(QLatin1Char(':'), 1, 1) == QLatin1String("mix")))
        return;
    if (!list.isEmpty() && list != QLatin1String("queue") && m_playlists->resumePlaylist(list, path, position))
        return;
    if (m_playlist->resumeInQueue(path, position))
        return;
    // In neither list any more (e.g. the Queue was cleared): a local file still opens on its own.
    if (!StreamResolver::isRemote(path.toStdString()) && QFileInfo::exists(path))
        m_playlist->resumeAlone(Metadata::read(path.toStdString()), position);
}
