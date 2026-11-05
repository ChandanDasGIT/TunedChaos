// Linux: an AppImage swaps its own file; the tarball's copy (~/.local/opt)
// runs the new tarball's install-app.sh. Flatpak and other copies only tell.
#include "wrapper/update/appupdater.h"

#include "wrapper/files/files.h"

#include <QCoreApplication>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QTemporaryDir>

#include <cstdio>

namespace {

// The system's tools, without the app's bundled libraries: the launcher points
// LD_LIBRARY_PATH (and Qt's paths) at them, and e.g. xz then loads the app's
// older liblzma and fails.
QProcessEnvironment systemTools()
{
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    for (const char *name : {"LD_LIBRARY_PATH", "QT_PLUGIN_PATH", "QML_IMPORT_PATH", "QML2_IMPORT_PATH"})
        env.remove(QString::fromLatin1(name));
    return env;
}

enum class Kind { None, AppImage, Tarball };

// How this copy was installed. (Debug builds: TUNEDCHAOS_UPDATE_KIND pretends, for tests.)
Kind kind()
{
#ifndef NDEBUG
    const QString forced = qEnvironmentVariable("TUNEDCHAOS_UPDATE_KIND");
    if (forced == QLatin1String("appimage"))
        return Kind::AppImage;
    if (forced == QLatin1String("tarball"))
        return Kind::Tarball;
#endif
    if (qEnvironmentVariableIsSet("FLATPAK_ID"))
        return Kind::None; // Flatpak updates itself (Flathub, or a new bundle)
    const QString appImage = qEnvironmentVariable("APPIMAGE");
    if (!appImage.isEmpty() && QFileInfo(QFileInfo(appImage).path()).isWritable())
        return Kind::AppImage;
    if (QDir::cleanPath(QCoreApplication::applicationDirPath())
        == QDir::homePath() + QStringLiteral("/.local/opt/TunedChaos/usr/bin"))
        return Kind::Tarball; // where install-app.sh puts it
    return Kind::None;
}

} // namespace

QString UpdatePlatform::assetSuffix()
{
    switch (kind()) {
    case Kind::AppImage: return QStringLiteral("-x86_64.AppImage");
    case Kind::Tarball: return QStringLiteral("-linux-x86_64.tar.xz");
    case Kind::None: break;
    }
    return {};
}

QString UpdatePlatform::downloadFolder()
{
    return Files::cacheDir() + QStringLiteral("/update");
}

bool UpdatePlatform::installAllowed() { return true; }
bool UpdatePlatform::openPermissionSettings() { return true; }
bool UpdatePlatform::readyToInstall() { return true; }

bool UpdatePlatform::startPendingInstall() { return false; }

QString UpdatePlatform::install(const QString &file, bool &restart)
{
    restart = true;
    if (kind() == Kind::AppImage) {
        // The new file next to the old one, then put in its place in one step
        const QString appImage = qEnvironmentVariable("APPIMAGE");
        const QString next = QFileInfo(appImage).path() + QStringLiteral("/.TunedChaos-update.AppImage");
        QFile::remove(next);
        if (!QFile::copy(file, next)
            || !QFile::setPermissions(next, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner
                                                | QFileDevice::ReadGroup | QFileDevice::ExeGroup
                                                | QFileDevice::ReadOther | QFileDevice::ExeOther)
            || std::rename(next.toLocal8Bit().constData(), appImage.toLocal8Bit().constData()) != 0) {
            QFile::remove(next);
            return QObject::tr("Couldn't replace the AppImage (%1).").arg(appImage);
        }
        QFile::remove(file);
        return {};
    }

    // The tarball: unpacked, then its own installer run (as by hand)
    QTemporaryDir unpacked(Files::cacheDir() + QStringLiteral("/update/unpacked-XXXXXX"));
    if (!unpacked.isValid())
        return QObject::tr("Couldn't unpack the update.");
    QProcess tar;
    tar.setProcessEnvironment(systemTools());
    tar.start(QStringLiteral("tar"), {QStringLiteral("-xJf"), file, QStringLiteral("-C"), unpacked.path()});
    if (!tar.waitForFinished(180000) || tar.exitStatus() != QProcess::NormalExit || tar.exitCode() != 0)
        return QObject::tr("Couldn't unpack the update.");
    QString script;
    QDirIterator it(unpacked.path(), {QStringLiteral("install-app.sh")}, QDir::Files, QDirIterator::Subdirectories);
    if (it.hasNext())
        script = it.next();
    if (script.isEmpty())
        return QObject::tr("The update has no installer.");
    QProcess installer;
    installer.setProcessEnvironment(systemTools());
    installer.setWorkingDirectory(QFileInfo(script).path());
    installer.start(QStringLiteral("bash"), {script});
    if (!installer.waitForFinished(180000) || installer.exitStatus() != QProcess::NormalExit || installer.exitCode() != 0)
        return QObject::tr("The update's installer failed: %1")
            .arg(QString::fromLocal8Bit(installer.readAllStandardError()).trimmed());
    QFile::remove(file);
    return {};
}
