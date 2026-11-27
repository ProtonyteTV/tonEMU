package com.jedplatforms.jedEmu;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.security.MessageDigest;
import java.util.Locale;

/**
 * File helpers that work on every Android API level (no java.nio.file, which needs API 26).
 * File.renameTo maps to rename(2): on the same filesystem it replaces the target atomically.
 */
final class FileUtil {
    private FileUtil() {}

    /** Moves [tmp] over [dest], replacing it. Falls back to a copy if the rename is refused. */
    static void replace(File tmp, File dest) throws IOException {
        if (tmp.renameTo(dest)) return;
        copy(tmp, dest);
        tmp.delete();
    }

    /** Copies [src] to [dst] through a side file, so a failed copy never leaves a half-written [dst]. */
    static void copy(File src, File dst) throws IOException {
        File parent = dst.getParentFile();
        if (parent != null && !parent.exists()) parent.mkdirs();
        File part = new File(dst.getPath() + ".cp");
        try (InputStream in = new FileInputStream(src);
             OutputStream out = new FileOutputStream(part)) {
            byte[] b = new byte[8192];
            int n;
            while ((n = in.read(b)) > 0) out.write(b, 0, n);
        } catch (IOException e) {
            part.delete();
            throw e;
        }
        if (!part.renameTo(dst)) {
            part.delete();
            throw new IOException("rename failed: " + dst);
        }
    }

    /** True if the volume that holds [dir] (or its nearest existing parent) has at least [needed] bytes free. */
    static boolean hasFreeSpace(File dir, long needed) {
        File d = dir;
        while (d != null && !d.exists()) d = d.getParentFile();
        if (d == null) return true; // cannot tell: do not block the user
        return d.getUsableSpace() >= needed;
    }

    /** Lower-case hex SHA-1 of a file (for BIOS identification), or null if it cannot be read. */
    static String sha1(File f) {
        try (InputStream in = new FileInputStream(f)) {
            MessageDigest md = MessageDigest.getInstance("SHA-1");
            byte[] b = new byte[8192];
            int n;
            while ((n = in.read(b)) > 0) md.update(b, 0, n);
            StringBuilder sb = new StringBuilder();
            for (byte x : md.digest()) sb.append(String.format(Locale.ROOT, "%02x", x & 0xFF));
            return sb.toString();
        } catch (Throwable t) {
            return null;
        }
    }

    /** Deletes a file or a whole folder tree. Returns true if nothing is left. */
    static boolean deleteTree(File f) {
        if (f == null || !f.exists()) return true;
        File[] kids = f.isDirectory() ? f.listFiles() : null;
        if (kids != null) for (File k : kids) deleteTree(k);
        return f.delete();
    }

    static byte[] readAll(File f) throws IOException {
        try (InputStream in = new FileInputStream(f);
             ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            byte[] b = new byte[8192];
            int n;
            while ((n = in.read(b)) > 0) out.write(b, 0, n);
            return out.toByteArray();
        }
    }
}