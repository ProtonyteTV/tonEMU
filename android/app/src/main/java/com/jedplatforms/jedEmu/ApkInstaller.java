package com.jedplatforms.jedEmu;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.util.Log;

import androidx.core.content.FileProvider;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.security.MessageDigest;
import java.util.Locale;

/**
 * Hands a downloaded update APK to Android's own package installer (the user still taps
 * "Install" there). Safety checks before the installer is opened:
 *  - the file must be inside <cache>/updates (nothing else can be passed in from Dart),
 *  - its SHA-256 must match when GitHub published one,
 *  - it must be a tonEMU package (same applicationId). Android additionally refuses an update
 *    that is not signed with the same key as the installed app.
 * Every failure is logged (tag tonEmuUpdate) and reported as a short code, never thrown.
 */
final class ApkInstaller {
    private ApkInstaller() {}

    static final String TAG = "tonEmuUpdate";

    static String authority(Activity a) { return a.getPackageName() + ".updates"; }

    static boolean canInstall(Activity a) {
        return Build.VERSION.SDK_INT < 26 || a.getPackageManager().canRequestPackageInstalls();
    }

    /** Opens "Install unknown apps" for tonEMU. Returns false if the screen could not be opened. */
    static boolean openInstallSettings(Activity a) {
        try {
            Intent i = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:" + a.getPackageName()));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            a.startActivity(i);
            return true;
        } catch (Throwable t) {
            Log.w(TAG, "install settings failed: " + t);
            return false;
        }
    }

    /** Returns "ok", or one of: outside, missing, hash, notapk, wrongapp, permission, nohandler, error. */
    static String install(Activity a, String path, String sha256) {
        try {
            File apk = new File(path);
            File dir = new File(a.getCacheDir(), "updates");
            if (!apk.getCanonicalPath().startsWith(dir.getCanonicalPath() + File.separator)) return "outside";
            if (!apk.isFile() || apk.length() == 0) return "missing";
            if (!canInstall(a)) return "permission";

            if (sha256 != null && !sha256.isEmpty()) {
                String got = sha256Of(apk);
                if (got == null || !got.equalsIgnoreCase(sha256)) {
                    Log.w(TAG, "sha256 mismatch: expected " + sha256 + " got " + got);
                    return "hash";
                }
            }

            PackageInfo info = a.getPackageManager().getPackageArchiveInfo(apk.getPath(), 0);
            if (info == null) return "notapk";
            if (!a.getPackageName().equals(info.packageName)) {
                Log.w(TAG, "wrong package in apk: " + info.packageName);
                return "wrongapp";
            }

            Uri uri = FileProvider.getUriForFile(a, authority(a), apk);
            Intent i = new Intent(Intent.ACTION_VIEW);
            i.setDataAndType(uri, "application/vnd.android.package-archive");
            i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
            a.startActivity(i);
            Log.i(TAG, "installer opened for " + info.packageName + " " + info.versionName);
            return "ok";
        } catch (android.content.ActivityNotFoundException e) {
            Log.w(TAG, "no installer: " + e);
            return "nohandler";
        } catch (Throwable t) {
            Log.w(TAG, "install failed: " + t);
            return "error";
        }
    }

    /** Deletes old downloaded updates (keeps the cache small). */
    static void cleanup(Activity a) {
        File[] kids = new File(a.getCacheDir(), "updates").listFiles();
        if (kids != null) for (File k : kids) k.delete();
    }

    private static String sha256Of(File f) {
        try (InputStream in = new FileInputStream(f)) {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] b = new byte[64 * 1024];
            int n;
            while ((n = in.read(b)) > 0) md.update(b, 0, n);
            StringBuilder sb = new StringBuilder();
            for (byte x : md.digest()) sb.append(String.format(Locale.ROOT, "%02x", x & 0xFF));
            return sb.toString();
        } catch (Throwable t) {
            return null;
        }
    }
}