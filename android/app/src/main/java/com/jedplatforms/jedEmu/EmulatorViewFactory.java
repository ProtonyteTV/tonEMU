package com.jedplatforms.jedEmu;

import android.content.Context;
import android.graphics.Bitmap;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.os.Build;
import android.view.PixelCopy;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.TextView;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.swordfish.libretrodroid.GLRetroView;
import com.swordfish.libretrodroid.GLRetroViewData;
import com.swordfish.libretrodroid.ShaderConfig;
import com.swordfish.libretrodroid.Variable;

import java.io.File;
import java.io.IOException;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;

public class EmulatorViewFactory extends PlatformViewFactory {
    private final FlutterActivity activity;
    @Nullable private GameSession current;

    public EmulatorViewFactory(FlutterActivity activity) {
        super(StandardMessageCodec.INSTANCE);
        this.activity = activity;
    }

    @Nullable GameSession getCurrent() { return current; }

    @Nullable GameSession getReadySession() {
        return (current != null && current.isReady()) ? current : null;
    }

    void destroyCurrent() {
        if (current != null) release(current);
    }

    private void release(GameSession session) {
        session.destroy();
        if (current == session) {
            current = null;
            activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        }
    }

    /** Finds the core .so in the native lib dir; tolerates naming differences (e.g. azahar/citra). */
    @Nullable
    static File resolveCore(Context context, String name) {
        File dir = new File(context.getApplicationInfo().nativeLibraryDir);
        File exact = new File(dir, name);
        if (exact.exists()) return exact;

        String key = name.startsWith("lib") ? name.substring(3) : name;
        int idx = key.indexOf("_libretro");
        if (idx > 0) key = key.substring(0, idx);

        String[] candidates = "azahar".equals(key) ? new String[] {"azahar", "citra"} : new String[] {key};
        File[] files = dir.listFiles();
        if (files == null) return null;
        for (String cand : candidates) {
            for (File f : files) {
                if (f.getName().contains(cand + "_libretro")) return f;
            }
        }
        return null;
    }

    @NonNull
    @Override
    @SuppressWarnings("unchecked")
    public PlatformView create(Context context, int viewId, Object args) {
        // Never let two cores exist at once (relaunching PSP/3DS with a live core = native crash).
        destroyCurrent();
        // Cores read the clock via libc: give this process the phone's timezone before one loads.
        TimeZoneSync.apply();

        Map<String, Object> params = args instanceof Map ? (Map<String, Object>) args : new HashMap<>();
        String coreName = (String) params.get("core");
        String romPath = (String) params.get("romPath");
        String layout = (String) params.get("layout");
        boolean useVulkan = Boolean.TRUE.equals(params.get("vulkan"));
        boolean bootBios = Boolean.TRUE.equals(params.get("bootBios"));

        // Player profile values sent from Flutter's AppSettings (used for 3DS & NDS)
        String nickname = params.get("nickname") instanceof String
            ? (String) params.get("nickname") : "tonEMU";
        int birthMonth = params.get("birthMonth") instanceof Number
            ? ((Number) params.get("birthMonth")).intValue() : 1;
        int birthDay = params.get("birthDay") instanceof Number
            ? ((Number) params.get("birthDay")).intValue() : 1;

        Map<String, String> userOptions = new HashMap<>();
        Object rawOpts = params.get("options");
        if (rawOpts instanceof Map) {
            for (Map.Entry<?, ?> e : ((Map<?, ?>) rawOpts).entrySet()) {
                if (e.getKey() != null && e.getValue() != null) {
                    userOptions.put(String.valueOf(e.getKey()), String.valueOf(e.getValue()));
                }
            }
        }

        Map<String, String> regionOptions = new HashMap<>();
        Object rawRegion = params.get("regionOptions");
        if (rawRegion instanceof Map) {
            for (Map.Entry<?, ?> e : ((Map<?, ?>) rawRegion).entrySet()) {
                if (e.getKey() != null && e.getValue() != null) {
                    regionOptions.put(String.valueOf(e.getKey()), String.valueOf(e.getValue()));
                }
            }
        }

        File core = coreName == null ? null : resolveCore(context, coreName);
        if (core == null) {
            return errorView(context, "This core is not available on this device.\n\n(" + coreName + ")");
        }
        if (!bootBios && (romPath == null || !new File(romPath).exists())) {
            return errorView(context, "Game file not found:\n" + romPath);
        }

        // Same root as Flutter's StorageService (see StorageRoot): the app-specific external
        // folder, or private filesDir as a fallback. BIOS, battery saves, memory cards and 3DS
        // NAND all live there.
        File root = activity instanceof MainActivity
            ? ((MainActivity) activity).getTonEmuRootDir()
            : new File(context.getFilesDir(), "tonEMU");
        File systemDir = new File(root, "system");
        File savesDir = new File(root, "saves");
        systemDir.mkdirs(); // cores crash if these don't exist
        savesDir.mkdirs();

        // Keep the PPSSPP folder hidden from the gallery (fonts come from the user's PPSSPP.zip)
        if (PpssppAssetsInstaller.isPpsspp(core.getName())) {
            PpssppAssetsInstaller.ensureInstalled(context, systemDir);
        }

        String effectiveGamePath = romPath;
        if (bootBios && CoreOptions.isMelonDs(core.getName())) {
            String[] required = new String[] { "bios7.bin", "bios9.bin", "firmware.bin" };
            for (String req : required) {
                if (!new File(systemDir, req).exists()) {
                    return errorView(context, "Missing DS BIOS file:\n" + req
                        + "\n\nImport bios7.bin, bios9.bin, and firmware.bin in Settings.");
                }
            }
            // LibretroDroid requires a valid gameFilePath to initialize native FPSSync/Core.
            File dummyCart = new File(systemDir, "boot_bios.nds");
            try {
                if (!dummyCart.exists() || dummyCart.length() != 512) {
                    GameSession.writeAtomically(dummyCart, new byte[512]);
                }
                effectiveGamePath = dummyCart.getAbsolutePath();
            } catch (IOException e) {
                return errorView(context, "Failed to prepare DS BIOS boot image:\n" + e.getMessage());
            }
        } else if (bootBios && CoreOptions.isPs1(core.getName())) {
            String[] biosNames = {
                "scph5501.bin", "scph1001.bin", "scph7001.bin", "scph7003.bin",
                "scph5500.bin", "scph5502.bin", "ps-22a.bin", "ps-20a.bin"
            };
            boolean haveBios = false;
            for (String n : biosNames) {
                if (new File(systemDir, n).exists()) { haveBios = true; break; }
            }
            if (!haveBios) {
                return errorView(context, "Missing PlayStation BIOS.\n\n"
                    + "Import a PS1 BIOS (e.g. scph5501.bin) in Settings.");
            }
            // The core needs a disc to start. A silent AUDIO CD makes the BIOS open its built-in
            // shell (CD player / memory card screen), exactly like a real console. A blank DATA
            // disc does not: the BIOS rejects it and stays on a black screen after the boot sound.
            final int sectors = 750; // ~10 s of silence at 75 sectors/s
            File bin = new File(systemDir, "boot_bios.bin");
            File cue = new File(systemDir, "boot_bios.cue");
            try {
                if (!bin.exists() || bin.length() != 2352L * sectors) {
                    GameSession.writeAtomically(bin, new byte[2352 * sectors]);
                }
                String cueText = "FILE \"boot_bios.bin\" BINARY\n"
                    + "  TRACK 01 AUDIO\n"
                    + "    INDEX 01 00:00:00\n";
                GameSession.writeAtomically(cue, cueText.getBytes(java.nio.charset.StandardCharsets.UTF_8));
                effectiveGamePath = cue.getAbsolutePath();
            } catch (IOException e) {
                return errorView(context, "Failed to prepare PS1 BIOS boot image:\n" + e.getMessage());
            }
        }

        if (effectiveGamePath == null || !new File(effectiveGamePath).exists()) {
            return errorView(context, "Game file not found:\n" + effectiveGamePath);
        }

        // Write 3DS / NDS Nickname & Birthday to native firmware/NAND config before core boot
        SystemProfileWriter.apply(core.getName(), systemDir, savesDir, nickname, birthMonth, birthDay);

        String saveName = romPath == null ? null : new File(romPath).getName();
        File sramFile = (!bootBios && romPath != null)
            ? sramFileFor(savesDir, saveName, core.getName())
            : null;

        GLRetroViewData data = new GLRetroViewData(context);
        data.setCoreFilePath(core.getAbsolutePath());
        data.setGameFilePath(effectiveGamePath);
        data.setSystemDirectory(systemDir.getAbsolutePath());
        data.setSavesDirectory(savesDir.getAbsolutePath());

        ShaderConfig shader = VideoOptions.shader((String) params.get("shader"));
        if (shader != null) data.setShader(shader);
        // Yabause is software rendered and runs close to its limit on phones: a tiny low-latency
        // audio buffer underruns there and is heard (and felt) as stutter, so never use it.
        final boolean isSaturn = CoreOptions.isSaturn(core.getName());
        data.setPreferLowLatencyAudio(Boolean.TRUE.equals(params.get("lowLatency")) && !isSaturn);
        // Without a device chosen for the ports Yabause starts with no pad plugged in.
        final boolean saturnPadsSet = isSaturn && SaturnSupport.applyLaunchConfig(data);

        // PS1: plug a DualShock (analog) into the ports, otherwise sticks and L3 / R3 do nothing.
        final boolean isPs1 = CoreOptions.isPs1(core.getName());
        final boolean ps1PadsSet = isPs1 && Ps1Support.applyLaunchConfig(data);

        if (sramFile != null && sramFile.exists()) {
            try {
                data.setSaveRAMState(FileUtil.readAll(sramFile));
            } catch (IOException e) {
                // The existing battery save cannot be read. Run without battery saves this session,
                // otherwise the first auto-flush would overwrite it with a blank one.
                Log.w("tonEmuSave", "cannot read " + sramFile + ", battery saves off for this session", e);
                sramFile = null;
            }
        }

        List<Variable> vars = CoreOptions.initial(core.getName(), useVulkan, layout, userOptions, bootBios, regionOptions);
        data.setVariables(vars.toArray(new Variable[0]));

        FrameLayout container = new FrameLayout(context);
        GLRetroView retroView = new GLRetroView(context, data);
        container.addView(retroView, new FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
            Gravity.CENTER));
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            container.setDefaultFocusHighlightEnabled(false);
            retroView.setDefaultFocusHighlightEnabled(false);
        }

        final GameSession session = new GameSession(retroView, core.getName(), activity.getLifecycle(), sramFile);
        current = session;
        activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        if (isSaturn) {
            // Safety net: re-select the Saturn Pad once the core is up (always, if the launch
            // config was not accepted by this LibretroDroid version).
            // setControllerType is a native call: wait until the core has really rendered a frame
            // (a fixed 3-5 s timer hit half-loaded cores on slow phones = SIGSEGV).
            final Handler sh = new Handler(Looper.getMainLooper());
            final long started = SystemClock.elapsedRealtime();
            sh.postDelayed(new Runnable() {
                @Override public void run() {
                    if (!session.isAlive()) return;
                    if (!session.isReady()) {
                        if (SystemClock.elapsedRealtime() - started < 120_000) sh.postDelayed(this, 500);
                        return;
                    }
                    SaturnSupport.forceJoypad(retroView);
                }
            }, saturnPadsSet ? 1500 : 500);
        }

        if (isPs1) {
            // Safety net, same rule as Saturn: only touch the core natively once it has drawn a frame.
            final Handler ph = new Handler(Looper.getMainLooper());
            final long pStarted = SystemClock.elapsedRealtime();
            ph.postDelayed(new Runnable() {
                @Override public void run() {
                    if (!session.isAlive()) return;
                    if (!session.isReady()) {
                        if (SystemClock.elapsedRealtime() - pStarted < 120_000) ph.postDelayed(this, 500);
                        return;
                    }
                    Ps1Support.forceAnalog(retroView);
                }
            }, ps1PadsSet ? 1500 : 500);
        }

        // The hardware renderer is opt-in and fails on some core builds. Say so instead of staying black.
        if (CoreOptions.isPs1(core.getName()) && CoreOptions.wantsGles(userOptions)) {
            watchForBlackScreen(retroView, container, session,
                "The OpenGL ES renderer did not draw anything.\n\n"
                + "This core build may not support it on your GPU. Open the core settings, set "
                + "Renderer back to Software, and restart the game.");
        }

        return new PlatformView() {
            @Override public View getView() { return container; }
            @Override public void dispose() { release(session); }
        };
    }


    /**
     * If the game surface is still pure black ~15 s after launch, overlay [message] so the user is not
     * left on a silent black screen. Re-checks every 5 s (about 75 s total); the overlay disappears
     * as soon as anything is drawn.
     */
    private void watchForBlackScreen(GLRetroView view, FrameLayout container, GameSession session,
                                     String message) {
        final Handler h = new Handler(Looper.getMainLooper());
        final TextView banner = new TextView(container.getContext());
        banner.setText(message);
        styleMessage(banner, 0xE6000000);
        final int[] attempts = {0};

        Runnable check = new Runnable() {
            @Override public void run() {
                if (!session.isAlive()) return;
                if (++attempts[0] > 12) return;
                if (!view.isAttachedToWindow() || view.getWidth() <= 0 || view.getHeight() <= 0) {
                    h.postDelayed(this, 3000);
                    return;
                }
                final Bitmap bmp = Bitmap.createBitmap(32, 18, Bitmap.Config.ARGB_8888);
                final Runnable self = this;
                try {
                    PixelCopy.request(view, bmp, code -> {
                        if (!session.isAlive()) return;
                        if (code != PixelCopy.SUCCESS) { h.postDelayed(self, 5000); return; }
                        boolean blank = true;
                        for (int y = 0; y < 18 && blank; y++) {
                            for (int x = 0; x < 32; x++) {
                                if ((bmp.getPixel(x, y) & 0x00FFFFFF) != 0) { blank = false; break; }
                            }
                        }
                        if (!blank) {
                            if (banner.getParent() != null) container.removeView(banner);
                            return;
                        }
                        if (banner.getParent() == null) {
                            container.addView(banner, new FrameLayout.LayoutParams(
                                FrameLayout.LayoutParams.MATCH_PARENT,
                                FrameLayout.LayoutParams.MATCH_PARENT));
                        }
                        h.postDelayed(self, 5000);
                    }, h);
                } catch (Throwable t) {
                    h.postDelayed(this, 5000);
                }
            }
        };
        h.postDelayed(check, 15_000);
    }

    /**
     * Battery save per ROM name AND core, so the same game on two cores never shares (and
     * corrupts) one file. An old "<rom>.srm" is copied over once, never deleted.
     */
    private static File sramFileFor(File savesDir, String romName, String coreName) {
        String key = coreName.replaceAll("(?i)^lib|_libretro.*$|\\.so$", "")
                             .replaceAll("[^A-Za-z0-9_-]", "");
        File f = new File(savesDir, romName + "." + key + ".srm");
        File legacy = new File(savesDir, romName + ".srm");
        // The plain "<rom>.srm" is the old pre-core-keyed name. Gearsystem replaced a core with a
        // different save layout, so it must never pick that file up.
        if (!f.exists() && legacy.exists() && !key.equals("gearsystem")) {
            try { FileUtil.copy(legacy, f); } catch (IOException ignored) { }
        }
        return f;
    }

    /** Shared look for native messages: readable size, dp padding, selectable so it can be copied. */
    private static void styleMessage(TextView tv, int background) {
        float d = tv.getResources().getDisplayMetrics().density;
        int pad = Math.round(28 * d);
        tv.setTextColor(0xFFFFFFFF);
        tv.setBackgroundColor(background);
        tv.setGravity(Gravity.CENTER);
        tv.setTextSize(15f);
        tv.setLineSpacing(0f, 1.25f);
        tv.setPadding(pad, pad, pad, pad);
        tv.setTextIsSelectable(true);
    }

    private PlatformView errorView(Context context, String message) {
        TextView tv = new TextView(context);
        tv.setText(message);
        styleMessage(tv, 0xFF000000);
        return new PlatformView() {
            @Override public View getView() { return tv; }
            @Override public void dispose() { }
        };
    }
}