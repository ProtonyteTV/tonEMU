package com.jedplatforms.jedEmu;

import android.util.Log;

import java.lang.reflect.Method;
import java.util.HashMap;
import java.util.Map;

/**
 * Sega Saturn (Yabause) specifics.
 *
 * Yabause only attaches a pad to a Saturn port when the frontend selects a device for that port
 * (retro_set_controller_port_device). LibretroDroid never does that unless it is told to, so the
 * core boots with NO controller plugged in: the game runs but every button is ignored.
 *
 * Done by reflection because the exact LibretroDroid API differs between versions; every failure
 * is logged (tag tonEmuSat) and never thrown.
 */
final class SaturnSupport {
    private SaturnSupport() {}

    static final String TAG = "tonEmuSat";

    /** RETRO_DEVICE_JOYPAD = "Saturn Pad" in the Yabause core. */
    private static final int DEVICE_JOYPAD = 1;
    private static final int PORTS = 2; // Saturn has two control ports

    /**
     * Asks LibretroDroid to select the Saturn Pad on both ports as soon as the core loads.
     * Call on GLRetroViewData BEFORE creating the GLRetroView. Returns true if it was accepted.
     */
    static boolean applyLaunchConfig(Object glRetroViewData) {
        try {
            Map<Integer, Integer> cfg = new HashMap<>();
            for (int port = 0; port < PORTS; port++) cfg.put(port, DEVICE_JOYPAD);
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

    /**
     * Safety net once the core is running: selects the Saturn Pad on both ports again. Harmless if
     * the launch config already did it.
     */
    static void forceJoypad(Object retroView) {
        try {
            Method set = retroView.getClass().getMethod("setControllerType", int.class, int.class);
            for (int port = 0; port < PORTS; port++) set.invoke(retroView, port, DEVICE_JOYPAD);
            Log.i(TAG, "setControllerType(0.." + (PORTS - 1) + ", JOYPAD) done");
        } catch (Throwable t) {
            Log.w(TAG, "setControllerType unavailable/failed: " + t);
        }
    }
}