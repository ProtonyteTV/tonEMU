package com.jedplatforms.jedEmu;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.system.Os;

import java.util.TimeZone;

/**
 * Libretro cores read the clock through the C library (localtime), which only knows the phone's
 * timezone if the TZ environment variable of THIS process is set. Without it the in-game RTC
 * (Pokemon clocks, Animal Crossing, DS/3DS clock...) runs on UTC. This copies the phone's current
 * timezone into TZ (an Olson id such as "Asia/Manila", so daylight saving works too) before a core
 * loads, and again whenever the phone's timezone changes.
 */
final class TimeZoneSync {
    private TimeZoneSync() {}

    private static BroadcastReceiver receiver;
    /** Number of Activities that called register() and have not unregistered yet. */
    private static int users = 0;

    /** Sets TZ to the phone's current timezone. Safe to call as often as needed. */
    static void apply() {
        try {
            TimeZone.setDefault(null); // drop the cached default so the system value is re-read
            String id = TimeZone.getDefault().getID();
            if (id == null || id.isEmpty()) id = "UTC";
            // Custom zones come back as "GMT+08:00". In a POSIX TZ value that sign is inverted
            // (it would mean UTC-8), so build the POSIX form from the real offset instead.
            if (id.startsWith("GMT") && id.length() > 3) {
                int min = TimeZone.getDefault().getRawOffset() / 60000;
                if (min == 0) {
                    id = "UTC";
                } else {
                    int a = Math.abs(min);
                    id = String.format(java.util.Locale.ROOT, "UTC%s%02d:%02d", min > 0 ? "-" : "+", a / 60, a % 60);
                }
            }
            Os.setenv("TZ", id, true);
        } catch (Throwable ignored) { }
    }

    /** The zone id the cores currently see (for showing "In-game clock: Asia/Manila" in settings). */
    static String currentId() {
        try {
            String tz = Os.getenv("TZ");
            if (tz != null && !tz.isEmpty()) return tz;
        } catch (Throwable ignored) { }
        return TimeZone.getDefault().getID();
    }

    /** Keeps TZ correct while the app is open (travel, automatic timezone, manual change). */
    static synchronized void register(Context context) {
        apply();
        users++;
        if (receiver != null) return;
        BroadcastReceiver r = new BroadcastReceiver() {
            @Override public void onReceive(Context c, Intent i) { apply(); }
        };
        try {
            IntentFilter f = new IntentFilter(Intent.ACTION_TIMEZONE_CHANGED);
            androidx.core.content.ContextCompat.registerReceiver(context.getApplicationContext(), r, f,
                androidx.core.content.ContextCompat.RECEIVER_NOT_EXPORTED);
            receiver = r;
        } catch (Throwable t) {
            receiver = null;
        }
    }

    /**
     * Counted, so an old Activity being destroyed after a new one registered (relaunch) does not
     * remove the receiver the new one still needs.
     */
    static synchronized void unregister(Context context) {
        if (users > 0) users--;
        if (users > 0 || receiver == null) return;
        try { context.getApplicationContext().unregisterReceiver(receiver); } catch (Throwable ignored) { }
        receiver = null;
    }
}