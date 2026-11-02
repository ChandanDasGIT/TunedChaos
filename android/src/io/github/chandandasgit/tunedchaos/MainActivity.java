package io.github.chandandasgit.tunedchaos;

import org.qtproject.qt.android.bindings.QtActivity;

// The app's activity: Qt's own, but the app ends for good once it is closed.
//
// Swiped away from the recent apps, the activity goes but the process stays
// (the playback service keeps it). Qt then shuts the app down from Android's
// thread, and can hang doing so: its own thread waits to draw a window that no
// longer has a screen, Android's waits for it (an ANR: "not responding", and
// the app won't open again until the process is killed). So once the activity
// is finishing, the process ends at the latest a moment later: Qt gets that
// moment to quit cleanly (settings, where the song was), and the next start is
// always a fresh one.
public class MainActivity extends QtActivity {
    private static final long QUIT_GRACE_MS = 1000;

    @Override
    protected void onDestroy() {
        if (isFinishing()) {
            Thread watchdog = new Thread(() -> {
                try {
                    Thread.sleep(QUIT_GRACE_MS);
                } catch (InterruptedException ignored) {
                }
                android.os.Process.killProcess(android.os.Process.myPid());
            }, "quit-watchdog");
            watchdog.setDaemon(true);
            watchdog.start();
        }
        super.onDestroy();
    }
}
