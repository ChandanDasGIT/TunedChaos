package io.github.chandandasgit.tunedchaos;

import android.Manifest;
import android.app.Activity;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.content.pm.ServiceInfo;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.support.v4.media.MediaMetadataCompat;
import android.support.v4.media.session.MediaSessionCompat;
import android.support.v4.media.session.PlaybackStateCompat;

import androidx.core.app.NotificationCompat;
import androidx.core.app.ServiceCompat;
import androidx.core.content.ContextCompat;
import androidx.media.app.NotificationCompat.MediaStyle;

import java.util.ArrayList;
import java.util.List;

// Plays on in the background: Android keeps an app's sound going only while it
// runs a foreground service with a notification. This one is the media
// notification (cover, title, artist; previous / play-pause / next), also on
// the lock screen and for headset buttons, through a media session. The app's
// C++ side (wrapper/systemmedia/systemmedia_android.cpp) tells it what plays
// and gets the buttons pressed (nativeAction).
public class MediaPlaybackService extends Service {
    public static final int PLAY = 0, PAUSE = 1, NEXT = 2, PREVIOUS = 3, STOP = 4;

    private static final String CHANNEL = "playback";
    private static final int NOTIFICATION = 1;
    private static final String ACTION = "io.github.chandandasgit.tunedchaos.ACTION";

    // What plays (set from C++, any thread)
    private static String s_title = "", s_artist = "", s_album = "", s_cover = "";
    private static boolean s_playing = false;
    private static long s_positionMs = 0, s_durationMs = 0;
    private static MediaPlaybackService s_service;

    private MediaSessionCompat m_session;
    private boolean m_foreground = false;

    // With the screen off, Android may put the CPU and Wi-Fi to sleep. While
    // music plays, and for a while after it stops (the next YouTube song or
    // more of a Mix is being fetched), both are kept awake.
    private static final long AWAKE_AFTER_STOP_MS = 60_000;
    private PowerManager.WakeLock m_wakeLock;
    private WifiManager.WifiLock m_wifiLock;
    private final Handler m_handler = new Handler(Looper.getMainLooper());
    private final Runnable m_releaseLocks = this::releaseLocks;

    // A button was pressed (handled in C++)
    private static native void nativeAction(int action);
    // The notification's seek bar was dragged (handled in C++)
    private static native void nativeSeek(long positionMs);

    // From C++: what plays now. Starts the service when a song is loaded, ends it when none is.
    public static void update(Context context, String title, String artist, String album, String cover,
                              boolean playing, boolean hasTrack, long positionMs, long durationMs) {
        synchronized (MediaPlaybackService.class) {
            s_title = title;
            s_artist = artist;
            s_album = album;
            s_cover = cover;
            s_playing = playing;
            s_positionMs = positionMs;
            s_durationMs = durationMs;
        }
        Intent intent = new Intent(context, MediaPlaybackService.class);
        if (hasTrack) {
            if (s_service != null) {
                s_service.keepAwake(playing);
                s_service.refresh();
            }
            else
                ContextCompat.startForegroundService(context, intent);
        } else if (s_service != null) {
            context.stopService(intent);
        }
    }

    // From C++ at start: ask for reading music and showing notifications
    public static void requestPermissions(Context context) {
        if (!(context instanceof Activity))
            return;
        List<String> wanted = new ArrayList<>();
        if (Build.VERSION.SDK_INT >= 33) {
            wanted.add(Manifest.permission.READ_MEDIA_AUDIO);
            wanted.add(Manifest.permission.POST_NOTIFICATIONS);
        } else {
            wanted.add(Manifest.permission.READ_EXTERNAL_STORAGE);
        }
        List<String> missing = new ArrayList<>();
        for (String permission : wanted)
            if (ContextCompat.checkSelfPermission(context, permission) != PackageManager.PERMISSION_GRANTED)
                missing.add(permission);
        if (!missing.isEmpty())
            ((Activity) context).requestPermissions(missing.toArray(new String[0]), 1);
    }

    @Override
    public void onCreate() {
        super.onCreate();
        s_service = this;
        NotificationManager manager = getSystemService(NotificationManager.class);
        manager.createNotificationChannel(
            new NotificationChannel(CHANNEL, "Playback", NotificationManager.IMPORTANCE_LOW));

        m_session = new MediaSessionCompat(this, "Tuned Chaos");
        m_session.setCallback(new MediaSessionCompat.Callback() {
            @Override public void onPlay() { nativeAction(PLAY); }
            @Override public void onPause() { nativeAction(PAUSE); }
            @Override public void onSkipToNext() { nativeAction(NEXT); }
            @Override public void onSkipToPrevious() { nativeAction(PREVIOUS); }
            @Override public void onStop() { nativeAction(STOP); }
            @Override public void onSeekTo(long positionMs) { nativeSeek(positionMs); }
        });
        m_session.setActive(true);

        m_wakeLock = getSystemService(PowerManager.class)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "TunedChaos:playback");
        m_wakeLock.setReferenceCounted(false);
        WifiManager wifi = (WifiManager) getApplicationContext().getSystemService(Context.WIFI_SERVICE);
        if (wifi != null) {
            m_wifiLock = wifi.createWifiLock(Build.VERSION.SDK_INT >= 29 ? WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                                                                          : WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                                             "TunedChaos:playback");
            m_wifiLock.setReferenceCounted(false);
        }
    }

    // Playing: awake. Not playing: awake for AWAKE_AFTER_STOP_MS more. (Any thread.)
    private synchronized void keepAwake(boolean playing) {
        m_handler.removeCallbacks(m_releaseLocks);
        if (!m_wakeLock.isHeld())
            m_wakeLock.acquire();
        if (m_wifiLock != null && !m_wifiLock.isHeld())
            m_wifiLock.acquire();
        if (!playing)
            m_handler.postDelayed(m_releaseLocks, AWAKE_AFTER_STOP_MS);
    }

    private synchronized void releaseLocks() {
        m_handler.removeCallbacks(m_releaseLocks);
        if (m_wakeLock.isHeld())
            m_wakeLock.release();
        if (m_wifiLock != null && m_wifiLock.isHeld())
            m_wifiLock.release();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && ACTION.equals(intent.getAction()))
            nativeAction(intent.getIntExtra("action", PLAY));
        // Only once: a button's result reaches the notification through update().
        // Building it here too would show the old position over the new one.
        if (!m_foreground) {
            boolean playing;
            synchronized (MediaPlaybackService.class) {
                playing = s_playing;
            }
            keepAwake(playing);
            ServiceCompat.startForeground(this, NOTIFICATION, buildNotification(),
                Build.VERSION.SDK_INT >= 29 ? ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK : 0);
            m_foreground = true;
        }
        return START_NOT_STICKY;
    }

    @Override
    public void onDestroy() {
        s_service = null;
        releaseLocks();
        m_session.setActive(false);
        m_session.release();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void refresh() {
        getSystemService(NotificationManager.class).notify(NOTIFICATION, buildNotification());
    }

    private PendingIntent action(int action) {
        Intent intent = new Intent(this, MediaPlaybackService.class).setAction(ACTION).putExtra("action", action);
        return PendingIntent.getService(this, action, intent, PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    // synchronized: called from Android's thread and from C++'s
    private synchronized Notification buildNotification() {
        String title, artist, album, cover;
        boolean playing;
        long positionMs, durationMs;
        synchronized (MediaPlaybackService.class) {
            title = s_title;
            artist = s_artist;
            album = s_album;
            cover = s_cover;
            playing = s_playing;
            positionMs = s_positionMs;
            durationMs = s_durationMs;
        }
        Bitmap art = cover.isEmpty() ? null : BitmapFactory.decodeFile(cover);

        m_session.setMetadata(new MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album)
            .putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, art)
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
            .build());
        // With a length and a position, Android draws a seek bar and moves it by itself.
        // (No length, e.g. a live stream: nothing to seek through, so no bar.)
        long actions = PlaybackStateCompat.ACTION_PLAY | PlaybackStateCompat.ACTION_PAUSE
                       | PlaybackStateCompat.ACTION_PLAY_PAUSE | PlaybackStateCompat.ACTION_SKIP_TO_NEXT
                       | PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS | PlaybackStateCompat.ACTION_STOP;
        if (durationMs > 0)
            actions |= PlaybackStateCompat.ACTION_SEEK_TO;
        m_session.setPlaybackState(new PlaybackStateCompat.Builder()
            .setActions(actions)
            .setState(playing ? PlaybackStateCompat.STATE_PLAYING : PlaybackStateCompat.STATE_PAUSED,
                      durationMs > 0 ? positionMs : PlaybackStateCompat.PLAYBACK_POSITION_UNKNOWN, 1.0f)
            .build());

        Intent open = getPackageManager().getLaunchIntentForPackage(getPackageName());
        PendingIntent openApp = PendingIntent.getActivity(this, 100, open, PendingIntent.FLAG_IMMUTABLE);
        return new NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setLargeIcon(art)
            .setContentTitle(title)
            .setContentText(artist)
            .setSubText(album)
            .setContentIntent(openApp)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setOngoing(playing)
            .addAction(android.R.drawable.ic_media_previous, "Previous", action(PREVIOUS))
            .addAction(playing ? android.R.drawable.ic_media_pause : android.R.drawable.ic_media_play,
                       playing ? "Pause" : "Play", action(playing ? PAUSE : PLAY))
            .addAction(android.R.drawable.ic_media_next, "Next", action(NEXT))
            .setStyle(new MediaStyle().setMediaSession(m_session.getSessionToken()).setShowActionsInCompactView(0, 1, 2))
            .build();
    }
}
