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
    private static MainActivity instance;

    @Override
    public void onCreate(android.os.Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        instance = this;
        OpenedFiles.handle(this, getIntent()); // opened to play a file
    }

    // A file opened while the app runs ("Open with" with the app already open)
    @Override
    protected void onNewIntent(android.content.Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        OpenedFiles.handle(this, intent);
    }

    // Back with nothing left to go back from: the app goes to the background
    // (like Home) instead of closing.
    public static void minimize() {
        final MainActivity activity = instance;
        if (activity != null)
            activity.runOnUiThread(() -> activity.moveTaskToBack(true));
    }

    @Override
    protected void onDestroy() {
        if (instance == this)
            instance = null;
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
