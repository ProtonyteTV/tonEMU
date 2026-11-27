// lib/screens/game_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/state_paths.dart';
import '../services/storage_service.dart';
import '../models/console_system.dart';
import '../models/screen_layout.dart';
import '../services/app_settings.dart';
import '../services/cheat_db.dart';
import '../services/core_settings.dart';
import '../services/emulator_bridge.dart';
import '../services/theme_service.dart';
import '../widgets/menu_widgets.dart';
import '../widgets/settings_kit.dart';
import '../services/jed_time_machine.dart';
import '../widgets/jed_time_machine_sheet.dart';
import '../widgets/fold_support.dart';
import '../widgets/touch_controls.dart';
import 'cheat_browser_sheet.dart';
import 'core_settings_screen.dart';

// ───────────────────────── Controls model ─────────────────────────

enum ControlKind { button, pill, shoulder, dpad, stick, faceCluster }

class ControlConfig {
  final String id;
  final String label;
  final int keyCode;
  final ControlKind kind;
  double x; // 0..1 of screen width (top-left corner)
  double y; // 0..1 of screen height (top-left corner)
  double size;

  ControlConfig({
    required this.id,
    this.label = '',
    this.keyCode = 0,
    this.kind = ControlKind.button,
    required this.x,
    required this.y,
    double? size,
  }) : size = size ?? _defaultSize(kind);

  static double _defaultSize(ControlKind k) {
    switch (k) {
      case ControlKind.dpad:
        return 136;
      case ControlKind.faceCluster:
        return 148;
      case ControlKind.stick:
        return 106;
      case ControlKind.pill:
        return 42;
      case ControlKind.shoulder:
        return 46;
      case ControlKind.button:
        return 52;
    }
  }

  double get minSize => switch (kind) {
    ControlKind.dpad => 100,
    ControlKind.faceCluster => 112,
    ControlKind.stick => 80,
    ControlKind.pill => 32,
    ControlKind.shoulder => 36,
    ControlKind.button => 36,
  };

  double get maxSize => switch (kind) {
    ControlKind.dpad => 230,
    ControlKind.faceCluster => 250,
    ControlKind.stick => 200,
    ControlKind.pill => 70,
    ControlKind.shoulder => 90,
    ControlKind.button => 90,
  };

  double get width => switch (kind) {
    ControlKind.pill => size * 1.65,
    ControlKind.shoulder => size * 1.45,
    _ => size,
  };

  double get height => switch (kind) {
    ControlKind.pill => size * 0.68,
    ControlKind.shoulder => size * 0.72,
    _ => size,
  };

  Map<String, dynamic> toJson() => {'id': id, 'x': x, 'y': y, 'size': size};
}

class Cheat {
  final int idx; // stable native slot index
  String name;
  String code;
  bool enabled;

  Cheat({
    required this.idx,
    required this.name,
    required this.code,
    this.enabled = false,
  });

  Map<String, dynamic> toJson() => {
    'idx': idx,
    'name': name,
    'code': code,
    'enabled': enabled,
  };

  factory Cheat.fromJson(Map<String, dynamic> j) => Cheat(
    idx: j['idx'] as int,
    name: j['name'] as String,
    code: j['code'] as String,
    enabled: j['enabled'] as bool? ?? false,
  );
}

/// Describes the active hinge/fold posture on foldable & flip phones.
class _FoldPosture {
  final Rect? horizontalHinge; // Z Flip / tabletop fold
  final Rect? verticalHinge; // Z Fold book-style crease
  final bool isHalfOpened;

  const _FoldPosture({
    this.horizontalHinge,
    this.verticalHinge,
    this.isHalfOpened = false,
  });

  bool get isFlipTabletop => horizontalHinge != null && isHalfOpened;
  bool get isBookFold => verticalHinge != null;

  static _FoldPosture fromFeatures(List<DisplayFeature> features) {
    for (final f in features) {
      if (f.type != DisplayFeatureType.hinge &&
          f.type != DisplayFeatureType.fold) {
        continue;
      }
      final halfOpen = f.state == DisplayFeatureState.postureHalfOpened;
      if (f.bounds.width >= f.bounds.height) {
        return _FoldPosture(horizontalHinge: f.bounds, isHalfOpened: halfOpen);
      } else {
        return _FoldPosture(verticalHinge: f.bounds, isHalfOpened: halfOpen);
      }
    }
    return const _FoldPosture();
  }
}

// ───────────────────────── Screen ─────────────────────────

class GameScreen extends StatefulWidget {
  final File? romFile;
  final ConsoleSystem system;
  final bool useVulkan;
  final bool bootBios;

  /// Load the auto-save right after the core starts (the library asks the player first).
  final bool resumeFromAuto;

  /// Real core filename returned by EmulatorBridge.resolveCore().
  final String coreFile;

  const GameScreen({
    super.key,
    this.romFile,
    required this.system,
    required this.useVulkan,
    required this.coreFile,
    this.bootBios = false,
    this.resumeFromAuto = false,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  static const _surfaceType = 'xemu_game_surface';
  static const _layoutVersion = 7; // 7: PS1 portrait right stick clear of X / Square; 6: PS1 portrait L2/R2 stacked under L1/R1

  SharedPreferences? _prefs;
  bool _loaded = false;
  bool _portrait = false;
  Size _lastScreenSize = Size.zero;
  EdgeInsets _lastPadding = EdgeInsets.zero;

  /// Signature (layout key + screen size + safe area) the current [_controls] were built for.
  /// If it ever differs from the live one, build() regenerates the controls before drawing.
  String? _builtFor;
  _FoldPosture _fold = const _FoldPosture();
  bool _quitting = false;
  bool _menuOpen = false;
  // True while the game is auto-paused (app left / notification shade). A or B continues.
  bool _autoPaused = false;

  bool _editMode = false;
  // Saved layout (and its key) as it was when edit mode started, so Cancel can restore it.
  String? _editBackupKey;
  String? _editBackupValue;
  String? _selectedButtonId;
  List<ControlConfig> _controls = [];

  /// Top (px) of the shoulder-button row. The quick bar is anchored here in portrait even when
  /// the system has no L/R buttons (NES).
  double? _shoulderTopPx;

  int _fastForwardSpeed = 1;
  int _slot = 1;
  bool _muted = false;
  bool _hideControls = false;
  bool _haptics = true;
  bool _autoSaveOnQuit = true;
  double _opacity = 1.0;
  late String _screenMode;
  double _screenScale = 1.0;
  double _screenDx = 0;
  double _screenDy = 0;
  bool _screenEdit = false;
  double _editBaseScale = 1.0;
  Timer? _layoutRefreshTimer;

  // WonderSwan only: the core rotates vertical games, so the game view has to take the shape of
  // the picture it is really drawing (tall instead of wide) or a rotated game shows up small.
  Timer? _wsAspectTimer;
  bool _wsRotated = false;
  Map<ScreenContext, ScreenProfile> _profiles = {};
  List<Cheat> _cheats = [];
  Map<String, String> _coreOverrides = {};
  Map<String, String> _regionOptions = {};

  final AppSettings _settings = AppSettings.instance;
  bool _gamepad = false;
  StreamSubscription<String>? _hotkeySub;
  Map<int, DateTime?> _slotTimes = {};
  Map<int, Uint8List?> _slotThumbs = {};
  Uint8List?
  _menuSnapshot; // frame grabbed just before the quick menu pauses the game

  // Play-time tracking: counts only while the game is actually running.
  final Stopwatch _playClock = Stopwatch();
  int _flushedSecs = 0;
  Timer? _playFlushTimer;
  Timer? _autoSaveTimer;
  JedTimeMachine? _tm; // rolling snapshots of this session
  Timer? _tmTimer;
  int _tmPlaySec =
      0; // seconds of real play covered by the jedTimeMachine so far
  bool _tmNotified = false;
  // True while the "continue or start new?" prompt is up: background auto-saves must not
  // overwrite the snapshot the player is still deciding about.
  bool _awaitingResumeChoice = false;

  int? _touchPointer;

  /// States are only valid for the core that wrote them (see StatePaths).
  String get _coreKey => StatePaths.coreKey(widget.coreFile);
  Future<void>? _legacyMigrated;

  String get _romName {
    final segs = widget.romFile?.uri.pathSegments
        .where((x) => x.isNotEmpty)
        .toList();
    if (segs != null && segs.isNotEmpty) {
      return segs.last;
    }
    return '${widget.system.shortName.toLowerCase()}_firmware';
  }

  String get _displayTitle => widget.bootBios
      ? (widget.system.type == ConsoleType.nds
            ? '${widget.system.name} Firmware'
            : '${widget.system.name} BIOS')
      : ConsoleSystem.cleanTitle(_romName);
  String get _sys => widget.system.shortName;

  /// Shape (width / height) of the game view. Same as the console's own, except a WonderSwan game
  /// the core has rotated, which is tall.
  double get _pictureAspect =>
      (widget.system.type == ConsoleType.wonderswan && _wsRotated)
      ? 1 / widget.system.aspect
      : widget.system.aspectFor(_screenMode);

  void _startWsRotationWatch() {
    if (widget.system.type != ConsoleType.wonderswan) return;
    _wsAspectTimer?.cancel();
    _wsAspectTimer = Timer.periodic(const Duration(milliseconds: 500), (
      _,
    ) async {
      if (!mounted || _quitting) return;
      final a = await EmulatorBridge.getVideoAspect(); // null until the core has a frame
      if (a == null || !mounted || _quitting) return;
      final rotated = a < 1.0; // wide is about 1.56, rotated is about 0.64
      if (rotated == _wsRotated) return;
      setState(() => _wsRotated = rotated);
      _scheduleLayoutRefresh(); // the view just changed size: let the surface follow
    });
  }

  @override
  void initState() {
    super.initState();
    FoldShell.suspend(); // the game lays itself out around the hinge
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _screenMode = widget.system.defaultScreenMode;
    WidgetsBinding.instance.addObserver(this);
    _playClock.start();
    _startWsRotationWatch();
    _playFlushTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _flushPlayTime();
      _checkBreakReminder();
    });
    _init();
  }

  String _initStep = 'starting';
  String? _initError;

  /// Never leaves the black spinner up forever: a failure is shown with the step it happened in.
  Future<void> _init() async {
    try {
      await _initInner();
    } catch (e, st) {
      debugPrint('GameScreen init failed at "$_initStep": $e\n$st');
      if (mounted) setState(() => _initError = '$_initStep\n$e');
    }
  }

  Future<void> _initInner() async {
    _initStep = 'reading settings';
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    _haptics = prefs.getBool('ui_haptics') ?? true;
    _opacity = prefs.getDouble('ui_opacity') ?? 1.0;
    _autoSaveOnQuit = prefs.getBool('autosave_on_quit') ?? true;
    _initStep = 'loading screen layouts';
    _profiles = await ScreenLayouts.load(prefs, _sys);
    _initStep = 'preparing storage';

    if (!StorageService.instance.isInitialized) {
      await StorageService.instance.init();
    }
    _initStep = 'loading app settings';
    await _settings.load();
    if (!mounted) return;
    _initStep = 'setting up input';
    await _setupInput();
    if (!mounted)
      return; // left the screen while setting up: do not start timers
    _startAutoSaveTimer();
    unawaited(_startJedTimeMachine());

    // Pick the premade / custom layout for the current view BEFORE the surface is created.
    _resolveScreenProfile(pushToCore: false);

    // If the last launch of this core never got stable, its saved options are the likely cause:
    // they are backed up and cleared so the game can start instead of crashing again.
    _initStep = 'reading core settings';
    final rescuedSettings = await CoreSettings.rescueIfLastLaunchFailed(
      widget.system.coreLibName,
    );
    _coreOverrides = await CoreSettings.loadOverrides(
      widget.system.coreLibName,
    );
    _coreOverrides.removeWhere(
      (k, v) => v.trim().isEmpty || CoreSettings.isBlockedValue(k, v),
    );
    _regionOptions = await CoreSettings.loadRegionLaunchOptions(
      widget.system.coreLibName,
    );
    unawaited(
      Future<void>.delayed(
        const Duration(seconds: 15),
        () => CoreSettings.markLaunchStable(widget.system.coreLibName),
      ),
    );

    final rawCheats = prefs.getString('cheats_$_romName');
    if (rawCheats != null) {
      try {
        _cheats = (jsonDecode(rawCheats) as List)
            .map((e) => Cheat.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _cheats = [];
      }
    }
    if (!mounted) return;
    _initStep = 'building touch controls';
    _buildControlsNow();
    setState(() => _loaded = true);
    if (rescuedSettings) {
      _toast('Last launch failed - core settings were reset to defaults');
    }
    unawaited(_reapplyCheatsWhenReady());
    unawaited(_syncCoreOptionsWhenReady());
    if (!widget.bootBios) {
      _legacyMigrated = StatePaths.migrateLegacy(
        StorageService.instance.statesDir,
        _romName,
        _coreKey,
        slots: kSaveSlots,
      );
    }
    unawaited(_autoResume());
  }

  /// Caches the core's option list and forces region options to US.
  Future<void> _syncCoreOptionsWhenReady() async {
    if (!await EmulatorBridge.waitUntilReady()) return;
    final opts = await EmulatorBridge.getCoreOptions();
    if (opts.isEmpty) return;
    await CoreSettings.saveSchema(widget.system.coreLibName, opts);
    // Region options are forced to US, but never changed while the game runs (that breaks
    // video/audio timing and can crash). They are saved and sent when the game starts.
    final region = <String, String>{};
    for (final o in opts) {
      if (!o.isRegion) continue;
      final us = CoreSettings.usValue(o);
      if (us != null) region[o.key] = us;
    }
    await CoreSettings.saveRegionLaunchOptions(
      widget.system.coreLibName,
      region,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mq = MediaQuery.of(context);
    final portrait = mq.orientation == Orientation.portrait;
    final size = mq.size;
    final pad = mq.padding;
    final fold = _FoldPosture.fromFeatures(mq.displayFeatures);

    // Safe-area changes count too (landscape-left <-> landscape-right moves the notch).
    final changed =
        portrait != _portrait ||
        size != _lastScreenSize ||
        pad != _lastPadding ||
        fold.isFlipTabletop != _fold.isFlipTabletop ||
        fold.isBookFold != _fold.isBookFold;

    // Rotating while customizing: store the edits under the OLD orientation's key
    // (_layoutKey still reflects it here) before anything is rebuilt, so nothing is lost.
    if (changed && _loaded && _editMode && _controls.isNotEmpty) {
      unawaited(_saveCustomLayout());
    }

    _portrait = portrait;
    _lastScreenSize = size;
    _lastPadding = pad;
    _fold = fold;

    if (changed && _loaded) {
      _selectedButtonId = null;
      _resolveScreenProfile();
      _rebuildControls();
      _scheduleLayoutRefresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _layoutRefreshTimer?.cancel();
    _wsAspectTimer?.cancel();
    _playFlushTimer?.cancel();
    _autoSaveTimer?.cancel();
    _tmTimer?.cancel();
    unawaited(_tm?.dispose());
    _playClock.stop();
    unawaited(_flushPlayTime());
    _hotkeySub?.cancel();
    EmulatorBridge.onGateRelease = null;
    EmulatorBridge.setPauseGate(false);
    EmulatorBridge.gamepadConnected.removeListener(_onGamepadChanged);
    EmulatorBridge.setUiCaptured(false);
    // Normal exit: the launch did not crash.
    unawaited(CoreSettings.markLaunchStable(widget.system.coreLibName));
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    FoldShell.resume();
    super.dispose();
  }

  // ───────── Play time ─────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_menuOpen &&
          !_autoPaused &&
          !_editMode &&
          !_screenEdit &&
          !_quitting &&
          !_playClock.isRunning) {
        _playClock.start();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _enterAutoPause();
      _playClock.stop();
      unawaited(_flushPlayTime());
      // The app may be killed while in the background, so keep the auto-save fresh.
      if (state == AppLifecycleState.paused &&
          _autoSaveOnQuit &&
          _loaded &&
          !_quitting &&
          !widget.bootBios) {
        unawaited(_saveState(0, silent: true));
      }
    }
  }

  /// Minutes of play (this session) at which the next break reminder is due.
  int _nextBreakMin = 0;

  String _fmtSession(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${d.inMinutes}m';
  }

  /// Optional gentle nudge. Counts only time the game was actually running (the play clock stops
  /// while paused), shows once per interval and never interrupts the game.
  void _checkBreakReminder() {
    final every = AppSettings.instance.breakReminderMinutes;
    if (every <= 0 || !mounted || widget.bootBios) return;
    if (_nextBreakMin < every) _nextBreakMin = every;
    final played = _playClock.elapsed;
    if (played.inMinutes < _nextBreakMin) return;
    _nextBreakMin += every;
    _showTopSnack(
      _topSnack(
        Text(
          'You\'ve been playing for ${_fmtSession(played)}. Time for a break?',
        ),
        const Duration(seconds: 5),
      ),
    );
  }

  /// Adds the seconds played since the last flush to 'playtime_<rom>' (read by the library).
  Future<void> _flushPlayTime() async {
    if (widget.bootBios) return;
    final delta = _playClock.elapsed.inSeconds - _flushedSecs;
    if (delta < 1) return;
    _flushedSecs += delta;
    final p = _prefs ?? await SharedPreferences.getInstance();
    final key = 'playtime_$_romName';
    await p.setInt(key, (p.getInt(key) ?? 0) + delta);
  }

  // ───────── Auto-pause (leaving the app / notification shade) ─────────

  /// Pauses the game when the player leaves it (home, app switcher, notification or quick-settings
  /// shade...). It stays paused, behind a "Press A or B" overlay, until A or B is pressed, so the
  /// game never keeps running (or comes back mid-action) without the player noticing.
  void _enterAutoPause() {
    if (!_settings.pauseOnLeave ||
        _autoPaused ||
        !_loaded ||
        _quitting ||
        _menuOpen || // the menu already holds the game paused
        _editMode ||
        _screenEdit ||
        _awaitingResumeChoice) {
      return;
    }
    _autoPaused = true;
    _playClock.stop();
    EmulatorBridge.setPaused(true);
    EmulatorBridge.setPauseGate(true);
    if (mounted) setState(() {});
  }

  /// A or B (touch or gamepad) was pressed on the pause overlay.
  void _leaveAutoPause() {
    if (!_autoPaused) return;
    _autoPaused = false;
    EmulatorBridge.setPauseGate(false);
    if (!_menuOpen && !_quitting && !_editMode && !_screenEdit) {
      EmulatorBridge.setPaused(false);
      _playClock.start();
    }
    if (mounted) setState(() {});
  }

  Widget _buildPauseOverlay(bool showControls) {
    final canTap =
        !showControls && !_gamepad; // no A / B anywhere: a tap must be enough
    final hint = canTap
        ? 'Tap anywhere to continue'
        : 'Press A or B to continue';
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canTap ? _leaveAutoPause : null,
        child: ColoredBox(
          color: const Color(0x99000000),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.pause_circle_outline,
                  color: Colors.white,
                  size: 64,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Paused',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  hint,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ───────── Gamepad / hotkeys / resume ─────────

  Future<void> _setupInput() async {
    await EmulatorBridge.init();
    if (!mounted)
      return; // otherwise the listeners below are added after dispose and leak
    EmulatorBridge.setInputConfig(
      swapAB: _settings.swapAB,
      swapXY: _settings.swapXY,
      deadzone: _settings.deadzone,
      comboHotkeys: _settings.comboHotkeys,
    );
    _gamepad = EmulatorBridge.gamepadConnected.value;
    EmulatorBridge.gamepadConnected.addListener(_onGamepadChanged);
    _hotkeySub = EmulatorBridge.hotkeys.listen(_onHotkey);
    EmulatorBridge.onGateRelease = _leaveAutoPause;
  }

  void _onGamepadChanged() {
    if (!mounted) return;
    final connected = EmulatorBridge.gamepadConnected.value;
    setState(() {
      _gamepad = connected;
      _resolveScreenProfile();
    });
    if (_loaded) {
      // Rebuilding re-reads the SAVED layout, which would wipe unsaved edits while customizing.
      if (!_editMode) _rebuildControls();
      _scheduleLayoutRefresh();
      _toast(
        connected
            ? 'Controller connected — touch controls hidden'
            : 'Controller disconnected — touch controls restored',
      );
      if (!connected && _settings.pauseOnDisconnect)
        unawaited(_openQuickMenu());
    }
  }

  /// jedTimeMachine: a snapshot every N seconds of real play (menu, background and loading time
  /// don't count), kept as a thinned rolling history.
  Future<void> _startJedTimeMachine() async {
    _tmTimer?.cancel();
    final secs = _settings.jedTimeMachineSeconds;
    if (secs <= 0 || widget.bootBios) return;
    final tm = JedTimeMachine(romName: _romName);
    try {
      await tm.init();
    } catch (_) {
      return;
    }
    if (!mounted) {
      unawaited(tm.dispose());
      return;
    }
    _tm = tm;
    _tmTimer = Timer.periodic(Duration(seconds: secs), (_) {
      if (!mounted ||
          !_loaded ||
          _menuOpen ||
          _quitting ||
          _editMode ||
          _screenEdit ||
          _awaitingResumeChoice ||
          !_playClock.isRunning) {
        return;
      }
      _tmPlaySec += secs;
      unawaited(
        tm.capture(_tmPlaySec).then((_) {
          if (tm.disabled && !_tmNotified) {
            _tmNotified = true;
            _tmTimer?.cancel();
            _toast(tm.disabledReason ?? 'jedTimeMachine stopped');
          }
        }),
      );
    });
  }

  Future<void> _openJedTimeMachine() async {
    if (!mounted) return;
    final picked = await showJedTimeMachineSheet(
      context,
      anchorPoint: _menuAnchor,
      machine: _tm,
      nowSec: _tmPlaySec,
      intervalSec: _settings.jedTimeMachineSeconds,
    );
    if (picked == null || !mounted) return;
    await _loadState(0, pathOverride: picked.state.path);
  }

  /// Silently refreshes the auto-save slot every N minutes (a crash/kill loses at most N minutes).
  void _startAutoSaveTimer() {
    _autoSaveTimer?.cancel();
    final mins = _settings.autoSaveMinutes;
    if (mins <= 0 || widget.bootBios) return;
    _autoSaveTimer = Timer.periodic(Duration(minutes: mins), (_) {
      if (!mounted ||
          !_loaded ||
          _menuOpen ||
          _quitting ||
          _editMode ||
          _screenEdit)
        return;
      unawaited(_saveState(0, silent: true));
    });
  }

  /// Phone hit its low-battery level: refresh the auto-save slot right away (even with the menu
  /// open) so a phone that dies mid-game loses nothing. Follows the "auto-save on quit" setting.
  void _onBatteryLow() {
    if (!mounted ||
        !_loaded ||
        _quitting ||
        widget.bootBios ||
        _awaitingResumeChoice ||
        !_autoSaveOnQuit) {
      return;
    }
    unawaited(_saveState(0, silent: true));
    _toast('Battery low – progress auto-saved');
  }

  void _onHotkey(String key) {
    if (key == 'batteryLow') {
      _onBatteryLow();
      return;
    }
    if (key == 'focusLost') {
      _enterAutoPause();
      return;
    }
    if (key == 'resumeGate') {
      _leaveAutoPause();
      return;
    }
    if (_autoPaused)
      return; // only A / B (resumeGate) does anything while auto-paused
    if (_menuOpen || _quitting || _editMode || _screenEdit || !mounted) return;
    switch (key) {
      case 'menu':
        _openQuickMenu();
      case 'quickSave':
        _saveState(_slot);
      case 'quickLoad':
        _loadState(_slot);
      case 'fastForward':
        _toggleFastForward();
      case 'nextSlot':
        setState(() => _slot = _slot % kSaveSlots + 1);
        _toast('Save slot $_slot selected');
      case 'screenshot':
        unawaited(_takeScreenshot());
      case 'mute':
        setState(() => _muted = !_muted);
        EmulatorBridge.setMuted(_muted);
        _toast(_muted ? 'Muted' : 'Sound on');
      case 'audioNoisy':
        if (_settings.pauseOnDisconnect) unawaited(_openQuickMenu());
    }
  }

  void _toggleFastForward() {
    setState(
      () => _fastForwardSpeed = _fastForwardSpeed == 1
          ? _settings.fastForwardSpeed
          : 1,
    );
    EmulatorBridge.setFastForward(_fastForwardSpeed);
    _toast(
      _fastForwardSpeed == 1
          ? 'Normal speed'
          : 'Fast-forward ${_fastForwardSpeed}x',
    );
  }

  Future<void> _takeScreenshot() async {
    if (_menuOpen || _quitting) return;
    try {
      final dir = StorageService.instance.screenshotsDir;
      if (!await dir.exists()) await dir.create(recursive: true);
      final t = DateTime.now();
      String two(int n) => n.toString().padLeft(2, '0');
      final stamp =
          '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}';
      final safeTitle = _displayTitle.replaceAll(
        RegExp(r'[^A-Za-z0-9._-]+'),
        '_',
      );
      final shotPath = '${dir.path}/${safeTitle}_$stamp.png';
      final ok = await EmulatorBridge.takeScreenshot(shotPath);
      if (ok && _haptics) HapticFeedback.selectionClick();
      if (ok && _settings.screenshotToGallery) {
        final inGallery = await EmulatorBridge.exportToGallery(shotPath);
        _toast(
          inGallery
              ? 'Screenshot saved to Gallery'
              : 'Screenshot saved (Gallery copy failed)',
        );
      } else {
        _toast(ok ? 'Screenshot saved' : 'Screenshot failed');
      }
    } catch (_) {
      _toast('Screenshot failed');
    }
  }

  /// The library already asked "continue or start new?" and passes [GameScreen.resumeFromAuto].
  /// When true, load the auto-save as soon as the core is up.
  Future<void> _autoResume() async {
    if (widget.bootBios) return;
    if (!widget.resumeFromAuto) {
      // Starting fresh will eventually replace the old auto-save: keep it as a backup first.
      await _backupAutoSave();
      return;
    }
    // Until the snapshot is loaded, background/periodic/quit auto-saves must not overwrite it
    // with the fresh boot state.
    _awaitingResumeChoice = true;
    if (!await File(await _getStatePath(0)).exists()) {
      _awaitingResumeChoice = false;
      return;
    }
    var loaded = false;
    // Only "the core is not ready yet" is retried. Once the core was ready and still refused the
    // state, the data is not for this core: retrying just repeats the failure (and the core's
    // error spam), so the first real failure is final.
    for (var attempt = 0; attempt < 5 && !loaded; attempt++) {
      if (!mounted || _quitting)
        return; // flag stays set: nothing may overwrite the auto-save
      if (await EmulatorBridge.waitUntilReady()) {
        await Future<void>.delayed(
          Duration(milliseconds: attempt == 0 ? 600 : 2500),
        );
        if (!mounted || _quitting) return;
        loaded = await _loadState(
          0,
          undoable: false,
          quiet: false,
          announce: false,
        );
        break;
      }
    }
    // Only a successful load lifts the protection. If it never worked, the old auto-save is
    // kept as is instead of being replaced by the fresh boot state when the user quits.
    if (loaded) {
      _awaitingResumeChoice = false;
      _offerStartOver();
    }
  }

  /// Copies the current auto-save to "<name>.auto.state.bak" (restorable from the library's
  /// long-press menu), so "Start over" / "Start Fresh" never destroy earlier progress.
  Future<void> _backupAutoSave() async {
    try {
      final src = File(await _getStatePath(0));
      if (!await src.exists() || await src.length() == 0) return;
      final bak = '${src.path}.bak';
      await src.copy('$bak.tmp');
      await File('$bak.tmp').rename(bak);
    } catch (_) {}
  }

  /// Replaces the old "continue or start new?" dialog: the game is already running from the
  /// auto-save, and for a few seconds one tap restarts it (with Undo, in case of a mis-tap).
  void _offerStartOver() {
    if (!mounted || _quitting) return;
    _showTopSnack(
      _topSnack(
        const Text('Continued from auto-save'),
        const Duration(seconds: 5),
        action: SnackBarAction(label: 'Start over', onPressed: _startOver),
      ),
    );
  }

  Future<void> _startOver() async {
    await _backupAutoSave();
    var haveUndo = false;
    try {
      haveUndo = await EmulatorBridge.saveState(await _undoStatePath());
    } catch (_) {}
    final ok = await EmulatorBridge.resetGame();
    if (!mounted) return;
    if (!ok || !haveUndo) {
      _toast(ok ? 'Restarted' : 'Restart failed');
      return;
    }
    _showTopSnack(
      _topSnack(
        const Text('Restarted'),
        const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            final undone = await EmulatorBridge.loadState(
              await _undoStatePath(),
            );
            _toast(undone ? 'Back where you were' : 'Undo failed');
          },
        ),
      ),
    );
  }

  Future<void> _refreshSlotTimes() async {
    final times = <int, DateTime?>{};
    final thumbs = <int, Uint8List?>{};
    for (var i = 1; i <= kSaveSlots; i++) {
      final f = File(await _getStatePath(i));
      times[i] = await f.exists() ? await f.lastModified() : null;
      final t = File(await _getThumbPath(i));
      thumbs[i] = (times[i] != null && await t.exists())
          ? await t.readAsBytes()
          : null;
    }
    _slotTimes = times;
    _slotThumbs = thumbs;
  }

  Future<String> _getThumbPath(int slot) async {
    final statePath = await _getStatePath(slot);
    return '${statePath.substring(0, statePath.length - '.state'.length)}.jpg';
  }

  /// Small JPEG of the current picture, or null if the capture isn't available.
  Future<Uint8List?> _captureThumb() async {
    try {
      final dir = StorageService.instance.statesDir;
      if (!await dir.exists()) await dir.create(recursive: true);
      final tmp = File('${dir.path}/.thumb_tmp.jpg');
      final ok = await EmulatorBridge.takeScreenshot(
        tmp.path,
        maxWidth: 320,
      ).timeout(const Duration(milliseconds: 900), onTimeout: () => false);
      if (!ok || !await tmp.exists()) return null;
      final bytes = await tmp.readAsBytes();
      try {
        await tmp.delete();
      } catch (_) {}
      return bytes;
    } catch (_) {
      return null;
    }
  }

  // ───────── Screen & Foldable Layout Helpers ─────────

  ScreenContext get _screenCtx => ScreenLayouts.contextOf(
    portrait: _portrait || _fold.isFlipTabletop,
    gamepad: _gamepad,
  );

  /// Applies the layout for the current view (portrait / landscape, with or without a
  /// controller): the user's own choice if they made one, otherwise the premade recommendation.
  /// Side-by-side arrangements only make sense on a wide (landscape) view.
  static bool _landscapeOnly(String id) =>
      id == 'left_right' || id == 'right_left';

  /// Top-only / bottom-only are produced by CROPPING the stacked picture in Flutter, so they
  /// work on every core. The core itself always draws the normal stacked layout for them.
  static bool _isCropMode(String id) => id == 'top_only' || id == 'bottom_only';
  static String _coreMode(String id) =>
      (_isCropMode(id) || id == 'free') ? 'top_bottom' : id;

  bool get _isFree => widget.system.isDualScreen && _screenMode == 'free';

  // ── Free form: two screens, each placed independently ──
  int? _mirrorTex;
  bool _mirrorStarting = false;
  int _freeSel = 0; // 0 = top, 1 = bottom while editing

  double get _topAspect =>
      widget.system.type == ConsoleType.n3ds ? 5 / 3 : 4 / 3;
  double get _bottomAspect => 4 / 3;

  Rect _toPx(Rect f, Size s) => Rect.fromLTWH(
    f.left * s.width,
    f.top * s.height,
    f.width * s.width,
    f.height * s.height,
  );
  Rect _toFrac(Rect r, Size s) => Rect.fromLTWH(
    r.left / s.width,
    r.top / s.height,
    r.width / s.width,
    r.height / s.height,
  );

  /// [top, bottom] rectangles in pixels. Defaults to the normal stacked arrangement.
  List<Rect> _freeRects(Size size, EdgeInsets pad) {
    final p = _profiles[_screenCtx] ?? const ScreenProfile();
    if (p.topRect != null && p.bottomRect != null) {
      return [_toPx(p.topRect!, size), _toPx(p.bottomRect!, size)];
    }
    final base = _screenRect(size, pad);
    final fa = widget.system.aspectFor('top_bottom');
    var w = base.width;
    var h = w / fa;
    if (h > base.height) {
      h = base.height;
      w = h * fa;
    }
    final x = base.left + (base.width - w) / 2;
    final y = base.top + (base.height - h) / 2;
    final bw = w * _bottomWidthFraction;
    return [
      Rect.fromLTWH(x, y, w, h / 2),
      Rect.fromLTWH(x + (w - bw) / 2, y + h / 2, bw, h / 2),
    ];
  }

  /// Makes sure the frame mirror runs exactly while Free form is active.
  Future<void> _syncMirror() async {
    if (!_isFree) {
      if (_mirrorTex != null || _mirrorStarting) {
        _mirrorTex = null;
        _mirrorStarting = false;
        await EmulatorBridge.stopMirror();
        if (mounted) setState(() {});
      }
      return;
    }
    if (_mirrorTex != null || _mirrorStarting) return;
    _mirrorStarting = true;
    final fa = widget.system.aspectFor('top_bottom');
    const w = 720;
    final h = (w / fa).round();
    for (var i = 0; i < 40 && mounted && _isFree; i++) {
      if (await EmulatorBridge.isReady()) {
        final id = await EmulatorBridge.startMirror(w, h);
        if (id != null) {
          _mirrorStarting = false;
          if (mounted) setState(() => _mirrorTex = id);
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    _mirrorStarting = false;
  }

  void _resolveScreenProfile({bool pushToCore = true}) {
    if (!widget.system.isDualScreen) return;
    final ctx = _screenCtx;
    final profile = _profiles[ctx] ?? const ScreenProfile();
    var mode =
        profile.modeId ??
        ScreenLayouts.recommended(
          portrait: ctx.isPortrait,
          gamepad: ctx.isController,
        );
    if (!widget.system.screenModes.any((m) => m.id == mode)) {
      mode = widget.system.defaultScreenMode;
    }
    // Side by side is landscape only.
    if (ctx.isPortrait && _landscapeOnly(mode)) {
      mode = widget.system.defaultScreenMode;
    }
    // Z Flip tabletop with a controller keeps the screens stacked above the hinge.
    if (_fold.isFlipTabletop && _gamepad) mode = 'top_bottom';
    _screenScale = profile.scale;
    _screenDx = profile.dx;
    _screenDy = profile.dy;
    if (mode != _screenMode) {
      final prevCore = _coreMode(_screenMode);
      _screenMode = mode;
      if (pushToCore && _coreMode(mode) != prevCore) {
        EmulatorBridge.setScreenLayout(_coreMode(mode));
      }
    }
    _syncMirror();
  }

  /// Re-applies the screen layout once the view has settled at its NEW size. Rotating or
  /// resizing used to leave the core drawing for the old size (the same mode in both
  /// orientations never got re-sent), so after the dust settles we force a recompute.
  void _scheduleLayoutRefresh({bool nudge = true}) {
    _layoutRefreshTimer?.cancel();
    _layoutRefreshTimer = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted || _quitting) return;
      if (!await EmulatorBridge.isReady()) return;
      // Every core can be left drawing at the old size after a rotation, so the surface
      // refresh below runs for all of them; only dual-screen systems also re-send a layout.
      if (!widget.system.isDualScreen) {
        EmulatorBridge.refreshVideo();
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (!mounted || _quitting) return;
        EmulatorBridge.refreshVideo();
        return;
      }
      final mode = _coreMode(_screenMode);
      if (nudge) {
        final alt = widget.system.screenModes
            .map((m) => m.id)
            .firstWhere((id) => id != mode, orElse: () => mode);
        if (alt != mode) {
          EmulatorBridge.setScreenLayout(alt);
          await Future<void>.delayed(const Duration(milliseconds: 90));
          if (!mounted || _quitting) return;
        }
      }
      EmulatorBridge.setScreenLayout(_coreMode(_screenMode));
      EmulatorBridge.refreshVideo();
      // Second pass once the resized surface has surely settled.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted || _quitting) return;
      EmulatorBridge.refreshVideo();
    });
  }

  Future<void> _persistScreenProfile() async {
    final prefs = _prefs;
    final p = _profiles[_screenCtx];
    if (prefs != null && p != null) {
      await ScreenLayouts.save(prefs, _sys, _screenCtx, p);
    }
  }

  /// Preview while dragging: only a ghost outline moves, the emulator view is NOT resized on
  /// every frame (that resizing was the glitching). The real picture jumps there on release.
  ScreenProfile? _pendingEdit;
  Rect? _editGhost;

  void _updateScreenEdit({Offset delta = Offset.zero, double? scale}) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final sc = _screenCtx;
    final committed = _profiles[sc] ?? const ScreenProfile();
    var p = _pendingEdit ?? committed;
    p = p.copyWith(
      scale: (scale ?? p.scale).clamp(ScreenLayouts.minScale, 1.0),
    );
    // Work out the room available at this size with no offset applied.
    final keepScale = _screenScale, keepDx = _screenDx, keepDy = _screenDy;
    _screenScale = p.scale;
    _screenDx = 0;
    _screenDy = 0;
    final base = _screenRect(size, mq.padding);
    final minDx = -base.left / size.width;
    final maxDx = math.max(
      minDx,
      (size.width - base.width - base.left) / size.width,
    );
    final minDy = -base.top / size.height;
    final maxDy = math.max(
      minDy,
      (size.height - base.height - base.top) / size.height,
    );
    final dx = (p.dx + delta.dx / size.width).clamp(minDx, maxDx).toDouble();
    final dy = (p.dy + delta.dy / size.height).clamp(minDy, maxDy).toDouble();
    p = p.copyWith(dx: dx, dy: dy);
    _pendingEdit = p;
    _screenDx = dx;
    _screenDy = dy;
    _editGhost = _screenRect(size, mq.padding);
    _screenScale = keepScale;
    _screenDx = keepDx;
    _screenDy = keepDy;
    setState(() {});
  }

  void _commitScreenEdit() {
    final p = _pendingEdit;
    if (p == null) return;
    _profiles[_screenCtx] = p;
    _screenScale = p.scale;
    _screenDx = p.dx;
    _screenDy = p.dy;
    _pendingEdit = null;
    _editGhost = null;
    _rebuildControls();
    _persistScreenProfile();
    setState(() {});
  }

  Rect _nudge(Rect r, Size size) {
    if (_screenDx == 0 && _screenDy == 0) return r;
    final left = (r.left + _screenDx * size.width)
        .clamp(0.0, math.max(0.0, size.width - r.width))
        .toDouble();
    final top = (r.top + _screenDy * size.height)
        .clamp(0.0, math.max(0.0, size.height - r.height))
        .toDouble();
    return Rect.fromLTWH(left, top, r.width, r.height);
  }

  Rect _shrink(Rect r, {required bool keepTop}) {
    final k = _screenScale.clamp(ScreenLayouts.minScale, 1.0).toDouble();
    if (k >= 0.999) return r;
    final w = r.width * k;
    final h = r.height * k;
    return Rect.fromLTWH(
      r.left + (r.width - w) / 2,
      keepTop ? r.top : r.top + (r.height - h) / 2,
      w,
      h,
    );
  }

  Rect _screenRect(Size size, EdgeInsets pad) {
    final controlsHidden = (_gamepad || _hideControls) && !_editMode;

    // 1. Flip Tabletop Posture (half-opened horizontal hinge)
    if (_fold.isFlipTabletop) {
      final hinge = _fold.horizontalHinge!;
      final upperHeight = (hinge.top - pad.top).clamp(80.0, size.height);
      final aspect = _pictureAspect;
      final fitW = (upperHeight * aspect).clamp(0.0, size.width);
      final fitH = (fitW / aspect).clamp(0.0, upperHeight);
      return Rect.fromLTWH(
        (size.width - fitW) / 2,
        pad.top + (upperHeight - fitH) / 2,
        fitW,
        fitH,
      );
    }

    // 2. Landscape Posture
    if (!_portrait) {
      return _nudge(_shrink(Offset.zero & size, keepTop: false), size);
    }

    // 3. Portrait Posture
    final aspect = _pictureAspect;
    if (controlsHidden) {
      final availH = (size.height - pad.top - pad.bottom).clamp(
        120.0,
        size.height,
      );
      var fitW = size.width;
      var fitH = fitW / aspect;
      if (fitH > availH) {
        fitH = availH;
        fitW = fitH * aspect;
      }
      return _nudge(
        _shrink(
          Rect.fromLTWH(
            (size.width - fitW) / 2,
            pad.top + (availH - fitH) / 2,
            fitW,
            fitH,
          ),
          keepTop: false,
        ),
        size,
      );
    }

    final maxH = size.height * _settings.portraitMaxHeight;
    var fitW = size.width;
    var fitH = fitW / aspect;
    if (fitH > maxH) {
      fitH = maxH;
      fitW = fitH * aspect;
    }
    return _nudge(
      _shrink(
        Rect.fromLTWH((size.width - fitW) / 2, pad.top, fitW, fitH),
        keepTop: true,
      ),
      size,
    );
  }

  String get _layoutKey {
    final mode = _fold.isFlipTabletop
        ? 'flip'
        : (_fold.isBookFold
              ? 'fold_${_portrait ? 'p' : 'l'}'
              : (_portrait ? 'p' : 'l'));
    return 'layout_v${_layoutVersion}_${_sys}_$mode';
  }

  String _controlsSig(Size size, EdgeInsets pad) =>
      '$_layoutKey|$_screenMode|${_screenScale.toStringAsFixed(2)}|'
      '${size.width.round()}x${size.height.round()}|'
      '${pad.left.round()},${pad.top.round()},${pad.right.round()},${pad.bottom.round()}';

  /// Builds the default controls for the CURRENT orientation, then applies that orientation's
  /// saved custom layout (portrait and landscape are stored under separate keys).
  void _buildControlsNow() {
    _controls = _defaultControls();
    _applySavedLayout();
    final mq = MediaQuery.of(context);
    _builtFor = _controlsSig(mq.size, mq.padding);
  }

  void _rebuildControls() {
    _buildControlsNow();
    if (mounted) setState(() {});
  }

  ControlConfig _place({
    required Size screen,
    required String id,
    String label = '',
    int keyCode = 0,
    ControlKind kind = ControlKind.button,
    required double leftPx,
    required double topPx,
    double? size,
  }) {
    final cfg = ControlConfig(
      id: id,
      label: label,
      keyCode: keyCode,
      kind: kind,
      x: 0,
      y: 0,
      size: size,
    );
    final maxLeft = (screen.width - cfg.width).clamp(0.0, screen.width);
    final maxTop = (screen.height - cfg.height).clamp(0.0, screen.height);
    cfg.x = screen.width > 0 ? (leftPx.clamp(0.0, maxLeft) / screen.width) : 0;
    cfg.y = screen.height > 0 ? (topPx.clamp(0.0, maxTop) / screen.height) : 0;
    return cfg;
  }

  List<ControlConfig> _defaultControls() {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final pad = mq.padding;
    final rect = _screenRect(size, pad);

    final sys = widget.system;
    final ps = sys.faceStyle == FaceStyle.playstation;
    final isGbFamily =
        sys.type == ConsoleType.nes ||
        sys.type == ConsoleType.gb ||
        sys.type == ConsoleType.gbc ||
        sys.type == ConsoleType.gba;
    final analog = sys.hasAnalog;
    final padSpec = sys.pad;
    // N64 C buttons and the PS1 DualShock right stick: a second stick on the right analog axis.
    final dualStick = padSpec?.cStick == true || sys.type == ConsoleType.ps1;

    final double areaTop;
    final double areaBottom = size.height - pad.bottom - 12.0;
    if (_fold.isFlipTabletop) {
      areaTop = _fold.horizontalHinge!.bottom + 8.0;
    } else if (_portrait) {
      areaTop = rect.bottom + 12.0;
    } else {
      areaTop = pad.top + 10.0;
    }

    final areaHeight = (areaBottom - areaTop).clamp(140.0, size.height);
    final sideMargin = (_portrait || _fold.isFlipTabletop)
        ? 16.0
        : (pad.left > 16 ? pad.left : 20.0);
    final rightMargin = (_portrait || _fold.isFlipTabletop)
        ? 16.0
        : (pad.right > 16 ? pad.right : 20.0);

    final leftPanelRight = _fold.isBookFold
        ? (_fold.verticalHinge!.left - 12.0)
        : (size.width * 0.44);
    final rightPanelLeft = _fold.isBookFold
        ? (_fold.verticalHinge!.right + 12.0)
        : (size.width * 0.56);

    final compact = areaHeight < 250 || size.width < 380;
    final dpadSize = analog
        ? (compact ? 110.0 : 122.0)
        : (compact ? 126.0 : 138.0);
    final stickSize = compact ? 92.0 : 102.0;
    final btnSize = compact ? 48.0 : 52.0;
    final shoulderSize = compact ? 42.0 : 46.0;
    final pillSize = compact ? 38.0 : 42.0;
    final shoulderW = shoulderSize * 1.45;
    final shoulderH = shoulderSize * 0.72;
    final pillW = pillSize * 1.65;
    final pillH = pillSize * 0.68;

    final list = <ControlConfig>[];

    // ─── 1. Bottom Center: Select & Start Pills ───
    final pillTop = areaBottom - pillH;
    const pillGap = 16.0;
    final centerX = size.width / 2;

    // Systems with their own pad (N64 / Sega) can drop SELECT or rename the pills.
    final showSelect = padSpec?.hasSelect ?? true;
    final showStart = padSpec?.hasStart ?? true;
    final bothPills = showSelect && showStart;
    if (showSelect) {
      list.add(
        _place(
          screen: size,
          id: 'select',
          label: padSpec?.selectLabel ?? 'SELECT',
          keyCode: EmulatorBridge.keySelect,
          kind: ControlKind.pill,
          leftPx: bothPills
              ? centerX - pillGap / 2 - pillW
              : centerX - pillW / 2,
          topPx: pillTop,
          size: pillSize,
        ),
      );
    }
    if (showStart) {
      list.add(
        _place(
          screen: size,
          id: 'start',
          label: padSpec?.startLabel ?? 'START',
          keyCode: EmulatorBridge.keyStart,
          kind: ControlKind.pill,
          leftPx: bothPills ? centerX + pillGap / 2 : centerX - pillW / 2,
          topPx: pillTop,
          size: pillSize,
        ),
      );
    }

    final faceClusterSize = padSpec != null
        ? (((btnSize * 2) + 26.0) * padSpec.faceScale)
        : isGbFamily
        ? (btnSize * 2.25)
        : ((btnSize * 2) + 26.0);
    final double dpadLeft = sideMargin + 4.0;
    final double dpadTop;
    final double faceTop;

    // Top of the left analog stick; the N64 C-stick is placed on the same row.
    double stickRowTop = 0.0;
    if (_portrait || _fold.isFlipTabletop) {
      // Lower-half thumb reach for portrait & Z Flip tabletop
      if (analog) {
        final stickTop = pillTop - 12.0 - stickSize;
        stickRowTop = stickTop;
        final stickLeft = dpadLeft + (dpadSize - stickSize) / 2;
        list.add(
          _place(
            screen: size,
            id: 'stick',
            kind: ControlKind.stick,
            leftPx: stickLeft,
            topPx: stickTop,
            size: stickSize,
          ),
        );
        // Clean 16px vertical clearance between D-Pad and Analog Stick
        dpadTop = stickTop - 16.0 - dpadSize;
        final leftSpanCenter = dpadTop + (dpadSize + 16.0 + stickSize) * 0.52;
        // N64: face buttons mirror the D-pad row, with the C-stick under them.
        // PS1: the right stick sits right under the face cluster, so lift the cluster until its
        // lowest button (X) is a full thumb-width above the stick, not just 16 px.
        final mirrored = dpadTop + (dpadSize - faceClusterSize) / 2;
        faceTop = dualStick
            ? (sys.type == ConsoleType.ps1
                  ? math.min(mirrored, stickTop - 30.0 - faceClusterSize)
                  : mirrored)
            : leftSpanCenter - (faceClusterSize / 2);
      } else {
        dpadTop = pillTop - 18.0 - dpadSize;
        faceTop = dpadTop + (dpadSize - faceClusterSize) / 2;
      }
    } else {
      // Natural lower-corner thumb arc for landscape handheld play with clean D-Pad/Stick separation
      final thumbBottom = areaBottom - 6.0;
      if (analog) {
        final stickTop = thumbBottom - stickSize;
        stickRowTop = stickTop;
        final stickMaxLeft = leftPanelRight - stickSize;
        final stickLeft = (dpadLeft + dpadSize * 0.78)
            .clamp(math.min(sideMargin, stickMaxLeft), stickMaxLeft)
            .toDouble();
        list.add(
          _place(
            screen: size,
            id: 'stick',
            kind: ControlKind.stick,
            leftPx: stickLeft,
            topPx: stickTop,
            size: stickSize,
          ),
        );
        // Lift D-Pad slightly above the stick so their circular housings never overlap
        dpadTop = math.max(
          areaTop + shoulderH + 10.0,
          stickTop - dpadSize * 0.94,
        );
      } else {
        dpadTop = thumbBottom - dpadSize - 4.0;
      }
      faceTop = dualStick
          ? math.max(
              areaTop + shoulderH + 10.0,
              // PS1: full clearance so the right stick never touches X / Square.
              stickRowTop -
                  faceClusterSize * (sys.type == ConsoleType.ps1 ? 1.06 : 0.94),
            )
          : thumbBottom - faceClusterSize - 4.0;
    }

    list.add(
      _place(
        screen: size,
        id: 'dpad',
        kind: ControlKind.dpad,
        leftPx: dpadLeft,
        topPx: dpadTop,
        size: dpadSize,
      ),
    );

    // The 6-button Sega cluster is wide: on narrow screens the allowed range can invert, and
    // num.clamp throws then (that left Genesis stuck on "building touch controls").
    final faceMaxLeft = size.width - rightMargin - faceClusterSize;
    final faceLeft = (size.width - rightMargin - faceClusterSize - 4.0)
        .clamp(math.min(rightPanelLeft, faceMaxLeft), faceMaxLeft)
        .toDouble();

    list.add(
      _place(
        screen: size,
        id: 'face_cluster',
        kind: ControlKind.faceCluster,
        leftPx: faceLeft,
        topPx: faceTop,
        size: faceClusterSize,
      ),
    );
    final clusterTop = math.min(dpadTop, faceTop);

    // N64 C buttons: a second stick on the right analog axis.
    if (dualStick) {
      final double cLeft = (_portrait || _fold.isFlipTabletop)
          ? faceLeft + faceClusterSize / 2 - stickSize / 2
          : (faceLeft +
                    faceClusterSize *
                        (sys.type == ConsoleType.ps1 ? -0.10 : 0.22) -
                    stickSize)
                .clamp(
                  math.min(
                    // PS1 may sit a little past the centre line so it can clear the Square button.
                    sys.type == ConsoleType.ps1
                        ? size.width * 0.5
                        : rightPanelLeft,
                    size.width - rightMargin - stickSize,
                  ),
                  size.width - rightMargin - stickSize,
                )
                .toDouble();
      list.add(
        _place(
          screen: size,
          id: 'cstick',
          kind: ControlKind.stick,
          leftPx: cLeft,
          topPx: stickRowTop,
          size: stickSize,
        ),
      );
    }

    // ─── 4. Shoulder Buttons (L1 / R1 / L2 / R2) ───
    // Portrait pads with two shoulders per side (N64: L + Z, PS1: L1/L2 + R1/R2) stack the second
    // one under the first, otherwise it slides under the floating menu bar centred on the shoulder row.
    final bool stackLeftShoulders =
        (_portrait || _fold.isFlipTabletop) &&
        ((padSpec != null && padSpec.left.length > 1) ||
            (padSpec == null && sys.hasL2R2));
    final double shoulderTop = (_portrait || _fold.isFlipTabletop)
        ? math.max(
            areaTop,
            clusterTop -
                16.0 -
                shoulderH -
                (stackLeftShoulders ? shoulderH + 8.0 : 0.0),
          )
        : areaTop;

    _shoulderTopPx = shoulderTop;

    // The NES pad has no shoulder buttons at all.
    if (sys.type == ConsoleType.nes) return list;

    // Systems with their own pad spec (N64 / Sega): shoulders come straight from the spec
    // (Master System, Game Gear and Genesis have none).
    if (padSpec != null) {
      for (var i = 0; i < padSpec.left.length; i++) {
        final b = padSpec.left[i];
        list.add(
          _place(
            screen: size,
            id: b.id,
            kind: ControlKind.shoulder,
            label: b.label,
            keyCode: b.key,
            leftPx: stackLeftShoulders
                ? sideMargin
                : sideMargin + i * (shoulderW + 8.0),
            topPx: stackLeftShoulders && i > 0
                ? shoulderTop + (shoulderH + 8.0) * i
                : shoulderTop,
            size: shoulderSize,
          ),
        );
      }
      for (var i = 0; i < padSpec.right.length; i++) {
        final b = padSpec.right[i];
        list.add(
          _place(
            screen: size,
            id: b.id,
            kind: ControlKind.shoulder,
            label: b.label,
            keyCode: b.key,
            leftPx:
                size.width - rightMargin - shoulderW - i * (shoulderW + 8.0),
            topPx: shoulderTop,
            size: shoulderSize,
          ),
        );
      }
      return list;
    }

    final l1 = _place(
      screen: size,
      id: 'l1',
      kind: ControlKind.shoulder,
      label: ps ? 'L1' : 'L',
      keyCode: EmulatorBridge.keyL1,
      leftPx: sideMargin,
      topPx: shoulderTop,
      size: shoulderSize,
    );
    final r1 = _place(
      screen: size,
      id: 'r1',
      kind: ControlKind.shoulder,
      label: ps ? 'R1' : 'R',
      keyCode: EmulatorBridge.keyR1,
      leftPx: size.width - rightMargin - shoulderW,
      topPx: shoulderTop,
      size: shoulderSize,
    );
    list.addAll([l1, r1]);

    if (sys.hasL2R2) {
      if (_portrait || _fold.isFlipTabletop) {
        list.add(
          _place(
            screen: size,
            id: 'l2',
            kind: ControlKind.shoulder,
            label: 'L2',
            keyCode: EmulatorBridge.keyL2,
            leftPx: sideMargin,
            topPx: shoulderTop + shoulderH + 8.0,
            size: shoulderSize,
          ),
        );
        list.add(
          _place(
            screen: size,
            id: 'r2',
            kind: ControlKind.shoulder,
            label: 'R2',
            keyCode: EmulatorBridge.keyR2,
            leftPx: size.width - rightMargin - shoulderW,
            topPx: shoulderTop + shoulderH + 8.0,
            size: shoulderSize,
          ),
        );
      } else {
        list.add(
          _place(
            screen: size,
            id: 'l2',
            kind: ControlKind.shoulder,
            label: 'L2',
            keyCode: EmulatorBridge.keyL2,
            leftPx: sideMargin,
            topPx: shoulderTop,
            size: shoulderSize,
          ),
        );
        list.add(
          _place(
            screen: size,
            id: 'r2',
            kind: ControlKind.shoulder,
            label: 'R2',
            keyCode: EmulatorBridge.keyR2,
            leftPx: size.width - rightMargin - shoulderW,
            topPx: shoulderTop,
            size: shoulderSize,
          ),
        );
        final row2Top = shoulderTop + shoulderH + 10.0;
        l1.y = row2Top / size.height;
        r1.y = row2Top / size.height;
      }
    }

    return list;
  }

  void _applySavedLayout() {
    final saved = _prefs?.getString(_layoutKey);
    if (saved == null) return;
    try {
      final List decoded = jsonDecode(saved);
      for (final item in decoded) {
        final match = _controls.where((c) => c.id == item['id']).firstOrNull;
        if (match != null) {
          match.x = (item['x'] as num).toDouble().clamp(0.0, 0.98).toDouble();
          match.y = (item['y'] as num).toDouble().clamp(0.0, 0.98).toDouble();
          match.size = (item['size'] as num)
              .toDouble()
              .clamp(match.minSize, match.maxSize)
              .toDouble();
        }
      }
    } catch (_) {
      // corrupt layout -> keep defaults
    }
  }

  Future<void> _saveCustomLayout() async {
    if (_controls.isEmpty) return;
    final encoded = jsonEncode(_controls.map((c) => c.toJson()).toList());
    await _prefs?.setString(_layoutKey, encoded);
  }

  /// Unfreezes the game after an editor (controls or screen) closes.
  void _resumeAfterEdit() {
    if (_quitting || _menuOpen || _editMode || _screenEdit) return;
    EmulatorBridge.setUiCaptured(false);
    if (_autoPaused) return; // still waiting for A / B
    EmulatorBridge.setPaused(false);
    _playClock.start();
  }

  /// Leaves edit mode WITHOUT keeping the changes, and unfreezes the game.
  Future<void> _cancelEdit() async {
    final key = _editBackupKey;
    if (key != null) {
      if (_editBackupValue == null) {
        await _prefs?.remove(key);
      } else {
        await _prefs?.setString(key, _editBackupValue!);
      }
    }
    if (!mounted) return;
    _selectedButtonId = null;
    _editMode = false;
    _buildControlsNow();
    setState(() {});
    EmulatorBridge.setUiCaptured(false);
    EmulatorBridge.setPaused(false);
    _playClock.start();
  }

  Future<void> _resetLayout() async {
    await _prefs?.remove(_layoutKey);
    _selectedButtonId = null;
    _rebuildControls();
  }

  // ───────── State / save helpers ─────────

  /// slot 0 = auto-save
  Future<String> _getStatePath(int slot) async {
    final statesDir = StorageService.instance.statesDir;
    if (!await statesDir.exists()) await statesDir.create(recursive: true);
    await _legacyMigrated; // old un-keyed states are copied over first, never loaded directly
    final label = slot == 0 ? 'auto' : 'slot$slot';
    return StatePaths.path(statesDir, _romName, _coreKey, label);
  }

  /// Floating pill pinned to the TOP of the screen, so it never covers the on-screen
  /// buttons / sticks while playing.
  /// On a half-open Z Flip (tabletop) Flutter would open dialogs and sheets in the UPPER half, where
  /// the game picture is. This point lies in the lower half, so they open under the hinge instead.
  Offset? get _menuAnchor {
    if (!_fold.isFlipTabletop) return null;
    return Offset(
      _lastScreenSize.width / 2,
      _fold.horizontalHinge!.bottom + 8.0,
    );
  }

  SnackBar _topSnack(
    Widget content,
    Duration duration, {
    SnackBarAction? action,
  }) {
    final mq = MediaQuery.of(context);
    // Tabletop: the pill sits just under the hinge instead of over the game picture.
    final topLimit = _fold.isFlipTabletop
        ? _fold.horizontalHinge!.bottom + 8.0
        : mq.padding.top;
    final bottom = (mq.size.height - topLimit - 88).clamp(0.0, 4000.0);
    return SnackBar(
      content: content,
      duration: duration,
      action: action,
      behavior: SnackBarBehavior.floating,
      dismissDirection: DismissDirection.up,
      margin: EdgeInsets.fromLTRB(24, 0, 24, bottom),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  /// Shows [bar] and ALWAYS closes it when its duration is over. A SnackBar with an action (such as
  /// "Start over" / "Undo") does not time out by itself on current Flutter versions, so it stayed
  /// on screen until the player swiped it away.
  void _showTopSnack(SnackBar bar) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final ctl = messenger.showSnackBar(bar);
    var closed = false;
    ctl.closed.whenComplete(() => closed = true);
    Timer(bar.duration + const Duration(milliseconds: 300), () {
      if (closed) return;
      try {
        ctl.close();
      } catch (_) {}
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    _showTopSnack(_topSnack(Text(msg), const Duration(milliseconds: 1600)));
  }

  Future<void> _saveState(int slot, {bool silent = false}) async {
    if (slot == 0 && silent && _awaitingResumeChoice) return;
    final ok = await EmulatorBridge.saveState(await _getStatePath(slot));
    if (ok && slot > 0) {
      final thumb = _menuSnapshot ?? await _captureThumb();
      final tf = File(await _getThumbPath(slot));
      try {
        if (thumb != null) {
          await tf.writeAsBytes(thumb, flush: true);
        } else if (await tf.exists()) {
          await tf.delete(); // don't leave a thumbnail from an older save
        }
      } catch (_) {}
    }
    if (silent) return;
    _toast(
      ok
          ? (slot == 0 ? 'Auto-save written' : 'Saved to slot $slot')
          : 'Save failed (game still loading?)',
    );
  }

  /// Where the "state before the last load" lives so an accidental load can be undone.
  Future<String> _undoStatePath() async {
    final statesDir = StorageService.instance.statesDir;
    if (!await statesDir.exists()) await statesDir.create(recursive: true);
    return StatePaths.path(statesDir, _romName, _coreKey, 'undo');
  }

  Future<bool> _loadState(
    int slot, {
    bool undoable = true,
    bool quiet = false,
    bool announce = true,
    String?
    pathOverride, // a state file outside the numbered slots (jedTimeMachine)
  }) async {
    final path = pathOverride ?? await _getStatePath(slot);
    if (!await File(path).exists()) {
      if (!quiet)
        _toast(slot == 0 ? 'No auto-save yet' : 'Slot $slot is empty');
      return false;
    }
    // Keep the current progress so a mis-tapped "Load" can be taken back.
    var haveUndo = false;
    if (undoable) {
      try {
        haveUndo = await EmulatorBridge.saveState(await _undoStatePath());
      } catch (_) {}
    }
    final ok = await EmulatorBridge.loadState(path);
    if (!mounted) return ok;
    if (ok && !announce) return ok;
    if (!ok || !haveUndo) {
      if (ok || !quiet) _toast(ok ? 'Loaded' : 'Load failed');
      return ok;
    }
    _showTopSnack(
      _topSnack(
        const Text('Loaded'),
        const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            final undone = await EmulatorBridge.loadState(
              await _undoStatePath(),
            );
            _toast(undone ? 'Load undone' : 'Undo failed');
          },
        ),
      ),
    );
    return true;
  }

  Future<void> _quit() async {
    if (_quitting) return;
    _quitting = true;
    _playClock.stop();
    await _flushPlayTime();
    if (_autoSaveOnQuit && !widget.bootBios && !_awaitingResumeChoice) {
      try {
        await EmulatorBridge.saveState(await _getStatePath(0));
      } catch (_) {}
    }
    await EmulatorBridge.stopGame();
    if (mounted) Navigator.pop(context);
  }

  // ───────── Cheats ─────────

  Future<void> _persistCheats() async {
    await _prefs?.setString(
      'cheats_$_romName',
      jsonEncode(_cheats.map((c) => c.toJson()).toList()),
    );
  }

  Future<void> _reapplyCheatsWhenReady() async {
    if (!_cheats.any((c) => c.enabled)) return;
    if (!await EmulatorBridge.waitUntilReady()) return;
    await Future<void>.delayed(const Duration(seconds: 1));
    // The core can still be settling right after its first frame: retry a few times.
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!mounted) return;
      if (await _syncCheats()) return;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  /// Pushes the full cheat list to the core (see EmulatorBridge.setCheats).
  /// [removed]: a cheat just deleted from the list. It is still sent (disabled) so cores whose
  /// native layer cannot clear the cheat table also switch it off.
  Future<bool> _syncCheats({Cheat? removed}) => EmulatorBridge.setCheats([
    for (final c in _cheats) (idx: c.idx, enabled: c.enabled, code: c.code),
    if (removed != null) (idx: removed.idx, enabled: false, code: removed.code),
  ]);

  /// Adds a cheat to the list (not synced/persisted yet). Multi-line codes are joined with '+'
  /// the way libretro cores expect. Returns null for empty or duplicate codes.
  Cheat? _addCheat(String name, String rawCode, {bool enabled = true}) {
    final code = CheatDb.normalizeCode(rawCode);
    if (code.isEmpty || _cheats.any((c) => c.code == code)) return null;
    final nextIdx = _cheats.isEmpty
        ? 0
        : _cheats.map((c) => c.idx).reduce((a, b) => a > b ? a : b) + 1;
    final trimmed = name.trim();
    final cheat = Cheat(
      idx: nextIdx,
      name: trimmed.isEmpty ? 'Cheat ${nextIdx + 1}' : trimmed,
      code: code,
      enabled: enabled,
    );
    _cheats.add(cheat);
    return cheat;
  }

  /// Sync + save after any change; tells the player when the core did not accept the list.
  Future<void> _commitCheats({Cheat? removed}) async {
    final ok = await _syncCheats(removed: removed);
    await _persistCheats();
    if (!ok && mounted) _toast('The core did not accept the cheat change');
  }

  Future<void> _showCheatDialog() {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    return showDialog<void>(
      context: context,
      anchorPoint: _menuAnchor,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          // Every color / font comes from the active style (Classic or Dot) and Light / Dark.
          final c = XEmuColors.of(ctx);
          final mono = c.labelFont;
          final note = CheatDb.supportNote(widget.system.type);
          final mq = MediaQuery.of(ctx);
          final landscape = mq.size.width > mq.size.height;

          Future<void> add() async {
            final cheat = _addCheat(nameCtrl.text, codeCtrl.text);
            if (cheat == null) {
              if (codeCtrl.text.trim().isNotEmpty) {
                _toast('That code is already in your list');
              }
              return;
            }
            nameCtrl.clear();
            codeCtrl.clear();
            setDlg(() {});
            await _commitCheats();
          }

          Future<void> browse() async {
            final picked = await showCheatBrowser(
              ctx,
              anchorPoint: _menuAnchor,
              system: widget.system,
              romName: _romName,
              alreadyAdded: (code) => _cheats.any((x) => x.code == code),
            );
            if (picked == null || picked.isEmpty) return;
            var added = 0;
            for (final e in picked) {
              if (_addCheat(e.desc, e.code) != null) added++;
            }
            setDlg(() {});
            if (added > 0) await _commitCheats();
            if (mounted) {
              _toast(
                added == 0
                    ? 'Those cheats were already added'
                    : 'Added $added cheat${added == 1 ? '' : 's'}',
              );
            }
          }

          final nameField = TextField(
            controller: nameCtrl,
            style: TextStyle(color: c.primaryText, fontFamily: mono),
            cursorColor: c.accent,
            decoration: const InputDecoration(
              hintText: 'Name (e.g. Infinite HP)',
            ),
          );
          final codeField = TextField(
            controller: codeCtrl,
            style: TextStyle(color: c.primaryText, fontFamily: mono),
            cursorColor: c.accent,
            decoration: const InputDecoration(
              hintText: 'GameShark / Action Replay code',
            ),
          );

          // A plain Dialog (not AlertDialog): AlertDialog reserves fixed title / actions bands that
          // ate the whole height in landscape. Here only the list scrolls; the header and the add
          // form stay compact and Close lives in the header.
          return Dialog(
            insetPadding: EdgeInsets.symmetric(
              horizontal: 24,
              vertical: landscape ? 8 : 24,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: landscape ? 640 : 440,
                maxHeight: mq.size.height - (landscape ? 16 : 48),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  landscape ? 6 : 14,
                  12,
                  landscape ? 10 : 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Cheats',
                            style: TextStyle(
                              color: c.primaryText,
                              fontFamily: c.displayFont,
                              fontSize: c.isDot ? 22 : 19,
                              fontWeight: c.isDot
                                  ? FontWeight.w900
                                  : FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          icon: Icon(Icons.close, color: c.primaryText),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: landscape
                          ? Row(
                              children: [
                                Expanded(child: nameField),
                                const SizedBox(width: 10),
                                Expanded(child: codeField),
                              ],
                            )
                          : Column(
                              children: [
                                nameField,
                                const SizedBox(height: 10),
                                codeField,
                              ],
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Row(
                        children: [
                          Flexible(
                            child: TextButton.icon(
                              icon: const Icon(
                                Icons.cloud_download_outlined,
                                size: 18,
                              ),
                              label: const Text(
                                'Browse database',
                                overflow: TextOverflow.ellipsis,
                              ),
                              onPressed: browse,
                            ),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add & enable'),
                            onPressed: add,
                          ),
                        ],
                      ),
                    ),
                    if (note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 8),
                        child: Text(
                          note,
                          style: TextStyle(
                            color: c.warn,
                            fontFamily: mono,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    Divider(color: c.hairline, height: 16),
                    Flexible(
                      child: _cheats.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'No cheats for this game yet.',
                                style: TextStyle(
                                  color: c.secondaryText,
                                  fontFamily: mono,
                                ),
                              ),
                            )
                          : ListView(
                              shrinkWrap: true,
                              children: [
                                for (final cheat in List<Cheat>.from(_cheats))
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      cheat.name,
                                      style: TextStyle(color: c.primaryText),
                                    ),
                                    subtitle: Text(
                                      cheat.code,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: c.tertiaryText,
                                        fontFamily: mono,
                                        fontSize: 11,
                                      ),
                                    ),
                                    leading: Switch(
                                      value: cheat.enabled,
                                      onChanged: (v) async {
                                        cheat.enabled = v;
                                        setDlg(() {});
                                        await _commitCheats();
                                      },
                                    ),
                                    trailing: IconButton(
                                      tooltip: 'Delete cheat',
                                      icon: Icon(
                                        Icons.delete_outline,
                                        color: c.danger,
                                      ),
                                      onPressed: () async {
                                        _cheats.remove(cheat);
                                        setDlg(() {});
                                        await _commitCheats(removed: cheat);
                                      },
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ───────── Screen layout picker (NDS / 3DS) ─────────

  Future<void> _showScreenLayoutPicker() {
    return showModalBottomSheet<void>(
      context: context,
      anchorPoint: _menuAnchor,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: XEmuColors.of(context).groupedBg,
      constraints: const BoxConstraints(maxWidth: 760),
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setSheet) {
            final c = XEmuColors.of(ctx);
            final sc = _screenCtx;
            final profile = _profiles[sc] ?? const ScreenProfile();
            final rec = ScreenLayouts.recommended(
              portrait: sc.isPortrait,
              gamepad: sc.isController,
            );
            final premade = [
              for (final id in ScreenLayouts.premade(widget.system, sc))
                if (!(sc.isPortrait && _landscapeOnly(id))) id,
            ];
            final more = [
              for (final m in widget.system.screenModes)
                if (!premade.contains(m.id) &&
                    !(sc.isPortrait && _landscapeOnly(m.id)))
                  m.id,
            ];

            Future<void> apply(ScreenProfile p, {bool persist = true}) async {
              final before = _screenMode;
              _profiles[sc] = p;
              _resolveScreenProfile();
              _rebuildControls();
              if (persist || _screenMode != before) {
                _scheduleLayoutRefresh(nudge: false);
              }
              setSheet(() {});
              final prefs = _prefs;
              if (persist && prefs != null) {
                await ScreenLayouts.save(prefs, _sys, sc, p);
              }
            }

            Widget modeRow(String id) => MenuCheckRow(
              title: ScreenLayouts.name(id),
              subtitle: ScreenLayouts.blurb(id, sc),
              tag: id == rec ? 'Recommended' : null,
              selected: _screenMode == id,
              // Tapping the recommended row goes back to "follow the premade layout".
              onTap: () => apply(
                id == rec
                    ? profile.copyWith(clearMode: true)
                    : profile.copyWith(modeId: id),
              ),
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Screen layout',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      color: c.primaryText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${sc.label} view · saved separately for each view',
                    style: TextStyle(fontSize: 12.5, color: c.secondaryText),
                  ),
                  MenuSection(
                    title: 'Premade for this view',
                    child: MenuGroupCard(
                      children: [for (final id in premade) modeRow(id)],
                    ),
                  ),
                  if (more.isNotEmpty)
                    MenuSection(
                      title: 'More arrangements',
                      child: MenuGroupCard(
                        children: [for (final id in more) modeRow(id)],
                      ),
                    ),
                  MenuSection(
                    title: 'Make it yours',
                    child: MenuGroupCard(
                      children: [
                        MenuSliderRow(
                          title: 'Picture size',
                          subtitle: sc.isController
                              ? 'Touch buttons are hidden, so the picture can use the whole screen'
                              : 'Smaller picture leaves more room for the buttons',
                          value: profile.scale,
                          min: ScreenLayouts.minScale,
                          max: 1.0,
                          divisions: 10,
                          format: (v) => '${(v * 100).round()}%',
                          onChanged: (v) =>
                              apply(profile.copyWith(scale: v), persist: false),
                          onChangeEnd: (v) async {
                            _scheduleLayoutRefresh(nudge: false);
                            final prefs = _prefs;
                            if (prefs != null) {
                              await ScreenLayouts.save(
                                prefs,
                                _sys,
                                sc,
                                _profiles[sc] ?? profile,
                              );
                            }
                          },
                        ),
                        MenuRow(
                          icon: Icons.open_with_rounded,
                          badgeColor: const Color(0xFF5856D6),
                          title: 'Move & resize on screen',
                          subtitle: 'Drag the picture anywhere, pinch or use the slider',
                          onTap: () {
                            Navigator.pop(ctx);
                            setState(() {
                              _screenEdit = true;
                              _editBaseScale = _screenScale;
                            });
                          },
                        ),
                        MenuRow(
                          icon: Icons.auto_fix_high,
                          badgeColor: const Color(0xFF007AFF),
                          title: 'Reset this view to recommended',
                          showChevron: false,
                          onTap: () => apply(const ScreenProfile()),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                    child: Text(
                      'Rotate the device or connect a controller to edit those views. '
                      'Touch the game picture directly to use the touch screen.',
                      style: TextStyle(color: c.secondaryText, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ───────── Quick menu ─────────

  Future<void> _openQuickMenu() async {
    if (_menuOpen || _quitting) return;
    _menuOpen = true;
    // Grab the picture while the surface is still live; it becomes the save-slot thumbnail.
    _menuSnapshot = await _captureThumb();
    if (!mounted || _quitting) {
      _menuSnapshot = null;
      _menuOpen = false;
      return;
    }
    _playClock.stop();
    EmulatorBridge.setPaused(true);
    EmulatorBridge.setUiCaptured(true);
    try {
      try {
        await _refreshSlotTimes();
      } catch (_) {
        // Missing thumbnails/timestamps must never stop the menu from opening.
      }
      if (!mounted) return;
      final mqs = MediaQuery.sizeOf(context);
      final wideMenu = mqs.width >= 640 && mqs.width > mqs.height;
      int selPane = 0;

      List<_MenuPane> buildPanes(BuildContext ctx, StateSetter setSheet) => [
        _MenuPane(
          icon: Icons.save_rounded,
          title: 'Save states',
          child: MenuGroupCard(
            children: [
              SlotPicker(
                selected: _slot,
                times: _slotTimes,
                thumbs: _slotThumbs,
                onSelect: (s) => setSheet(() => _slot = s),
              ),
              MenuRow(
                icon: Icons.save_rounded,
                badgeColor: const Color(0xFF34C759),
                title: 'Save to slot $_slot',
                onTap: () => Navigator.pop(ctx, QuickAction.save),
              ),
              MenuRow(
                icon: Icons.restore_rounded,
                badgeColor: const Color(0xFF007AFF),
                title: 'Load slot $_slot',
                onTap: () => Navigator.pop(ctx, QuickAction.load),
              ),
              MenuRow(
                icon: Icons.history_rounded,
                badgeColor: const Color(0xFF8E8E93),
                title: 'Load auto-save',
                onTap: () => Navigator.pop(ctx, QuickAction.loadAuto),
              ),
              MenuRow(
                icon: Icons.fast_rewind_rounded,
                badgeColor: const Color(0xFF5E5CE6),
                title: 'jedTimeMachine',
                value: (_tm?.entries.isNotEmpty ?? false)
                    ? '${_tm!.entries.length}'
                    : null,
                onTap: () => Navigator.pop(ctx, QuickAction.jedTimeMachine),
              ),
            ],
          ),
        ),
        _MenuPane(
          icon: Icons.tune_rounded,
          title: 'Speed, video & audio',
          child: MenuGroupCard(
            children: [
              MenuSegmentedRow<int>(
                title: 'Fast-forward',
                value: _fastForwardSpeed,
                options: const {1: '1x', 2: '2x', 3: '3x', 4: '4x'},
                onChanged: (v) {
                  setSheet(() => _fastForwardSpeed = v);
                  EmulatorBridge.setFastForward(v);
                },
              ),
              MenuSwitchRow(
                icon: _muted ? Icons.volume_off : Icons.volume_up,
                badgeColor: const Color(0xFFFF9500),
                title: 'Mute',
                value: _muted,
                onChanged: (v) {
                  setSheet(() => _muted = v);
                  EmulatorBridge.setMuted(v);
                },
              ),
              MenuRow(
                icon: Icons.filter_b_and_w,
                badgeColor: const Color(0xFFAF52DE),
                title: 'Video filter',
                value: _settings.filter.label,
                active: _settings.filter != VideoFilter.none,
                onTap: () {
                  final next =
                      VideoFilter.values[(_settings.filter.index + 1) %
                          VideoFilter.values.length];
                  setSheet(() => _settings.filter = next);
                  _prefs?.setInt('set_filter', next.index);
                  EmulatorBridge.setShader(next.name);
                },
              ),
              if (widget.system.isDualScreen)
                MenuRow(
                  icon: Icons.splitscreen,
                  badgeColor: const Color(0xFF5856D6),
                  title: 'Screen layout',
                  value: widget.system.screenModes
                      .firstWhere(
                        (m) => m.id == _screenMode,
                        orElse: () => widget.system.screenModes.first,
                      )
                      .label,
                  onTap: () => Navigator.pop(ctx, QuickAction.layout),
                ),
              MenuRow(
                icon: Icons.restart_alt,
                badgeColor: const Color(0xFFFF9500),
                title: 'Reset game',
                onTap: () => Navigator.pop(ctx, QuickAction.reset),
              ),
            ],
          ),
        ),
        _MenuPane(
          icon: Icons.gamepad_rounded,
          title: 'On-screen controls',
          child: MenuGroupCard(
            children: [
              MenuRow(
                icon: Icons.gamepad,
                badgeColor: const Color(0xFF007AFF),
                title: _editMode ? 'Finish editing' : 'Customize',
                active: _editMode,
                onTap: () => Navigator.pop(ctx, QuickAction.customize),
              ),
              MenuSwitchRow(
                icon: Icons.visibility_off,
                badgeColor: const Color(0xFF8E8E93),
                title: 'Hide controls',
                value: _hideControls,
                onChanged: (v) {
                  setState(() => _hideControls = v);
                  setSheet(() {});
                },
              ),
              MenuSwitchRow(
                icon: Icons.vibration,
                badgeColor: const Color(0xFF34C759),
                title: 'Haptic feedback',
                value: _haptics,
                onChanged: (v) {
                  setState(() => _haptics = v);
                  _prefs?.setBool('ui_haptics', v);
                  setSheet(() {});
                },
              ),
              MenuSliderRow(
                title: 'Button opacity',
                value: _opacity,
                min: 0.2,
                max: 1.0,
                divisions: 8,
                format: (v) => '${(v * 100).round()}%',
                onChanged: (v) {
                  setState(() => _opacity = v);
                  setSheet(() {});
                },
                onChangeEnd: (v) => _prefs?.setDouble('ui_opacity', v),
              ),
            ],
          ),
        ),
        _MenuPane(
          icon: Icons.more_horiz_rounded,
          title: 'More',
          child: MenuGroupCard(
            children: [
              MenuRow(
                icon: Icons.code,
                badgeColor: const Color(0xFF5856D6),
                title: 'Cheats',
                onTap: () => Navigator.pop(ctx, QuickAction.cheats),
              ),
              MenuRow(
                icon: Icons.tune,
                badgeColor: const Color(0xFF8E8E93),
                title: 'Core options',
                onTap: () => Navigator.pop(ctx, QuickAction.coreOptions),
              ),
              MenuSwitchRow(
                icon: Icons.auto_mode,
                badgeColor: const Color(0xFF007AFF),
                title: 'Auto-save on quit',
                value: _autoSaveOnQuit,
                onChanged: (v) {
                  setState(() => _autoSaveOnQuit = v);
                  _prefs?.setBool('autosave_on_quit', v);
                  setSheet(() {});
                },
              ),
            ],
          ),
        ),
        _MenuPane(
          icon: Icons.exit_to_app,
          title: 'Session',
          child: MenuGroupCard(
            children: [
              MenuRow(
                icon: Icons.exit_to_app,
                title: 'Quit game',
                danger: true,
                onTap: () => Navigator.pop(ctx, QuickAction.quit),
              ),
            ],
          ),
        ),
      ];

      final action = wideMenu
          ? await showGeneralDialog<QuickAction>(
              context: context,
              barrierDismissible: false,
              barrierLabel: 'Menu',
              barrierColor: Colors.black,
              transitionDuration: const Duration(milliseconds: 160),
              transitionBuilder: (_, a, __, child) =>
                  FadeTransition(opacity: a, child: child),
              pageBuilder: (ctx, _, __) => CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.gameButtonB): () =>
                      Navigator.pop(ctx, QuickAction.resume),
                },
                child: StatefulBuilder(
                  builder: (ctx, setSheet) {
                    final c = XEmuColors.of(ctx);
                    final panes = buildPanes(ctx, setSheet);
                    final sel = selPane.clamp(0, panes.length - 1);
                    final sideW = (MediaQuery.sizeOf(ctx).width * 0.30).clamp(
                      230.0,
                      320.0,
                    );
                    return Scaffold(
                      backgroundColor: c.groupedBg,
                      appBar: AppBar(
                        backgroundColor: c.groupedBg,
                        toolbarHeight: 48,
                        centerTitle: true,
                        leading: IconButton(
                          tooltip: 'Resume',
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () =>
                              Navigator.pop(ctx, QuickAction.resume),
                        ),
                        title: Text(
                          _displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 17,
                          ),
                        ),
                        actions: [
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: FilledButton.icon(
                              autofocus: true,
                              onPressed: () =>
                                  Navigator.pop(ctx, QuickAction.resume),
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                size: 20,
                              ),
                              label: const Text('Resume'),
                            ),
                          ),
                        ],
                      ),
                      body: SafeArea(
                        top: false,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: sideW,
                              child: ListView(
                                physics: const BouncingScrollPhysics(),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                children: [
                                  for (var i = 0; i < panes.length; i++)
                                    SideRailItem(
                                      icon: panes[i].icon,
                                      label: panes[i].title,
                                      selected: i == sel,
                                      danger: panes[i].title == 'Session',
                                      onTap: () => setSheet(() => selPane = i),
                                    ),
                                ],
                              ),
                            ),
                            VerticalDivider(
                              width: 0.5,
                              thickness: 0.5,
                              color: c.hairline,
                            ),
                            Expanded(
                              child: ListView(
                                key: ValueKey(sel),
                                physics: const BouncingScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  24,
                                ),
                                children: [
                                  MenuSection(
                                    title: panes[sel].title,
                                    child: panes[sel].child,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            )
          : await showModalBottomSheet<QuickAction>(
              context: context,
              anchorPoint: _menuAnchor,
              backgroundColor: XEmuColors.of(context).groupedBg,
              isScrollControlled: true,
              showDragHandle: true,
              constraints: const BoxConstraints(maxWidth: 760),
              builder: (ctx) => SafeArea(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.gameButtonB): () =>
                        Navigator.pop(ctx, QuickAction.resume),
                  },
                  child: StatefulBuilder(
                    builder: (ctx, setSheet) => SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MenuSheetHeader(
                            title: _displayTitle,
                            subtitle:
                                'This session: ${_fmtSession(_playClock.elapsed)}',
                            onResume: () =>
                                Navigator.pop(ctx, QuickAction.resume),
                          ),
                          for (final p in buildPanes(ctx, setSheet))
                            MenuSection(title: p.title, child: p.child),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );

      switch (action) {
        case QuickAction.save:
          await _saveState(_slot);
        case QuickAction.load:
          await _loadState(_slot);
        case QuickAction.loadAuto:
          await _loadState(0);
        case QuickAction.jedTimeMachine:
          await _openJedTimeMachine();
        case QuickAction.cheats:
          await _showCheatDialog();
        case QuickAction.coreOptions:
          if (mounted) {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CoreSettingsScreen(
                  coreLibName: widget.system.coreLibName,
                  live: true,
                ),
              ),
            );
          }
        case QuickAction.layout:
          await _showScreenLayoutPicker();
        case QuickAction.reset:
          await _confirmReset();
        case QuickAction.customize:
          setState(() {
            _editMode = !_editMode;
            if (_editMode) {
              _hideControls = false;
              _editBackupKey = _layoutKey;
              _editBackupValue = _prefs?.getString(_layoutKey);
            }
          });
          if (!_editMode) _saveCustomLayout();
        case QuickAction.quit:
          await _quit();
          return;
        case QuickAction.resume:
        case null:
          break;
      }
    } finally {
      _menuOpen = false;
      _menuSnapshot = null;
      if (!_editMode && !_screenEdit) EmulatorBridge.setUiCaptured(false);
      // While editing the touch controls the game stays frozen; Save resumes it.
      if (!_quitting && !_editMode && !_screenEdit && !_autoPaused) {
        EmulatorBridge.setPaused(false);
        _playClock.start();
      }
    }
  }

  Future<void> _confirmReset() {
    return showDialog<void>(
      context: context,
      anchorPoint: _menuAnchor,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset game?'),
        content: const Text('Unsaved progress will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              EmulatorBridge.resetGame();
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  // ───────── Build ─────────

  /// Shared smoked-glass circular button matching [PressButton] and [FaceButtonCluster].
  Widget _utilityCapButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool active = false,
    Color accent = const Color(0xFF0A84FF),
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: ControlCapSurface(
          width: 40,
          height: 40,
          borderRadius: 20,
          active: active,
          accent: accent,
          child: Icon(
            icon,
            size: 19,
            color: active ? Colors.white : Colors.white.withValues(alpha: 0.88),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_initError == null) const CircularProgressIndicator(),
              if (_initError != null)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not start the game:\n$_initError',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final mq = MediaQuery.of(context);
    final size = mq.size;
    // Safety net: never draw controls that belong to another orientation / screen size.
    if (_controls.isEmpty || _builtFor != _controlsSig(size, mq.padding)) {
      _buildControlsNow();
    }
    final rect = _screenRect(size, mq.padding);

    final showControls = (!_hideControls && !_gamepad) || _editMode;

    final l1Ctrl = _controls.where((c) => c.id == 'l1').firstOrNull;
    final double? shoulderRowTop = l1Ctrl != null
        ? l1Ctrl.y * size.height
        : _shoulderTopPx;
    final double barTop;
    if (!showControls && _fold.isFlipTabletop) {
      barTop = _fold.horizontalHinge!.bottom + 6.0;
    } else if (showControls &&
        (_portrait || _fold.isFlipTabletop) &&
        shoulderRowTop != null) {
      barTop = shoulderRowTop - 3.0;
    } else if (_fold.isFlipTabletop) {
      barTop = _fold.horizontalHinge!.bottom + 6.0;
    } else {
      barTop = mq.padding.top + 8.0;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _openQuickMenu();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            _buildCroppedSurface(rect),

            // Free form: hide the real surface and show two independent cropped copies
            if (_isFree) ..._buildFreeScreens(size, mq.padding),

            // Touch screen layer (NDS / 3DS): forwards finger position to the core
            if (widget.system.isDualScreen && !_editMode && !_screenEdit)
              Positioned.fromRect(
                rect: _isFree
                    ? _freeRects(size, mq.padding)[1]
                    : _visibleRect(rect),
                child: _buildTouchLayer(
                  (_isFree
                          ? _freeRects(size, mq.padding)[1]
                          : _visibleRect(rect))
                      .size,
                ),
              ),

            // Auto-pause overlay: below the controls, so A / B stay reachable on screen
            if (_autoPaused) _buildPauseOverlay(showControls),

            if (showControls) ..._controls.map((c) => _buildControl(c, size)),

            // Free move / resize of the game picture
            if (_screenEdit && _isFree) ..._buildFreeEdit(size, mq.padding),
            if (_screenEdit && !_isFree) ...[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: (_) =>
                      _editBaseScale = (_pendingEdit?.scale ?? _screenScale),
                  onScaleUpdate: (d) => _updateScreenEdit(
                    delta: d.focalPointDelta,
                    scale: d.pointerCount > 1 ? _editBaseScale * d.scale : null,
                  ),
                  onScaleEnd: (_) {
                    _commitScreenEdit();
                    _scheduleLayoutRefresh(nudge: false);
                  },
                  child: const SizedBox.expand(),
                ),
              ),
              Positioned.fromRect(
                rect: _editGhost ?? rect,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFF0A84FF),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: mq.padding.bottom + 12,
                child: Center(
                  child: Material(
                    color: const Color(0xE61C1C1E),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          const Text(
                            'Drag to move · pinch to resize',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(
                            width: 150,
                            child: Slider(
                              min: ScreenLayouts.minScale,
                              max: 1.0,
                              value: (_pendingEdit?.scale ?? _screenScale)
                                  .clamp(ScreenLayouts.minScale, 1.0)
                                  .toDouble(),
                              onChanged: (v) => _updateScreenEdit(scale: v),
                              onChangeEnd: (_) {
                                _commitScreenEdit();
                                _scheduleLayoutRefresh(nudge: false);
                              },
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              final p =
                                  _profiles[_screenCtx] ??
                                  const ScreenProfile();
                              _pendingEdit = null;
                              _editGhost = null;
                              _profiles[_screenCtx] = p.copyWith(
                                scale: 1.0,
                                dx: 0,
                                dy: 0,
                              );
                              _resolveScreenProfile();
                              _rebuildControls();
                              _persistScreenProfile();
                              _scheduleLayoutRefresh(nudge: false);
                            },
                            child: const Text('Reset'),
                          ),
                          FilledButton(
                            onPressed: () {
                              _commitScreenEdit();
                              _rebuildControls();
                              _scheduleLayoutRefresh(nudge: false);
                              setState(() => _screenEdit = false);
                              _resumeAfterEdit();
                            },
                            child: const Text('Done'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],

            // Floating utility bar (Hamburger Menu, Fast Forward, Screenshot)
            Positioned(
              top: barTop,
              left: (!showControls && !_editMode) ? (mq.padding.left + 10) : 0,
              right: (!showControls && !_editMode) ? null : 0,
              child: Align(
                alignment: (!showControls && !_editMode)
                    ? Alignment.centerLeft
                    : Alignment.center,
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  children: [
                    _utilityCapButton(
                      icon: Icons.menu,
                      tooltip: 'Menu',
                      onTap: _openQuickMenu,
                    ),
                    if (!_editMode) ...[
                      _utilityCapButton(
                        icon: Icons.fast_forward,
                        tooltip: 'Fast-forward',
                        active: _fastForwardSpeed > 1,
                        accent: const Color(0xFF00E5FF),
                        onTap: _toggleFastForward,
                      ),
                      _utilityCapButton(
                        icon: Icons.photo_camera_outlined,
                        tooltip: 'Screenshot',
                        onTap: _takeScreenshot,
                      ),
                    ],
                    if (_gamepad)
                      ControlCapSurface(
                        width: 36,
                        height: 28,
                        borderRadius: 14,
                        child: Icon(
                          Icons.sports_esports,
                          color: Colors.white.withValues(alpha: 0.72),
                          size: 16,
                        ),
                      ),
                    if (_editMode) ...[
                      FilledButton.icon(
                        onPressed: () {
                          _saveCustomLayout();
                          setState(() {
                            _editMode = false;
                            _selectedButtonId = null;
                          });
                          // Leaving edit mode: unfreeze the game.
                          EmulatorBridge.setUiCaptured(false);
                          EmulatorBridge.setPaused(false);
                          _playClock.start();
                        },
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Save'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _cancelEdit,
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Cancel'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _resetLayout,
                        icon: const Icon(Icons.undo, size: 18),
                        label: const Text('Reset'),
                      ),
                      if (_selectedButtonId != null)
                        Builder(
                          builder: (_) {
                            final sel = _controls
                                .where((c) => c.id == _selectedButtonId)
                                .firstOrNull;
                            if (sel == null) return const SizedBox.shrink();
                            return SizedBox(
                              width: 150,
                              child: Slider(
                                min: sel.minSize,
                                max: sel.maxSize,
                                value: sel.size
                                    .clamp(sel.minSize, sel.maxSize)
                                    .toDouble(),
                                onChanged: (v) => setState(() => sel.size = v),
                              ),
                            );
                          },
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The part of [rect] that actually shows picture. Equals [rect] except for the cropped
  /// single-screen modes, where it is the single screen fitted (and centred) inside [rect].
  Rect _visibleRect(Rect rect) {
    if (!widget.system.isDualScreen || !_isCropMode(_screenMode)) return rect;
    final va = widget.system.aspectFor(_screenMode);
    var w = rect.width;
    var h = w / va;
    if (h > rect.height) {
      h = rect.height;
      w = h * va;
    }
    return Rect.fromCenter(center: rect.center, width: w, height: h);
  }

  /// Fraction of the stacked picture's width the 3DS bottom screen occupies (320 of 400 px).
  double get _bottomWidthFraction =>
      widget.system.type == ConsoleType.n3ds ? 0.8 : 1.0;

  /// Size and position of the full stacked surface, relative to the visible window.
  Rect _surfaceBox(Size vis) {
    if (!widget.system.isDualScreen || !_isCropMode(_screenMode)) {
      return Offset.zero & vis;
    }
    return _cropBox(vis, _screenMode == 'bottom_only');
  }

  /// Where the full stacked picture sits so that only one screen shows through [vis].
  Rect _cropBox(Size vis, bool bottom) {
    final wf = bottom ? _bottomWidthFraction : 1.0;
    final fw = vis.width / wf;
    final fh = fw / widget.system.aspectFor('top_bottom');
    return Rect.fromLTWH(-(fw - vis.width) / 2, bottom ? -fh / 2 : 0.0, fw, fh);
  }

  /// Free form: the real emulator surface stays alive at stacked aspect (hidden under a black
  /// cover); only copies of its frames are shown.
  Rect _hostRect(Size screen) {
    final fa = widget.system.aspectFor('top_bottom');
    var w = screen.width;
    var h = w / fa;
    if (h > screen.height) {
      h = screen.height;
      w = h * fa;
    }
    return Rect.fromCenter(
      center: Offset(screen.width / 2, screen.height / 2),
      width: w,
      height: h,
    );
  }

  /// Keeps the SAME widget structure in every mode so switching layouts never recreates
  /// (and therefore never restarts) the emulator view.
  Widget _buildCroppedSurface(Rect rect) {
    final vis = _isFree
        ? _hostRect(MediaQuery.of(context).size)
        : _visibleRect(rect);
    final box = _surfaceBox(vis.size);
    return Positioned.fromRect(
      rect: vis,
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.none,
          children: [Positioned.fromRect(rect: box, child: _buildSurface())],
        ),
      ),
    );
  }

  List<Widget> _buildFreeScreens(Size size, EdgeInsets pad) {
    final rects = _freeRects(size, pad);
    final host = _hostRect(size);
    Widget shot(Rect r, bool bottom) {
      final box = _cropBox(r.size, bottom);
      return Positioned.fromRect(
        rect: r,
        child: ClipRect(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fromRect(
                rect: box,
                child: Texture(
                  textureId: _mirrorTex!,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return [
      Positioned.fromRect(
        rect: host,
        child: const ColoredBox(color: Colors.black),
      ),
      if (_mirrorTex != null) shot(rects[0], false),
      if (_mirrorTex != null) shot(rects[1], true),
    ];
  }

  void _setFreeRect(int which, Rect px, Size size) {
    final sc = _screenCtx;
    final p = _profiles[sc] ?? const ScreenProfile();
    final rects = _freeRects(size, MediaQuery.of(context).padding);
    rects[which] = px;
    _profiles[sc] = p.copyWith(
      modeId: 'free',
      topRect: _toFrac(rects[0], size),
      bottomRect: _toFrac(rects[1], size),
    );
    setState(() {});
  }

  List<Widget> _buildFreeEdit(Size size, EdgeInsets pad) {
    final rects = _freeRects(size, pad);
    final aspects = [_topAspect, _bottomAspect];
    final names = ['Top screen', 'Bottom screen'];
    var baseW = 0.0;

    Widget handle(int i) {
      final r = rects[i];
      return Positioned.fromRect(
        rect: r,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (_) {
            baseW = r.width;
            setState(() => _freeSel = i);
          },
          onScaleUpdate: (d) {
            final cur = _freeRects(size, pad)[i];
            final w = (d.pointerCount > 1 ? baseW * d.scale : cur.width)
                .clamp(70.0, size.width)
                .toDouble();
            final h = w / aspects[i];
            var c = cur.center + d.focalPointDelta;
            c = Offset(
              c.dx.clamp(w / 2, math.max(w / 2, size.width - w / 2)).toDouble(),
              c.dy
                  .clamp(h / 2, math.max(h / 2, size.height - h / 2))
                  .toDouble(),
            );
            _setFreeRect(
              i,
              Rect.fromCenter(center: c, width: w, height: h),
              size,
            );
          },
          onScaleEnd: (_) => _persistScreenProfile(),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0x220A84FF),
              border: Border.all(
                color: _freeSel == i
                    ? const Color(0xFF0A84FF)
                    : const Color(0x99FFFFFF),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xCC000000),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  names[i],
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return [
      Positioned.fill(child: Container(color: const Color(0x33000000))),
      // Selected screen is drawn last so it is always the one you grab.
      handle(1 - _freeSel),
      handle(_freeSel),
      Positioned(
        left: 12,
        right: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
        child: Center(
          child: Material(
            color: const Color(0xE61C1C1E),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  const Text(
                    'Drag each screen · pinch to resize',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      final sc = _screenCtx;
                      _profiles[sc] = (_profiles[sc] ?? const ScreenProfile())
                          .copyWith(clearFree: true);
                      _persistScreenProfile();
                      setState(() {});
                    },
                    child: const Text('Reset'),
                  ),
                  FilledButton(
                    onPressed: () {
                      _persistScreenProfile();
                      setState(() => _screenEdit = false);
                      _resumeAfterEdit();
                    },
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// Maps a touch inside the visible window to the full stacked picture the core sees.
  Offset _touchMap(double nx, double ny) {
    switch (_screenMode) {
      case 'top_only':
        return Offset(nx, ny * 0.5);
      case 'bottom_only':
      case 'free':
        final wf = _bottomWidthFraction;
        return Offset((1 - wf) / 2 + nx * wf, 0.5 + ny * 0.5);
      default:
        return Offset(nx, ny);
    }
  }

  /// Hybrid-composition platform view (required for SurfaceView based GLRetroView).
  Widget _buildSurface() {
    final params = <String, dynamic>{
      'core': widget.coreFile,
      'romPath': widget.romFile?.path,
      'bootBios': widget.bootBios,
      'vulkan': widget.useVulkan && widget.system.supportsVulkan,
      'layout': widget.system.isDualScreen ? _coreMode(_screenMode) : null,
      'options': _coreOverrides,
      'regionOptions': _regionOptions,
      'shader': _settings.filter.name,
      'lowLatency': _settings.lowLatencyAudio,
      'nickname': _settings.nickname,
      'birthMonth': _settings.birthMonth,
      'birthDay': _settings.birthDay,
    };
    return PlatformViewLink(
      viewType: _surfaceType,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        gestureRecognizers: const {},
        hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      ),
      onCreatePlatformView: (p) {
        return PlatformViewsService.initExpensiveAndroidView(
            id: p.id,
            viewType: _surfaceType,
            layoutDirection: TextDirection.ltr,
            creationParams: params,
            creationParamsCodec: const StandardMessageCodec(),
            onFocus: () => p.onFocusChanged(true),
          )
          ..addOnPlatformViewCreatedListener(p.onPlatformViewCreated)
          ..create();
      },
    );
  }

  Widget _buildTouchLayer(Size s) {
    void send(int action, Offset p) {
      final m = _touchMap(
        (p.dx / s.width).clamp(0.0, 1.0).toDouble(),
        (p.dy / s.height).clamp(0.0, 1.0).toDouble(),
      );
      EmulatorBridge.sendTouch(action, m.dx, m.dy);
    }

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (_touchPointer != null) return;
        _touchPointer = e.pointer;
        send(0, e.localPosition);
      },
      onPointerMove: (e) {
        if (e.pointer == _touchPointer) send(1, e.localPosition);
      },
      onPointerUp: (e) {
        if (e.pointer != _touchPointer) return;
        _touchPointer = null;
        send(2, e.localPosition);
      },
      onPointerCancel: (e) {
        if (e.pointer != _touchPointer) return;
        _touchPointer = null;
        send(2, e.localPosition);
      },
    );
  }

  Widget _buildControl(ControlConfig c, Size screen) {
    final ps = widget.system.faceStyle == FaceStyle.playstation;
    final isGbFamily =
        widget.system.type == ConsoleType.nes ||
        widget.system.type == ConsoleType.gb ||
        widget.system.type == ConsoleType.gbc ||
        widget.system.type == ConsoleType.gba;

    final Widget control;
    switch (c.kind) {
      case ControlKind.dpad:
        control = DPadControl(size: c.size, haptics: _haptics);
      case ControlKind.stick:
        control = StickControl(
          size: c.size,
          source: c.id == 'cstick'
              ? EmulatorBridge.analogRight
              : EmulatorBridge.analogLeft,
          // PS1 DualShock: tap a stick to press L3 / R3.
          clickKeyCode: widget.system.type == ConsoleType.ps1
              ? (c.id == 'cstick' ? EmulatorBridge.keyR3 : EmulatorBridge.keyL3)
              : null,
        );
      case ControlKind.faceCluster:
        final padSpec = widget.system.pad;
        final padFace = padSpec?.face ?? const <PadButton>[];
        final r =
            c.size *
            (padFace.isNotEmpty
                ? padSpec!.faceRadius
                : (isGbFamily ? 0.22 : 0.185));
        final half = c.size / 2;
        final step = c.size * 0.29;
        final specs = padFace.isNotEmpty
            ? <FaceButtonSpec>[
                for (final b in padFace)
                  FaceButtonSpec(
                    id: b.id,
                    label: b.label,
                    keyCode: b.key,
                    center: Offset(c.size * b.x, c.size * b.y),
                    radius: r,
                  ),
              ]
            : isGbFamily
            ? <FaceButtonSpec>[
                FaceButtonSpec(
                  id: 'b',
                  label: 'B',
                  keyCode: EmulatorBridge.keyB,
                  center: Offset(c.size * 0.28, c.size * 0.60),
                  radius: r,
                ),
                FaceButtonSpec(
                  id: 'a',
                  label: 'A',
                  keyCode: EmulatorBridge.keyA,
                  center: Offset(c.size * 0.72, c.size * 0.40),
                  radius: r,
                ),
              ]
            : <FaceButtonSpec>[
                FaceButtonSpec(
                  id: 'b',
                  label: ps ? '✕' : 'B',
                  keyCode: EmulatorBridge.keyB,
                  center: Offset(half, half + step),
                  radius: r,
                ),
                FaceButtonSpec(
                  id: 'a',
                  label: ps ? '○' : 'A',
                  keyCode: EmulatorBridge.keyA,
                  center: Offset(half + step, half),
                  radius: r,
                ),
                FaceButtonSpec(
                  id: 'y',
                  label: ps ? '□' : 'Y',
                  keyCode: EmulatorBridge.keyY,
                  center: Offset(half - step, half),
                  radius: r,
                ),
                FaceButtonSpec(
                  id: 'x',
                  label: ps ? '△' : 'X',
                  keyCode: EmulatorBridge.keyX,
                  center: Offset(half, half - step),
                  radius: r,
                ),
              ];
        control = FaceButtonCluster(
          width: c.size,
          height: c.size,
          buttons: specs,
          haptics: _haptics,
        );
      case ControlKind.button:
      case ControlKind.pill:
      case ControlKind.shoulder:
        control = PressButton(
          label: c.label,
          keyCode: c.keyCode,
          width: c.width,
          height: c.height,
          shape: switch (c.kind) {
            ControlKind.pill => PadShape.pill,
            ControlKind.shoulder => PadShape.shoulder,
            _ => PadShape.circle,
          },
          haptics: _haptics,
        );
    }

    final selected = _editMode && _selectedButtonId == c.id;
    final Widget child = _editMode
        ? GestureDetector(
            onTap: () => setState(() => _selectedButtonId = c.id),
            onPanStart: (_) => setState(() => _selectedButtonId = c.id),
            onPanUpdate: (d) => setState(() {
              final maxX = (1 - c.width / screen.width)
                  .clamp(0.0, 1.0)
                  .toDouble();
              final maxY = (1 - c.height / screen.height)
                  .clamp(0.0, 1.0)
                  .toDouble();
              c.x = (c.x + d.delta.dx / screen.width)
                  .clamp(0.0, maxX)
                  .toDouble();
              c.y = (c.y + d.delta.dy / screen.height)
                  .clamp(0.0, maxY)
                  .toDouble();
            }),
            child: Container(
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(
                  c.kind == ControlKind.pill || c.kind == ControlKind.shoulder
                      ? 20
                      : 999,
                ),
                border: selected
                    ? Border.all(color: Colors.cyanAccent, width: 2.5)
                    : null,
              ),
              child: IgnorePointer(child: control),
            ),
          )
        : control;

    return Positioned(
      left: c.x * screen.width,
      top: c.y * screen.height,
      child: Opacity(opacity: _opacity, child: child),
    );
  }
}

/// One section of the in-game quick menu (a card on the right pane in landscape, a stacked
/// section in the portrait sheet).
class _MenuPane {
  final IconData icon;
  final String title;
  final Widget child;
  const _MenuPane({
    required this.icon,
    required this.title,
    required this.child,
  });
}
