package com.jedplatforms.jedEmu;

import android.util.Log;

import java.lang.reflect.Method;
import java.util.HashMap;
import java.util.Map;

/**
 * PlayStation 1 (SwanStation / DuckStation) controller type.
 *
 * The core boots with a plain Digital Controller on each port, so analog sticks, L3 / R3 and
 * DualShock-only games get nothing. Selecting RETRO_DEVICE_ANALOG ("Analog Controller / DualShock")
 * on the pad ports fixes that. A DualShock still plays digital-only games normally; games that
 * support analog switch it on themselves, like on a real console.
 *
 * Same approach as SaturnSupport: reflection (the LibretroDroid API differs between versions), every
 * failure is logged (tag tonEmuPs1) and never thrown.
 */
final class Ps1Support {
    private Ps1Support() {}

    static final String TAG = "tonEmuPs1";

    /**
     * SwanStation's "DualShock" device = RETRO_DEVICE_SUBCLASS(RETRO_DEVICE_ANALOG, 0) = (1 << 8) | 5 = 261
     * (the same value RetroArch stores as input_libretro_device_pN). The plain base id 5 is NOT
     * recognised by the core and leaves the port with no working controller.
     */
    private static final int DEVICE_ANALOG = 261;
    private static final int PORTS = 2;

    /** Call on GLRetroViewData BEFORE creating the GLRetroView. Returns true if accepted. */
    static boolean applyLaunchConfig(Object glRetroViewData) {
        try {
            Map<Integer, Integer> cfg = new HashMap<>();
            for (int port = 0; port < PORTS; port++) cfg.put(port, DEVICE_ANALOG);
            for (Method m : glRetroViewData.getClass().getMethods()) {
                if (!m.getName().equals("setControllerConfigs")) continue;
                if (m.getParameterTypes().length != 1
                    || !m.getParameterTypes()[0].isAssignableFrom(HashMap.class)) continue;
                m.invoke(glRetroViewData, cfg);
                Log.i(TAG, "launch controller config applied: " + cfg);
                return true;
            }
            Log.w(TAG, "setControllerConfigs not found on GLRetroViewData");
        } catch (Throwable t) {
            Log.w(TAG, "launch controller config failed: " + t);
        }
        return false;
    }

    /** Safety net once the core is running (harmless if the launch config already did it). */
    static void forceAnalog(Object retroView) {
        try {
            Method set = retroView.getClass().getMethod("setControllerType", int.class, int.class);
            for (int port = 0; port < PORTS; port++) set.invoke(retroView, port, DEVICE_ANALOG);
            Log.i(TAG, "setControllerType(0.." + (PORTS - 1) + ", ANALOG) done");
        } catch (Throwable t) {
            Log.w(TAG, "setControllerType unavailable/failed: " + t);
        }
    }
}