package io.github.chandandasgit.tunedchaos;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.widget.RemoteViews;

// The home-screen player: the cover, the song and previous / play / next.
// It shows what MediaPlaybackService knows (set from C++). While the app runs
// the buttons reach the player; otherwise every tap opens the app (the player
// isn't loaded, nothing could act on a button).
public class PlayerWidget extends AppWidgetProvider {
    private static final String BUTTON = "io.github.chandandasgit.tunedchaos.WIDGET_BUTTON";

    // What the widgets show now (to redraw only when it changes)
    private static String s_shown = null;
    private static String s_coverPath = null;
    private static Bitmap s_cover = null;

    @Override
    public void onUpdate(Context context, AppWidgetManager manager, int[] ids) {
        s_shown = null; // a new widget: draw it whatever was shown before
        refresh(context);
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        if (BUTTON.equals(intent.getAction())) {
            int action = intent.getIntExtra("action", MediaPlaybackService.PLAY);
            if (!MediaPlaybackService.sendAction(action)) {
                // The app was closed meanwhile: open it, and show the widget as such
                openApp(context);
                s_shown = null;
                refresh(context);
            }
            return;
        }
        super.onReceive(context, intent);
    }

    // From MediaPlaybackService whenever what plays may have changed.
    static synchronized void refresh(Context context) {
        AppWidgetManager manager = AppWidgetManager.getInstance(context);
        int[] ids = manager.getAppWidgetIds(new ComponentName(context, PlayerWidget.class));
        if (ids.length == 0)
            return;

        MediaPlaybackService.State state = MediaPlaybackService.state();
        boolean live = state.running && state.hasTrack;
        String key = live + "\n" + state.title + "\n" + state.artist + "\n" + state.cover + "\n" + state.playing;
        if (key.equals(s_shown))
            return;
        s_shown = key;

        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_player);
        views.setTextViewText(R.id.widget_title, live ? state.title : "Tuned Chaos");
        views.setTextViewText(R.id.widget_artist, live ? state.artist : "Tap to open");
        Bitmap cover = live ? coverOf(state.cover) : null;
        if (cover != null)
            views.setImageViewBitmap(R.id.widget_cover, cover);
        else
            views.setImageViewResource(R.id.widget_cover, R.mipmap.ic_launcher);
        views.setImageViewResource(R.id.widget_play, live && state.playing ? android.R.drawable.ic_media_pause
                                                                           : android.R.drawable.ic_media_play);

        PendingIntent open = openIntent(context);
        views.setOnClickPendingIntent(R.id.widget_root, open);
        views.setOnClickPendingIntent(R.id.widget_cover, open);
        views.setOnClickPendingIntent(R.id.widget_text, open);
        if (live) {
            views.setOnClickPendingIntent(R.id.widget_previous, button(context, MediaPlaybackService.PREVIOUS));
            views.setOnClickPendingIntent(R.id.widget_play, button(context, state.playing ? MediaPlaybackService.PAUSE
                                                                                          : MediaPlaybackService.PLAY));
            views.setOnClickPendingIntent(R.id.widget_next, button(context, MediaPlaybackService.NEXT));
        } else {
            views.setOnClickPendingIntent(R.id.widget_previous, open);
            views.setOnClickPendingIntent(R.id.widget_play, open);
            views.setOnClickPendingIntent(R.id.widget_next, open);
        }
        manager.updateAppWidget(ids, views);
    }

    // The cover, small (a widget's pictures travel between processes: keep them light)
    private static Bitmap coverOf(String path) {
        if (path == null || path.isEmpty())
            return null;
        if (path.equals(s_coverPath))
            return s_cover;
        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        BitmapFactory.decodeFile(path, bounds);
        BitmapFactory.Options options = new BitmapFactory.Options();
        options.inSampleSize = 1;
        while (Math.max(bounds.outWidth, bounds.outHeight) / (options.inSampleSize * 2) >= 192)
            options.inSampleSize *= 2;
        Bitmap bitmap = BitmapFactory.decodeFile(path, options);
        if (bitmap != null && Math.max(bitmap.getWidth(), bitmap.getHeight()) > 256)
            bitmap = Bitmap.createScaledBitmap(bitmap, 192, Math.max(1, 192 * bitmap.getHeight() / bitmap.getWidth()), true);
        s_coverPath = path;
        s_cover = bitmap;
        return bitmap;
    }

    private static PendingIntent button(Context context, int action) {
        Intent intent = new Intent(context, PlayerWidget.class).setAction(BUTTON).putExtra("action", action);
        return PendingIntent.getBroadcast(context, 200 + action, intent,
                                          PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    private static PendingIntent openIntent(Context context) {
        Intent open = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        return PendingIntent.getActivity(context, 210, open, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    private static void openApp(Context context) {
        Intent open = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        if (open == null)
            return;
        open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        try {
            context.startActivity(open);
        } catch (RuntimeException e) {
            // (Android may not let a closed app open itself from the background)
        }
    }
}
