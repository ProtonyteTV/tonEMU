// lib/services/core_presets.dart
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core_settings.dart';

enum OptionCategory { video, performance, audio, input, system, other }

extension OptionCategoryX on OptionCategory {
  String get label => switch (this) {
    OptionCategory.video => 'Video',
    OptionCategory.performance => 'Performance',
    OptionCategory.audio => 'Audio',
    OptionCategory.input => 'Input',
    OptionCategory.system => 'System',
    OptionCategory.other => 'Other',
  };

  IconData get icon => switch (this) {
    OptionCategory.video => Icons.hd_outlined,
    OptionCategory.performance => Icons.speed,
    OptionCategory.audio => Icons.volume_up_outlined,
    OptionCategory.input => Icons.sports_esports_outlined,
    OptionCategory.system => Icons.settings_applications_outlined,
    OptionCategory.other => Icons.more_horiz,
  };
}

class CorePreset {
  final String id;
  final String label;
  final String hint;
  const CorePreset(this.id, this.label, this.hint);
}

/// One-tap Performance / Balanced / Quality bundles per core, plus the option categoriser.
/// Every level of a core lists the same keys, so switching level fully replaces the previous one.
/// Values that a core doesn't offer are skipped by the settings screen.
/// The preset the user last tapped for a core, plus the keys/values that were really saved
/// (options a core does not offer are skipped, so this can be a subset of the preset).
class AppliedPreset {
  final String id;
  final Map<String, String> values;
  const AppliedPreset(this.id, this.values);
}

class CorePresets {
  static const presets = [
    CorePreset('perf', 'Performance', 'Fastest'),
    CorePreset('balanced', 'Balanced', 'Good mix'),
    CorePreset('quality', 'Quality', 'Sharpest'),
  ];

  static const Map<String, Map<String, Map<String, String>>> _data = {
    'ppsspp': {
      'perf': {
        'ppsspp_internal_resolution': '480x272',
        'ppsspp_auto_frameskip': 'disabled',
        'ppsspp_skip_buffer_effects': 'disabled',
        'ppsspp_lazy_texture_caching': 'enabled',
        'ppsspp_texture_scaling_level': 'disabled',
        'ppsspp_texture_anisotropic_filtering': 'off',
        'ppsspp_texture_filtering': 'Auto',
      },
      'balanced': {
        'ppsspp_internal_resolution': '960x544',
        'ppsspp_auto_frameskip': 'disabled',
        'ppsspp_skip_buffer_effects': 'disabled',
        'ppsspp_lazy_texture_caching': 'enabled',
        'ppsspp_texture_scaling_level': 'disabled',
        'ppsspp_texture_anisotropic_filtering': '4x',
        'ppsspp_texture_filtering': 'Auto',
      },
      'quality': {
        'ppsspp_internal_resolution': '1440x816',
        'ppsspp_auto_frameskip': 'disabled',
        'ppsspp_skip_buffer_effects': 'disabled',
        'ppsspp_lazy_texture_caching': 'disabled',
        'ppsspp_texture_scaling_level': '2x',
        'ppsspp_texture_anisotropic_filtering': '8x',
        'ppsspp_texture_filtering': 'Auto max quality',
      },
    },
    'swanstation': {
      'perf': {
        'swanstation_GPU_ResolutionScale': '1',
        'swanstation_GPU_TrueColor': 'false',
        'swanstation_GPU_PGXPEnable': 'false',
        'swanstation_GPU_TextureFilter': 'Nearest',
      },
      'balanced': {
        'swanstation_GPU_ResolutionScale': '2',
        'swanstation_GPU_TrueColor': 'false',
        'swanstation_GPU_PGXPEnable': 'true',
        'swanstation_GPU_TextureFilter': 'Nearest',
      },
      'quality': {
        'swanstation_GPU_ResolutionScale': '4',
        'swanstation_GPU_TrueColor': 'true',
        'swanstation_GPU_PGXPEnable': 'true',
        'swanstation_GPU_TextureFilter': 'JINC2',
      },
    },
    'azahar': {
      'perf': {
        'citra_resolution_factor': '1x (Native)',
        'citra_texture_filter': 'none',
        'citra_async_shader_compilation': 'enabled',
      },
      'balanced': {
        'citra_resolution_factor': '2x',
        'citra_texture_filter': 'none',
        'citra_async_shader_compilation': 'enabled',
      },
      'quality': {
        'citra_resolution_factor': '3x',
        'citra_texture_filter': 'xBRZ',
        'citra_async_shader_compilation': 'enabled',
      },
    },
    'mupen64plus': {
      'perf': {
        'mupen64plus-43screensize': '640x480',
        'mupen64plus-FrameDuping': 'True',
        'mupen64plus-BilinearMode': 'standard',
      },
      'balanced': {
        'mupen64plus-43screensize': '960x720',
        'mupen64plus-FrameDuping': 'False',
        'mupen64plus-BilinearMode': 'standard',
      },
      'quality': {
        'mupen64plus-43screensize': '1440x1080',
        'mupen64plus-FrameDuping': 'False',
        'mupen64plus-BilinearMode': '3point',
      },
    },
    'yabause': {
      'perf': {
        'yabause_frameskip': 'enabled',
        'yabause_force_hle_bios': 'disabled',
      },
      'balanced': {
        'yabause_frameskip': 'disabled',
        'yabause_force_hle_bios': 'disabled',
      },
      'quality': {
        'yabause_frameskip': 'disabled',
        'yabause_force_hle_bios': 'disabled',
      },
    },
    'mgba': {
      'perf': {
        'mgba_interframe_blending': 'OFF',
        'mgba_color_correction': 'OFF',
        'mgba_idle_optimization': 'Remove Known',
      },
      'balanced': {
        'mgba_interframe_blending': 'OFF',
        'mgba_color_correction': 'OFF',
        'mgba_idle_optimization': 'Remove Known',
      },
      'quality': {
        'mgba_interframe_blending': 'mix',
        'mgba_color_correction': 'Auto',
        'mgba_idle_optimization': 'Detect and Remove',
      },
    },
    'gambatte': {
      'perf': {
        'gambatte_gb_colorization': 'disabled',
        'gambatte_mix_frames': 'disabled',
      },
      'balanced': {
        'gambatte_gb_colorization': 'auto',
        'gambatte_mix_frames': 'disabled',
      },
      'quality': {
        'gambatte_gb_colorization': 'auto',
        'gambatte_mix_frames': 'mix',
      },
    },
    'fceumm': {
      'perf': {
        'fceumm_nospritelimit': 'disabled',
        'fceumm_sndquality': 'Low',
        'fceumm_ntsc_filter': 'disabled',
      },
      'balanced': {
        'fceumm_nospritelimit': 'disabled',
        'fceumm_sndquality': 'High',
        'fceumm_ntsc_filter': 'disabled',
      },
      'quality': {
        'fceumm_nospritelimit': 'enabled',
        'fceumm_sndquality': 'Very High',
        'fceumm_ntsc_filter': 'disabled',
      },
    },
    'bsnes': {
      'perf': {
        'bsnes_ppu_fast': 'ON',
        'bsnes_dsp_fast': 'ON',
        'bsnes_dsp_cubic': 'OFF',
        'bsnes_cpu_fastmath': 'ON',
        'bsnes_mode7_scale': '1x',
      },
      'balanced': {
        'bsnes_ppu_fast': 'ON',
        'bsnes_dsp_fast': 'ON',
        'bsnes_dsp_cubic': 'OFF',
        'bsnes_cpu_fastmath': 'OFF',
        'bsnes_mode7_scale': '2x',
      },
      'quality': {
        'bsnes_ppu_fast': 'ON',
        'bsnes_dsp_fast': 'ON',
        'bsnes_dsp_cubic': 'ON',
        'bsnes_cpu_fastmath': 'OFF',
        'bsnes_mode7_scale': '3x',
      },
    },
    'melonds': {
      'perf': {
        'melonds_threaded_renderer': 'enabled',
        'melonds_audio_interpolation': 'None',
      },
      'balanced': {
        'melonds_threaded_renderer': 'enabled',
        'melonds_audio_interpolation': 'Linear',
      },
      'quality': {
        'melonds_threaded_renderer': 'enabled',
        'melonds_audio_interpolation': 'Cubic',
      },
    },
  };

  static String? _keyFor(String coreLibName) {
    final c = coreLibName.toLowerCase();
    if (c.contains('citra')) return 'azahar';
    for (final k in _data.keys) {
      if (c.contains(k)) return k;
    }
    return null;
  }

  /// The core's own spelling of [wanted] (case-insensitive, off/disabled and on/enabled treated
  /// as the same), or null when the core has no such value. Presets are written once for all
  /// core builds, but cores differ in case ("Auto" vs "auto") and in off/disabled wording.
  static String? matchValue(CoreOption o, String wanted) {
    if (o.values.isEmpty) return wanted;
    String norm(String v) {
      final t = v.trim().toLowerCase();
      if (t == 'off' || t == 'false') return 'disabled';
      if (t == 'on' || t == 'true') return 'enabled';
      return t;
    }

    final w = norm(wanted);
    for (final v in o.values) {
      if (v == wanted) return v;
    }
    for (final v in o.values) {
      if (norm(v) == w) return v;
    }
    return null;
  }

  static bool hasPresets(String coreLibName) => _keyFor(coreLibName) != null;

  static String _appliedKey(String core) => 'core_preset_applied_$core';

  static Future<void> rememberApplied(
    String coreLibName,
    String presetId,
    Map<String, String> savedValues,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (savedValues.isEmpty) {
      await prefs.remove(_appliedKey(coreLibName));
      return;
    }
    await prefs.setString(
      _appliedKey(coreLibName),
      jsonEncode({'id': presetId, 'values': savedValues}),
    );
  }

  static Future<AppliedPreset?> loadApplied(String coreLibName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_appliedKey(coreLibName));
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final vals = (m['values'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v.toString()),
      );
      return AppliedPreset(m['id'] as String, vals);
    } catch (_) {
      return null;
    }
  }

  /// The one preset level that is currently active, or an empty set for custom / untouched.
  /// Uses what was really saved when the preset was tapped (so options a core does not offer
  /// cannot block the match, and two levels with identical values cannot both light up).
  /// Without a remembered preset it falls back to a full match, but only if that is unambiguous.
  static Set<String> activeLevels(
    String coreLibName,
    Map<String, String> overrides, {
    AppliedPreset? applied,
  }) {
    if (applied != null &&
        applied.values.isNotEmpty &&
        applied.values.entries.every((e) => overrides[e.key] == e.value)) {
      return {applied.id};
    }
    final out = <String>{};
    for (final p in presets) {
      final wanted = forCore(coreLibName, p.id);
      if (wanted.isEmpty) continue;
      if (wanted.entries.every((e) => overrides[e.key] == e.value)) {
        out.add(p.id);
      }
    }
    return out.length == 1 ? out : <String>{};
  }

  static Map<String, String> forCore(String coreLibName, String presetId) {
    final k = _keyFor(coreLibName);
    return k == null ? const {} : (_data[k]![presetId] ?? const {});
  }

  /// Groups any option (including ones we've never seen) by keywords in its key + label.
  static OptionCategory categoryOf(CoreOption o) {
    final s = '${o.key} ${o.label}'.toLowerCase();
    bool any(List<String> words) => words.any(s.contains);

    if (any([
      'audio',
      'sound',
      'volume',
      'interpolation',
      'bitrate',
      'low-pass',
      'lowpass',
      'ym2612',
      'dsp',
    ])) {
      return OptionCategory.audio;
    }
    if (any([
      'input',
      'touch',
      'pointer',
      'joypad',
      'analog',
      'rumble',
      'button',
      'controller',
      'dpad',
      'direction',
      'joystick',
    ])) {
      return OptionCategory.input;
    }
    if (any([
      'region',
      'language',
      'model',
      'bios',
      'console',
      'boot',
      'hardware',
      'firmware',
      'system',
    ])) {
      return OptionCategory.system;
    }
    if (any([
      'cpu',
      'jit',
      'thread',
      'skip',
      'fast',
      'speed',
      'fps',
      'cache',
      'overclock',
      'idle',
      'async',
      'lazy',
      'timing',
      'buffer',
      'pipeline',
      'memory',
      'loading',
      'load image',
      'preload',
      'drc',
      'recompiler',
      'dup',
      'rsp',
    ])) {
      return OptionCategory.performance;
    }
    if (any([
      'resolution',
      'scale',
      'scaling',
      'filter',
      'texture',
      'shader',
      'render',
      'gpu',
      'screen',
      'layout',
      'aspect',
      'color',
      'blending',
      'ghost',
      'vsync',
      'anisotropic',
      'upscal',
      'pgxp',
      'widescreen',
      'crop',
      'border',
      'overscan',
      'sharp',
      'smooth',
      'dither',
      'graphics',
      'api',
      'gap',
      'mix',
      'rdp',
      'bilinear',
      'sprite',
      'sprlim',
      'mipmap',
      'lcd',
    ])) {
      return OptionCategory.video;
    }
    return OptionCategory.other;
  }
}
