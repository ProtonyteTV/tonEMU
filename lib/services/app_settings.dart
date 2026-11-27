// lib/services/app_settings.dart
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Post-processing shader applied by LibretroDroid. `name` is sent to the native side.
enum VideoFilter { none, sharp, crt, lcd }

extension VideoFilterX on VideoFilter {
  String get label => switch (this) {
    VideoFilter.none => 'None',
    VideoFilter.sharp => 'Sharp',
    VideoFilter.crt => 'CRT',
    VideoFilter.lcd => 'LCD',
  };
}

/// What happens when a game that already has an auto-save is opened.
///  smart = jump straight back in (no prompt); the game shows a "Start over" button for a few seconds
///  ask   = the old "Continue / New game" dialog
///  fresh = always start from the beginning
enum ResumeMode { smart, ask, fresh }

/// Player name written into DS / 3DS profiles until the user picks their own.
const String kDefaultNickname = 'tonEMU';

/// App-wide settings (not per core). Call [load] when a screen opens; it always re-reads
/// SharedPreferences, so the in-game menu and the settings screen can't drift apart.
/// Keys `ui_opacity`, `ui_haptics` and `autosave_on_quit` are the ones GameScreen already used.
class AppSettings {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  // Video
  VideoFilter filter = VideoFilter.none;
  double portraitMaxHeight =
      0.62; // share of the screen height the picture may use in portrait
  bool lowLatencyAudio = false;

  // Touch controls
  double opacity = 1.0;
  bool haptics = true;
  bool autoHideTouch =
      true; // hide on-screen buttons while a gamepad is connected

  // Physical controller
  bool swapAB = false;
  bool swapXY = false;
  double deadzone = 0.12;
  bool comboHotkeys = false; // Select + Start/R1/L1/Y

  bool pauseOnDisconnect =
      true; // auto-open the menu when the pad / headphones drop out
  bool pauseOnLeave = true; // pause when the app is left / the notification shade opens; A or B continues
  int fastForwardSpeed =
      2; // speed used by the fast-forward button / hotkey (2..4)

  // Saves
  bool autoSaveOnQuit = true;
  ResumeMode resumeMode = ResumeMode.smart;
  int autoSaveMinutes =
      0; // 0 = off; otherwise silently refresh the auto-save slot
  bool screenshotToGallery =
      false; // also copy screenshots into the phone's Photos/Gallery
  int jedTimeMachineSeconds =
      30; // 0 = off; otherwise a rolling snapshot every N seconds of play

  /// 0 = off; otherwise a gentle "time for a break?" note every N minutes of play.
  int breakReminderMinutes = 0;

  // Library page
  /// Storage key of [downloadCoverArt]; BoxArtService reads it directly, so it also works before
  /// any settings screen has loaded.
  static const String coverArtKey = 'set_cover_art';

  /// Download missing cover art from GitHub (libretro-thumbnails). Off = no cover request is ever
  /// sent; covers already on the device and ones the player picked keep showing.
  bool downloadCoverArt = true;
  bool showStats = true; // games / consoles / played tiles + Surprise Me
  bool showRecent = true; // "Continue playing" shelf
  bool showFavorites = true; // Favorites shelf
  bool showMostPlayed = true; // Most Played shelf
  bool showNewAdditions = true; // New Additions shelf

  // 3DS & NDS System Profile (max 10 chars on real hardware)
  String nickname = kDefaultNickname;
  int birthMonth = 1; // 1..12
  int birthDay = 1; // 1..31

  /// What is currently stored, per key. [save] only writes keys whose value changed: every
  /// SharedPreferences write is a platform-channel call, and a slider drag used to fire 19 of
  /// them per tick.
  final Map<String, Object?> _stored = {};
  Timer? _saveTimer;

  /// Debounced save for rapid changes (slider drags, toggles). Writes ~350 ms after the last
  /// change; call [flush] to write immediately (the settings screen does this when it closes).
  void scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), () {
      _saveTimer = null;
      save();
    });
  }

  /// Writes right away if a debounced save is still waiting.
  Future<void> flush() async {
    if (_saveTimer == null) return;
    _saveTimer!.cancel();
    _saveTimer = null;
    await save();
  }

  Future<void> load() async {
    await flush(); // never re-read over a change that has not reached disk yet
    final p = await SharedPreferences.getInstance();
    for (final k in _keys) {
      _stored[k] = p.get(k);
    }
    final f = p.getInt('set_filter') ?? 0;
    filter = VideoFilter.values[f.clamp(0, VideoFilter.values.length - 1)];
    portraitMaxHeight = p.getDouble('set_portrait_h') ?? 0.62;
    lowLatencyAudio = p.getBool('set_low_latency') ?? false;
    opacity = p.getDouble('ui_opacity') ?? 1.0;
    haptics = p.getBool('ui_haptics') ?? true;
    autoHideTouch = p.getBool('set_autohide') ?? true;
    swapAB = p.getBool('set_swap_ab') ?? false;
    swapXY = p.getBool('set_swap_xy') ?? false;
    deadzone = p.getDouble('set_deadzone') ?? 0.12;
    comboHotkeys = p.getBool('set_combo') ?? false;
    autoSaveOnQuit = p.getBool('autosave_on_quit') ?? true;
    final rm = p.getInt('set_resume_mode');
    resumeMode = rm == null
        ? ResumeMode.smart
        : ResumeMode.values[rm.clamp(0, ResumeMode.values.length - 1)];
    pauseOnDisconnect = p.getBool('set_pause_disc') ?? true;
    pauseOnLeave = p.getBool('set_pause_leave') ?? true;
    fastForwardSpeed = (p.getInt('set_ff_speed') ?? 2).clamp(2, 4);
    autoSaveMinutes = const [0, 2, 5, 10].contains(p.getInt('set_autosave_min'))
        ? p.getInt('set_autosave_min')!
        : 0;
    screenshotToGallery = p.getBool('set_shot_gallery') ?? false;
    jedTimeMachineSeconds =
        const [0, 15, 30, 60].contains(p.getInt('set_tm_sec'))
        ? p.getInt('set_tm_sec')!
        : 30;
    breakReminderMinutes =
        const [0, 30, 60, 90].contains(p.getInt('set_break_min'))
        ? p.getInt('set_break_min')!
        : 0;
    showStats = p.getBool('set_lib_stats') ?? true;
    showRecent = p.getBool('set_lib_recent') ?? true;
    showFavorites = p.getBool('set_lib_fav') ?? true;
    showMostPlayed = p.getBool('set_lib_most') ?? true;
    showNewAdditions = p.getBool('set_lib_new') ?? true;
    downloadCoverArt = p.getBool(coverArtKey) ?? true;

    final savedNick = p.getString('set_nickname')?.trim() ?? '';
    // 'xEmu' was the old automatic default (before the app was named tonEMU): upgrade it.
    nickname = (savedNick.isEmpty || savedNick == 'xEmu')
        ? kDefaultNickname
        : _clampNickname(savedNick);
    birthMonth = (p.getInt('set_birth_month') ?? 1).clamp(1, 12);
    birthDay = (p.getInt('set_birth_day') ?? 1).clamp(1, 31);
  }

  static const _keys = <String>[
    'set_filter',
    'set_portrait_h',
    'set_low_latency',
    'ui_opacity',
    'ui_haptics',
    'set_autohide',
    'set_swap_ab',
    'set_swap_xy',
    'set_deadzone',
    'set_combo',
    'autosave_on_quit',
    'set_resume_mode',
    'set_pause_disc',
    'set_pause_leave',
    'set_ff_speed',
    'set_autosave_min',
    'set_shot_gallery',
    'set_tm_sec',
    'set_break_min',
    'set_lib_stats',
    'set_lib_recent',
    'set_lib_fav',
    coverArtKey,
    'set_nickname',
    'set_birth_month',
    'set_birth_day',
  ];

  Future<void> save() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final p = await SharedPreferences.getInstance();

    final cleanNick = _clampNickname(nickname.trim());
    nickname = cleanNick.isEmpty ? kDefaultNickname : cleanNick;

    final values = _snapshot();
    for (final e in values.entries) {
      if (_stored.containsKey(e.key) && _stored[e.key] == e.value) continue;
      final v = e.value;
      if (v is int) {
        await p.setInt(e.key, v);
      } else if (v is double) {
        await p.setDouble(e.key, v);
      } else if (v is bool) {
        await p.setBool(e.key, v);
      } else if (v is String) {
        await p.setString(e.key, v);
      }
      _stored[e.key] = v;
    }
  }

  /// Every setting as it is stored, keyed by its SharedPreferences key.
  Map<String, Object> _snapshot() {
    return <String, Object>{
      'set_filter': filter.index,
      'set_portrait_h': portraitMaxHeight,
      'set_low_latency': lowLatencyAudio,
      'ui_opacity': opacity,
      'ui_haptics': haptics,
      'set_autohide': autoHideTouch,
      'set_swap_ab': swapAB,
      'set_swap_xy': swapXY,
      'set_deadzone': deadzone,
      'set_combo': comboHotkeys,
      'autosave_on_quit': autoSaveOnQuit,
      'set_resume_mode': resumeMode.index,
      'set_pause_disc': pauseOnDisconnect,
      'set_pause_leave': pauseOnLeave,
      'set_ff_speed': fastForwardSpeed.clamp(2, 4),
      'set_autosave_min': autoSaveMinutes,
      'set_shot_gallery': screenshotToGallery,
      'set_tm_sec': jedTimeMachineSeconds,
      'set_break_min': breakReminderMinutes,
      'set_lib_stats': showStats,
      'set_lib_recent': showRecent,
      'set_lib_fav': showFavorites,
      'set_lib_most': showMostPlayed,
      'set_lib_new': showNewAdditions,
      coverArtKey: downloadCoverArt,
      'set_nickname': nickname,
      'set_birth_month': birthMonth.clamp(1, 12),
      'set_birth_day': birthDay.clamp(1, 31),
    };
  }

  /// All app settings as plain JSON-ready data, for backing them up or moving to another phone.
  Map<String, Object> exportJson() => _snapshot();

  /// Restores settings from [exportJson] data. Unknown keys and values of the wrong type are
  /// ignored; the rest go through [load], which clamps every value to its allowed range.
  /// Returns how many settings were applied.
  Future<int> importJson(Map<String, dynamic> data) async {
    await flush();
    final defaults = _snapshot();
    final p = await SharedPreferences.getInstance();
    var applied = 0;
    for (final e in data.entries) {
      final want = defaults[e.key];
      final v = e.value;
      if (want == null) continue;
      if (want is int && v is int) {
        await p.setInt(e.key, v);
      } else if (want is double && v is num) {
        await p.setDouble(e.key, v.toDouble());
      } else if (want is bool && v is bool) {
        await p.setBool(e.key, v);
      } else if (want is String && v is String) {
        await p.setString(e.key, v);
      } else {
        continue;
      }
      applied++;
    }
    await load();
    return applied;
  }

  /// Both NDS and 3DS firmware cap user nicknames at 10 UTF-16 code units.
  static String _clampNickname(String raw) {
    if (raw.length <= 10) return raw;
    var end = 10;
    final last = raw.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) {
      end -= 1; // don't cut an emoji in half
    }
    return raw.substring(0, end);
  }
}
