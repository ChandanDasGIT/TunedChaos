#include "wrapper/files/files.h"

#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>
#include <QStorageInfo>

#ifdef Q_OS_ANDROID
#include <QJniObject>
#endif

namespace {

QVariantMap place(const QString &name, const QString &path)
{
    return {{QStringLiteral("name"), name}, {QStringLiteral("url"), QUrl::fromLocalFile(path)}};
}

} // namespace

Files::Files(QObject *parent)
    : QObject(parent)
{
}

void Files::minimizeApp() const
{
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>("io/github/chandandasgit/tunedchaos/MainActivity", "minimize");
#endif
}

QString Files::toPath(const QUrl &url) const
{
    return url.isLocalFile() ? QDir::cleanPath(url.toLocalFile()) : QDir::cleanPath(url.toString());
}

QUrl Files::toUrl(const QString &path) const
{
    return path.isEmpty() ? QUrl() : QUrl::fromLocalFile(QDir::cleanPath(path));
}

QString Files::displayPath(const QUrl &url) const
{
    return QDir::toNativeSeparators(toPath(url));
}

QUrl Files::child(const QUrl &folder, const QString &name) const
{
    return QUrl::fromLocalFile(QDir(toPath(folder)).filePath(name));
}

bool Files::isRoot(const QUrl &folder) const
{
    return QDir(toPath(folder)).isRoot();
}

QUrl Files::parentOf(const QUrl &folder) const
{
    QDir dir(toPath(folder));
    if (!dir.isRoot())
        dir.cdUp();
    return QUrl::fromLocalFile(dir.absolutePath());
}

QVariantList Files::crumbs(const QUrl &folder) const
{
    QVariantList out;
    QDir dir(toPath(folder));
    for (;;) {
        const QString path = dir.absolutePath();
        // A root shows as "/" or "C:"
        const QString name = dir.isRoot() ? (path == QStringLiteral("/") ? path : path.chopped(path.endsWith(u'/') ? 1 : 0))
                                          : dir.dirName();
        out.prepend(place(name, path));
        if (dir.isRoot() || !dir.cdUp())
            break;
    }
    return out;
}

namespace {

QString ownFolder(QStandardPaths::StandardLocation desktop, QStandardPaths::StandardLocation android)
{
#if defined(Q_OS_ANDROID)
    Q_UNUSED(desktop)
    return QStandardPaths::writableLocation(android);
#else
    Q_UNUSED(android)
    return QStandardPaths::writableLocation(desktop) + QStringLiteral("/TunedChaos");
#endif
}

} // namespace

QString Files::configDir()
{
    return ownFolder(QStandardPaths::GenericConfigLocation, QStandardPaths::AppConfigLocation);
}

QString Files::dataDir()
{
    return ownFolder(QStandardPaths::GenericDataLocation, QStandardPaths::AppDataLocation);
}

QString Files::cacheDir()
{
    return ownFolder(QStandardPaths::GenericCacheLocation, QStandardPaths::CacheLocation);
}

void Files::moveOldFolders()
{
#if !defined(Q_OS_ANDROID)
    for (const auto location : {QStandardPaths::GenericConfigLocation, QStandardPaths::GenericDataLocation,
                                QStandardPaths::GenericCacheLocation}) {
        const QString base = QStandardPaths::writableLocation(location);
        const QString oldFolder = base + QStringLiteral("/ChaoticMusicPlayer");
        const QString newFolder = base + QStringLiteral("/TunedChaos");
        // (Windows: config and data are one folder, moved the first time)
        if (QFileInfo(oldFolder).isDir() && !QFileInfo::exists(newFolder))
            QDir().rename(oldFolder, newFolder); // failing, the app starts fresh; nothing is lost
    }
#endif
}

QString Files::appFolder(const QString &kind) const
{
    return kind == QLatin1String("config") ? configDir() : kind == QLatin1String("cache") ? cacheDir() : dataDir();
}

QString Files::homeFolder() const
{
#if defined(Q_OS_ANDROID)
    return QStringLiteral("/storage/emulated/0");
#else
    return QDir::homePath();
#endif
}

QVariantList Files::drives() const
{
    QVariantList out;
#if defined(Q_OS_ANDROID)
    // (the phone's own storage is homeFolder(), listed first already)
    for (const QStorageInfo &volume : QStorageInfo::mountedVolumes()) {
        const QString root = volume.rootPath();
        if (volume.isValid() && volume.isReady() && root.startsWith(QStringLiteral("/storage/"))
            && !root.startsWith(QStringLiteral("/storage/emulated")) && root != QStringLiteral("/storage/self"))
            out.append(place(tr("SD card (%1)").arg(root.section(u'/', -1)), root));
    }
#else
    for (const QStorageInfo &volume : QStorageInfo::mountedVolumes()) {
        const QString root = volume.rootPath();
        if (!volume.isValid() || !volume.isReady())
            continue;
#if defined(Q_OS_WIN)
        // Every drive: "Data (D:)"
        const QString letter = root.left(2);
        const QString label = volume.name();
        out.append(place(label.isEmpty() ? letter : QStringLiteral("%1 (%2)").arg(label, letter), root));
#else
        // The system's own mounts are left out: other disks and USB sticks only
        const bool removableOrExtra = root.startsWith(QStringLiteral("/mnt/")) || root.startsWith(QStringLiteral("/media/"))
                                      || root.startsWith(QStringLiteral("/run/media/"));
        if (!removableOrExtra)
            continue;
        QString name = volume.displayName();
        if (name.isEmpty() || name == root)
            name = root.section(u'/', -1);
        out.append(place(name, root));
#endif
    }
#endif
    return out;
}
