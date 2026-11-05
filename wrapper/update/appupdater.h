#pragma once

#include <QObject>
#include <QString>

#include <atomic>
#include <memory>

class SettingsController;

// Asks GitHub at startup whether a newer Tuned Chaos is out (backend/update)
// and, if asked to, downloads it and installs it the way this copy of the app
// was installed (appupdater_<platform>.cpp): Android's installer for the APK;
// on Linux the AppImage is swapped, or the tarball's install-app.sh run, then
// the app restarts; on Windows the new setup or portable ZIP is installed once
// the app has closed, and the app started again. Other kinds (Flatpak, own builds) only
// tell about it, with the release's page. A check that fails stays silent:
// being offline is normal (unless asked for: Settings > About > Check now). A
// download carries on from where it stopped. Whatever goes wrong, the release's
// page stays one tap away; an update that didn't take (still the old version at
// the next start, or Android's installer back without it) says so.
class AppUpdater : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool canInstall READ canInstall NOTIFY stateChanged) // false: only tell (download page)
    Q_PROPERTY(bool downloading READ downloading NOTIFY stateChanged)
    Q_PROPERTY(bool needsPermission READ needsPermission NOTIFY stateChanged)
    Q_PROPERTY(bool installed READ installed NOTIFY stateChanged) // desktop: restart to use it
    Q_PROPERTY(QString error READ error NOTIFY stateChanged) // why the download failed
    // The update to `version` was handed over but this is still the older one
    // (installer cancelled or failed, the app restarted unchanged...)
    Q_PROPERTY(bool unfinished READ unfinished NOTIFY stateChanged)
    Q_PROPERTY(int progress READ progress NOTIFY progressChanged) // percent
    Q_PROPERTY(QString notes READ notes NOTIFY updateAvailable) // what's new (Markdown)
    // Settings > About's "Check now": "" (not asked), "checking", "latest"
    // (this is the newest), "failed" (GitHub couldn't be reached), "found"
    Q_PROPERTY(QString checkState READ checkState NOTIFY checkStateChanged)

public:
    AppUpdater(SettingsController *settings, QObject *parent);
    ~AppUpdater() override;

    void check(); // in the background; off in Settings > About = no check
    // Asked for: whatever the switch says, a skipped version too; says how it went (checkState)
    Q_INVOKABLE void checkNow();

    bool canInstall() const;
    bool downloading() const { return m_downloading; }
    bool needsPermission() const { return m_needsPermission; }
    bool installed() const { return m_installed; }
    QString error() const { return m_error; }
    bool unfinished() const { return m_unfinished; }
    int progress() const { return m_progress; }
    QString notes() const { return m_notes; }
    QString checkState() const { return m_checkState; }

    Q_INVOKABLE void startUpdate();
    Q_INVOKABLE void openInstallSettings();
    Q_INVOKABLE void openDownloadPage(); // the release's page, in the browser
    Q_INVOKABLE void restartNow();       // after a desktop install
    Q_INVOKABLE void skipThisVersion();  // until a newer one comes out
    Q_INVOKABLE void cancel();           // what was downloaded stays, for next time

signals:
    void updateAvailable(const QString &version);
    void installStarted();
    void stateChanged();
    void progressChanged();
    void checkStateChanged();
    void quitRequested(); // Windows: the update installs once the app has closed

private:
    void lookForRelease(bool anyVersion, bool report);
    void showUnfinished(const QString &version);
    void failed(const QString &error);
    void setCheckState(const QString &state);
    void continueInstall();

    SettingsController *m_settings;
    QString m_version, m_notes;
    QString m_assetName, m_assetUrl, m_assetSha256;
    qint64 m_assetSize = 0;
    QString m_downloaded; // waiting to be installed
    QString m_error;
    QString m_checkState;
    int m_progress = 0;
    bool m_downloading = false;
    bool m_needsPermission = false;
    bool m_installed = false;
    bool m_unfinished = false;
    bool m_handedOver = false;  // Android: its installer has the update
    bool m_leftForInstaller = false;
    std::shared_ptr<std::atomic_bool> m_cancelled;
};

// The parts that differ per system (appupdater_android.cpp, _linux.cpp, _other.cpp).
namespace UpdatePlatform {

QString assetSuffix();    // the release file for this copy of the app ("" = can't install itself)
QString downloadFolder(); // where downloads wait
bool installAllowed();    // Android: "install unknown apps" allowed
bool openPermissionSettings();
bool readyToInstall();    // Android: only the app on screen may open the installer
// Installs `file`: "" when done (or handed to the system's installer), else what went wrong.
// `restart`: the app must start again to use it.
QString install(const QString &file, bool &restart);
// Windows: the install runs once the app has closed (true: it's started; quit
// now, it starts the app again). Elsewhere false: the app restarts itself.
bool startPendingInstall();

} // namespace UpdatePlatform
