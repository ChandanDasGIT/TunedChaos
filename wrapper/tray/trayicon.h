#pragma once

#include <QObject>

#include <memory>

class PlayerController;
class PlaylistController;

// The app's icon in the system tray (Linux: the StatusNotifier tray of the
// desktop or bar; Windows: the notification area). A click shows or hides the
// window; its menu has the playback buttons and Quit. Android has none
// (available stays false there).
// QML: the "Tray" context property.
class TrayIcon : public QObject
{
    Q_OBJECT
    // The icon is showing (the system has a tray): closing the window can hide it there
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    // The window is showing (set by QML), for the menu's Show / Hide
    Q_PROPERTY(bool windowShown READ windowShown WRITE setWindowShown NOTIFY windowShownChanged)

public:
    TrayIcon(PlayerController *player, PlaylistController *playlist, QObject *parent);
    ~TrayIcon() override;

    bool available() const;
    bool windowShown() const { return m_windowShown; }
    void setWindowShown(bool shown);

signals:
    void availableChanged();
    void windowShownChanged();
    void showRequested();   // bring the window to the front
    void hideRequested();   // put the window away (to the tray)
    void quitRequested();   // quit for real

private:
    struct Impl;
    std::unique_ptr<Impl> m_impl;
    bool m_windowShown = true;
};
