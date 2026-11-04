package io.github.chandandasgit.tunedchaos;

import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Environment;
import android.provider.DocumentsContract;
import android.provider.OpenableColumns;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;

// Music Android asks the app to open ("Open with", a file manager, a share):
// turned into a file path the player can read (the song's own file when the
// app may read it, else a copy in the app's cache), then handed to C++
// (wrapper/opener/fileopener_android.cpp).
public class OpenedFiles {
    private static final List<String> s_pending = new ArrayList<>();

    // C++ is ready for them (takePending)
    private static native void nativeFilesOpened();
    private static boolean s_listening = false;

    // From MainActivity: an intent that may carry music
    public static void handle(final Context context, Intent intent) {
        if (intent == null)
            return;
        final List<Uri> uris = new ArrayList<>();
        if (Intent.ACTION_VIEW.equals(intent.getAction()) && intent.getData() != null) {
            uris.add(intent.getData());
        } else if (Intent.ACTION_SEND.equals(intent.getAction())) {
            Uri uri = intent.getParcelableExtra(Intent.EXTRA_STREAM);
            if (uri != null)
                uris.add(uri);
        } else if (Intent.ACTION_SEND_MULTIPLE.equals(intent.getAction())) {
            ArrayList<Uri> list = intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM);
            if (list != null)
                uris.addAll(list);
        }
        if (uris.isEmpty())
            return;
        intent.setData(null); // (not opened again when the activity is recreated)
        intent.removeExtra(Intent.EXTRA_STREAM);
        final Context app = context.getApplicationContext();
        new Thread(() -> { // (a copy can take a moment)
            List<String> paths = new ArrayList<>();
            for (Uri uri : uris) {
                String path = pathFor(app, uri);
                if (path != null)
                    paths.add(path);
            }
            boolean tell;
            synchronized (OpenedFiles.class) {
                s_pending.addAll(paths);
                tell = s_listening && !paths.isEmpty();
            }
            if (tell)
                nativeFilesOpened();
        }, "open-files").start();
    }

    // From C++: what is waiting to be opened; from now on it's told of more.
    public static String[] takePending() {
        synchronized (OpenedFiles.class) {
            s_listening = true;
            String[] out = s_pending.toArray(new String[0]);
            s_pending.clear();
            return out;
        }
    }

    private static String pathFor(Context context, Uri uri) {
        if ("file".equals(uri.getScheme()))
            return uri.getPath();
        // The song's own file, if Android says where it is and the app may read it
        try (Cursor cursor = context.getContentResolver().query(uri, new String[] {"_data"}, null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                String path = cursor.getString(0);
                if (path != null && new File(path).canRead())
                    return path;
            }
        } catch (Exception ignored) {
        }
        // Files picked in Android's own file browser: "primary:Music/song.mp3"
        try {
            if (DocumentsContract.isDocumentUri(context, uri)
                && "com.android.externalstorage.documents".equals(uri.getAuthority())) {
                String[] parts = DocumentsContract.getDocumentId(uri).split(":", 2);
                if (parts.length == 2 && "primary".equalsIgnoreCase(parts[0])) {
                    File file = new File(Environment.getExternalStorageDirectory(), parts[1]);
                    if (file.canRead())
                        return file.getPath();
                }
            }
        } catch (Exception ignored) {
        }
        return copyToCache(context, uri);
    }

    // Anything else: a copy the player can read (cache: Android may clear it)
    private static String copyToCache(Context context, Uri uri) {
        String name = "song";
        try (Cursor cursor = context.getContentResolver().query(uri, new String[] {OpenableColumns.DISPLAY_NAME},
                                                                null, null, null)) {
            if (cursor != null && cursor.moveToFirst() && cursor.getString(0) != null)
                name = cursor.getString(0).replace('/', '_');
        } catch (Exception ignored) {
        }
        File folder = new File(context.getCacheDir(), "opened");
        folder.mkdirs();
        File file = new File(folder, name);
        try (InputStream in = context.getContentResolver().openInputStream(uri);
             OutputStream out = new FileOutputStream(file)) {
            if (in == null)
                return null;
            byte[] buffer = new byte[64 * 1024];
            for (int n; (n = in.read(buffer)) > 0; )
                out.write(buffer, 0, n);
            return file.getPath();
        } catch (Exception e) {
            file.delete();
            return null;
        }
    }
}
