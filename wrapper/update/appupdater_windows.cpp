// Windows: a running program can't be replaced, so the update is prepared as a
// small script that waits for the app to close, then runs the new setup (a
// copy installed with it: unins000.exe next to the app) or unpacks the new
// portable ZIP over the app's folder, and starts the app again.
#include "wrapper/update/appupdater.h"

#include "wrapper/files/files.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QStringConverter>
#include <QTextStream>

#include <windows.h>

namespace {

QString s_pendingScript; // written by install(), started on "Restart now"

bool installedWithSetup()
{
    return QFileInfo::exists(QCoreApplication::applicationDirPath() + QStringLiteral("/unins000.exe"));
}

QString native(const QString &path)
{
    return QDir::toNativeSeparators(path);
}

// For PowerShell's single-quoted strings
QString psQuoted(const QString &text)
{
    QString out = text;
    return QLatin1Char('\'') + out.replace(QLatin1Char('\''), QStringLiteral("''")) + QLatin1Char('\'');
}

} // namespace

QString UpdatePlatform::assetSuffix()
{
    if (installedWithSetup())
        return QStringLiteral("-setup-x64.exe");
    if (QFileInfo(QCoreApplication::applicationDirPath()).isWritable())
        return QStringLiteral("-windows-x64-portable.zip");
    return {}; // a portable copy in a folder it can't write to: only tell
}

QString UpdatePlatform::downloadFolder()
{
    return Files::cacheDir() + QStringLiteral("/update");
}

bool UpdatePlatform::installAllowed() { return true; }
bool UpdatePlatform::openPermissionSettings() { return true; }
bool UpdatePlatform::readyToInstall() { return true; }

QString UpdatePlatform::install(const QString &file, bool &restart)
{
    restart = true;
    const QString pid = QString::number(QCoreApplication::applicationPid());
    const QString exe = native(QCoreApplication::applicationFilePath());
    const QString appDir = native(QCoreApplication::applicationDirPath());
    const QString script = QFileInfo(file).path() + QStringLiteral("/install-update.cmd");

    QFile out(script);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text))
        return QObject::tr("Couldn't prepare the update.");
    QTextStream s(&out);
    s.setEncoding(QStringConverter::Utf8);
    s << "@echo off\n"
      << "chcp 65001 >nul\n"
      << "rem Tuned Chaos update: waits for the app to close, installs, starts it again\n"
      << ":wait\n"
      << "tasklist /FI \"PID eq " << pid << "\" 2>nul | find \"" << pid << "\" >nul && (timeout /t 1 /nobreak >nul & goto wait)\n";
    if (installedWithSetup()) {
        // The setup keeps the earlier choice (just me / everyone) and the folder
        s << "\"" << native(file) << "\" /SILENT /SUPPRESSMSGBOXES /NORESTART /NOCANCEL\n";
    } else {
        const QString unpacked = native(QFileInfo(file).path() + QStringLiteral("/unpacked"));
        s << "if exist \"" << unpacked << "\" rmdir /s /q \"" << unpacked << "\"\n"
          << "powershell -NoProfile -ExecutionPolicy Bypass -Command \"Expand-Archive -LiteralPath "
          << psQuoted(native(file)) << " -DestinationPath " << psQuoted(unpacked) << " -Force\"\n"
          // (the ZIP holds a TunedChaos folder)
          << "robocopy \"" << unpacked << "\\TunedChaos\" \"" << appDir << "\" /E /NFL /NDL /NJH /NJS /NP >nul\n"
          << "rmdir /s /q \"" << unpacked << "\"\n";
    }
    s << "del \"" << native(file) << "\" >nul 2>&1\n"
      << "start \"\" \"" << exe << "\"\n"
      << "(goto) 2>nul & del \"%~f0\"\n"; // the script removes itself
    s.flush();
    if (out.error() != QFileDevice::NoError)
        return QObject::tr("Couldn't prepare the update.");
    s_pendingScript = script;
    return {};
}

bool UpdatePlatform::startPendingInstall()
{
    if (s_pendingScript.isEmpty())
        return false;
    QProcess process;
    process.setProgram(QStringLiteral("cmd.exe"));
    process.setArguments({QStringLiteral("/c"), native(s_pendingScript)});
    process.setCreateProcessArgumentsModifier([](QProcess::CreateProcessArguments *args) {
        args->flags |= CREATE_NO_WINDOW; // (the setup shows its own progress)
    });
    const bool started = process.startDetached();
    if (started)
        s_pendingScript.clear();
    return started;
}
