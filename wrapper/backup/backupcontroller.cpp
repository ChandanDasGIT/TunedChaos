#include "backupcontroller.h"

#include "backend/backup/backuparchive/backuparchive.h"
#include "wrapper/files/files.h"
#include "wrapper/settings/settingscontroller.h"

#include <QCoreApplication>
#include <QDate>
#include <QDir>
#include <QFileInfo>
#include <QUrl>

namespace {

BackupArchive::Folders folders()
{
    return {QDir::toNativeSeparators(Files::configDir()).toStdString(),
            QDir::toNativeSeparators(Files::dataDir()).toStdString()};
}

// Outside the folders it restores (they are emptied)
std::string stagingDir()
{
    return QDir(Files::cacheDir()).filePath(QStringLiteral("restore-pending")).toStdString();
}

QString localPath(const QString &file)
{
    const QUrl url(file);
    return url.isLocalFile() ? url.toLocalFile() : file;
}

} // namespace

BackupController::BackupController(SettingsController *settings, QObject *parent)
    : QObject(parent), m_settings(settings)
{
}

QString BackupController::suggestedName() const
{
    return QStringLiteral("TunedChaos-backup-%1.tcbackup").arg(QDate::currentDate().toString(Qt::ISODate));
}

void BackupController::backUp(const QString &file)
{
    if (file.isEmpty())
        return;
    m_settings->flush(); // the latest settings in the file first
    std::string error;
    if (BackupArchive::create(folders(), localPath(file).toStdString(), error))
        emit notice(tr("Backed up to %1").arg(QFileInfo(localPath(file)).fileName()));
    else
        emit notice(tr("Couldn't back up: %1").arg(QString::fromStdString(error)));
}

void BackupController::restore(const QString &file)
{
    if (file.isEmpty())
        return;
    std::string error;
    const int count = BackupArchive::restore(localPath(file).toStdString(), stagingDir(),
                                             long(QCoreApplication::applicationPid()), error);
    if (count < 0) {
        emit notice(tr("Couldn't restore: %1").arg(QString::fromStdString(error)));
        return;
    }
    m_settings->restartApp(); // the next start puts it in place
}

bool BackupController::applyPending()
{
    return BackupArchive::applyStaged(stagingDir(), folders());
}
