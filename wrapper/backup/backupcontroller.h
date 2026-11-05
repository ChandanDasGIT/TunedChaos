#pragma once

#include <QObject>
#include <QString>

class SettingsController;

// Settings > About > Back up / Restore (QML: the "Backup" context property).
// One file with the app's settings and data; restoring replaces them and
// restarts the app (see backend/backup/backuparchive).
class BackupController : public QObject
{
    Q_OBJECT

public:
    BackupController(SettingsController *settings, QObject *parent);

    // A file name for a new backup, e.g. "TunedChaos-backup-2026-11-05.tcbackup"
    Q_INVOKABLE QString suggestedName() const;
    // Writes a backup to that file (a path or file:// URL); says how it went (notice)
    Q_INVOKABLE void backUp(const QString &file);
    // Checks that file and, if it's a backup, restarts the app with it in place
    Q_INVOKABLE void restore(const QString &file);

    // At start, before anything reads the folders: a restore waiting is put in place
    static bool applyPending();

signals:
    void notice(const QString &text);

private:
    SettingsController *m_settings;
};
