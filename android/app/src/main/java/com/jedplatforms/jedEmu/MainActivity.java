package com.jedplatforms.jedEmu;

import android.Manifest;
import android.content.BroadcastReceiver;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.media.AudioManager;
import android.media.MediaScannerConnection;
import android.graphics.Bitmap;
import android.hardware.input.InputManager;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.provider.MediaStore;
import android.provider.Settings;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.PixelCopy;
import android.view.View;
import android.view.ViewGroup;

import androidx.annotation.NonNull;

import com.swordfish.libretrodroid.GLRetroView;
import com.swordfish.libretrodroid.ShaderConfig;
import com.swordfish.libretrodroid.Variable;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.lang.ref.WeakReference;
import java.io.FileInputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.view.TextureRegistry;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "com.jedplatforms.jedEmu/core";

    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private EmulatorViewFactory factory;
    private TextureRegistry textures;
    private ScreenMirror mirror;
    // Last view/size refreshVideo acted on. Tied to the view itself so a NEW game (new GL surface)
    // is never skipped just because it happens to have the same size as the previous one.
    private WeakReference<GLRetroView> lastRvView = new WeakReference<>(null);
    private int lastRvW = -1, lastRvH = -1;
    private final boolean[] l2Down = new boolean[4], r2Down = new boolean[4]; // per port
    /** On-screen (Flutter) buttons/sticks currently held, so they can be released if the app loses focus. */
    private final HashSet<Integer> virtualKeys = new HashSet<>(); // (port << 16) | keyCode
    private final HashSet<Integer> virtualAxes = new HashSet<>(); // (port << 8) | source
    private long touchDownTime = 0;
    private boolean touchActive = false;
    private float lastTouchX, lastTouchY;

    // Controller settings pushed from Flutter (setInputConfig)
    private volatile float deadzone = 0.12f;
    private boolean swapAB = false, swapXY = false, comboHotkeys = false;
    // True while a Flutter menu/dialog is open: gamepad then drives the UI, not the game.
    private volatile boolean uiCaptured = false;
    /** While true the game is auto-paused: only A / B on a gamepad does anything (it continues). */
    private volatile boolean pauseGate = false;
    private boolean selectHeld = false, comboUsed = false;
    /** Held pad buttons, encoded as (port << 16) | keyCode. */
    private final HashSet<Integer> held = new HashSet<>();
    private final Handler ui = new Handler(Looper.getMainLooper());
    private MethodChannel channel;
    private InputManager.InputDeviceListener deviceListener;
    private boolean focusHighlightHooked = false;
    private BroadcastReceiver noisyReceiver;
    private BroadcastReceiver batteryReceiver;

    /** jedManager: request code + pending reply of the "pick the old tonEMU folder" dialog. */
    private static final int REQ_LEGACY_TREE = 0x7E31;
    private MethodChannel.Result pendingTreeResult;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        factory = new EmulatorViewFactory(this);
        textures = flutterEngine.getRenderer();
        flutterEngine.getPlatformViewsController().getRegistry()
            .registerViewFactory("xemu_game_surface", factory);

        channel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL);
        registerGamepadListener();
        registerNoisyReceiver();
        registerBatteryReceiver();
        TimeZoneSync.register(this);
        channel.setMethodCallHandler(this::handleMethodCall);
    }

    @Override
    protected void onResume() {
        super.onResume();
        TimeZoneSync.apply();
        requestHighRefreshRate();
        hookFocusHighlight();
        prewarmPpsspp();
    }

    @Override
    protected void onPause() {
        // A button held while the app goes to the background never gets its key-up, and the
        // character would keep walking on its own when the player comes back.
        releaseAllInput(factory == null ? null : factory.getReadySession());
        emit("focusLost"); // Flutter pauses the game and waits for A / B
        super.onPause();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (!hasFocus) {
            releaseAllInput(factory == null ? null : factory.getReadySession());
            // Notification shade, quick settings, a system dialog...: pause until A / B.
            emit("focusLost");
        }
    }

    /**
     * Asks Android for the highest refresh rate the display offers at its CURRENT resolution
     * (e.g. 120 Hz at FHD+ on a Galaxy S20). Without a request many phones (Samsung especially)
     * keep a Flutter app at 60 Hz. preferredDisplayModeId is honoured far more reliably than
     * preferredRefreshRate. Only a preference: the system may still lower it (battery saver,
     * "Standard" motion smoothness), and nothing happens on 60 Hz screens.
     */
    private void requestHighRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return;
        try {
            android.view.Display display = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
                ? getDisplay() : getWindowManager().getDefaultDisplay();
            if (display == null) return;
            android.view.Display.Mode current = display.getMode();
            android.view.Display.Mode best = current;
            for (android.view.Display.Mode m : display.getSupportedModes()) {
                if (m.getPhysicalWidth() == current.getPhysicalWidth()
                    && m.getPhysicalHeight() == current.getPhysicalHeight()
                    && m.getRefreshRate() > best.getRefreshRate() + 0.5f) {
                    best = m;
                }
            }
            android.view.WindowManager.LayoutParams lp = getWindow().getAttributes();
            if (lp.preferredDisplayModeId == best.getModeId()) return;
            lp.preferredDisplayModeId = best.getModeId();
            getWindow().setAttributes(lp);
        } catch (Throwable ignored) { }
    }

    /**
     * Keeps the PPSSPP folder hidden from the gallery, off the UI thread (PPSSPP fonts come from
     * the user's PPSSPP.zip, nothing is bundled). Cheap and safe to repeat on every resume.
     */
    private void prewarmPpsspp() {
        if (io.isShutdown()) return;
        try {
            io.execute(() -> {
                try {
                    File sys = new File(getTonEmuRootDir(), "system");
                    sys.mkdirs();
                    PpssppAssetsInstaller.hideFromGallery(sys); // also for installs made by older builds
                    if (PpssppAssetsInstaller.isInstalled(sys)) return;
                    PpssppAssetsInstaller.ensureInstalled(this, sys);
                } catch (Throwable ignored) { }
            });
        } catch (RejectedExecutionException ignored) { }
    }

    /** Android draws a green focus box on the focused view once a gamepad/keyboard is attached. */
    private void hookFocusHighlight() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        View decor = getWindow().getDecorView();
        killHighlight(decor);
        if (focusHighlightHooked) return;
        focusHighlightHooked = true;
        decor.getViewTreeObserver().addOnGlobalFocusChangeListener((oldFocus, newFocus) -> {
            if (newFocus != null) {
                newFocus.setDefaultFocusHighlightEnabled(false);
                newFocus.invalidate();
            }
        });
    }

    private void killHighlight(View v) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        v.setDefaultFocusHighlightEnabled(false);
        if (v instanceof ViewGroup) {
            ViewGroup g = (ViewGroup) v;
            for (int i = 0; i < g.getChildCount(); i++) killHighlight(g.getChildAt(i));
        }
    }

    /**
     * tonEMU's folder. App-private storage: no storage permission is needed. Users reach these
     * files through the system Files app (TonEmuDocumentsProvider). Same folder as Dart's StorageService.
     */
    public File getTonEmuRootDir() {
        return StorageRoot.get(this);
    }

    private void handleMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        GameSession s = factory.getCurrent();
        GameSession ready = factory.getReadySession();

        switch (call.method) {
            case "getDeviceInfo": {
                // EGL probe runs off the main thread; the reply goes back on it.
                new Thread(() -> {
                    final Map<String, String> info = DeviceInfo.get();
                    runOnUiThread(() -> result.success(info));
                }, "device-info").start();
                break;
            }
            case "openUrl": {
                // http(s) -> browser, mailto: -> mail app. Reports false if nothing can handle it.
                String url = call.argument("url");
                boolean opened = false;
                if (url != null) {
                    try {
                        Uri u = Uri.parse(url);
                        String scheme = u.getScheme() == null ? "" : u.getScheme().toLowerCase(java.util.Locale.ROOT);
                        Intent i = new Intent(scheme.equals("mailto") ? Intent.ACTION_SENDTO : Intent.ACTION_VIEW, u);
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        if (scheme.equals("http") || scheme.equals("https") || scheme.equals("mailto")) {
                            startActivity(i);
                            opened = true;
                        }
                    } catch (Throwable ignored) { }
                }
                result.success(opened);
                break;
            }
            case "canInstallApks":
                result.success(ApkInstaller.canInstall(this));
                break;
            case "openInstallSettings":
                result.success(ApkInstaller.openInstallSettings(this));
                break;
            case "installApk": {
                String path = call.argument("path");
                String sha = call.argument("sha256");
                if (path == null) { result.success("missing"); break; }
                // Hashing a big APK takes a moment: off the main thread, reply on it.
                new Thread(() -> {
                    final String r = ApkInstaller.install(this, path, sha);
                    runOnUiThread(() -> result.success(r));
                }, "apk-install").start();
                break;
            }
            case "cleanupUpdates":
                ApkInstaller.cleanup(this);
                result.success(true);
                break;
            case "getPublicRoot":
                // tonEMU's storage root (app-private; shown in the Files app by TonEmuDocumentsProvider).
                result.success(getTonEmuRootDir().getAbsolutePath());
                break;
            case "openStorageInFiles": {
                // Opens the "tonEMU" location in the system Files app. False if no app can show it.
                boolean opened = false;
                try {
                    Uri rootUri = android.provider.DocumentsContract.buildRootUri(
                        TonEmuDocumentsProvider.authority(this), TonEmuDocumentsProvider.ROOT_ID);
                    Intent i = new Intent(Intent.ACTION_VIEW);
                    i.setDataAndType(rootUri, android.provider.DocumentsContract.Root.MIME_TYPE_ITEM);
                    i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_GRANT_READ_URI_PERMISSION);
                    startActivity(i);
                    opened = true;
                } catch (Throwable ignored) { }
                result.success(opened);
                break;
            }
            case "resolveCore": {
                String name = call.argument("core");
                File f = name == null ? null : EmulatorViewFactory.resolveCore(this, name);
                result.success(f == null ? null : f.getName());
                break;
            }
            case "isReady":
                result.success(ready != null);
                break;
            case "getVideoAspect":
                result.success(ready == null ? null : VideoAspect.read(ready.retroView));
                break;
            case "startMirror": {
                if (mirror != null) { mirror.stop(); mirror = null; }
                Integer mw = call.argument("width");
                Integer mh = call.argument("height");
                if (ready == null || mw == null || mh == null || mw < 16 || mh < 16) {
                    result.success(null);
                    break;
                }
                try {
                    mirror = new ScreenMirror(textures, ready.retroView, mw, mh);
                    Map<String, Object> out = new HashMap<>();
                    out.put("id", mirror.textureId());
                    result.success(out);
                } catch (Throwable t) {
                    mirror = null;
                    result.success(null);
                }
                break;
            }
            case "refreshVideo": {
                // After a rotation/resize the GL surface can stay at its OLD size (picture
                // squeezed into a corner). Recreating the surface at the new size fixes it; this
                // is the same path the view takes when the app goes to the background and back.
                if (ready != null) {
                    final GLRetroView rv = ready.retroView;
                    ui.post(() -> {
                        try {
                            int w = rv.getWidth(), h = rv.getHeight();
                            if (w <= 0 || h <= 0) return;
                            // Only when the size really changed since the last refresh.
                            if (rv == lastRvView.get() && w == lastRvW && h == lastRvH) return;
                            lastRvView = new WeakReference<>(rv);
                            lastRvW = w;
                            lastRvH = h;
                            try {
                                java.lang.reflect.Method m = rv.getClass()
                                    .getMethod("setViewport", android.graphics.RectF.class);
                                m.invoke(rv, new android.graphics.RectF(0f, 0f, 1f, 1f));
                            } catch (Throwable ignored) { }
                            rv.setVisibility(android.view.View.INVISIBLE);
                            ui.postDelayed(() -> {
                                rv.setVisibility(android.view.View.VISIBLE);
                                rv.requestLayout();
                            }, 60);
                        } catch (Throwable ignored) { }
                    });
                }
                result.success(ready != null);
                break;
            }
            case "stopMirror":
                if (mirror != null) { mirror.stop(); mirror = null; }
                result.success(true);
                break;
            case "stopGame":
                if (mirror != null) { mirror.stop(); mirror = null; }
                releaseAllInput(ready); // nothing stays "held" for the next game
                pauseGate = false;
                factory.destroyCurrent();
                lastRvView = new WeakReference<>(null);
                lastRvW = lastRvH = -1;
                result.success(true);
                break;
            case "setPauseGate": {
                pauseGate = Boolean.TRUE.equals(call.argument("on"));
                result.success(true);
                break;
            }
            case "setPaused": {
                Boolean paused = call.argument("paused");
                if (s != null && paused != null) s.setUserPaused(paused);
                result.success(true);
                break;
            }
            case "saveState":
                saveStateToFile(ready, call.argument("path"), result);
                break;
            case "loadState":
                loadStateFromFile(call.argument("path"), result);
                break;
            case "takeScreenshot": {
                Integer maxW = call.argument("maxWidth");
                takeScreenshot(ready, call.argument("path"), maxW == null ? 0 : maxW, result);
                break;
            }
            case "resetGame":
                boolean resetOk = false;
                if (ready != null) {
                    try { ready.retroView.reset(); resetOk = true; } catch (Throwable ignored) { }
                }
                result.success(resetOk);
                break;
            case "setMuted": {
                Boolean muted = call.argument("muted");
                if (ready != null && muted != null) {
                    try { ready.retroView.setAudioEnabled(!muted); } catch (Throwable ignored) { }
                }
                result.success(true);
                break;
            }
            case "setFastForward": {
                Integer speed = call.argument("speed");
                if (ready != null && speed != null) {
                    try { ready.retroView.setFrameSpeed(speed); } catch (Throwable ignored) { }
                }
                result.success(true);
                break;
            }
            case "applyCheat": {
                Integer index = call.argument("index");
                Boolean enabled = call.argument("enabled");
                String code = call.argument("code");
                boolean ok = ready != null && index != null && enabled != null && code != null;
                if (ok) {
                    try {
                        ready.retroView.setCheat(index, enabled, code);
                    } catch (Throwable t) {
                        ok = false;
                    }
                }
                result.success(ok);
                break;
            }
            case "setCheats": {
                // Whole cheat list at once: clear the core's table, then set every entry.
                List<Map<String, Object>> list = call.argument("cheats");
                boolean ok = ready != null && list != null;
                if (ok) {
                    try {
                        ok = applyCheatList(ready.retroView, list);
                    } catch (Throwable t) {
                        ok = false;
                    }
                }
                result.success(ok);
                break;
            }
            case "setScreenLayout": {
                String layout = call.argument("layout");
                if (ready != null && layout != null) {
                    List<Variable> vars = CoreOptions.screenLayout(ready.coreName, layout);
                    if (!vars.isEmpty()) {
                        try {
                            ready.retroView.updateVariables(vars.toArray(new Variable[0]));
                        } catch (Throwable ignored) { }
                    }
                }
                result.success(ready != null);
                break;
            }
            case "getCoreOptions": {
                if (ready == null) {
                    result.success(null);
                    break;
                }
                try {
                    Variable[] vars = ready.retroView.getVariables();
                    ArrayList out = new ArrayList();
                    for (Variable var : vars) {
                        if ((getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
                            android.util.Log.i("CoreOptions", "dump: " + var.getKey() + " = " + var.getValue()
                                + " | " + var.getDescription());
                        }
                        Map<String, String> m = new HashMap<>();
                        m.put("key", var.getKey());
                        m.put("value", var.getValue());
                        m.put("description", var.getDescription());
                        out.add(m);
                    }
                    result.success(out);
                } catch (Throwable t) {
                    result.success(null);
                }
                break;
            }
            case "setCoreOption": {
                String key = call.argument("key");
                String value = call.argument("value");
                boolean applied = false;
                // Startup-only options and unsafe values are never sent to a running core.
                if (ready != null && key != null && value != null && !CoreOptions.requiresRestart(key)) {
                    String safe = CoreOptions.sanitize(key, value);
                    if (safe != null) {
                        try {
                            ready.retroView.updateVariables(new Variable[] { CoreOptions.v(key, safe) });
                            applied = true;
                        } catch (Throwable ignored) { }
                    }
                }
                result.success(applied);
                break;
            }
            case "setCoreOptions": {
                // Several options in ONE update, so the core sees them together instead of a burst.
                Map<String, Object> opts = call.argument("options");
                boolean applied = false;
                if (ready != null && opts != null) {
                    List<Variable> batch = new ArrayList<>();
                    for (Map.Entry<String, Object> e : opts.entrySet()) {
                        if (e.getKey() == null || e.getValue() == null) continue;
                        if (CoreOptions.requiresRestart(e.getKey())) continue;
                        String safe = CoreOptions.sanitize(e.getKey(), String.valueOf(e.getValue()));
                        if (safe != null) batch.add(CoreOptions.v(e.getKey(), safe));
                    }
                    if (batch.isEmpty()) {
                        applied = true;
                    } else {
                        try {
                            ready.retroView.updateVariables(batch.toArray(new Variable[0]));
                            applied = true;
                        } catch (Throwable ignored) { }
                    }
                }
                result.success(applied);
                break;
            }
            case "setInputConfig": {
                Boolean ab = call.argument("swapAB");
                Boolean xy = call.argument("swapXY");
                Number dzv = call.argument("deadzone");
                Boolean combo = call.argument("comboHotkeys");
                swapAB = Boolean.TRUE.equals(ab);
                swapXY = Boolean.TRUE.equals(xy);
                comboHotkeys = Boolean.TRUE.equals(combo);
                if (dzv != null) deadzone = (float) Math.max(0.0, Math.min(0.5, dzv.doubleValue()));
                result.success(true);
                break;
            }
            case "setUiCaptured": {
                Boolean cap = call.argument("captured");
                uiCaptured = Boolean.TRUE.equals(cap);
                if (uiCaptured) releaseAllInput(ready);
                result.success(true);
                break;
            }
            case "hasGamepad":
                result.success(anyGamepad());
                break;
            case "setShader": {
                String name = call.argument("shader");
                ShaderConfig sc = VideoOptions.shader(name);
                boolean ok = ready != null && sc != null;
                if (ok) {
                    try { ready.retroView.setShader(sc); } catch (Throwable t) { ok = false; }
                }
                result.success(ok);
                break;
            }
            case "extractPpssppZip": {
                String zipPath = call.argument("path");
                if (zipPath == null) {
                    result.error("BAD_ARGS", "Missing zip path", null);
                    break;
                }
                extractPpssppZipAsync(zipPath, result);
                break;
            }
            case "importBiosZip": {
                String zipPath = call.argument("path");
                Map<String, String> lookup = call.argument("lookup");
                if (zipPath == null || lookup == null) {
                    result.error("BAD_ARGS", "Missing zip path or lookup", null);
                    break;
                }
                importBiosZipAsync(zipPath, lookup, result);
                break;
            }
            case "pickLegacyFolder": {
                // jedManager: system folder picker (no storage permission). Replies with the
                // chosen tree Uri as a String, or null when the user backs out.
                if (pendingTreeResult != null) {
                    result.error("BUSY", "A folder picker is already open", null);
                    break;
                }
                try {
                    Intent pick = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
                    pick.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION
                        | Intent.FLAG_GRANT_PREFIX_URI_PERMISSION);
                    pendingTreeResult = result;
                    startActivityForResult(pick, REQ_LEGACY_TREE);
                } catch (Throwable t) {
                    pendingTreeResult = null;
                    result.error("NO_PICKER", "No folder picker is available on this device", null);
                }
                break;
            }
            case "importLegacyTree": {
                final String treeUri = call.argument("uri");
                final Boolean overwrite = call.argument("overwrite");
                if (treeUri == null) {
                    result.error("BAD_ARGS", "Missing folder", null);
                    break;
                }
                execIo(result, () -> {
                    try {
                        final Map<String, Object> r = LegacyFolderImporter.run(
                            MainActivity.this, Uri.parse(treeUri), getTonEmuRootDir(),
                            Boolean.TRUE.equals(overwrite));
                        runOnUiThread(() -> result.success(r));
                    } catch (Throwable t) {
                        runOnUiThread(() -> result.error("IMPORT_FAILED", String.valueOf(t.getMessage()), null));
                    }
                });
                break;
            }
            case "legacyImportProgress":
                result.success(LegacyFolderImporter.progress());
                break;
            case "cancelLegacyImport":
                LegacyFolderImporter.cancel();
                result.success(true);
                break;
            case "exportToGallery": {
                String path = call.argument("path");
                String album = call.argument("album");
                if (path == null) {
                    result.success(false);
                    break;
                }
                exportToGalleryAsync(path, album == null ? "tonEMU" : album, result);
                break;
            }
            case "sendVirtualInput": {
                Integer port = call.argument("port");
                Integer keyCode = call.argument("keyCode");
                Boolean isDown = call.argument("isDown");
                if (ready != null && port != null && keyCode != null && isDown != null) {
                    int vk = (port << 16) | keyCode;
                    if (isDown) virtualKeys.add(vk); else virtualKeys.remove(vk);
                    try {
                        ready.retroView.sendKeyEvent(
                            isDown ? KeyEvent.ACTION_DOWN : KeyEvent.ACTION_UP, keyCode, port);
                    } catch (Throwable ignored) { }
                }
                result.success(null);
                break;
            }
            case "sendVirtualAnalog": {
                Integer port = call.argument("port");
                Integer source = call.argument("source");
                Number x = call.argument("x");
                Number y = call.argument("y");
                if (ready != null && port != null && source != null && x != null && y != null) {
                    int va = (port << 8) | source;
                    if (x.doubleValue() == 0.0 && y.doubleValue() == 0.0) virtualAxes.remove(va);
                    else virtualAxes.add(va);
                    try {
                        ready.retroView.sendMotionEvent(source, x.floatValue(), y.floatValue(), port);
                    } catch (Throwable ignored) { }
                }
                result.success(null);
                break;
            }
            case "sendTouch": {
                Integer action = call.argument("action");
                Number nx = call.argument("x");
                Number ny = call.argument("y");
                if (ready != null && action != null && nx != null && ny != null) {
                    GLRetroView v = ready.retroView;
                    float px = (float) (nx.doubleValue() * v.getWidth());
                    float py = (float) (ny.doubleValue() * v.getHeight());
                    int a = action == 0 ? MotionEvent.ACTION_DOWN
                          : action == 1 ? MotionEvent.ACTION_MOVE
                          : MotionEvent.ACTION_UP;
                    // A MOVE/UP with no finger down would make the pointer jump or stay stuck.
                    if (a == MotionEvent.ACTION_DOWN || touchActive) {
                        dispatchTouch(v, a, px, py);
                        touchActive = a != MotionEvent.ACTION_UP;
                        lastTouchX = px;
                        lastTouchY = py;
                    }
                }
                result.success(null);
                break;
            }
            default:
                result.notImplemented();
        }
    }

    /**
     * Sets the complete cheat list on the core. resetCheat() is looked up reflectively because it
     * is not present in every LibretroDroid version; without it, disabled entries are still sent
     * with enabled=false (same behaviour as before). Returns false if any entry was rejected.
     */
    private static boolean applyCheatList(GLRetroView view, List<Map<String, Object>> cheats) {
        try {
            view.getClass().getMethod("resetCheat").invoke(view);
        } catch (Throwable ignored) { }
        boolean all = true;
        for (Map<String, Object> c : cheats) {
            Object idx = c.get("index");
            Object code = c.get("code");
            if (!(idx instanceof Number) || !(code instanceof String)) { all = false; continue; }
            try {
                view.setCheat(((Number) idx).intValue(), Boolean.TRUE.equals(c.get("enabled")), (String) code);
            } catch (Throwable t) {
                all = false;
            }
        }
        return all;
    }

    /** Copies a PNG/JPG into the system gallery (Pictures/<album>) so it shows up in Photos. */
    private void exportToGalleryAsync(String path, String album, MethodChannel.Result result) {
        execIo(result, () -> {
            boolean ok = false;
            try {
                File src = new File(path);
                if (src.exists()) {
                    String lower = src.getName().toLowerCase(java.util.Locale.ROOT);
                    String mime = (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) ? "image/jpeg" : "image/png";
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        ContentValues cv = new ContentValues();
                        cv.put(MediaStore.Images.Media.DISPLAY_NAME, src.getName());
                        cv.put(MediaStore.Images.Media.MIME_TYPE, mime);
                        cv.put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/" + album);
                        cv.put(MediaStore.Images.Media.IS_PENDING, 1);
                        Uri uri = getContentResolver().insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, cv);
                        if (uri != null) {
                            boolean wrote = false;
                            try (OutputStream os = getContentResolver().openOutputStream(uri);
                                 InputStream is = new FileInputStream(src)) {
                                if (os != null) {
                                    byte[] b = new byte[8192];
                                    int n;
                                    while ((n = is.read(b)) > 0) os.write(b, 0, n);
                                    wrote = true;
                                }
                            } catch (Throwable t) {
                                wrote = false;
                            }
                            if (wrote) {
                                ContentValues done = new ContentValues();
                                done.put(MediaStore.Images.Media.IS_PENDING, 0);
                                getContentResolver().update(uri, done, null, null);
                                ok = true;
                            } else {
                                // Never leave a half-made, invisible "pending" entry behind.
                                try { getContentResolver().delete(uri, null, null); } catch (Throwable ignored) { }
                            }
                        }
                    } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M
                        || checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE)
                            == PackageManager.PERMISSION_GRANTED) {
                        File dir = new File(Environment.getExternalStoragePublicDirectory(
                            Environment.DIRECTORY_PICTURES), album);
                        if (dir.exists() || dir.mkdirs()) {
                            File dst = new File(dir, src.getName());
                            FileUtil.copy(src, dst);
                            MediaScannerConnection.scanFile(this, new String[] { dst.getAbsolutePath() },
                                new String[] { mime }, null);
                            ok = true;
                        }
                    }
                }
            } catch (Throwable ignored) {
                ok = false;
            }
            final boolean res = ok;
            runOnUiThread(() -> result.success(res));
        });
    }

    /** Runs [task] on the file thread; after the Activity closed the pool is shut down and execute() would throw. */
    private void execIo(MethodChannel.Result result, Runnable task) {
        try {
            io.execute(task);
        } catch (RejectedExecutionException e) {
            result.error("CLOSING", "The app is closing", null);
        }
    }

    private void importBiosZipAsync(String zipPath, Map<String, String> lookup, MethodChannel.Result result) {
        execIo(result, () -> {
            try {
                File sysDir = new File(getTonEmuRootDir(), "system");
                if (!sysDir.exists()) sysDir.mkdirs();
                List<String> installed = BiosZipInstaller.extract(new File(zipPath), sysDir, lookup);
                runOnUiThread(() -> result.success(installed));
            } catch (Exception e) {
                runOnUiThread(() -> result.error("UNZIP_FAILED", e.getMessage(), null));
            }
        });
    }

    private void extractPpssppZipAsync(String zipPath, MethodChannel.Result result) {
        execIo(result, () -> {
            try {
                // Must be the SAME folder the cores read (EmulatorViewFactory: <tonEMU>/system).
                File sysDir = new File(getTonEmuRootDir(), "system");
                if (!sysDir.exists()) sysDir.mkdirs();
                int fonts = PpssppAssetsInstaller.extractZip(new File(zipPath), sysDir);
                runOnUiThread(() -> result.success(fonts));
            } catch (Exception e) {
                runOnUiThread(() -> result.error("UNZIP_FAILED", e.getMessage(), null));
            }
        });
    }

    /** Copies the live game picture to [path] (.png or .jpg). maxWidth > 0 downsizes it (thumbnails). */
    private void takeScreenshot(GameSession s, String path, int maxWidth, MethodChannel.Result result) {
        if (s == null || path == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            result.success(false);
            return;
        }
        final GLRetroView v = s.retroView;
        final int w = v.getWidth();
        final int h = v.getHeight();
        if (w <= 0 || h <= 0) {
            result.success(false);
            return;
        }
        final Bitmap bmp;
        try {
            bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
        } catch (Throwable t) { // OutOfMemoryError on a huge view must not crash the app
            result.success(false);
            return;
        }
        try {
            PixelCopy.request(v, bmp, code -> {
                if (code != PixelCopy.SUCCESS) {
                    bmp.recycle();
                    result.success(false);
                    return;
                }
                if (io.isShutdown()) { // Activity is closing: nothing left to do, and no crash
                    bmp.recycle();
                    result.success(false);
                    return;
                }
                try {
                io.execute(() -> {
                    boolean ok = false;
                    try {
                        Bitmap out = bmp;
                        if (maxWidth > 0 && w > maxWidth) {
                            int nh = Math.max(1, Math.round(h * (maxWidth / (float) w)));
                            out = Bitmap.createScaledBitmap(bmp, maxWidth, nh, true);
                        }
                        File f = new File(path);
                        File parent = f.getParentFile();
                        if (parent != null && !parent.exists()) parent.mkdirs();
                        String lower = path.toLowerCase(java.util.Locale.ROOT);
                        boolean jpg = lower.endsWith(".jpg") || lower.endsWith(".jpeg");
                        try (FileOutputStream fo = new FileOutputStream(f)) {
                            ok = out.compress(
                                jpg ? Bitmap.CompressFormat.JPEG : Bitmap.CompressFormat.PNG,
                                jpg ? 85 : 100, fo);
                        }
                        if (out != bmp) out.recycle();
                    } catch (Throwable t) {
                        ok = false;
                    }
                    bmp.recycle();
                    final boolean res = ok;
                    runOnUiThread(() -> result.success(res));
                });
                } catch (RejectedExecutionException e) {
                    bmp.recycle();
                    result.success(false);
                }
            }, ui);
        } catch (Throwable t) {
            bmp.recycle();
            result.success(false);
        }
    }

    private void saveStateToFile(GameSession s, String path, MethodChannel.Result result) {
        if (s == null || path == null) {
            result.error("NO_CORE", "Emulator is not running yet", null);
            return;
        }
        final byte[] bytes;
        try {
            bytes = s.retroView.serializeState();
        } catch (Throwable t) {
            result.error("SAVE_FAILED", String.valueOf(t.getMessage()), null);
            return;
        }
        execIo(result, () -> {
            try {
                GameSession.writeAtomically(new File(path), bytes);
                runOnUiThread(() -> result.success(true));
            } catch (Exception e) {
                runOnUiThread(() -> result.error("SAVE_FAILED", e.getMessage(), null));
            }
        });
    }

    private void loadStateFromFile(String path, MethodChannel.Result result) {
        if (path == null || factory.getReadySession() == null) {
            result.error("NO_CORE", "Emulator is not running yet", null);
            return;
        }
        execIo(result, () -> {
            try {
                byte[] bytes = FileUtil.readAll(new File(path));
                runOnUiThread(() -> {
                    GameSession s = factory.getReadySession();
                    if (s == null) {
                        result.error("NO_CORE", "Emulator closed", null);
                        return;
                    }
                    try {
                        result.success(s.retroView.unserializeState(bytes));
                    } catch (Throwable t) {
                        result.error("LOAD_FAILED", String.valueOf(t.getMessage()), null);
                    }
                });
            } catch (Throwable e) { // never leave the Flutter call hanging
                final String msg = String.valueOf(e.getMessage());
                runOnUiThread(() -> result.error("LOAD_FAILED", msg, null));
            }
        });
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == REQ_LEGACY_TREE) {
            MethodChannel.Result r = pendingTreeResult;
            pendingTreeResult = null;
            if (r != null) {
                Uri tree = (resultCode == RESULT_OK && data != null) ? data.getData() : null;
                r.success(tree == null ? null : tree.toString());
            }
            return;
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    @Override
    protected void onDestroy() {
        LegacyFolderImporter.cancel();
        TimeZoneSync.unregister(this);
        if (mirror != null) { mirror.stop(); mirror = null; }
        if (factory != null) factory.destroyCurrent();
        InputManager im = (InputManager) getSystemService(Context.INPUT_SERVICE);
        if (im != null && deviceListener != null) im.unregisterInputDeviceListener(deviceListener);
        if (noisyReceiver != null) {
            try { unregisterReceiver(noisyReceiver); } catch (Throwable ignored) { }
            noisyReceiver = null;
        }
        if (batteryReceiver != null) {
            try { unregisterReceiver(batteryReceiver); } catch (Throwable ignored) { }
            batteryReceiver = null;
        }
        io.shutdown();
        super.onDestroy();
    }

    // ---------- Physical gamepad (Bluetooth / USB) ----------

    private void emit(String name) {
        if (channel != null) channel.invokeMethod("hotkey", name);
    }

    private boolean anyGamepad() {
        for (int id : InputDevice.getDeviceIds()) {
            InputDevice d = InputDevice.getDevice(id);
            if (d != null && !d.isVirtual() && isGamepad(d)) return true;
        }
        return false;
    }

    private void registerGamepadListener() {
        if (deviceListener != null) return;
        InputManager im = (InputManager) getSystemService(Context.INPUT_SERVICE);
        if (im == null) return;
        deviceListener = new InputManager.InputDeviceListener() {
            @Override public void onInputDeviceAdded(int id) {
                invalidatePads();
                try { emitGamepad(); } catch (Throwable t) {
                    android.util.Log.w("tonEmuPad", "emitGamepad failed", t);
                }
                ui.post(() -> killHighlight(getWindow().getDecorView()));
            }
            @Override public void onInputDeviceRemoved(int id) {
                invalidatePads();
                // A pad that vanishes mid-press never sends its key-up: release everything so
                // the game doesn't keep running/walking on its own. Guarded: this runs while the
                // core is live, and an exception here must never take the whole app down.
                try {
                    GameSession cur = factory == null ? null : factory.getReadySession();
                    releaseAllInput(cur);
                } catch (Throwable t) {
                    android.util.Log.w("tonEmuPad", "release on pad removal failed", t);
                }
                try { emitGamepad(); } catch (Throwable t) {
                    android.util.Log.w("tonEmuPad", "emitGamepad failed", t);
                }
            }
            @Override public void onInputDeviceChanged(int id) { invalidatePads(); }
        };
        im.registerInputDeviceListener(deviceListener, ui);
    }

    /** Headphones unplugged / Bluetooth audio dropped: let Flutter auto-pause. */
    /**
     * Android sends ACTION_BATTERY_LOW once when the battery drops to its "low" level (about 15%).
     * Flutter then writes the auto-save slot, so a phone that dies mid-game loses nothing.
     */
    private void registerBatteryReceiver() {
        if (batteryReceiver != null) return;
        batteryReceiver = new BroadcastReceiver() {
            @Override public void onReceive(Context c, Intent i) {
                if (Intent.ACTION_BATTERY_LOW.equals(i.getAction())) emit("batteryLow");
            }
        };
        try {
            androidx.core.content.ContextCompat.registerReceiver(this, batteryReceiver, new IntentFilter(Intent.ACTION_BATTERY_LOW), androidx.core.content.ContextCompat.RECEIVER_NOT_EXPORTED);
        } catch (Throwable t) {
            batteryReceiver = null;
        }
    }

    private void registerNoisyReceiver() {
        if (noisyReceiver != null) return;
        noisyReceiver = new BroadcastReceiver() {
            @Override public void onReceive(Context c, Intent i) {
                if (AudioManager.ACTION_AUDIO_BECOMING_NOISY.equals(i.getAction())) emit("audioNoisy");
            }
        };
        try {
            androidx.core.content.ContextCompat.registerReceiver(this, noisyReceiver, new IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY), androidx.core.content.ContextCompat.RECEIVER_NOT_EXPORTED);
        } catch (Throwable t) {
            noisyReceiver = null;
        }
    }

    /** Releases every pad button/stick/trigger the game currently thinks is held. */
    private void releaseAllInput(GameSession s) {
        // Runs from onPause / focus loss / pad removal while the core may be tearing down: a
        // failing native call must never crash the app, and the bookkeeping below must still reset.
        for (int port = 0; port < 4; port++) {
            try { releasePort(s, port); } catch (Throwable ignored) { }
        }
        held.clear();
        selectHeld = false;
        if (s != null) {
            for (Integer vk : new ArrayList<>(virtualKeys)) {
                try { s.retroView.sendKeyEvent(KeyEvent.ACTION_UP, vk & 0xFFFF, vk >> 16); }
                catch (Throwable ignored) { }
            }
            for (Integer va : new ArrayList<>(virtualAxes)) {
                try { s.retroView.sendMotionEvent(va & 0xFF, 0f, 0f, va >> 8); }
                catch (Throwable ignored) { }
            }
        }
        virtualKeys.clear();
        virtualAxes.clear();
        // A finger on the DS/3DS touch screen whose "up" never arrives leaves the pointer stuck.
        if (touchActive && s != null) {
            try { dispatchTouch(s.retroView, MotionEvent.ACTION_UP, lastTouchX, lastTouchY); }
            catch (Throwable ignored) { }
        }
        touchActive = false;
    }

    private void dispatchTouch(GLRetroView v, int action, float px, float py) {
        long now = SystemClock.uptimeMillis();
        if (action == MotionEvent.ACTION_DOWN || touchDownTime == 0) touchDownTime = now;
        MotionEvent ev = MotionEvent.obtain(touchDownTime, now, action, px, py, 0);
        ev.setSource(InputDevice.SOURCE_TOUCHSCREEN);
        try {
            v.dispatchTouchEvent(ev);
        } finally {
            ev.recycle();
        }
    }

    /** Releases everything held through one port (a pad that vanished must not leave keys down). */
    private void releasePort(GameSession s, int port) {
        try {
            releasePortNative(s, port);
        } finally {
            for (Integer k : new ArrayList<>(held)) if ((k >> 16) == port) held.remove(k);
            l2Down[port] = false;
            r2Down[port] = false;
            for (float[] a : lastAxis[port]) { a[0] = 0f; a[1] = 0f; }
        }
    }

    private void releasePortNative(GameSession s, int port) {
        if (s != null) {
            GLRetroView v = s.retroView;
            for (Integer k : new ArrayList<>(held)) {
                if ((k >> 16) == port) padKey(v, port, KeyEvent.ACTION_UP, k & 0xFFFF);
            }
            if (l2Down[port]) padKey(v, port, KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BUTTON_L2);
            if (r2Down[port]) padKey(v, port, KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BUTTON_R2);
            padAxis(v, port, GLRetroView.MOTION_SOURCE_ANALOG_LEFT, 0f, 0f);
            padAxis(v, port, GLRetroView.MOTION_SOURCE_ANALOG_RIGHT, 0f, 0f);
            padAxis(v, port, GLRetroView.MOTION_SOURCE_DPAD, 0f, 0f);
        }
    }

    /**
     * Connected pad ids in port order. Rebuilt only when a device is added/removed/changed:
     * portFor() runs for EVERY key and stick event (hundreds per second), and enumerating and
     * sorting all input devices each time allocated heavily and caused stutter while playing.
     */
    private volatile int[] padOrder = null;

    private void invalidatePads() { padOrder = null; }

    private int[] padOrder() {
        int[] cached = padOrder;
        if (cached != null) return cached;
        List<Integer> ids = new ArrayList<>();
        for (int id : InputDevice.getDeviceIds()) {
            InputDevice d = InputDevice.getDevice(id);
            if (d != null && !d.isVirtual() && isGamepad(d)) ids.add(id);
        }
        Collections.sort(ids);
        int[] out = new int[ids.size()];
        for (int i = 0; i < out.length; i++) out[i] = ids.get(i);
        padOrder = out;
        return out;
    }

    /** Port a physical pad drives: connected pads in device-id order are P1..P4. */
    private int portFor(InputDevice device) {
        if (device == null) return 0;
        int[] ids = padOrder();
        int id = device.getId();
        for (int i = 0; i < ids.length; i++) {
            if (ids[i] == id) return Math.min(i, 3);
        }
        return 0;
    }

    private void padKey(GLRetroView v, int port, int action, int code) {
        try { v.sendKeyEvent(action, code, port); } catch (Throwable ignored) { }
    }

    /** Last value sent per port/source (0 = D-pad hat, 1 = left stick, 2 = right stick). */
    private final float[][][] lastAxis = new float[4][3][2];

    private void padAxis(GLRetroView v, int port, int source, float x, float y) {
        if (port >= 0 && port < 4 && source >= 0 && source < 3) {
            float[] last = lastAxis[port][source];
            if (last[0] == x && last[1] == y) return; // unchanged: no JNI call
            last[0] = x;
            last[1] = y;
        }
        try { v.sendMotionEvent(source, x, y, port); } catch (Throwable ignored) { }
    }

    private void emitGamepad() {
        if (channel != null) channel.invokeMethod("gamepad", anyGamepad());
    }

    /** A/B and X/Y swap for pads whose labels are laid out the other way round. */
    private int remap(int k) {
        if (swapAB) {
            if (k == KeyEvent.KEYCODE_BUTTON_A) return KeyEvent.KEYCODE_BUTTON_B;
            if (k == KeyEvent.KEYCODE_BUTTON_B) return KeyEvent.KEYCODE_BUTTON_A;
        }
        if (swapXY) {
            if (k == KeyEvent.KEYCODE_BUTTON_X) return KeyEvent.KEYCODE_BUTTON_Y;
            if (k == KeyEvent.KEYCODE_BUTTON_Y) return KeyEvent.KEYCODE_BUTTON_X;
        }
        return k;
    }

    private void sendPad(GameSession s, int port, int code, int action) {
        int key = (port << 16) | code;
        if (action == KeyEvent.ACTION_DOWN) held.add(key); else held.remove(key);
        padKey(s.retroView, port, action, code);
    }

    private boolean handleCombo(GameSession s, int code, int action) {
        if (code == KeyEvent.KEYCODE_BUTTON_SELECT) {
            if (action == KeyEvent.ACTION_DOWN) {
                selectHeld = true;
                comboUsed = false;
            } else {
                selectHeld = false;
                if (!comboUsed) {
                    sendPad(s, 0, KeyEvent.KEYCODE_BUTTON_SELECT, KeyEvent.ACTION_DOWN);
                    ui.postDelayed(() -> {
                        GameSession cur = factory == null ? null : factory.getReadySession();
                        if (cur != null) sendPad(cur, 0, KeyEvent.KEYCODE_BUTTON_SELECT, KeyEvent.ACTION_UP);
                    }, 60);
                }
            }
            return true;
        }
        if (!selectHeld) return false;
        // Button pressed BEFORE Select was held: let its release through, or the game keeps it down.
        if (action == KeyEvent.ACTION_UP && held.contains(remap(code))) return false; // combo hotkeys only exist on port 0 (key = code)
        String hk = null;
        switch (code) {
            case KeyEvent.KEYCODE_BUTTON_START: hk = "menu"; break;
            case KeyEvent.KEYCODE_BUTTON_R1:    hk = "quickSave"; break;
            case KeyEvent.KEYCODE_BUTTON_L1:    hk = "quickLoad"; break;
            case KeyEvent.KEYCODE_BUTTON_X:     hk = "nextSlot"; break;
            case KeyEvent.KEYCODE_BUTTON_THUMBR: hk = "screenshot"; break;
            case KeyEvent.KEYCODE_BUTTON_THUMBL: hk = "mute"; break;
            case KeyEvent.KEYCODE_Y:            // fallback safety
            case KeyEvent.KEYCODE_BUTTON_Y:     hk = "fastForward"; break;
        }
        if (hk == null) return false;
        comboUsed = true;
        if (action == KeyEvent.ACTION_DOWN) emit(hk);
        return true;
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        GameSession s = factory == null ? null : factory.getReadySession();
        int code = event.getKeyCode();
        if (s == null || uiCaptured || !isGamepad(event.getDevice()) || !isGameKey(code)) {
            return super.dispatchKeyEvent(event);
        }
        int action = event.getAction();
        if (code == KeyEvent.KEYCODE_BUTTON_MODE) {
            if (action == KeyEvent.ACTION_DOWN && event.getRepeatCount() == 0) emit("menu");
            return true;
        }
        if (pauseGate) {
            // Auto-paused: A or B continues, every other press is ignored. Releases still pass,
            // so a button held when the pause began cannot stay stuck down.
            if (action == KeyEvent.ACTION_DOWN) {
                if (event.getRepeatCount() == 0
                    && (code == KeyEvent.KEYCODE_BUTTON_A || code == KeyEvent.KEYCODE_BUTTON_B)) {
                    emit("resumeGate");
                }
                return true;
            }
        }
        if (event.getRepeatCount() > 0) return true;
        int port = portFor(event.getDevice());
        // Hotkey combos belong to the first pad only; the others are plain players.
        if (comboHotkeys && port == 0 && handleCombo(s, code, action)) return true;
        sendPad(s, port, remap(code), action);
        return true;
    }

    @Override
    public boolean dispatchGenericMotionEvent(MotionEvent event) {
        GameSession s = factory == null ? null : factory.getReadySession();
        if (s != null && !uiCaptured && event.getAction() == MotionEvent.ACTION_MOVE
            && (event.getSource() & InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK) {
            GLRetroView v = s.retroView;
            int port = portFor(event.getDevice());
            stick(v, port, GLRetroView.MOTION_SOURCE_ANALOG_LEFT,
                event.getAxisValue(MotionEvent.AXIS_X), event.getAxisValue(MotionEvent.AXIS_Y));

            float rx = pickLarger(event.getAxisValue(MotionEvent.AXIS_Z), event.getAxisValue(MotionEvent.AXIS_RX));
            float ry = pickLarger(event.getAxisValue(MotionEvent.AXIS_RZ), event.getAxisValue(MotionEvent.AXIS_RY));
            stick(v, port, GLRetroView.MOTION_SOURCE_ANALOG_RIGHT, rx, ry);

            padAxis(v, port, GLRetroView.MOTION_SOURCE_DPAD,
                event.getAxisValue(MotionEvent.AXIS_HAT_X), event.getAxisValue(MotionEvent.AXIS_HAT_Y));

            boolean l2 = Math.max(event.getAxisValue(MotionEvent.AXIS_LTRIGGER),
                                  event.getAxisValue(MotionEvent.AXIS_BRAKE)) > 0.5f;
            boolean r2 = Math.max(event.getAxisValue(MotionEvent.AXIS_RTRIGGER),
                                  event.getAxisValue(MotionEvent.AXIS_GAS)) > 0.5f;
            if (l2 != l2Down[port]) {
                l2Down[port] = l2;
                padKey(v, port, l2 ? KeyEvent.ACTION_DOWN : KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BUTTON_L2);
            }
            if (r2 != r2Down[port]) {
                r2Down[port] = r2;
                padKey(v, port, r2 ? KeyEvent.ACTION_DOWN : KeyEvent.ACTION_UP, KeyEvent.KEYCODE_BUTTON_R2);
            }
            return true;
        }
        return super.dispatchGenericMotionEvent(event);
    }

    /**
     * Radial dead zone with rescaling. The old per-axis cut made diagonals snap to the nearest
     * axis and the stick jump from 0 to the dead-zone value; this keeps full precision.
     */
    private void stick(GLRetroView v, int port, int source, float x, float y) {
        float m = (float) Math.hypot(x, y);
        float dzone = deadzone;
        if (m <= dzone || m == 0f) {
            padAxis(v, port, source, 0f, 0f);
            return;
        }
        float scale = Math.min(1f, (m - dzone) / (1f - dzone)) / m;
        padAxis(v, port, source, x * scale, y * scale);
    }
    private static float pickLarger(float a, float b) { return Math.abs(a) >= Math.abs(b) ? a : b; }

    private static boolean isGameKey(int k) {
        return KeyEvent.isGamepadButton(k)
            || (k >= KeyEvent.KEYCODE_DPAD_UP && k <= KeyEvent.KEYCODE_DPAD_RIGHT);
    }

    private static boolean isGamepad(InputDevice device) {
        if (device == null) return false;
        int sources = device.getSources();
        return ((sources & InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD)
            || ((sources & InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK);
    }
}