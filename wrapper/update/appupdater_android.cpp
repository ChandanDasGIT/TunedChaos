// Android: the release's APK, handed to Android's installer.
#include "wrapper/update/appupdater.h"

#include <QGuiApplication>
#include <QJniObject>

namespace {

constexpr char kInstaller[] = "io/github/chandandasgit/tunedchaos/AppInstaller";

QJniObject context()
{
    return QNativeInterface::QAndroidApplication::context();
}

} // namespace

QString UpdatePlatform::assetSuffix()
{
    return QStringLiteral(".apk");
}

QString UpdatePlatform::downloadFolder()
{
    return QJniObject::callStaticObjectMethod(kInstaller, "apkFolder", "(Landroid/content/Context;)Ljava/lang/String;",
                                              context().object()).toString();
}

bool UpdatePlatform::installAllowed()
{
    return QJniObject::callStaticMethod<jboolean>(kInstaller, "canInstall", "(Landroid/content/Context;)Z",
                                                  context().object());
}

bool UpdatePlatform::openPermissionSettings()
{
    return QJniObject::callStaticMethod<jboolean>(kInstaller, "openInstallSettings", "(Landroid/content/Context;)Z",
                                                  context().object());
}

bool UpdatePlatform::readyToInstall()
{
    return QGuiApplication::applicationState() == Qt::ApplicationActive;
}

bool UpdatePlatform::startPendingInstall() { return false; }

QString UpdatePlatform::install(const QString &file, bool &restart)
{
    restart = false; // Android's installer replaces and restarts the app itself
    const QJniObject path = QJniObject::fromString(file);
    const bool started = QJniObject::callStaticMethod<jboolean>(kInstaller, "install",
                                                                "(Landroid/content/Context;Ljava/lang/String;)Z",
                                                                context().object(), path.object<jstring>());
    return started ? QString() : QObject::tr("Couldn't open Android's installer.");
}
