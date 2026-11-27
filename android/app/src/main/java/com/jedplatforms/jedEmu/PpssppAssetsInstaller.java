package com.jedplatforms.jedEmu;

import java.io.BufferedInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.Locale;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/**
 * PPSSPP system fonts (flash0/font/*.pgf) and UI assets are NOT bundled with tonEMU: the user
 * imports a PPSSPP.zip, which is extracted into:
 *   <filesDir>/tonEMU/system/PPSSPP/flash0/font/
 * and mirrored to <filesDir>/tonEMU/system/PPSSPP/assets/flash0/ so every libppsspp_libretro
 * revision finds the system dialog fonts. Without them games still run, but system dialogs
 * (save / load prompts) show no text.
 *
 * An import only counts as complete once the ".installed" marker exists, and the marker is written
 * LAST, so an interrupted copy (low storage, process killed) never looks finished.
 */
final class PpssppAssetsInstaller {
    private PpssppAssetsInstaller() {}

    private static final String MARKER = ".installed";

    static boolean isPpsspp(String coreName) {
        return coreName != null && coreName.toLowerCase(Locale.ROOT).contains("ppsspp");
    }

    /**
     * system/ is visible to the user, so the gallery would index PPSSPP's PNG/JPG UI assets as
     * photos. A ".nomedia" file makes every media scanner and photo app skip the whole folder
     * (including sub-folders). Safe to call any number of times.
     */
    static void hideFromGallery(File systemDir) {
        File ppssppDir = new File(systemDir, "PPSSPP");
        try {
            if (!ppssppDir.exists()) ppssppDir.mkdirs();
            File nomedia = new File(ppssppDir, ".nomedia");
            if (!nomedia.exists()) nomedia.createNewFile();
        } catch (IOException ignored) { }
    }

    static boolean isInstalled(File systemDir) {
        File ppssppDir = new File(systemDir, "PPSSPP");
        if (!new File(ppssppDir, MARKER).exists()) return false;
        File f1 = new File(ppssppDir, "flash0/font/ltn0.pgf");
        File f2 = new File(ppssppDir, "assets/flash0/font/ltn0.pgf");
        return (f1.exists() && f1.length() > 0) || (f2.exists() && f2.length() > 0);
    }

    /**
     * Prepares the PPSSPP folder before a game starts. Nothing is bundled: fonts come from the
     * user's PPSSPP.zip (see extractZip), so this only keeps the folder hidden from the gallery.
     */
    static synchronized void ensureInstalled(android.content.Context context, File systemDir) {
        hideFromGallery(systemDir);
    }

    private static void markInstalled(File ppssppDir) {
        File font = new File(ppssppDir, "flash0/font/ltn0.pgf");
        File font2 = new File(ppssppDir, "assets/flash0/font/ltn0.pgf");
        if (!(font.length() > 0 || font2.length() > 0)) return; // nothing usable was installed
        try {
            new File(ppssppDir, MARKER).createNewFile();
        } catch (IOException ignored) { }
    }

    /**
     * Extracts a user-imported PPSSPP.zip into system/PPSSPP/, normalizing ANY nested
     * wrapper folders (e.g. "PPSSPP-master/assets/flash0/..." -> "flash0/...").
     * Returns the number of font files (.pgf / .bwfon) installed.
     */
    static synchronized int extractZip(File zipFile, File systemDir) throws IOException {
        File ppssppDir = new File(systemDir, "PPSSPP");
        hideFromGallery(systemDir); // before the first file is written, so nothing is ever indexed

        int fontCount = 0;
        String canonicalBase = ppssppDir.getCanonicalPath() + File.separator;

        try (ZipInputStream zis = new ZipInputStream(new BufferedInputStream(new FileInputStream(zipFile)))) {
            ZipEntry entry;
            byte[] buf = new byte[8192];
            while ((entry = zis.getNextEntry()) != null) {
                String raw = entry.getName().replace('\\', '/');
                String normalized = normalizeEntryPath(raw);
                if (normalized.isEmpty()) continue;
                // Skip macOS zip junk ("__MACOSX/", "._name") so it is never installed or counted as a font.
                if (raw.contains("__MACOSX/") || normalized.substring(normalized.lastIndexOf('/') + 1).startsWith("._")) continue;

                if (normalized.equals(".nomedia")) continue; // ours; the zip must not replace it

                File outFile = new File(ppssppDir, normalized);
                if (!outFile.getCanonicalPath().startsWith(canonicalBase)) continue; // zip-slip guard

                if (entry.isDirectory()) {
                    // Parents are created when a file is written; creating folders here left empty
                    // wrapper folders such as "PPSSPP-master/" behind.
                    zis.closeEntry();
                    continue;
                } else {
                    File parent = outFile.getParentFile();
                    if (parent != null && !parent.exists()) parent.mkdirs();
                    // Write to a temp file and move it into place, so an interrupted import (low
                    // storage, app killed) can never leave a half-written font/asset behind.
                    File tmp = new File(outFile.getPath() + ".part");
                    try {
                        try (FileOutputStream fos = new FileOutputStream(tmp)) {
                            int n;
                            while ((n = zis.read(buf)) > 0) fos.write(buf, 0, n);
                        }
                        FileUtil.replace(tmp, outFile);
                    } catch (IOException e) {
                        tmp.delete();
                        throw e;
                    }
                    String lower = normalized.toLowerCase(Locale.ROOT);
                    if (lower.endsWith(".pgf") || lower.endsWith(".bwfon")) {
                        fontCount++;
                    }
                }
                zis.closeEntry();
            }
        }

        mirrorFlash0(ppssppDir);
        if (fontCount > 0) markInstalled(ppssppDir);
        return fontCount;
    }

    /**
     * Strips arbitrary outer folders so "flash0/...", "lang/...", "shaders/..." sit at root.
     * An anchor only matches as a WHOLE folder name (start of path or right after a "/"), so a
     * folder like "english_lang/" or "myflash0/" is no longer cut in the middle.
     */
    private static String normalizeEntryPath(String path) {
        String[] anchors = new String[] { "flash0/", "lang/", "shaders/", "themes/" };
        for (String anchor : anchors) {
            if (path.startsWith(anchor)) return path;
            int idx = path.indexOf("/" + anchor);
            if (idx >= 0) return path.substring(idx + 1);
        }
        String p = path;
        boolean changed = true;
        while (changed) {
            changed = false;
            if (p.startsWith("PPSSPP/")) { p = p.substring("PPSSPP/".length()); changed = true; }
            else if (p.startsWith("assets/")) { p = p.substring("assets/".length()); changed = true; }
            else {
                int i = p.indexOf("/assets/");
                if (i >= 0) { p = p.substring(i + "/assets/".length()); changed = true; }
            }
        }
        return p;
    }

    /** Mirrors PPSSPP/flash0 -> PPSSPP/assets/flash0 for cores expecting the assets/ subpath. */
    private static void mirrorFlash0(File ppssppDir) {
        File src = new File(ppssppDir, "flash0");
        if (!src.isDirectory()) return;
        File dst = new File(ppssppDir, "assets/flash0");
        copyDirectory(src, dst);
    }

    private static void copyDirectory(File src, File dst) {
        File[] children = src.listFiles();
        if (children == null) return;
        if (!dst.exists()) dst.mkdirs();
        for (File child : children) {
            File target = new File(dst, child.getName());
            if (child.isDirectory()) {
                copyDirectory(child, target);
            } else {
                try {
                    FileUtil.copy(child, target);
                } catch (IOException ignored) {
                }
            }
        }
    }
}