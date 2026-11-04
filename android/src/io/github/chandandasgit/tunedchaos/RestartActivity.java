package io.github.chandandasgit.tunedchaos;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.os.Process;

// Starts the app again (Settings > Appearance > Interface size: the new size
// needs a fresh start). An app can't simply launch a second copy of itself, so
// this invisible screen runs in a process of its own: it ends the app's
// process, opens the app anew and goes away.
public class RestartActivity extends Activity {
    private static final String EXTRA_PID = "pid";

    // From C++, once the app has quit cleanly (settings and the song saved).
    public static void restart(Context context) {
        Intent intent = new Intent(context, RestartActivity.class)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            .putExtra(EXTRA_PID, Process.myPid());
        context.startActivity(intent);
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Process.killProcess(getIntent().getIntExtra(EXTRA_PID, -1));
        startActivity(new Intent(this, MainActivity.class)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK));
        finish();
        Runtime.getRuntime().exit(0); // this helper process isn't needed any more
    }
}
