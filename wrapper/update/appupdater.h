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
// the app has closed, and the app started again. Other kinds (Flatpak, Windows for now, own builds) only
// tell about it, with the release's page. A check that fails stays silent:
// being offline is normal. A download carries on from where it stopped.
class AppUpdater : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool canInstall READ canInstall CONSTANT) // false: only tell (download page)
    Q_PROPERTY(bool downloading READ downloading NOTIFY stateChanged)
    Q_PROPERTY(bool needsPermission READ needsPermission NOTIFY stateChanged)
    Q_PROPERTY(bool installed READ installed NOTIFY stateChanged) // desktop: restart to use it
    Q_PROPERTY(QString error READ error NOTIFY stateChanged) // why the download failed
    Q_PROPERTY(int progress READ progress NOTIFY progressChanged) // percent

public:
    AppUpdater(SettingsController *settings, QObject *parent);
    ~AppUpdater() override;

    void check(); // in the background; off in Settings > About = no check

    bool canInstall() const;
    bool downloading() const { return m_downloading; }
    bool needsPermission() const { return m_needsPermission; }
    bool installed() const { return m_installed; }
    QString error() const { return m_error; }
    int progress() const { return m_progress; }

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
    void quitRequested(); // Windows: the update installs once the app has closed

private:
    void continueInstall();

    SettingsController *m_settings;
    QString m_version, m_pageUrl;
    QString m_assetName, m_assetUrl, m_assetSha256;
    qint64 m_assetSize = 0;
    QString m_downloaded; // waiting to be installed
    QString m_error;
    int m_progress = 0;
    bool m_downloading = false;
    bool m_needsPermission = false;
    bool m_installed = false;
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
