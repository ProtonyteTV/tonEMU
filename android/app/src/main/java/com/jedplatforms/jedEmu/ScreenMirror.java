package com.jedplatforms.jedEmu;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.SurfaceTexture;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.os.SystemClock;
import android.view.PixelCopy;
import android.view.Surface;

import com.swordfish.libretrodroid.GLRetroView;

import io.flutter.view.TextureRegistry;

/**
 * Free-form screens workaround. The core draws BOTH screens into one GL surface, which Flutter
 * cannot split. So we keep that surface alive (hidden behind a black cover on the Flutter side),
 * copy its frames with PixelCopy into a Flutter Texture, and Flutter shows that same texture
 * twice - each copy cropped to one screen and placed wherever the user wants.
 */
final class ScreenMirror {
    /** Default ~60 fps. Requesting the next copy 4 ms after the last one just burned GPU and battery. */
    private static final int DEFAULT_FPS = 60;

    private final TextureRegistry.SurfaceTextureEntry entry;
    private final SurfaceTexture texture;
    private final Surface surface;
    private final GLRetroView source;
    private final HandlerThread thread = new HandlerThread("screen-mirror");
    private final Handler handler;
    private final Bitmap bitmap;
    private volatile boolean running = true;
    private volatile long frameIntervalMs = 1000 / DEFAULT_FPS;
    // Measured copy rate, so the app can show it or lower the target on weak phones.
    private int framesInWindow = 0;
    private long windowStart = SystemClock.uptimeMillis();
    private volatile int measuredFps = 0;

    final int width, height;

    ScreenMirror(TextureRegistry registry, GLRetroView source, int width, int height) {
        this.source = source;
        this.width = width;
        this.height = height;
        entry = registry.createSurfaceTexture();
        texture = entry.surfaceTexture();
        texture.setDefaultBufferSize(width, height);
        surface = new Surface(texture);
        bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        thread.start();
        handler = new Handler(thread.getLooper());
        handler.post(this::tick);
    }

    long textureId() { return entry.id(); }

    /** Lowers (or restores) the mirror rate, 15..60 fps. Saves battery on phones that cannot keep up. */
    void setTargetFps(int fps) {
        int f = Math.max(15, Math.min(60, fps));
        frameIntervalMs = 1000L / f;
    }

    /** Frames per second the mirror really achieved over the last second (0 until measured). */
    int measuredFps() { return measuredFps; }

    private void countFrame() {
        framesInWindow++;
        long now = SystemClock.uptimeMillis();
        long span = now - windowStart;
        if (span >= 1000) {
            measuredFps = (int) Math.round(framesInWindow * 1000.0 / span);
            framesInWindow = 0;
            windowStart = now;
        }
    }

    private void tick() {
        if (!running) return;
        if (source.getWidth() <= 0 || source.getHeight() <= 0 || !source.isAttachedToWindow()) {
            handler.postDelayed(this::tick, 50);
            return;
        }
        final long started = SystemClock.uptimeMillis();
        try {
            PixelCopy.request(source, bitmap, code -> {
                if (!running) return;
                if (code == PixelCopy.SUCCESS) {
                    draw();
                    countFrame();
                    // Pace from the START of the copy so the mirror really runs at ~60 fps.
                    long wait = frameIntervalMs - (SystemClock.uptimeMillis() - started);
                    handler.postDelayed(this::tick, Math.max(0L, wait));
                } else {
                    handler.postDelayed(this::tick, 50); // don't hammer a source that can't be copied
                }
            }, handler);
        } catch (Throwable t) {
            handler.postDelayed(this::tick, 100);
        }
    }

    private void draw() {
        Canvas c = null;
        try {
            c = surface.lockHardwareCanvas();
            c.drawBitmap(bitmap, 0, 0, null);
        } catch (Throwable ignored) {
        } finally {
            if (c != null) {
                try { surface.unlockCanvasAndPost(c); } catch (Throwable ignored) { }
            }
        }
    }

    void stop() {
        if (!running) return;
        running = false;
        handler.removeCallbacksAndMessages(null);
        // Release on the mirror thread itself: it runs after any draw() already in progress, so
        // the Surface can never be released while it is being drawn to.
        handler.post(() -> {
            try { surface.release(); } catch (Throwable ignored) { }
            // FlutterJNI.unregisterTexture is @UiThread: release the entry on the main thread.
            new Handler(Looper.getMainLooper()).post(() -> {
                try { entry.release(); } catch (Throwable ignored) { }
            });
        });
        thread.quitSafely();
    }
}