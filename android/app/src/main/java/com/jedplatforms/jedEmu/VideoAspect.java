package com.jedplatforms.jedEmu;

import android.util.Log;

import java.lang.reflect.Field;
import java.lang.reflect.Method;

/** Reads the core's current picture shape (width / height) from GLRetroView, or null if unknown. */
final class VideoAspect {
    private VideoAspect() {}

    private static final String TAG = "tonEmuVid";
    private static final String[] GETTERS = { "getAspectRatio", "getVideoAspectRatio", "getViewportAspectRatio" };
    private static final String[] FIELDS = { "aspectRatio", "videoAspectRatio", "viewportAspectRatio" };
    private static boolean loggedMiss = false;

    /** Double (the Flutter codec cannot carry a Float) or null. */
    static Double read(Object retroView) {
        if (retroView == null) return null;
        for (String g : GETTERS) {
            try {
                Method m = retroView.getClass().getMethod(g);
                Double d = asAspect(m.invoke(retroView));
                if (d != null) return d;
            } catch (Throwable ignored) { }
        }
        for (Class<?> c = retroView.getClass(); c != null; c = c.getSuperclass()) {
            for (String f : FIELDS) {
                try {
                    Field fld = c.getDeclaredField(f);
                    fld.setAccessible(true);
                    Double d = asAspect(fld.get(retroView));
                    if (d != null) return d;
                } catch (Throwable ignored) { }
            }
        }
        if (!loggedMiss) {
            loggedMiss = true;
            Log.w(TAG, "no aspect ratio accessor found on " + retroView.getClass().getName());
        }
        return null;
    }

    private static Double asAspect(Object o) {
        if (!(o instanceof Number)) return null;
        double d = ((Number) o).doubleValue();
        return (Double.isNaN(d) || Double.isInfinite(d) || d <= 0) ? null : d;
    }
}