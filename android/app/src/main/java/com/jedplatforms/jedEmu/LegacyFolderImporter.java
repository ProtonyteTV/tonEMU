package com.jedplatforms.jedEmu;

import android.content.ContentResolver;
import android.content.Context;
import android.database.Cursor;
import android.net.Uri;
import android.provider.DocumentsContract;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * jedManager: brings an OLD tonEMU folder (the one the previous, non-Play-compliant build kept in
 * /storage/emulated/0/tonEMU) into the new app-specific storage.
 *
 * It uses the system folder picker (ACTION_OPEN_DOCUMENT_TREE), so no storage permission is
 * needed: the user picks the old "tonEMU" folder and we copy through DocumentsContract.
 *
 * What is copied: roms/, saves/, states/, system/, screenshots/ and the root file
 * "jed_stats.json" (play time per ROM, see the Dart side). Nothing is ever deleted from the old
 * folder. An existing file is never overwritten unless [overwrite] is set, and then the old copy
 * of a save / state is kept as "<name>.bak".
 *
 * Every file goes through a ".part" side file, so a killed app or a full disk never leaves a
 * half-written ROM or save behind.
 */
final class LegacyFolderImporter {
    private LegacyFolderImporter() {}

    static final String STATS_FILE = "jed_stats.json";
    private static final long SPACE_MARGIN = 16L * 1024 * 1024;

    private static final AtomicBoolean cancelFlag = new AtomicBoolean(false);

    // Live progress, polled from Dart (no callbacks into the Flutter channel needed).
    private static volatile boolean running = false;
    private static volatile int filesTotal = 0, filesDone = 0;
    private static volatile long bytesTotal = 0, bytesDone = 0;
    private static volatile String current = "";

    static void cancel() { cancelFlag.set(true); }

    static Map<String, Object> progress() {
        Map<String, Object> m = new HashMap<>();
        m.put("running", running);
        m.put("filesTotal", filesTotal);
        m.put("filesDone", filesDone);
        m.put("bytesTotal", bytesTotal);
        m.put("bytesDone", bytesDone);
        m.put("current", current);
        return m;
    }

    private static final class Child {
        String id, name, mime;
        long size;
        boolean isDir() { return DocumentsContract.Document.MIME_TYPE_DIR.equals(mime); }
    }

    private static final class Job {
        Uri docUri;
        String rel;     // path inside the new tonEMU root, e.g. "saves/Game.gba.mgba.srm"
        long size;      // -1 when unknown
    }

    private static List<Child> children(ContentResolver cr, Uri tree, String parentId) {
        List<Child> out = new ArrayList<>();
        Uri kids = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId);
        String[] cols = {
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE
        };
        try (Cursor c = cr.query(kids, cols, null, null, null)) {
            if (c == null) return out;
            while (c.moveToNext()) {
                Child k = new Child();
                k.id = c.getString(0);
                k.name = c.getString(1);
                k.mime = c.getString(2);
                k.size = c.isNull(3) ? -1 : c.getLong(3);
                if (k.id != null && k.name != null) out.add(k);
            }
        } catch (Throwable ignored) { }
        return out;
    }

    private static boolean isTemp(String n) {
        String l = n.toLowerCase(Locale.ROOT);
        return l.endsWith(".tmp") || l.endsWith(".part") || l.endsWith(".cp");
    }

    private static boolean safeName(String n) {
        return n != null && !n.isEmpty() && !n.equals(".") && !n.equals("..")
            && n.indexOf('/') < 0 && n.indexOf('\\') < 0;
    }

    private static String knownFolder(String name) {
        String l = name.toLowerCase(Locale.ROOT);
        for (String f : StorageRoot.FOLDERS) if (f.equals(l)) return f;
        return null;
    }

    private static void collect(ContentResolver cr, Uri tree, String dirId, String relPrefix, List<Job> out) {
        if (cancelFlag.get()) return;
        for (Child k : children(cr, tree, dirId)) {
            if (cancelFlag.get()) return;
            if (!safeName(k.name) || isTemp(k.name)) continue;
            // Session leftovers of the old build: never worth copying.
            if (k.name.equals(".timemachine") || k.name.equals(".migrate_tmp")) continue;
            if (k.isDir()) {
                collect(cr, tree, k.id, relPrefix + k.name + "/", out);
            } else {
                Job j = new Job();
                j.docUri = DocumentsContract.buildDocumentUriUsingTree(tree, k.id);
                j.rel = relPrefix + k.name;
                j.size = k.size;
                out.add(j);
            }
        }
    }

    /** Copies the picked folder into [root]. Blocks: call from a background thread. */
    static Map<String, Object> run(Context ctx, Uri tree, File root, boolean overwrite) {
        ContentResolver cr = ctx.getContentResolver();
        cancelFlag.set(false);
        running = true;
        filesTotal = filesDone = 0;
        bytesTotal = bytesDone = 0;
        current = "Looking through the folder…";

        int copied = 0, alreadyThere = 0, kept = 0, failed = 0, noSpace = 0, replaced = 0;
        long copiedBytes = 0;
        boolean statsFound = false;
        List<String> failedNames = new ArrayList<>();
        String sourceName = "";

        try {
            String rootId = DocumentsContract.getTreeDocumentId(tree);
            List<Child> top = children(cr, tree, rootId);

            // The user may have picked the folder that CONTAINS "tonEMU" instead of tonEMU itself.
            boolean looksRight = false;
            for (Child k : top) {
                if ((k.isDir() && knownFolder(k.name) != null) || k.name.equals(STATS_FILE)) looksRight = true;
            }
            String baseId = rootId;
            if (!looksRight) {
                for (Child k : top) {
                    if (k.isDir() && k.name.equalsIgnoreCase("tonEMU")) {
                        baseId = k.id;
                        top = children(cr, tree, baseId);
                        sourceName = k.name;
                        looksRight = true;
                        break;
                    }
                }
            }
            if (!looksRight) {
                Map<String, Object> r = new HashMap<>();
                r.put("notTonEmu", true);
                return r;
            }

            List<Job> jobs = new ArrayList<>();
            for (Child k : top) {
                if (cancelFlag.get()) break;
                if (k.isDir()) {
                    String f = knownFolder(k.name);
                    if (f != null) collect(cr, tree, k.id, f + "/", jobs);
                } else if (k.name.equals(STATS_FILE)) {
                    Job j = new Job();
                    j.docUri = DocumentsContract.buildDocumentUriUsingTree(tree, k.id);
                    j.rel = STATS_FILE;
                    j.size = k.size;
                    jobs.add(j);
                }
            }

            filesTotal = jobs.size();
            for (Job j : jobs) if (j.size > 0) bytesTotal += j.size;

            String base = root.getCanonicalPath() + File.separator;
            byte[] buf = new byte[64 * 1024];

            for (Job j : jobs) {
                if (cancelFlag.get()) break;
                current = j.rel;
                File out = new File(root, j.rel);
                if (!out.getCanonicalPath().startsWith(base)) { filesDone++; continue; } // path guard

                boolean isStats = j.rel.equals(STATS_FILE);
                boolean exists = out.exists();
                if (exists && !isStats) {
                    if (j.size >= 0 && out.length() == j.size) {
                        alreadyThere++;
                        filesDone++;
                        if (j.size > 0) bytesDone += j.size;
                        continue;
                    }
                    if (!overwrite) {
                        kept++;
                        filesDone++;
                        if (j.size > 0) bytesDone += j.size;
                        continue;
                    }
                }
                if (j.size > 0 && !FileUtil.hasFreeSpace(root, j.size + SPACE_MARGIN)) {
                    noSpace++;
                    failedNames.add(j.rel);
                    filesDone++;
                    continue;
                }

                File parent = out.getParentFile();
                if (parent != null && !parent.exists()) parent.mkdirs();
                File part = new File(out.getPath() + ".part");
                try (InputStream in = cr.openInputStream(j.docUri);
                     FileOutputStream fos = new FileOutputStream(part)) {
                    if (in == null) throw new IOException("cannot open");
                    int n;
                    long total = 0;
                    while ((n = in.read(buf)) > 0) {
                        if (cancelFlag.get()) throw new IOException("cancelled");
                        fos.write(buf, 0, n);
                        total += n;
                        bytesDone += n;
                    }
                    fos.getFD().sync();
                    if (j.size >= 0 && total != j.size) throw new IOException("size mismatch");
                    copiedBytes += total;
                } catch (Throwable e) {
                    part.delete();
                    if (cancelFlag.get()) break;
                    failed++;
                    if (failedNames.size() < 20) failedNames.add(j.rel);
                    filesDone++;
                    continue;
                }

                try {
                    // The old copy of a save / state is never thrown away silently.
                    if (exists && !isStats && (j.rel.startsWith("saves/") || j.rel.startsWith("states/"))
                        && out.length() > 0) {
                        try { FileUtil.copy(out, new File(out.getPath() + ".bak")); } catch (IOException ignored) { }
                    }
                    FileUtil.replace(part, out);
                    if (exists && !isStats) replaced++; else copied++;
                    if (isStats) statsFound = true;
                } catch (IOException e) {
                    part.delete();
                    failed++;
                    if (failedNames.size() < 20) failedNames.add(j.rel);
                }
                filesDone++;
            }

            if (!statsFound && new File(root, STATS_FILE).exists()) statsFound = true;
        } catch (Throwable t) {
            failed++;
        } finally {
            running = false;
            current = "";
        }

        Map<String, Object> r = new HashMap<>();
        r.put("copied", copied);
        r.put("replaced", replaced);
        r.put("alreadyThere", alreadyThere);
        r.put("kept", kept);
        r.put("failed", failed);
        r.put("noSpace", noSpace);
        r.put("bytes", copiedBytes);
        r.put("statsFound", statsFound);
        r.put("cancelled", cancelFlag.get());
        r.put("failedNames", failedNames);
        r.put("source", sourceName);
        return r;
    }
}