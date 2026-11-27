package com.jedplatforms.jedEmu;

import android.opengl.EGL14;
import android.opengl.EGLConfig;
import android.opengl.EGLContext;
import android.opengl.EGLDisplay;
import android.opengl.EGLSurface;
import android.opengl.GLES20;
import android.os.Build;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * Phone model, CPU and GPU names for the library page. The GPU name comes from a tiny throw-away
 * OpenGL ES context (the same driver the cores render with). Everything is best-effort: any value
 * that cannot be read is simply left out, and the result is cached after the first call.
 * Call from a background thread (creating the GL context takes a few ms).
 */
final class DeviceInfo {
    private DeviceInfo() {}

    private static Map<String, String> cache;

    static synchronized Map<String, String> get() {
        if (cache != null) return cache;
        Map<String, String> m = new HashMap<>();

        String maker = Build.MANUFACTURER == null ? "" : Build.MANUFACTURER.trim();
        String model = Build.MODEL == null ? "" : Build.MODEL.trim();
        // "samsung SM-S918B" reads better than "SM-S918B"; avoid "Google Google Pixel".
        if (!maker.isEmpty() && !model.toLowerCase(Locale.ROOT).startsWith(maker.toLowerCase(Locale.ROOT))) {
            model = capitalize(maker) + " " + model;
        }
        m.put("model", model.trim());

        m.put("cpu", cpuName());
        int cores = Runtime.getRuntime().availableProcessors();
        m.put("cores", String.valueOf(cores));
        long mhz = maxFreqMhz();
        if (mhz > 0) m.put("maxMhz", String.valueOf(mhz));

        String gpu = gpuName();
        if (gpu != null) m.put("gpu", gpu);

        m.put("android", Build.VERSION.RELEASE + " (API " + Build.VERSION.SDK_INT + ")");
        m.put("api", String.valueOf(Build.VERSION.SDK_INT));
        String[] abis = Build.SUPPORTED_ABIS;
        m.put("abi", abis != null && abis.length > 0 ? abis[0] : "unknown");
        m.put("is64", String.valueOf(is64Bit(abis)));
        long ram = totalRamMb();
        if (ram > 0) m.put("ramMb", String.valueOf(ram));
        m.put("tier", tierFor(ram, cores, mhz));

        cache = m;
        return m;
    }

    private static boolean is64Bit(String[] abis) {
        if (abis == null) return false;
        for (String a : abis) if (a != null && a.contains("64")) return true;
        return false;
    }

    /** Total RAM in MB from /proc/meminfo (the OS reserves some, so a "6 GB" phone reports about 5.5 GB). 0 if unreadable. */
    private static long totalRamMb() {
        try (BufferedReader r = new BufferedReader(new FileReader("/proc/meminfo"))) {
            String line;
            while ((line = r.readLine()) != null) {
                if (!line.startsWith("MemTotal")) continue;
                String digits = line.replaceAll("[^0-9]", "");
                if (!digits.isEmpty()) return Long.parseLong(digits) / 1024; // kB -> MB
            }
        } catch (Throwable ignored) { }
        return 0;
    }

    /**
     * Rough speed class: "low", "mid" or "high". Unknown RAM is treated as mid. An unreadable CPU
     * frequency (maxMhz == 0: most phones hide cpuinfo_max_freq from apps) is "unknown", not "slow":
     * it must not stop a big-RAM phone from ever reaching "high".
     */
    private static String tierFor(long ramMb, int cores, long maxMhz) {
        if (ramMb <= 0) return "mid";
        if (ramMb < 3000 || cores < 6) return "low";
        if (ramMb >= 5500 && (maxMhz <= 0 || maxMhz >= 2600)) return "high";
        return "mid";
    }

    /** The core-settings preset that suits this phone: "performance", "balanced" or "quality". */
    static String recommendedPreset() {
        String tier = get().get("tier");
        if ("low".equals(tier)) return "performance";
        if ("high".equals(tier)) return "quality";
        return "balanced";
    }

    /**
     * How well this phone should run a system, from the minimum / recommended figures tonEMU
     * publishes: "good", "limited" or "unlikely". [system] is one of: 8bit16bit (NES, SNES, GB, GBC,
     * GBA, Master System, Game Gear, Genesis), nds, ps1, n64, saturn, psp, 3ds. Unknown
     * systems return "good" (never block). The 3DS core is arm64 only.
     */
    static String compatibility(String system) {
        Map<String, String> m = get();
        if (system == null) return "good";
        long ram = parse(m.get("ramMb"));
        boolean is64 = "true".equals(m.get("is64"));
        // Reported RAM is ~85% of the marketed size, so scale the GB limits down the same way.
        double minGb, recGb;
        switch (system) {
            case "8bit16bit": minGb = 2; recGb = 2; break;
            case "nds":
            case "ps1":       minGb = 3; recGb = 4; break;
            case "n64":
            case "saturn":
            case "psp":       minGb = 4; recGb = 6; break;
            case "3ds":
                if (!is64) return "unlikely";
                minGb = 6; recGb = 8; break;
            default:          return "good";
        }
        if (ram <= 0) return "good"; // RAM unknown: do not scare the user
        if (ram >= recGb * 1024 * 0.85) return "good";
        if (ram >= minGb * 1024 * 0.85) return "limited";
        return "unlikely";
    }

    private static long parse(String s) {
        try { return s == null ? 0 : Long.parseLong(s); } catch (Exception e) { return 0; }
    }

    private static String capitalize(String s) {
        return s.isEmpty() ? s : Character.toUpperCase(s.charAt(0)) + s.substring(1);
    }

    private static String cpuName() {
        if (Build.VERSION.SDK_INT >= 31) {
            String soc = Build.SOC_MODEL;
            String man = Build.SOC_MANUFACTURER;
            if (soc != null && !soc.isEmpty() && !soc.equalsIgnoreCase("unknown")) {
                if (man != null && !man.isEmpty() && !man.equalsIgnoreCase("unknown")
                    && !soc.toLowerCase(Locale.ROOT).contains(man.toLowerCase(Locale.ROOT))) {
                    return man + " " + soc;
                }
                return soc;
            }
        }
        try (BufferedReader r = new BufferedReader(new FileReader("/proc/cpuinfo"))) {
            String line;
            while ((line = r.readLine()) != null) {
                if (line.toLowerCase(Locale.ROOT).startsWith("hardware")) {
                    int i = line.indexOf(':');
                    if (i >= 0 && i + 1 < line.length()) return line.substring(i + 1).trim();
                }
            }
        } catch (Throwable ignored) { }
        String hw = Build.HARDWARE;
        return hw == null || hw.isEmpty() ? "Unknown" : hw;
    }

    /** Highest per-core max frequency, in MHz; 0 if the kernel does not let apps read it. */
    private static long maxFreqMhz() {
        long best = 0;
        for (int i = 0; i < 16; i++) {
            File f = new File("/sys/devices/system/cpu/cpu" + i + "/cpufreq/cpuinfo_max_freq");
            if (!f.canRead()) continue;
            try (BufferedReader r = new BufferedReader(new FileReader(f))) {
                String s = r.readLine();
                if (s != null) best = Math.max(best, Long.parseLong(s.trim()) / 1000);
            } catch (Throwable ignored) { }
        }
        return best;
    }

    private static String gpuName() {
        EGLDisplay dpy = EGL14.EGL_NO_DISPLAY;
        EGLContext ctx = EGL14.EGL_NO_CONTEXT;
        EGLSurface surf = EGL14.EGL_NO_SURFACE;
        try {
            dpy = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY);
            int[] ver = new int[2];
            if (dpy == EGL14.EGL_NO_DISPLAY || !EGL14.eglInitialize(dpy, ver, 0, ver, 1)) return null;

            int[] attribs = {
                EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
                EGL14.EGL_NONE
            };
            EGLConfig[] cfgs = new EGLConfig[1];
            int[] n = new int[1];
            if (!EGL14.eglChooseConfig(dpy, attribs, 0, cfgs, 0, 1, n, 0) || n[0] < 1) return null;

            ctx = EGL14.eglCreateContext(dpy, cfgs[0], EGL14.EGL_NO_CONTEXT,
                new int[] { EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE }, 0);
            surf = EGL14.eglCreatePbufferSurface(dpy, cfgs[0],
                new int[] { EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE }, 0);
            if (ctx == EGL14.EGL_NO_CONTEXT || surf == EGL14.EGL_NO_SURFACE) return null;
            if (!EGL14.eglMakeCurrent(dpy, surf, surf, ctx)) return null;

            String r = GLES20.glGetString(GLES20.GL_RENDERER);
            return r == null || r.isEmpty() ? null : r.trim();
        } catch (Throwable t) {
            return null;
        } finally {
            try {
                if (dpy != EGL14.EGL_NO_DISPLAY) {
                    EGL14.eglMakeCurrent(dpy, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT);
                    if (surf != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(dpy, surf);
                    if (ctx != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(dpy, ctx);
                    // No eglTerminate: the default display is shared with Flutter and the cores.
                }
            } catch (Throwable ignored) { }
        }
    }
}