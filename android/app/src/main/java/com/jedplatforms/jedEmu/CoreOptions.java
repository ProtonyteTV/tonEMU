package com.jedplatforms.jedEmu;

import com.swordfish.libretrodroid.Variable;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Pattern;

/** All libretro core option keys/values live here so they are easy to adjust per core build. */
final class CoreOptions {
    private CoreOptions() {}

    /** LibretroDroid 0.12.0 Variable is (key, value, description); description is informational only. */
    static Variable v(String key, String value) {
        return new Variable(key, value, "");
    }

    private static boolean has(String core, String needle) {
        return core != null && core.toLowerCase(Locale.ROOT).contains(needle);
    }

    static boolean isMelonDs(String core) { return has(core, "melonds"); }
    static boolean isAzahar(String core)  { return has(core, "azahar"); }
    static boolean isPs1(String core)     { return has(core, "swanstation") || has(core, "duckstation"); }
    static boolean is3ds(String core)     { return has(core, "azahar") || has(core, "citra"); }
    static boolean isSaturn(String core)  { return has(core, "yabause"); }

    /** App-level setting sent from Flutter's core settings (never forwarded to the core itself). */
    static final String RENDERER_KEY = "xemu_renderer";

    /** True when the user picked the hardware OpenGL ES renderer instead of the default Software one. */
    static boolean wantsGles(Map<String, String> user) {
        String v = user == null ? null : user.get(RENDERER_KEY);
        return v != null && v.toLowerCase(Locale.ROOT).contains("opengl");
    }

    static List<Variable> initial(String core, boolean vulkan, String layout, Map<String, String> user) {
        return initial(core, vulkan, layout, user, false);
    }

    // ───────────────────── Safety for user-changed options ─────────────────────

    /** Options a core only reads at startup / game load: never changed on a running core. */
    private static final Pattern RESTART_ONLY = Pattern.compile(
        "(region|bios|firmware|language|jit|cpu_core|cpucore|cpu_mode|dynarec|drc|recompiler|"
        + "execution_mode|renderer|backend|graphics_api|threaded|usethread|boot|sdcard|sd_card|"
        + "virtual_sd|memcard|memory_card|multitap|console_mode|hwmode|gb_model|colorization|"
        + "is_new_3ds|fast_memory|io_timing|button_preference|inflight|plugin|fbemulation|"
        + "screensize|add_?on|cart|numthreads|sgb_borders|custom_textures|preload_textures|pak\\d|"
        + "video_scale|gfx_colors)");

    static boolean requiresRestart(String key) {
        if (key == null) return true;
        String k = key.toLowerCase(Locale.ROOT);
        if (k.equals("mupen64plus-aspect") || k.equals("xemu_renderer")) return true;
        return RESTART_ONLY.matcher(k).find();
    }

    /** Leading integer of values such as "3", "3x" or "3x (for 720p)"; 0 if there is none. */
    private static int leadingInt(String v) {
        int i = 0;
        while (i < v.length() && Character.isDigit(v.charAt(i))) i++;
        if (i == 0) return 0;
        if (i > 6) return Integer.MAX_VALUE; // absurdly large: let the caller cap it
        return Integer.parseInt(v.substring(0, i));
    }

    private static int width(String v) {
        try { return Integer.parseInt(v.split("x")[0].trim()); } catch (Exception e) { return 0; }
    }

    /**
     * Returns the value that is safe to send to the core, or null to drop the option. Empty values
     * and values that exhaust GPU memory / crash on phones are replaced or dropped. Applied both
     * at launch (saved options) and for live changes, so a bad saved value can never crash the
     * game on every start.
     */
    static String sanitize(String key, String value) {
        if (key == null || value == null) return null;
        String v = value.trim();
        if (v.isEmpty()) return null;
        String k = key.toLowerCase(Locale.ROOT);
        switch (k) {
            case "ppsspp_skip_buffer_effects":
            case "ppsspp_auto_frameskip":
                return "disabled"; // crash PPSSPP on LibretroDroid's GL surface
            case "ppsspp_texture_scaling_level":
                return v.equalsIgnoreCase("5x") ? "4x" : v;
            case "ppsspp_internal_resolution":
                return width(v) > 2880 ? "2880x1632" : v;
            case "mupen64plus-43screensize":
                return width(v) > 1920 ? "1920x1440" : v;
            case "mupen64plus-169screensize":
                return width(v) > 1920 ? "1920x1080" : v;
            case "swanstation_gpu_resolutionscale":
            case "duckstation_gpu_resolutionscale":
                if (leadingInt(v) > 8) return v.contains("x") ? "8x" : "8";
                return v;
            case "azahar_graphics_api":
            case "citra_graphics_api":
                return "OpenGL"; // LibretroDroid has no Vulkan
            case "citra_resolution_factor":
            case "azahar_resolution_factor":
                return width(v) > 6 ? "6x" : v;
            default:
                return v;
        }
    }

    /**
     * Adds a core option under both the underscore spelling (what the libretro core actually
     * exposes, e.g. "swanstation_GPU_Renderer") and the dotted spelling (internal ini name,
     * e.g. "swanstation_GPU.Renderer"). Unknown keys are ignored by the core, so sending both is safe.
     */
    private static void addBoth(List<Variable> out, String prefix, String section, String name, String value) {
        out.add(v(prefix + "_" + section + "_" + name, value));
        out.add(v(prefix + "_" + section + "." + name, value));
    }

    /**
     * Variables applied when the core starts. Order matters (later wins):
     * core defaults -> user overrides -> forced GL backends -> screen layout -> forced US region -> BIOS boot override.
     */
    static List<Variable> initial(String core, boolean vulkan, String layout,
                                  Map<String, String> user, boolean bootBios) {
        return initial(core, vulkan, layout, user, bootBios, null);
    }

    /** [regionForced]: region options (cached from the core, forced to US) applied only at launch. */
    static List<Variable> initial(String core, boolean vulkan, String layout,
                                  Map<String, String> user, boolean bootBios,
                                  Map<String, String> regionForced) {
        List<Variable> out = new ArrayList<>();
        if (isMelonDs(core)) {
            // Touch screen only works when the core is in "Touch" pointer mode.
            out.add(v("melonds_touch_mode", "Touch"));
        }
        // Saturn: frameskip is OFF by default (skipped frames look like stutter). Sent BEFORE the
        // user's options, so a user who turns it on in the core settings still wins.
        if (isSaturn(core)) {
            out.add(v("yabause_frameskip", "disabled"));
        }

        // User tweaks (saved per core by the Flutter side). Region keys are never user-controlled.
        if (user != null) {
            for (Map.Entry<String, String> e : user.entrySet()) {
                if (e.getKey() == null || e.getValue() == null || isRegionKey(e.getKey())
                    || RENDERER_KEY.equals(e.getKey())) continue;
                String safe = sanitize(e.getKey(), e.getValue());
                if (safe == null) continue;
                out.add(v(e.getKey(), safe));
            }
        }

        // LibretroDroid only provides OpenGL ES; a Vulkan backend asserts/crashes, so always force GL.
        // (3DS used to be set BEFORE the user options, so a saved "Vulkan" value crashed it.)
        if (is3ds(core)) {
            // Keys may use either prefix; unknown keys are ignored by the core.
            out.add(v("azahar_graphics_api", "OpenGL"));
            out.add(v("citra_graphics_api", "OpenGL"));
        }
        if (has(core, "ppsspp")) {
            out.add(v("ppsspp_backend", "opengl"));
            // Non-buffered rendering and auto frameskip crash on LibretroDroid's GL surface.
            out.add(v("ppsspp_skip_buffer_effects", "disabled"));
            out.add(v("ppsspp_auto_frameskip", "disabled"));
        }

        // PS1 (SwanStation / DuckStation):
        //  - Vulkan is unsupported by LibretroDroid ("Failed to get HW render interface").
        //  - The OpenGL renderer fails on some builds ("Invalid #version" -> black screen with sound).
        // So Software is the default. The user can opt in to OpenGL (ES) in the core settings; Vulkan
        // and "Auto" are never used because Auto could pick Vulkan. Forced AFTER user options so it wins.
        String ps1Renderer = wantsGles(user) ? "OpenGL" : "Software";
        if (has(core, "swanstation")) addBoth(out, "swanstation", "GPU", "Renderer", ps1Renderer);
        if (has(core, "duckstation")) addBoth(out, "duckstation", "GPU", "Renderer", ps1Renderer);

        out.addAll(screenLayout(core, layout));
        // Region is left on each core's own auto-detect: forcing US made PAL/JP games run at the
        // wrong speed. [regionForced] (sent by Dart) is intentionally no longer applied.
        out.addAll(usRegion(core));

        // When booting NDS BIOS/Firmware directly, never skip straight to a cartridge
        if (isMelonDs(core) && bootBios) {
            out.add(v("melonds_boot_directly", "disabled"));
            out.add(v("melonds_use_fw_settings", "enabled"));
        }
        // Booting the PS1 BIOS shell: fast boot would skip straight past it.
        if (isPs1(core) && bootBios) {
            addBoth(out, "swanstation", "BIOS", "PatchFastBoot", "false");
            addBoth(out, "duckstation", "BIOS", "PatchFastBoot", "false");
        }

        return out;
    }

    static boolean isRegionKey(String key) {
        if (key == null) return false;
        String k = key.toLowerCase(Locale.ROOT);
        // Sega cores (Genesis / SMS / GG) keep their own region auto-detect.
        if (k.startsWith("blastem_") || k.startsWith("gearsystem_")) return false;
        return k.contains("region");
    }

    /** Known region options, set to Auto (detect from the game) on every start. */
    static List<Variable> usRegion(String core) {
        List<Variable> out = new ArrayList<>();
        if (is3ds(core)) {
            out.add(v("azahar_region_value", "Auto"));
            out.add(v("citra_region_value", "Auto"));
        }
        if (has(core, "swanstation")) addBoth(out, "swanstation", "Console", "Region", "Auto");
        if (has(core, "duckstation")) addBoth(out, "duckstation", "Console", "Region", "Auto");
        return out;
    }

    /** Maps our neutral layout ids to the values each core understands. */
    static List<Variable> screenLayout(String core, String layout) {
        List<Variable> out = new ArrayList<>();
        if (layout == null) return out;

        if (isMelonDs(core)) {
            String val;
            switch (layout) {
                case "bottom_top":    val = "Bottom/Top"; break;
                case "left_right":    val = "Left/Right"; break;
                case "right_left":    val = "Right/Left"; break;
                case "top_only":      val = "Top Only"; break;
                case "bottom_only":   val = "Bottom Only"; break;
                case "hybrid_top":    val = "Hybrid Top"; break;
                case "hybrid_bottom": val = "Hybrid Bottom"; break;
                default:              val = "Top/Bottom";
            }
            out.add(v("melonds_screen_layout", val));
            // Newer "melonDS DS" builds use numbered layout slots with lowercase ids instead.
            // Unknown keys are ignored by whichever core is loaded, so sending both is safe.
            String ds;
            switch (layout) {
                case "bottom_top":    ds = "bottom-top"; break;
                case "left_right":    ds = "left-right"; break;
                case "right_left":    ds = "right-left"; break;
                case "top_only":      ds = "top"; break;
                case "bottom_only":   ds = "bottom"; break;
                case "hybrid_top":    ds = "hybrid-top"; break;
                case "hybrid_bottom": ds = "hybrid-bottom"; break;
                default:              ds = "top-bottom";
            }
            out.add(v("melonds_number_of_screen_layouts", "1"));
            out.add(v("melonds_screen_layout1", ds));
        } else if (is3ds(core)) {
            // The Azahar libretro core keeps the legacy "citra_" option keys (see docs.libretro.com/library/azahar),
            // with these exact values. "azahar_" keys do not exist, so the layout was silently ignored before.
            String val;
            String swap = "Top Screen";
            switch (layout) {
                case "top_only":      val = "Single Screen Only"; swap = "Top Screen"; break;
                case "bottom_only":   val = "Single Screen Only"; swap = "Bottom Screen"; break;
                case "hybrid_top":    val = "Large Screen, Small Screen"; swap = "Top Screen"; break;
                case "hybrid_bottom": val = "Large Screen, Small Screen"; swap = "Bottom Screen"; break;
                case "left_right":    val = "Side by Side"; break;
                default:              val = "Default Top-Bottom";
            }
            out.add(v("citra_layout_option", val));
            out.add(v("citra_swap_screen", swap));
        }
        return out;
    }
}