package com.jedplatforms.jedEmu;

import android.content.Context;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.CancellationSignal;
import android.os.ParcelFileDescriptor;
import android.provider.DocumentsContract;
import android.provider.DocumentsContract.Document;
import android.provider.DocumentsContract.Root;
import android.provider.DocumentsProvider;
import android.webkit.MimeTypeMap;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.util.Locale;

/**
 * Shows the tonEMU folder (roms / saves / states / system / screenshots) in the Android Files app
 * and in every "choose a file" dialog. This is the Google-Play-approved way to give users access to
 * an app's files: no All Files Access permission, and the user still sees "tonEMU" as a storage
 * location they can browse, copy from / to, rename and delete in.
 *
 * Document ids are paths relative to the root: "tonemu" is the root, "tonemu/system/dc/x.bin" a file.
 * Every id is resolved through fileFor(), which rejects anything that escapes the root
 * (".." or symlinks), so a hostile client cannot reach other app data.
 */
public class TonEmuDocumentsProvider extends DocumentsProvider {
    static final String ROOT_ID = "tonemu";

    private static final String[] ROOT_PROJECTION = {
        Root.COLUMN_ROOT_ID, Root.COLUMN_MIME_TYPES, Root.COLUMN_FLAGS, Root.COLUMN_ICON,
        Root.COLUMN_TITLE, Root.COLUMN_SUMMARY, Root.COLUMN_DOCUMENT_ID, Root.COLUMN_AVAILABLE_BYTES
    };
    private static final String[] DOC_PROJECTION = {
        Document.COLUMN_DOCUMENT_ID, Document.COLUMN_MIME_TYPE, Document.COLUMN_DISPLAY_NAME,
        Document.COLUMN_LAST_MODIFIED, Document.COLUMN_FLAGS, Document.COLUMN_SIZE
    };

    static String authority(Context c) { return c.getPackageName() + ".documents"; }

    @Override public boolean onCreate() { return true; }

    private File root() { return StorageRoot.get(getContext()); }

    // The full projection is always returned (a superset of what a client asks for).
    @Override
    public Cursor queryRoots(String[] projection) {
        MatrixCursor c = new MatrixCursor(ROOT_PROJECTION);
        File root = root();
        MatrixCursor.RowBuilder r = c.newRow();
        r.add(Root.COLUMN_ROOT_ID, ROOT_ID);
        r.add(Root.COLUMN_DOCUMENT_ID, ROOT_ID);
        r.add(Root.COLUMN_TITLE, "tonEMU");
        r.add(Root.COLUMN_SUMMARY, "Games, BIOS and saves");
        r.add(Root.COLUMN_ICON, R.mipmap.ic_launcher);
        r.add(Root.COLUMN_MIME_TYPES, "*/*");
        r.add(Root.COLUMN_FLAGS, Root.FLAG_SUPPORTS_CREATE | Root.FLAG_SUPPORTS_IS_CHILD | Root.FLAG_LOCAL_ONLY);
        r.add(Root.COLUMN_AVAILABLE_BYTES, root.getUsableSpace());
        return c;
    }

    @Override
    public Cursor queryDocument(String documentId, String[] projection) throws FileNotFoundException {
        MatrixCursor c = new MatrixCursor(DOC_PROJECTION);
        includeFile(c, fileFor(documentId));
        return c;
    }

    @Override
    public Cursor queryChildDocuments(String parentId, String[] projection, String sortOrder)
            throws FileNotFoundException {
        MatrixCursor c = new MatrixCursor(DOC_PROJECTION);
        File parent = fileFor(parentId);
        if (!parent.isDirectory()) throw new FileNotFoundException("Not a folder: " + parentId);
        File[] kids = parent.listFiles();
        if (kids != null) {
            for (File k : kids) {
                if (isTempName(k.getName())) continue; // half-written files of a running save / import
                includeFile(c, k);
            }
        }
        c.setNotificationUri(getContext().getContentResolver(),
            DocumentsContract.buildChildDocumentsUri(authority(getContext()), parentId));
        return c;
    }

    @Override
    public ParcelFileDescriptor openDocument(String documentId, String mode, CancellationSignal signal)
            throws FileNotFoundException {
        File f = fileFor(documentId);
        if (f.isDirectory()) throw new FileNotFoundException("Is a folder: " + documentId);
        return ParcelFileDescriptor.open(f, ParcelFileDescriptor.parseMode(mode));
    }

    @Override
    public String createDocument(String parentId, String mimeType, String displayName)
            throws FileNotFoundException {
        File parent = fileFor(parentId);
        if (!parent.isDirectory()) throw new FileNotFoundException("Not a folder: " + parentId);
        File f = uniqueFile(parent, cleanName(displayName));
        try {
            boolean ok = Document.MIME_TYPE_DIR.equals(mimeType) ? f.mkdir() : f.createNewFile();
            if (!ok) throw new FileNotFoundException("Could not create " + f.getName());
        } catch (IOException e) {
            throw new FileNotFoundException("Could not create " + f.getName() + ": " + e.getMessage());
        }
        notifyChildren(parentId);
        return idFor(f);
    }

    @Override
    public void deleteDocument(String documentId) throws FileNotFoundException {
        File f = fileFor(documentId);
        if (isProtected(f)) throw new FileNotFoundException("tonEMU needs this folder");
        if (!FileUtil.deleteTree(f)) throw new FileNotFoundException("Could not delete " + f.getName());
        notifyChildren(idFor(f.getParentFile()));
    }

    @Override
    public String renameDocument(String documentId, String displayName) throws FileNotFoundException {
        File f = fileFor(documentId);
        if (isProtected(f)) throw new FileNotFoundException("tonEMU needs this folder");
        File dest = new File(f.getParentFile(), cleanName(displayName));
        if (dest.exists()) throw new FileNotFoundException("A file with that name already exists");
        if (!f.renameTo(dest)) throw new FileNotFoundException("Could not rename " + f.getName());
        notifyChildren(idFor(f.getParentFile()));
        return idFor(dest);
    }

    @Override
    public boolean isChildDocument(String parentId, String documentId) {
        try {
            String p = fileFor(parentId).getCanonicalPath();
            String d = fileFor(documentId).getCanonicalPath();
            return d.equals(p) || d.startsWith(p + File.separator);
        } catch (IOException e) {
            return false;
        }
    }

    @Override
    public String getDocumentType(String documentId) throws FileNotFoundException {
        File f = fileFor(documentId);
        return f.isDirectory() ? Document.MIME_TYPE_DIR : mimeOf(f);
    }

    // ───────────────────────────── helpers ─────────────────────────────

    private void includeFile(MatrixCursor c, File f) throws FileNotFoundException {
        String id = idFor(f);
        int flags;
        String mime;
        if (f.isDirectory()) {
            mime = Document.MIME_TYPE_DIR;
            flags = Document.FLAG_DIR_SUPPORTS_CREATE;
            if (!isProtected(f)) flags |= Document.FLAG_SUPPORTS_DELETE | Document.FLAG_SUPPORTS_RENAME;
        } else {
            mime = mimeOf(f);
            flags = Document.FLAG_SUPPORTS_WRITE | Document.FLAG_SUPPORTS_DELETE | Document.FLAG_SUPPORTS_RENAME;
        }
        MatrixCursor.RowBuilder r = c.newRow();
        r.add(Document.COLUMN_DOCUMENT_ID, id);
        r.add(Document.COLUMN_DISPLAY_NAME, id.equals(ROOT_ID) ? "tonEMU" : f.getName());
        r.add(Document.COLUMN_SIZE, f.isDirectory() ? 0L : f.length());
        r.add(Document.COLUMN_MIME_TYPE, mime);
        r.add(Document.COLUMN_LAST_MODIFIED, f.lastModified());
        r.add(Document.COLUMN_FLAGS, flags);
    }

    /** The root and its standard folders (roms, saves, ...) cannot be renamed or deleted: the app needs them. */
    private boolean isProtected(File f) {
        File root = root();
        return f.equals(root) || root.equals(f.getParentFile());
    }

    private String idFor(File f) {
        String base = root().getPath();
        String p = f.getPath();
        if (p.equals(base)) return ROOT_ID;
        return ROOT_ID + "/" + p.substring(base.length() + 1);
    }

    /** Resolves a document id to a file INSIDE the root, or throws. */
    private File fileFor(String id) throws FileNotFoundException {
        File root = root();
        File f;
        if (ROOT_ID.equals(id)) {
            f = root;
        } else if (id != null && id.startsWith(ROOT_ID + "/")) {
            f = new File(root, id.substring(ROOT_ID.length() + 1));
        } else {
            throw new FileNotFoundException("Unknown document: " + id);
        }
        try {
            String base = root.getCanonicalPath();
            String p = f.getCanonicalPath();
            if (!p.equals(base) && !p.startsWith(base + File.separator)) {
                throw new FileNotFoundException("Outside tonEMU: " + id);
            }
        } catch (IOException e) {
            throw new FileNotFoundException("Cannot resolve " + id);
        }
        if (!f.exists()) throw new FileNotFoundException("Missing: " + id);
        return f;
    }

    private static boolean isTempName(String n) {
        return n.endsWith(".tmp") || n.endsWith(".part") || n.endsWith(".cp");
    }

    /** A file name with no path separators and never "." / "..". */
    private static String cleanName(String name) {
        String n = name == null ? "" : name.replace('/', '_').replace('\\', '_').trim();
        if (n.isEmpty() || n.equals(".") || n.equals("..")) n = "file";
        return n;
    }

    private static File uniqueFile(File dir, String name) {
        File f = new File(dir, name);
        if (!f.exists()) return f;
        int dot = name.lastIndexOf('.');
        String stem = dot > 0 ? name.substring(0, dot) : name;
        String ext = dot > 0 ? name.substring(dot) : "";
        for (int i = 1; i < 1000; i++) {
            f = new File(dir, stem + " (" + i + ")" + ext);
            if (!f.exists()) return f;
        }
        return f;
    }

    private static String mimeOf(File f) {
        String n = f.getName();
        int dot = n.lastIndexOf('.');
        if (dot >= 0) {
            String m = MimeTypeMap.getSingleton().getMimeTypeFromExtension(n.substring(dot + 1).toLowerCase(Locale.ROOT));
            if (m != null) return m;
        }
        return "application/octet-stream";
    }

    private void notifyChildren(String parentId) {
        try {
            Uri uri = DocumentsContract.buildChildDocumentsUri(authority(getContext()), parentId);
            getContext().getContentResolver().notifyChange(uri, null);
        } catch (Throwable ignored) { }
    }
}