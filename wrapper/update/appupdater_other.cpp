// Systems where the app doesn't install updates itself yet (Windows): it only
// tells about a new version, with the release's page.
#include "wrapper/update/appupdater.h"

QString UpdatePlatform::assetSuffix() { return {}; }
QString UpdatePlatform::downloadFolder() { return {}; }
bool UpdatePlatform::installAllowed() { return true; }
bool UpdatePlatform::openPermissionSettings() { return true; }
bool UpdatePlatform::readyToInstall() { return true; }
QString UpdatePlatform::install(const QString &, bool &restart)
{
    restart = false;
    return QObject::tr("Updates can't be installed here.");
}
