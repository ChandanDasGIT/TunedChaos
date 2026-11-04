#include "wrapper/update/appupdater.h"

#include "backend/update/appupdate/appupdate.h"
#include "wrapper/settings/settingscontroller.h"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QPointer>
#include <QThreadPool>
#include <QUrl>

AppUpdater::AppUpdater(SettingsController *settings, QObject *parent)
    : QObject(parent)
    , m_settings(settings)
{
    // Android: back from its settings page, or from the background (only the
    // app on screen may open the installer).
    connect(qGuiApp, &QGuiApplication::applicationStateChanged, this, [this](Qt::ApplicationState state) {
        if (state == Qt::ApplicationActive)
            continueInstall();
    });
}

AppUpdater::~AppUpdater()
{
    if (m_cancelled)
        m_cancelled->store(true);
}

bool AppUpdater::canInstall() const
{
    return !UpdatePlatform::assetSuffix().isEmpty();
}

void AppUpdater::check()
{
    // What an earlier update left: that version, running now, or an older one
    const QString folder = UpdatePlatform::downloadFolder();
    if (!folder.isEmpty())
        for (const QFileInfo &file : QDir(folder).entryInfoList(QDir::Files))
            if (!AppUpdate::isNewer(file.completeBaseName().section(QLatin1Char('-'), 0, 0).toStdString(), APP_VERSION))
                QFile::remove(file.filePath());

    if (!m_settings->appUpdateCheck())
        return;

    QPointer<AppUpdater> self(this);
    const std::string suffix = UpdatePlatform::assetSuffix().toStdString();
    QThreadPool::globalInstance()->start([self, suffix] {
        const std::optional<UpdateRelease> release = AppUpdate::latest();
        QMetaObject::invokeMethod(QCoreApplication::instance(), [self, release, suffix] {
            if (!self || !release || !AppUpdate::isNewer(release->version, APP_VERSION)
                || QString::fromStdString(release->version) == self->m_settings->appUpdateSkipped())
                return;
            const UpdateAsset *asset = suffix.empty() ? nullptr : release->asset(suffix);
            if (!suffix.empty() && !asset)
                return; // a release without our kind of file has nothing to offer here
            self->m_version = QString::fromStdString(release->version);
            self->m_pageUrl = QString::fromStdString(release->pageUrl);
            if (asset) {
                self->m_assetName = QString::fromStdString(asset->name);
                self->m_assetUrl = QString::fromStdString(asset->url);
                self->m_assetSize = asset->size;
                self->m_assetSha256 = QString::fromStdString(asset->sha256);
            }
            emit self->updateAvailable(self->m_version);
        }, Qt::QueuedConnection);
    });
}

void AppUpdater::startUpdate()
{
    if (m_downloading || m_assetUrl.isEmpty())
        return;
    const QString folder = UpdatePlatform::downloadFolder();
    if (folder.isEmpty()) {
        m_error = tr("Couldn't save the download.");
        emit stateChanged();
        return;
    }
    // (Named by version first: check() clears older ones)
    const QString target = folder + QLatin1Char('/') + m_version + QLatin1Char('-') + m_assetName;
    m_error.clear();
    m_progress = 0;
    m_downloading = true;
    m_cancelled = std::make_shared<std::atomic_bool>(false);
    emit progressChanged();
    emit stateChanged();

    UpdateAsset asset;
    asset.name = m_assetName.toStdString();
    asset.url = m_assetUrl.toStdString();
    asset.size = m_assetSize;
    asset.sha256 = m_assetSha256.toStdString();
    QPointer<AppUpdater> self(this);
    QThreadPool::globalInstance()->start([self, asset, target, cancelled = m_cancelled] {
        const std::string error = AppUpdate::download(asset, target.toStdString(), *cancelled, [self](int percent) {
            QMetaObject::invokeMethod(QCoreApplication::instance(), [self, percent] {
                if (!self)
                    return;
                self->m_progress = percent;
                emit self->progressChanged();
            }, Qt::QueuedConnection);
        });
        QMetaObject::invokeMethod(QCoreApplication::instance(), [self, target, error, cancelled] {
            if (!self)
                return;
            self->m_downloading = false;
            if (!cancelled->load()) {
                self->m_error = QString::fromStdString(error);
                if (error.empty())
                    self->m_downloaded = target;
            }
            emit self->stateChanged();
            self->continueInstall();
        }, Qt::QueuedConnection);
    });
}

void AppUpdater::continueInstall()
{
    if (m_downloaded.isEmpty() || !UpdatePlatform::readyToInstall())
        return;
    m_needsPermission = !UpdatePlatform::installAllowed();
    if (m_needsPermission) {
        emit stateChanged();
        return;
    }
    const QString file = m_downloaded;
    m_downloaded.clear();
    bool restart = false;
    m_error = UpdatePlatform::install(file, restart);
    if (m_error.isEmpty() && !restart) {
        emit installStarted(); // the system's installer takes over
        return;
    }
    m_installed = m_error.isEmpty();
    emit stateChanged();
}

void AppUpdater::openInstallSettings()
{
    if (!UpdatePlatform::openPermissionSettings()) {
        m_error = tr("Couldn't open the system's settings.");
        emit stateChanged();
    }
}

void AppUpdater::openDownloadPage()
{
    QDesktopServices::openUrl(QUrl(m_pageUrl.isEmpty()
                                       ? QStringLiteral("https://github.com/ChandanDasGIT/TunedChaos/releases/latest")
                                       : m_pageUrl));
}

void AppUpdater::restartNow()
{
    if (UpdatePlatform::startPendingInstall())
        emit quitRequested(); // (it starts the app again once installed)
    else
        m_settings->restartApp(); // (main starts the new version)
}

void AppUpdater::skipThisVersion()
{
    m_settings->setAppUpdateSkipped(m_version);
}

void AppUpdater::cancel()
{
    if (m_cancelled)
        m_cancelled->store(true);
    m_downloaded.clear();
    m_needsPermission = false;
    m_error.clear();
    emit stateChanged();
}
