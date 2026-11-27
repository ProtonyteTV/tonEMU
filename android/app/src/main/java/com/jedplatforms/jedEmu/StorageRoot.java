package com.jedplatforms.jedEmu;

import android.content.Context;

import java.io.File;

/**
 * The ONE place that decides where tonEMU keeps its files: the app-specific EXTERNAL folder
 * (Android/data/<package>/files/tonEMU). It needs no permission (so no MANAGE_EXTERNAL_STORAGE),
 * Samsung My Files and a PC over USB can browse it, and TonEmuDocumentsProvider exposes the same
 * folder to the system Files app / file pickers. Falls back to private filesDir if external
 * storage is unavailable.
 *
 * Must stay identical to Dart's StorageService on Android: getExternalStorageDirectory()/tonEMU
 * (== getExternalFilesDir(null)), falling back to getApplicationSupportDirectory() (== filesDir).
 */
final class StorageRoot {
    private StorageRoot() {}

    static final String[] FOLDERS = { "roms", "saves", "states", "system", "screenshots" };

    static File get(Context context) {
        File base = context.getExternalFilesDir(null);
        if (base == null) base = context.getFilesDir();
        File dir = new File(base, "tonEMU");
        if (!dir.exists()) dir.mkdirs();
        // Create the standard folders so they are visible in the Files app even before the first launch.
        for (String name : FOLDERS) {
            File f = new File(dir, name);
            if (!f.exists()) f.mkdirs();
        }
        return dir;
    }
}