#pragma once

#include <QObject>
#include <QUrl>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

// Files and folders for QML (`Files` singleton), the same on every platform:
// QML never builds paths itself ("file://" + "/"), it asks here. Paths use "/"
// between folders (see release/README.md); drive letters ("C:/") and Android
// storage work too.
class Files : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit Files(QObject *parent = nullptr);

    // Android: sends the app to the background (Back at the bottom). Else nothing.
    Q_INVOKABLE void minimizeApp() const;
    Q_INVOKABLE QString toPath(const QUrl &url) const;
    Q_INVOKABLE QUrl toUrl(const QString &path) const;
    // For showing: the platform's own separators ("C:\Music")
    Q_INVOKABLE QString displayPath(const QUrl &url) const;
    Q_INVOKABLE QUrl child(const QUrl &folder, const QString &name) const;
    Q_INVOKABLE bool isRoot(const QUrl &folder) const;
    Q_INVOKABLE QUrl parentOf(const QUrl &folder) const; // a root: itself
    // The path bar: the root, then each folder down to this one: [{ name, url }]
    Q_INVOKABLE QVariantList crumbs(const QUrl &folder) const;
    // Places beyond home for the folder picker: [{ name, url }]. Linux: other
    // disks and USB sticks (/mnt, /media); Windows: every drive; Android: SD cards.
    Q_INVOKABLE QVariantList drives() const;
    // Where browsing starts: the home folder; on Android the phone's storage
    // (the app's own "home" there is its private folder)
    Q_INVOKABLE QString homeFolder() const;

    // The app's own folders: its settings, its data (library, playlists,
    // history) and its cache. Desktop: the system's config / data / cache folder
    // + "/TunedChaos" (~/.config/TunedChaos...; Windows: AppData);
    // Android: the app's private storage. Every file of the app goes in these.
    static QString configDir();
    static QString dataDir();
    static QString cacheDir();
    // Before it was renamed the app kept these in ".../ChaoticMusicPlayer":
    // moves them to the new names, once (desktop). Call before anything reads them.
    static void moveOldFolders();
    // For QML: "config", "data" or "cache"
    Q_INVOKABLE QString appFolder(const QString &kind) const;
};
