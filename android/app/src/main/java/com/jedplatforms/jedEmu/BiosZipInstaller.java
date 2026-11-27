package com.jedplatforms.jedEmu;

import java.io.BufferedInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

/**
 * Pulls known BIOS files out of a user zip. [lookup] maps a lower-case file name to the path it
 * must have inside system/ (e.g. "dc_boot.bin" -> "dc/dc_boot.bin"). Folders inside the zip are
 * ignored, names are matched case-insensitively and always written with the exact name the core
 * expects. Returns the relative paths that were installed.
 *
 * Extra safety: a single entry larger than MAX_ENTRY_BYTES is skipped (zip-bomb guard, no BIOS is
 * anywhere near that big) and an entry is skipped when the storage is too full to hold it.
 */
final class BiosZipInstaller {
    private BiosZipInstaller() {}

    /** No real BIOS / firmware / NAND dump is bigger than this. */
    static final long MAX_ENTRY_BYTES = 256L * 1024 * 1024;

    /** What happened to a zip, so the screen can show a clear summary. */
    static final class Report {
        /** Relative paths that were installed. */
        final List<String> installed = new ArrayList<>();
        /** Known BIOS names that were empty (placeholders) and therefore not installed. */
        final List<String> skippedEmpty = new ArrayList<>();
        /** Known BIOS names skipped for being too large or for lack of free space. */
        final List<String> skippedTooBig = new ArrayList<>();
        /** Known BIOS names that failed to write (disk error). */
        final List<String> failed = new ArrayList<>();
        /** Files in the zip that are not BIOS files tonEMU knows. */
        int unknownFiles = 0;
    }

    static List<String> extract(File zipFile, File systemDir, Map<String, String> lookup) throws IOException {
        return extractWithReport(zipFile, systemDir, lookup).installed;
    }

    static Report extractWithReport(File zipFile, File systemDir, Map<String, String> lookup) throws IOException {
        Report report = new Report();
        String base = systemDir.getCanonicalPath() + File.separator;
        byte[] buf = new byte[8192];

        try (ZipInputStream zis = new ZipInputStream(new BufferedInputStream(new FileInputStream(zipFile)))) {
            ZipEntry entry;
            while ((entry = zis.getNextEntry()) != null) {
                if (entry.isDirectory()) continue;
                String raw = entry.getName().replace('\\', '/');
                String name = raw.substring(raw.lastIndexOf('/') + 1).toLowerCase(Locale.ROOT);
                if (name.startsWith("._") || raw.contains("__MACOSX/")) continue; // macOS zip junk
                String rel = lookup.get(name);
                if (rel == null) { report.unknownFiles++; continue; }

                long declared = entry.getSize(); // -1 when the zip does not say
                if (declared > MAX_ENTRY_BYTES || (declared > 0 && !FileUtil.hasFreeSpace(systemDir, declared * 2))) {
                    report.skippedTooBig.add(rel);
                    continue;
                }

                File out = new File(systemDir, rel);
                if (!out.getCanonicalPath().startsWith(base)) continue; // zip-slip guard
                File parent = out.getParentFile();
                if (parent != null && !parent.exists()) parent.mkdirs();
                File tmp = new File(out.getPath() + ".tmp");
                try {
                    long total = 0;
                    boolean tooBig = false;
                    try (FileOutputStream fos = new FileOutputStream(tmp)) {
                        int n;
                        while ((n = zis.read(buf)) > 0) {
                            total += n;
                            if (total > MAX_ENTRY_BYTES) { tooBig = true; break; } // size was not declared
                            fos.write(buf, 0, n);
                        }
                    }
                    if (tooBig) {
                        tmp.delete();
                        report.skippedTooBig.add(rel);
                        continue;
                    }
                    if (total == 0) { // an empty placeholder must never replace a working BIOS
                        tmp.delete();
                        report.skippedEmpty.add(rel);
                        continue;
                    }
                    // Replaces the old file in one step: a failed move never deletes a working BIOS.
                    FileUtil.replace(tmp, out);
                    if (!report.installed.contains(rel)) report.installed.add(rel);
                } catch (IOException e) {
                    // One bad entry (disk full, ...) must not abort the others or leave a .tmp behind.
                    tmp.delete();
                    report.failed.add(rel);
                }
            }
        }
        return report;
    }
}