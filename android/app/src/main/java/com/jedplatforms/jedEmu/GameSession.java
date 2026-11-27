package com.jedplatforms.jedEmu;

import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;

import androidx.annotation.NonNull;
import androidx.lifecycle.Lifecycle;
import androidx.lifecycle.LifecycleEventObserver;
import androidx.lifecycle.LifecycleOwner;
import androidx.lifecycle.LifecycleRegistry;

import com.swordfish.libretrodroid.GLRetroView;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.TimeUnit;

import kotlin.Unit;
import kotlin.coroutines.Continuation;
import kotlin.coroutines.CoroutineContext;
import kotlinx.coroutines.Job;
import kotlinx.coroutines.JobKt;
import kotlinx.coroutines.flow.Flow;
import kotlinx.coroutines.flow.FlowCollector;

/**
 * Owns ONE running core. It has its own Lifecycle that mirrors the Activity while the game is alive,
 * and is driven to DESTROYED when the game ends, so GLRetroView really unloads the core
 * (this is what fixes the crash when relaunching PSP and other cores).
 * Also persists battery saves (SRAM), which LibretroDroid does NOT write by itself.
 */
public class GameSession implements LifecycleOwner {
    /**
     * The core is "ready" for native calls once it has rendered its first frame (see watchFirstFrame).
     * This timer is only a last resort in case that event never arrives (API mismatch), and is
     * deliberately long: a native call on a half-loaded core is a SIGSEGV that cannot be caught.
     */
    private static final long READY_FALLBACK_MS = 12_000;
    /** Used when the event Flow WAS hooked but no frame arrived: a big PSP/3DS game can load for a long time. */
    private static final long READY_FALLBACK_HOOKED_MS = 60_000;
    private static final long SRAM_FLUSH_INTERVAL_MS = 30_000;
    /**
     * Longest a stop/destroy waits for the save to reach flash. Pause never waits (see hostObserver).
     * Kept well under Android's 5 s input-dispatch ANR limit.
     */
    private static final long SYNC_SAVE_TIMEOUT_MS = 2000;
    /** The previous battery save is kept as "<name>.bak" at most this often (not on every 30 s flush). */
    private static final long BACKUP_INTERVAL_MS = 5 * 60_000;

    final GLRetroView retroView;
    final String coreName;

    private final Lifecycle hostLifecycle;
    private final LifecycleRegistry registry;
    private final LifecycleEventObserver hostObserver;
    private final File sramFile;
    private final long createdAt = SystemClock.elapsedRealtime();
    private final Handler handler = new Handler(Looper.getMainLooper());
    private final Job readyJob;
    private volatile boolean firstFrame = false;
    private boolean userPaused = false;
    private boolean destroyed = false;
    private volatile long lastBackupAt = 0;
    // Real play time: only counts while the core is actually running (not paused, not in the background).
    private volatile long playAccumMs = 0;
    private volatile long playStartedAt = -1;
    private volatile byte[] lastSram; // last save that really reached the disk
    private volatile byte[] queuedSram; // last save handed to SAVE_IO (may still be writing)
    private volatile Future<?> lastWrite; // newest queued write, so stop/destroy can wait for it
    // ALL save writes go through this single thread, so they can never overlap or arrive out of
    // order (an old periodic write can no longer overwrite the newer one made on pause/quit).
    private static final ExecutorService SAVE_IO = Executors.newSingleThreadExecutor();

    private final Runnable flushTask = new Runnable() {
        @Override public void run() {
            flushSave(true);
            if (!destroyed) handler.postDelayed(this, SRAM_FLUSH_INTERVAL_MS);
        }
    };

    GameSession(GLRetroView retroView, String coreName, Lifecycle host, File sramFile) {
        this.retroView = retroView;
        this.coreName = coreName;
        this.hostLifecycle = host;
        this.sramFile = sramFile;
        this.registry = new LifecycleRegistry(this);
        this.registry.addObserver(retroView);

        // Real "core is loaded" signal: first rendered frame (null if the API doesn't match;
        // the timed fallback in isReady() then covers it).
        this.readyJob = watchFirstFrame(retroView);

        this.hostObserver = (source, event) -> {
            if (event == Lifecycle.Event.ON_DESTROY) {
                destroy(); // never keep touching a core after its Activity is gone
                return;
            }
            // Pause only QUEUES the write (the UI thread never waits there); stop waits, bounded, so
            // the save is on disk before the process can be killed in the background.
            if (event == Lifecycle.Event.ON_PAUSE) flushSave(true);
            else if (event == Lifecycle.Event.ON_STOP) flushSave(false);
            syncState();
        };
        host.addObserver(hostObserver);
        handler.postDelayed(flushTask, SRAM_FLUSH_INTERVAL_MS);
    }

    /**
     * Collects LibretroDroid's event Flow from plain Java and sets [firstFrame] when the core
     * reports FrameRendered. The Flow getter is looked up reflectively and the event is matched by
     * class name, so a different LibretroDroid version cannot break compilation. Returns the Job
     * to cancel on destroy, or null if the Flow could not be hooked.
     */
    @SuppressWarnings("unchecked")
    private Job watchFirstFrame(GLRetroView view) {
        try {
            final Job job = JobKt.Job(null);
            Flow<Object> flow = (Flow<Object>) view.getClass().getMethod("getGLRetroEvents").invoke(view);
            flow.collect(new FlowCollector<Object>() {
                @Override public Object emit(Object value, @NonNull Continuation<? super Unit> c) {
                    if (value != null && "FrameRendered".equals(value.getClass().getSimpleName())) {
                        firstFrame = true;
                    }
                    return Unit.INSTANCE;
                }
            }, new Continuation<Unit>() {
                @NonNull @Override public CoroutineContext getContext() { return job; }
                @Override public void resumeWith(@NonNull Object result) { }
            });
            return job;
        } catch (Throwable t) {
            return null;
        }
    }

    @NonNull
    @Override
    public Lifecycle getLifecycle() { return registry; }

    boolean isAlive() { return !destroyed; }

    /** True once the core has rendered a frame (or, failing that, after a long fallback delay). */
    boolean isReady() {
        if (destroyed) return false;
        if (firstFrame) return true;
        // The short timer is ONLY for a LibretroDroid whose event Flow could not be hooked. With a
        // working Flow, a slow-loading core must not be touched natively after 12 s (SIGSEGV).
        long limit = readyJob != null ? READY_FALLBACK_HOOKED_MS : READY_FALLBACK_MS;
        return SystemClock.elapsedRealtime() - createdAt > limit;
    }

    void setUserPaused(boolean paused) {
        if (destroyed) return;
        userPaused = paused;
        syncState();
    }

    private void syncState() {
        if (destroyed) return;
        Lifecycle.State target = hostLifecycle.getCurrentState();
        if (userPaused && target.isAtLeast(Lifecycle.State.RESUMED)) {
            target = Lifecycle.State.STARTED; // STARTED == paused for GLRetroView
        }
        registry.setCurrentState(target);
        trackPlayTime(target.isAtLeast(Lifecycle.State.RESUMED));
    }

    private void trackPlayTime(boolean running) {
        long now = SystemClock.elapsedRealtime();
        if (running && playStartedAt < 0) {
            playStartedAt = now;
        } else if (!running && playStartedAt >= 0) {
            playAccumMs += now - playStartedAt;
            playStartedAt = -1;
        }
    }

    /** Milliseconds this game has really been running (menus, pauses and background time excluded). */
    long playTimeMs() {
        long now = SystemClock.elapsedRealtime();
        return playAccumMs + (playStartedAt >= 0 ? now - playStartedAt : 0);
    }

    /** True while the user has the game paused (in-game menu open, etc.). */
    boolean isUserPaused() { return userPaused; }

    void flushSave() { flushSave(false); }

    /**
     * [async]: don't wait for the write (periodic flush and pause). Stop/destroy wait (bounded) so
     * the save is on disk before the process can be killed. A sync call also waits for a write that
     * an earlier async call queued, even when nothing changed since.
     */
    private void flushSave(boolean async) {
        if (!isReady() || sramFile == null) return;
        final byte[] sram;
        try {
            sram = retroView.serializeSRAM();
        } catch (Throwable t) {
            return;
        }
        // Skip identical saves: already on disk (lastSram) or already queued (queuedSram), so a
        // pause followed by a stop does not write the same bytes twice.
        if (sram != null && sram.length > 0
            && !java.util.Arrays.equals(sram, lastSram)
            && !java.util.Arrays.equals(sram, queuedSram)) {
            final File target = sramFile;
            try {
                queuedSram = sram;
                lastWrite = SAVE_IO.submit(() -> {
                    try {
                        maybeBackup(target);
                        writeAtomically(target, sram);
                        lastSram = sram;
                    } catch (Throwable ignored) {
                        queuedSram = null; // failed: let the next flush try this data again
                    }
                });
            } catch (RejectedExecutionException e) {
                queuedSram = null;
                return;
            }
        }
        if (async) return;
        final Future<?> pending = lastWrite;
        if (pending == null || pending.isDone()) return;
        try {
            pending.get(SYNC_SAVE_TIMEOUT_MS, TimeUnit.MILLISECONDS);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        } catch (Throwable ignored) { }
    }

    void destroy() {
        if (destroyed) return;
        flushSave();
        trackPlayTime(false);
        destroyed = true;
        handler.removeCallbacks(flushTask);
        if (readyJob != null) readyJob.cancel(null);
        hostLifecycle.removeObserver(hostObserver);
        try {
            registry.setCurrentState(Lifecycle.State.DESTROYED); // -> GLRetroView.onPause/onDestroy -> core unloaded
        } catch (Throwable ignored) { }
    }

    /**
     * Keeps the save that is about to be replaced as "<name>.bak", at most every few minutes, so a
     * core that wrote a bad (empty / corrupt) battery save can still be rolled back. Best effort.
     */
    private void maybeBackup(File target) {
        try {
            long now = SystemClock.elapsedRealtime();
            if (!target.exists() || target.length() == 0) return;
            if (lastBackupAt != 0 && now - lastBackupAt < BACKUP_INTERVAL_MS) return;
            FileUtil.copy(target, backupOf(target));
            lastBackupAt = now;
        } catch (Throwable ignored) { }
    }

    static File backupOf(File sram) { return new File(sram.getPath() + ".bak"); }

    /** True if a previous battery save is available to roll back to. */
    static boolean hasBackup(File sram) {
        File b = backupOf(sram);
        return b.exists() && b.length() > 0;
    }

    /** Rolls the battery save back to its backup (call BEFORE the game starts). Returns true on success. */
    static boolean restoreBackup(File sram) {
        try {
            if (!hasBackup(sram)) return false;
            FileUtil.copy(backupOf(sram), sram);
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    /**
     * Writes [data] to a temp file, fsyncs it, then renames it over [target] in one step. The old
     * file is never deleted first, so a failure at any point leaves the previous save intact.
     * Uses File.renameTo (rename(2)) instead of java.nio.file, so it works below API 26 too.
     */
    static void writeAtomically(File target, byte[] data) throws IOException {
        File parent = target.getParentFile();
        if (parent != null) parent.mkdirs();
        File tmp = new File(target.getPath() + ".tmp");
        try {
            try (FileOutputStream fos = new FileOutputStream(tmp)) {
                fos.write(data);
                fos.getFD().sync();
            }
            FileUtil.replace(tmp, target);
        } catch (IOException | RuntimeException e) {
            tmp.delete();
            throw e;
        }
    }
}