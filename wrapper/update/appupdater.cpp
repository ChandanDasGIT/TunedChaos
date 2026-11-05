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
        if (state != Qt::ApplicationActive) {
            m_leftForInstaller = m_handedOver;
            return;
        }
        // Back from Android's installer and still running: it was cancelled or
        // failed (a finished update replaces this app; it never comes back here)
        if (m_handedOver && m_leftForInstaller) {
            m_handedOver = m_leftForInstaller = false;
            m_settings->setAppUpdatePending(QString());
            showUnfinished(m_version);
            return;
        }
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
    // (A release without this copy's kind of file: only its page)
    return !UpdatePlatform::assetSuffix().isEmpty() && (m_version.isEmpty() || !m_assetUrl.isEmpty());
}

void AppUpdater::check()
{
    // What an earlier update left: that version, running now, or an older one
    const QString folder = UpdatePlatform::downloadFolder();
    if (!folder.isEmpty())
        for (const QFileInfo &file : QDir(folder).entryInfoList(QDir::Files))
            if (!AppUpdate::isNewer(file.completeBaseName().section(QLatin1Char('-'), 0, 0).toStdString(), APP_VERSION))
                QFile::remove(file.filePath());

    // An update handed over earlier: done if this is that version (or newer)
    const QString pending = m_settings->appUpdatePending();
    if (!pending.isEmpty()) {
        m_settings->setAppUpdatePending(QString());
        if (AppUpdate::isNewer(pending.toStdString(), APP_VERSION)) {
            showUnfinished(pending);
            lookForRelease(true, false); // (its file again, for "Try again")
            return;
        }
    }

    if (m_settings->appUpdateCheck())
        lookForRelease(false, false);
}

// Says the update to `version` didn't take, with "Try again" and its page
void AppUpdater::showUnfinished(const QString &version)
{
    m_version = version;
    m_unfinished = true;
    m_installed = false;
    emit stateChanged();
    emit updateAvailable(m_version);
}

void AppUpdater::failed(const QString &error)
{
    m_error = error;
}

void AppUpdater::checkNow()
{
    if (m_checkState == QLatin1String("checking"))
        return;
    if (m_downloading || m_installed || !m_downloaded.isEmpty()) {
        emit updateAvailable(m_version); // (already under way: the dialog shows it)
        return;
    }
    setCheckState(QStringLiteral("checking"));
    lookForRelease(true, true);
}

void AppUpdater::setCheckState(const QString &state)
{
    if (m_checkState == state)
        return;
    m_checkState = state;
    emit checkStateChanged();
}

// `anyVersion`: a skipped version too, and one without our kind of file (its
// page then). `report`: from "Check now", which says how it went (checkState).
void AppUpdater::lookForRelease(bool anyVersion, bool report)
{
    QPointer<AppUpdater> self(this);
    const std::string suffix = UpdatePlatform::assetSuffix().toStdString();
    QThreadPool::globalInstance()->start([self, suffix, anyVersion, report] {
        const std::optional<UpdateRelease> release = AppUpdate::latest();
        QMetaObject::invokeMethod(QCoreApplication::instance(), [self, release, suffix, anyVersion, report] {
            if (!self)
                return;
            if (!release) {
                if (report)
                    self->setCheckState(QStringLiteral("failed"));
                return; // (at startup: being offline is normal)
            }
            if (self->m_downloading)
                return; // (one under way keeps its file)
            if (!AppUpdate::isNewer(release->version, APP_VERSION)
                || (!anyVersion && QString::fromStdString(release->version) == self->m_settings->appUpdateSkipped())) {
                if (report)
                    self->setCheckState(QStringLiteral("latest"));
                return;
            }
            const UpdateAsset *asset = suffix.empty() ? nullptr : release->asset(suffix);
            if (!suffix.empty() && !asset && !anyVersion)
                return; // a release without our kind of file has nothing to offer here
            const QString version = QString::fromStdString(release->version);
            if (version != self->m_version)
                self->m_unfinished = false; // (a newer one than the one that didn't take)
            self->m_version = version;
            self->m_notes = QString::fromStdString(release->notes).trimmed();
            self->m_assetName.clear();
            self->m_assetUrl.clear();
            self->m_assetSize = 0;
            self->m_assetSha256.clear();
            if (asset) {
                self->m_assetName = QString::fromStdString(asset->name);
                self->m_assetUrl = QString::fromStdString(asset->url);
                self->m_assetSize = asset->size;
                self->m_assetSha256 = QString::fromStdString(asset->sha256);
            }
            if (report)
                self->setCheckState(QStringLiteral("found"));
            emit self->stateChanged(); // (canInstall)
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
        failed(tr("Couldn't save the download."));
        emit stateChanged();
        return;
    }
    // (Named by version first: check() clears older ones)
    const QString target = folder + QLatin1Char('/') + m_version + QLatin1Char('-') + m_assetName;
    m_error.clear();
    m_unfinished = false;
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
                if (error.empty())
                    self->m_downloaded = target;
                else
                    self->failed(QString::fromStdString(error));
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
    // Still older at the next start = it didn't take (check() says so then)
    m_settings->setAppUpdatePending(m_version);
    bool restart = false;
    const QString error = UpdatePlatform::install(file, restart);
    if (!error.isEmpty()) {
        m_settings->setAppUpdatePending(QString());
        failed(error);
        emit stateChanged();
        return;
    }
    if (!restart) {
        m_handedOver = true; // the system's installer takes over
        m_leftForInstaller = false;
        emit installStarted();
        return;
    }
    m_installed = true;
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
    // (The newest release's page: also when the check never reached GitHub)
    QDesktopServices::openUrl(QUrl(QStringLiteral("https://github.com/ChandanDasGIT/TunedChaos/releases/latest")));
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
    m_unfinished = false;
    m_error.clear();
    emit stateChanged();
}
