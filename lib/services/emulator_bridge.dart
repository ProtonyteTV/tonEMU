import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'core_settings.dart';

class EmulatorBridge {
  static const MethodChannel _channel = MethodChannel(
    'com.jedplatforms.jedEmu/core',
  );

  // Android KeyEvent keycodes mapped to Libretro RetroPad buttons
  static const int keyUp = 19; // KEYCODE_DPAD_UP
  static const int keyDown = 20; // KEYCODE_DPAD_DOWN
  static const int keyLeft = 21; // KEYCODE_DPAD_LEFT
  static const int keyRight = 22; // KEYCODE_DPAD_RIGHT
  static const int keyA = 96; // KEYCODE_BUTTON_A
  static const int keyB = 97; // KEYCODE_BUTTON_B
  static const int keyX = 99; // KEYCODE_BUTTON_X
  static const int keyY = 100; // KEYCODE_BUTTON_Y
  static const int keyL1 = 102; // KEYCODE_BUTTON_L1
  static const int keyR1 = 103; // KEYCODE_BUTTON_R1
  static const int keyL2 = 104; // KEYCODE_BUTTON_L2
  static const int keyR2 = 105; // KEYCODE_BUTTON_R2
  static const int keyL3 = 106; // KEYCODE_BUTTON_THUMBL
  static const int keyR3 = 107; // KEYCODE_BUTTON_THUMBR
  static const int keyStart = 108; // KEYCODE_BUTTON_START
  static const int keySelect = 109; // KEYCODE_BUTTON_SELECT

  // LibretroDroid motion sources
  static const int analogDpad = 0;
  static const int analogLeft = 1;
  static const int analogRight = 2;

  // ───────── Native -> Dart events (gamepad hotkeys, controller plug/unplug) ─────────

  static final StreamController<String> _hotkeys =
      StreamController<String>.broadcast();

  /// "menu", "quickSave", "quickLoad", "fastForward", "nextSlot", "screenshot", "mute",
  /// "audioNoisy" (headphones unplugged)
  static Stream<String> get hotkeys => _hotkeys.stream;

  /// True while a physical gamepad is connected.
  static final ValueNotifier<bool> gamepadConnected = ValueNotifier<bool>(
    false,
  );

  static bool _handlerSet = false;

  static Map<String, String>? _deviceInfo;

  /// Opens [url] with the system (browser for http/https, mail app for mailto:). False if no
  /// app could handle it.
  static Future<bool> openUrl(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Phone model / CPU / GPU names (keys: model, cpu, cores, maxMhz, gpu). Cached; null if unavailable.
  static Future<Map<String, String>?> getDeviceInfo() async {
    if (_deviceInfo != null) return _deviceInfo;
    try {
      final r = await _channel.invokeMapMethod<String, String>('getDeviceInfo');
      if (r != null && r.isNotEmpty) _deviceInfo = r;
    } catch (_) {}
    return _deviceInfo;
  }

  /// Call once before a game starts. Safe to call repeatedly.
  static Future<void> init() async {
    if (!_handlerSet) {
      _handlerSet = true;
      _channel.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'hotkey':
            final name = call.arguments;
            if (name is String) _hotkeys.add(name);
          case 'gamepad':
            gamepadConnected.value = call.arguments == true;
        }
        return null;
      });
    }
    gamepadConnected.value = await hasGamepad();
  }

  static Future<bool> hasGamepad() => _callBool('hasGamepad');

  /// Tell native a Flutter menu/dialog is open: gamepad input then drives the UI instead of the game.
  static void setUiCaptured(bool captured) =>
      _fire('setUiCaptured', {'captured': captured});

  static void setInputConfig({
    required bool swapAB,
    required bool swapXY,
    required double deadzone,
    required bool comboHotkeys,
  }) => _fire('setInputConfig', {
    'swapAB': swapAB,
    'swapXY': swapXY,
    'deadzone': deadzone,
    'comboHotkeys': comboHotkeys,
  });

  /// name: "none" | "sharp" | "crt" | "lcd"
  static void setShader(String name) => _fire('setShader', {'shader': name});

  /// Calls a native method that answers true/false. Never throws and never hangs: a missing
  /// plugin, a platform error or no answer within [timeout] all return false. (A native call
  /// that never came back used to freeze whatever awaited it, such as a jedTimeMachine snapshot.)
  static Future<bool> _callBool(
    String method, {
    Map<String, dynamic>? args,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      return await _channel.invokeMethod<bool>(method, args).timeout(timeout) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  static void _fire(String method, [Map<String, dynamic>? args]) {
    unawaited(_channel.invokeMethod<void>(method, args).catchError((_) {}));
  }

  /// Returns the real core filename found in the app's native lib dir, or null if missing.
  static Future<String?> resolveCore(String coreLibName) async {
    try {
      return await _channel.invokeMethod<String>('resolveCore', {
        'core': coreLibName,
      });
    } on PlatformException {
      return null;
    }
  }

  /// True once the native core has had time to finish loading.
  static Future<bool> isReady() => _callBool('isReady');

  /// Width / height of the picture the core is producing right now, or null until the core has
  /// rendered a frame (or if this LibretroDroid build does not expose it).
  static Future<double?> getVideoAspect() async {
    try {
      final r = await _channel
          .invokeMethod<double>('getVideoAspect')
          .timeout(const Duration(seconds: 2));
      return (r != null && r.isFinite && r > 0) ? r : null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  static Future<bool> waitUntilReady({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final end = DateTime.now().add(timeout);
    // Poll quickly at first (most cores are ready within a second) and ease off to 400 ms, so a
    // fast core starts sooner and a slow one is not hammered with native calls.
    var wait = 100;
    while (DateTime.now().isBefore(end)) {
      if (await isReady()) return true;
      await Future<void>.delayed(Duration(milliseconds: wait));
      wait = (wait * 3 ~/ 2).clamp(100, 400);
    }
    return false;
  }

  /// True while the game is auto-paused (app left, notification shade pulled down...). On-screen
  /// buttons then do nothing to the game except A / B, which call [onGateRelease] to continue.
  static bool pauseGate = false;
  static void Function()? onGateRelease;

  /// Turns the pause gate on/off here and natively (physical gamepads are handled natively).
  static void setPauseGate(bool on) {
    pauseGate = on;
    _fire('setPauseGate', {'on': on});
  }

  static void sendButton(int keyCode, bool isDown, {int port = 0}) {
    if (pauseGate) {
      // Releases still go through, so a button held while pausing can never stay stuck down.
      if (isDown) {
        if (keyCode == keyA || keyCode == keyB) onGateRelease?.call();
        return;
      }
    }
    _fire('sendVirtualInput', {
      'port': port,
      'keyCode': keyCode,
      'isDown': isDown,
    });
  }

  /// source: [analogDpad], [analogLeft] or [analogRight]; x/y in -1..1
  static void sendAnalog(int source, double x, double y, {int port = 0}) {
    _fire('sendVirtualAnalog', {
      'port': port,
      'source': source,
      'x': x,
      'y': y,
    });
  }

  /// action: 0 = down, 1 = move, 2 = up. x/y are normalised (0..1) over the game view.
  static void sendTouch(int action, double x, double y) {
    _fire('sendTouch', {'action': action, 'x': x, 'y': y});
  }

  /// Big PSP / 3DS states can take several seconds, so these get a longer limit than other calls.
  static Future<bool> saveState(String path) => _callBool(
    'saveState',
    args: {'path': path},
    timeout: const Duration(seconds: 30),
  );

  static Future<bool> loadState(String path) => _callBool(
    'loadState',
    args: {'path': path},
    timeout: const Duration(seconds: 30),
  );

  static void setFastForward(int speed) =>
      _fire('setFastForward', {'speed': speed});

  static void setPaused(bool paused) => _fire('setPaused', {'paused': paused});

  static void setMuted(bool muted) => _fire('setMuted', {'muted': muted});

  static Future<bool> resetGame() => _callBool('resetGame');

  /// Saves the current game picture to [path] (.png or .jpg by extension).
  /// [maxWidth] > 0 downsizes it (used for save-state thumbnails).
  static Future<bool> takeScreenshot(String path, {int maxWidth = 0}) async {
    try {
      return await _channel.invokeMethod<bool>('takeScreenshot', {
            'path': path,
            'maxWidth': maxWidth,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// Copies an image file into the phone's gallery (Pictures/tonEMU). Returns false on failure.
  static Future<bool> exportToGallery(
    String path, {
    String album = 'tonEMU',
  }) async {
    try {
      return await _channel.invokeMethod<bool>('exportToGallery', {
            'path': path,
            'album': album,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> applyCheat(int index, bool enabled, String code) async {
    try {
      return await _channel.invokeMethod<bool>('applyCheat', {
            'index': index,
            'enabled': enabled,
            'code': code,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// Sends the WHOLE cheat list in one call. Native clears the core's cheat table first
  /// (retro_cheat_reset, when available) and then sets every entry, the way RetroArch does.
  /// Per-index enable/disable is not reliable across cores: many only ever add, so a cheat that
  /// was switched off kept running until the game was restarted.
  static Future<bool> setCheats(
    List<({int idx, bool enabled, String code})> cheats,
  ) async {
    try {
      return await _channel.invokeMethod<bool>('setCheats', {
            'cheats': [
              for (final c in cheats)
                {'index': c.idx, 'enabled': c.enabled, 'code': c.code},
            ],
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// layoutId is a neutral id from [ScreenMode.id]; native maps it to the right core option.
  static void setScreenLayout(String layoutId) =>
      _fire('setScreenLayout', {'layout': layoutId});

  /// Free-form screens: starts copying the game picture into a Flutter texture of this pixel
  /// size and returns the texture id (null if it could not start).
  static Future<int?> startMirror(int width, int height) async {
    try {
      final r = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'startMirror',
        {'width': width, 'height': height},
      );
      return (r?['id'] as num?)?.toInt();
    } on PlatformException {
      return null;
    }
  }

  static Future<void> stopMirror() async {
    try {
      await _channel.invokeMethod<bool>('stopMirror');
    } on PlatformException {
      // ignore
    }
  }

  /// Asks native to recompute the video viewport for the current view size. Safe to call even if
  /// the native side doesn't implement it (the error is swallowed).
  static void refreshVideo() => _fire('refreshVideo');

  /// Every option the running core declares (empty if the core isn't ready).
  static Future<List<CoreOption>> getCoreOptions() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getCoreOptions');
      return (raw ?? const [])
          .map(
            (e) => CoreOption.fromNative(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
    } on PlatformException {
      return [];
    }
  }

  static void setCoreOption(String key, String value) {
    // App-level settings (e.g. the renderer) and options a core only reads at startup are
    // never sent to a running core; blocked (crashing) values are never sent either.
    if (key == CoreSettings.rendererKey) return;
    if (CoreSettings.needsRestart(key)) return;
    if (value.trim().isEmpty || CoreSettings.isBlockedValue(key, value)) return;
    _fire('setCoreOption', {'key': key, 'value': value});
  }

  /// Applies several live-safe options in ONE native call, so the core sees them together in a
  /// single update instead of a burst of changes. Options that need a restart or have blocked
  /// values are dropped here. Returns false when the core is not ready (nothing was applied).
  static Future<bool> setCoreOptions(Map<String, String> options) async {
    final live = <String, String>{
      for (final e in options.entries)
        if (e.key != CoreSettings.rendererKey &&
            !CoreSettings.needsRestart(e.key) &&
            e.value.trim().isNotEmpty &&
            !CoreSettings.isBlockedValue(e.key, e.value))
          e.key: e.value,
    };
    if (live.isEmpty) return true;
    try {
      return await _channel.invokeMethod<bool>('setCoreOptions', {
            'options': live,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// Fully unloads the running core. Always call before leaving the game screen.
  static Future<void> stopGame() async {
    try {
      await _channel.invokeMethod<bool>('stopGame');
    } on PlatformException {
      // ignore
    }
  }
}
