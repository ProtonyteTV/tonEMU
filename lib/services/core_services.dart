// lib/services/core_presets.dart
import 'package:material_ui/material_ui.dart';

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
        'azahar_resolution_factor': '1x (Native)',
        'azahar_texture_filter': 'none',
        'azahar_async_shader_compilation': 'enabled',
      },
      'balanced': {
        'azahar_resolution_factor': '2x',
        'azahar_texture_filter': 'none',
        'azahar_async_shader_compilation': 'enabled',
      },
      'quality': {
        'azahar_resolution_factor': '3x',
        'azahar_texture_filter': 'xBRZ',
        'azahar_async_shader_compilation': 'enabled',
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

  static bool hasPresets(String coreLibName) => _keyFor(coreLibName) != null;

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
      'cache',
      'overclock',
      'idle',
      'async',
      'lazy',
      'timing',
      'buffer',
      'load image',
      'preload',
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
    ])) {
      return OptionCategory.video;
    }
    return OptionCategory.other;
  }
}
