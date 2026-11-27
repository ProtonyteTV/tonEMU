// lib/services/core_settings.dart
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One libretro core option, parsed from the core's own variable list.
class CoreOption {
  final String key;
  final String current;
  final String label;
  final List<String> values; // empty -> free text

  const CoreOption({
    required this.key,
    required this.current,
    required this.label,
    required this.values,
  });

  /// Native description format is "Label; value1|value2|value3".
  factory CoreOption.fromNative(Map<String, dynamic> m) {
    final key = '${m['key']}';
    final desc = '${m['description'] ?? ''}';
    var label = key;
    var values = <String>[];
    final i = desc.indexOf('; ');
    if (i >= 0) {
      label = desc.substring(0, i);
      values = desc.substring(i + 2).split('|');
    } else if (desc.isNotEmpty) {
      label = desc;
    }
    return CoreOption(
      key: key,
      current: '${m['value'] ?? ''}',
      label: label,
      values: values,
    );
  }

  factory CoreOption.fromJson(Map<String, dynamic> j) => CoreOption(
    key: j['key'] as String,
    current: j['current'] as String? ?? '',
    label: j['label'] as String? ?? j['key'] as String,
    values: (j['values'] as List?)?.cast<String>() ?? const [],
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'current': current,
    'label': label,
    'values': values,
  };

  bool get isRegion => CoreSettings.isRegionKey(key);

  /// True when the app overrides this option on every launch, so editing it does nothing.
  bool get isIneffective => CoreSettings.isIneffectiveKey(key);
}

/// Per-core settings, stored in SharedPreferences and keyed by the core library name
/// (so GB and GBC share the Gambatte settings, etc.).
class CoreSettings {
  static String _ovKey(String core) => 'core_opts_$core';
  static String _schemaKey(String core) => 'core_schema_$core';

  /// "libazahar_libretro_android.so" -> "azahar"
  static String coreTitle(String coreLibName) {
    var t = coreLibName;
    if (t.startsWith('lib')) t = t.substring(3);
    final i = t.indexOf('_libretro');
    if (i > 0) t = t.substring(0, i);
    return t;
  }

  /// App-level renderer choice (not a core option). Saved with the other per-core overrides and
  /// read by the native side at launch (see CoreOptions.java). Needs a game restart.
  static const rendererKey = 'xemu_renderer';
  static const rendererSoftware = 'Software';
  static const rendererGles = 'OpenGL ES (experimental)';

  /// The renderer choice for cores that have one (PS1 only: PPSSPP always runs on OpenGL ES,
  /// and LibretroDroid has no Vulkan), or null.
  static CoreOption? rendererOption(String coreLibName) {
    final c = coreLibName.toLowerCase();
    if (!c.contains('swanstation') && !c.contains('duckstation')) return null;
    return const CoreOption(
      key: rendererKey,
      current: rendererSoftware,
      label: 'Renderer (restart game to apply)',
      values: [rendererSoftware, rendererGles],
    );
  }

  /// Region options are always forced to the US value and can't be changed, except on the Sega
  /// cores (Genesis / SMS / GG), which keep their own auto-detect and can be changed freely.
  static bool isRegionKey(String key) {
    final k = key.toLowerCase();
    if (k.startsWith('blastem_') || k.startsWith('gearsystem_')) {
      return false;
    }
    return k.contains('region');
  }

  /// Options the native side forces on every start (see CoreOptions.java) or that can never work
  /// with LibretroDroid (OpenGL ES only). Changing them has no effect, so the screen hides them.
  static const _ineffectiveKeys = {
    // Renderer / backend: forced (Software / OpenGL) because Vulkan is unsupported.
    'ppsspp_backend',
    'swanstation_gpu_renderer',
    'swanstation_gpu.renderer',
    'duckstation_gpu_renderer',
    'duckstation_gpu.renderer',
    'azahar_graphics_api',
    'citra_graphics_api',
    // Touch mode and screen layout: driven by the app's own layout setting.
    'melonds_touch_mode',
    'melonds_screen_layout',
    'melonds_number_of_screen_layouts',
    'melonds_screen_layout1',
    'citra_layout_option',
    'citra_swap_screen',
    // Forced OFF natively: they crash PPSSPP on LibretroDroid's GL surface (see CoreOptions.java).
    'ppsspp_skip_buffer_effects',
    'ppsspp_auto_frameskip',
  };

  /// Region keys are always forced to US; the rest are in [_ineffectiveKeys].
  static bool isIneffectiveKey(String key) =>
      isRegionKey(key) || _ineffectiveKeys.contains(key.toLowerCase());

  /// The US-flavoured value of an option, or null if it has none.
  static String? usValue(CoreOption o) {
    const exact = {
      'usa',
      'us',
      'u.s.a.',
      'ntsc-u',
      'ntsc-u/c',
      'north america',
      'united states',
      'america',
    };
    for (final v in o.values) {
      if (exact.contains(v.trim().toLowerCase())) return v;
    }
    for (final v in o.values) {
      final l = v.toLowerCase();
      if (l.startsWith('ntsc-u') || l.contains('usa') || l.contains('(us)'))
        return v;
    }
    return null;
  }

  static Future<Map<String, String>> loadOverrides(String core) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_ovKey(core));
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveOverrides(String core, Map<String, String> m) async {
    final prefs = await SharedPreferences.getInstance();
    if (m.isEmpty) {
      await prefs.remove(_ovKey(core));
    } else {
      await prefs.setString(_ovKey(core), jsonEncode(m));
    }
  }

  /// Saves several overrides with ONE read/write (presets and "reset all" touch many keys).
  static Future<void> setOverrides(
    String core,
    Map<String, String> values,
  ) async {
    final m = await loadOverrides(core);
    m.addAll(values);
    await _saveOverrides(core, m);
  }

  static Future<void> setOverride(String core, String key, String value) async {
    final m = await loadOverrides(core);
    m[key] = value;
    await _saveOverrides(core, m);
  }

  static Future<void> clearOverride(String core, String key) async {
    final m = await loadOverrides(core);
    m.remove(key);
    await _saveOverrides(core, m);
  }

  static Future<void> clearAll(String core) => _saveOverrides(core, {});

  /// Option list cached from the last time this core ran, so it can be edited from the library.
  static Future<List<CoreOption>> loadSchema(String core) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_schemaKey(core));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => CoreOption.fromJson(Map<String, dynamic>.from(e as Map)))
          // "current" was only true when the schema was saved; the screen must show the
          // saved override or the default, not a stale value from an old session.
          .map(
            (o) => CoreOption(
              key: o.key,
              current: '',
              label: o.label,
              values: o.values,
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveSchema(String core, List<CoreOption> options) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _schemaKey(core),
      jsonEncode(options.map((o) => o.toJson()).toList()),
    );
  }

  // ───────────────────── Live-change safety ─────────────────────

  /// Options a core only reads when it starts or loads a game (renderer, CPU core / JIT, BIOS,
  /// region, language, hardware model, threading, plugins...). Changing them in the middle of a
  /// game does nothing at best and crashes or corrupts the session at worst, so the settings
  /// screen only SAVES them and they apply the next time the game starts.
  static final RegExp _restartRx = RegExp(
    r'(region|bios|firmware|language|jit|cpu_core|cpucore|cpu_mode|dynarec|drc|recompiler|'
    r'execution_mode|renderer|backend|graphics_api|threaded|usethread|boot|sdcard|sd_card|'
    r'virtual_sd|memcard|memory_card|multitap|console_mode|hwmode|gb_model|colorization|'
    r'is_new_3ds|fast_memory|io_timing|button_preference|inflight|plugin|fbemulation|'
    r'screensize|add_?on|cart|numthreads|sgb_borders|custom_textures|preload_textures|pak\d|'
    r'video_scale|gfx_colors)',
  );
  static const _restartExact = {'mupen64plus-aspect', rendererKey};

  static bool needsRestart(String key) {
    final k = key.toLowerCase();
    return _restartExact.contains(k) || _restartRx.hasMatch(k);
  }

  static int _width(String v) => int.tryParse(v.split('x').first.trim()) ?? 0;

  /// Values that exhaust GPU memory or crash the core on phones. They are never offered, never
  /// applied live and are clamped again natively at launch (CoreOptions.sanitize).
  static bool isBlockedValue(String key, String value) {
    final k = key.toLowerCase();
    final v = value.trim().toLowerCase();
    switch (k) {
      case 'ppsspp_skip_buffer_effects':
      case 'ppsspp_auto_frameskip':
        return v != 'disabled';
      case 'ppsspp_texture_scaling_level':
        return v == '5x';
      case 'ppsspp_internal_resolution':
        return _width(v) > 2880;
      case 'mupen64plus-43screensize':
      case 'mupen64plus-169screensize':
        return _width(v) > 1920;
      case 'swanstation_gpu_resolutionscale':
      case 'duckstation_gpu_resolutionscale':
        return (int.tryParse(v) ?? 0) > 8;
      case 'citra_resolution_factor':
      case 'azahar_resolution_factor':
        return _width(v) > 6;
    }
    return false;
  }

  /// The option as the settings screen shows it: unsafe values removed, and a "restart" note on
  /// options that cannot change during a game.
  static CoreOption safeOption(CoreOption o, {required bool live}) {
    final values = [
      for (final v in o.values)
        if (!isBlockedValue(o.key, v)) v,
    ];
    final label = live && needsRestart(o.key) && !o.label.endsWith(' · restart')
        ? '${o.label} · restart'
        : o.label;
    return CoreOption(
      key: o.key,
      current: o.current,
      label: label,
      values: values,
    );
  }

  // ───────────────────── Launch crash guard ─────────────────────

  static String _pendingKey(String core) => 'core_launch_pending_$core';
  static String _backupKey(String core) => 'core_opts_backup_$core';
  static String _regionKey(String core) => 'core_region_$core';

  /// Call right before a game starts. If the previous launch of this core never reached a stable
  /// state (the app crashed or was killed while starting or right after a live change) the
  /// saved overrides are the likely cause: they are backed up and cleared so the game can start
  /// again with defaults instead of crashing on every launch. Returns true when that happened.
  static Future<bool> rescueIfLastLaunchFailed(String core) async {
    final prefs = await SharedPreferences.getInstance();
    var rescued = false;
    if (prefs.getString(_pendingKey(core)) != null) {
      final raw = prefs.getString(_ovKey(core));
      if (raw != null && raw.isNotEmpty && raw != '{}') {
        await prefs.setString(_backupKey(core), raw);
        await prefs.remove(_ovKey(core));
        rescued = true;
      }
    }
    await prefs.setString(_pendingKey(core), DateTime.now().toIso8601String());
    return rescued;
  }

  /// Marks "something risky is happening now" (a live option change).
  static Future<void> beginRiskyChange(String core) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingKey(core), DateTime.now().toIso8601String());
  }

  /// The game ran / the change applied without taking the app down.
  static Future<void> markLaunchStable(String core) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingKey(core));
  }

  /// Puts back the overrides that [rescueIfLastLaunchFailed] cleared.
  static Future<bool> restoreBackup(String core) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_backupKey(core));
    if (raw == null) return false;
    await prefs.setString(_ovKey(core), raw);
    await prefs.remove(_backupKey(core));
    return true;
  }

  // ───────────────────── Region (applied at launch) ─────────────────────

  /// Region options are forced to US, but changing a region while a game runs breaks video/audio
  /// timing, so they are cached here and sent to the core when the game starts.
  static Future<void> saveRegionLaunchOptions(
    String core,
    Map<String, String> m,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (m.isEmpty) {
      await prefs.remove(_regionKey(core));
    } else {
      await prefs.setString(_regionKey(core), jsonEncode(m));
    }
  }

  static Future<Map<String, String>> loadRegionLaunchOptions(
    String core,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_regionKey(core));
    if (raw == null) return {};
    try {
      final m = (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));
      m.removeWhere(
        (k, _) => !isRegionKey(k),
      ); // drop values cached before a core went region-free
      return m;
    } catch (_) {
      return {};
    }
  }
}
