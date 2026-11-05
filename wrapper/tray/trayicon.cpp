#include "trayicon.h"

#include "wrapper/player/playercontroller.h"
#include "wrapper/playlist/playlistcontroller.h"

#ifdef CMP_TRAY
#include <QAction>
#include <QGuiApplication>
#include <QIcon>
#include <QMenu>
#include <QSystemTrayIcon>
#include <QTimer>
#endif

#ifdef CMP_TRAY

struct TrayIcon::Impl
{
    QSystemTrayIcon icon;
    QMenu menu;
    QAction *showHide = nullptr;
    QAction *playPause = nullptr;
    QAction *next = nullptr;
    QAction *previous = nullptr;
    bool available = false;
};

TrayIcon::TrayIcon(PlayerController *player, PlaylistController *playlist, QObject *parent)
    : QObject(parent), m_impl(std::make_unique<Impl>())
{
    Impl &d = *m_impl;
    // The installed icon (desktop entry's name), else the one inside the app
    d.icon.setIcon(QIcon::fromTheme(QGuiApplication::desktopFileName(),
                                    QIcon(QStringLiteral(":/qt/qml/TunedChaos/resources/icons/tunedchaos.svg"))));

    d.showHide = d.menu.addAction(tr("Hide Tuned Chaos"));
    d.menu.addSeparator();
    d.playPause = d.menu.addAction(tr("Play"));
    d.next = d.menu.addAction(tr("Next"));
    d.previous = d.menu.addAction(tr("Previous"));
    d.menu.addSeparator();
    QAction *quit = d.menu.addAction(tr("Quit"));
    d.icon.setContextMenu(&d.menu);

    connect(d.showHide, &QAction::triggered, this, [this] { m_windowShown ? emit hideRequested() : emit showRequested(); });
    connect(d.playPause, &QAction::triggered, playlist, &PlaylistController::playPause);
    connect(d.next, &QAction::triggered, playlist, &PlaylistController::next);
    connect(d.previous, &QAction::triggered, playlist, &PlaylistController::previous);
    connect(quit, &QAction::triggered, this, &TrayIcon::quitRequested);
    connect(&d.icon, &QSystemTrayIcon::activated, this, [this](QSystemTrayIcon::ActivationReason reason) {
        if (reason == QSystemTrayIcon::Trigger || reason == QSystemTrayIcon::DoubleClick)
            m_windowShown ? emit hideRequested() : emit showRequested();
    });

    // The tooltip and the menu follow the song
    const auto update = [this, player] {
        Impl &d = *m_impl;
        d.playPause->setText(player->playing() ? tr("Pause") : tr("Play"));
        d.next->setEnabled(player->hasTrack());
        d.previous->setEnabled(player->hasTrack());
        d.icon.setToolTip(player->hasTrack() ? tr("Tuned Chaos: %1").arg(player->title()) : tr("Tuned Chaos"));
    };
    connect(player, &PlayerController::stateChanged, this, update);
    connect(player, &PlayerController::sourceChanged, this, update);
    connect(this, &TrayIcon::windowShownChanged, this, [this] {
        m_impl->showHide->setText(m_windowShown ? tr("Hide Tuned Chaos") : tr("Show Tuned Chaos"));
    });
    update();

    d.icon.show();
    // A tray can appear later (a bar starting after the app): look again for a while
    const auto check = [this] {
        const bool now = QSystemTrayIcon::isSystemTrayAvailable() && m_impl->icon.isVisible();
        if (now != m_impl->available) {
            m_impl->available = now;
            if (now)
                m_impl->icon.show();
            emit availableChanged();
        }
    };
    check();
    auto *timer = new QTimer(this);
    timer->setInterval(5000);
    connect(timer, &QTimer::timeout, this, [this, check] {
        if (!m_impl->icon.isVisible() && QSystemTrayIcon::isSystemTrayAvailable())
            m_impl->icon.show();
        check();
    });
    timer->start();
}

bool TrayIcon::available() const
{
    return m_impl->available;
}

#else // no tray (Android)

struct TrayIcon::Impl
{
};

TrayIcon::TrayIcon(PlayerController *, PlaylistController *, QObject *parent)
    : QObject(parent), m_impl(std::make_unique<Impl>())
{
}

bool TrayIcon::available() const
{
    return false;
}

#endif

TrayIcon::~TrayIcon() = default;

void TrayIcon::setWindowShown(bool shown)
{
    if (shown == m_windowShown)
        return;
    m_windowShown = shown;
    emit windowShownChanged();
}
