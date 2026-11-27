package com.jedplatforms.jedEmu;

import androidx.annotation.Nullable;

import com.swordfish.libretrodroid.ShaderConfig;

/** Maps our neutral filter names to LibretroDroid shaders (looked up reflectively so object/class variants both work). */
final class VideoOptions {
    private VideoOptions() {}

    /** Every filter id the app knows. Newer LibretroDroid builds add the "cut" family; older ones lack them. */
    static final String[] ALL = { "none", "sharp", "crt", "lcd", "cut", "cut2", "cut3" };

    /** Class name inside ShaderConfig for a filter id, or "Default" for none / unknown. */
    private static String className(@Nullable String name) {
        if (name == null) return "Default";
        switch (name) {
            case "sharp": return "Sharp";
            case "crt":   return "CRT";
            case "lcd":   return "LCD";
            case "cut":   return "CUT";   // cubic upscale: smooth, no shimmering on pixel art
            case "cut2":  return "CUT2";
            case "cut3":  return "CUT3";
            default:      return "Default";
        }
    }

    @Nullable
    static ShaderConfig shader(@Nullable String name) {
        if (name == null) return null;
        String cls = className(name);
        try {
            Class<?> c = Class.forName("com.swordfish.libretrodroid.ShaderConfig$" + cls);
            try {
                return (ShaderConfig) c.getField("INSTANCE").get(null); // Kotlin object
            } catch (NoSuchFieldException e) {
                return (ShaderConfig) c.getDeclaredConstructor().newInstance(); // class with default args
            }
        } catch (Throwable t) {
            android.util.Log.w("tonEmuVid", "shader lookup failed for " + cls, t);
            return null;
        }
    }

    /** True when this LibretroDroid build really has the filter (so the settings screen can hide the rest). */
    static boolean isAvailable(@Nullable String name) {
        String cls = className(name);
        if (cls.equals("Default")) return true;
        try {
            Class.forName("com.swordfish.libretrodroid.ShaderConfig$" + cls);
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    /** Only the filter ids that work in this build, in display order. */
    static String[] available() {
        java.util.List<String> out = new java.util.ArrayList<>();
        for (String n : ALL) if (isAvailable(n)) out.add(n);
        return out.toArray(new String[0]);
    }
}