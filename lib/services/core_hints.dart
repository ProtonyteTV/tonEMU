// lib/services/core_hints.dart
import 'core_settings.dart';

/// One-line plain-English explanations shown under core options, so people don't have to guess
/// what "ppsspp_lazy_texture_caching" does. Exact keys win; otherwise keywords in the key/label.
class CoreHints {
  static const Map<String, String> _exact = {
    // PSP
    'ppsspp_internal_resolution':
        'Higher looks sharper but needs a much faster phone.',
    'ppsspp_skip_buffer_effects':
        'Faster, but some effects (glow, motion blur) may disappear.',
    'ppsspp_lazy_texture_caching':
        'Speeds up games that change textures often.',
    'ppsspp_auto_frameskip':
        'Drops frames automatically when the game runs slow.',
    'ppsspp_fast_memory':
        'Faster, but can crash some games. Turn off if a game closes.',
    'ppsspp_inflight_frames':
        'More buffering is smoother but adds input delay.',
    'ppsspp_locked_cpu_speed':
        'Limits the emulated CPU. Only change it to fix a specific game.',
    'ppsspp_button_preference': 'Which button confirms in system menus.',
    // PS1
    'swanstation_GPU_ResolutionScale':
        '1x is original. Higher is sharper and slower.',
    'swanstation_GPU_PGXPEnable':
        'Fixes wobbling 3D geometry. Small speed cost.',
    'swanstation_GPU_TrueColor': 'Removes colour banding. Small speed cost.',
    'swanstation_BIOS_PatchFastBoot': 'Skips the PlayStation logo on start.',
    // 3DS
    'citra_resolution_factor':
        'Native is 240p-class. Each step up is sharper and heavier.',
    'citra_use_cpu_jit':
        'Needed for good speed. Only turn off to test a crash.',
    'citra_async_shader_compilation': 'Reduces stutter while shaders compile.',
    'citra_is_new_3ds': 'A few games only work on one model.',
    'citra_use_virtual_sd': 'Lets games keep extra data on a virtual SD card.',
    // DS
    'melonds_threaded_renderer': 'Uses a second CPU core. Usually faster.',
    'melonds_console_mode':
        'DSi mode needs the DSi BIOS files (see BIOS & System Files).',
    'melonds_boot_directly':
        'Skips the DS menu. Turn off to see the firmware menu.',
    'melonds_use_fw_settings':
        'Use the language/name stored in your DS firmware.',
    'melonds_jit_enable': 'Much faster. Turn off only if a game crashes.',
    'melonds_mic_input':
        'What the DS microphone hears. Blow-type games use "blow".',
    'melonds_show_cursor': 'Draws a pointer on the touch screen.',
    // Saturn / N64
    'yabause_force_hle_bios': 'Use the built-in BIOS instead of your file.',
    'mupen64plus-43screensize':
        'Higher is sharper and slower. Pick lower if it stutters.',
    'mupen64plus-EnableFBEmulation':
        'Needed by some games for effects, costs speed.',
    // SNES
    'bsnes_ppu_fast':
        'Faster picture emulation. Turn off only for accuracy tests.',
    'bsnes_dsp_fast': 'Faster sound emulation. Leave on unless audio glitches.',
    'bsnes_dsp_cubic': 'Smoother sound. Small speed cost.',
    'bsnes_mode7_scale': 'Sharper spinning/scaling backgrounds (F-Zero, Mario Kart). Higher is heavier.',
    'bsnes_cpu_fastmath': 'Faster, but can break a few games.',
    'bsnes_ppu_no_sprite_limit':
        'Removes the original sprite limit. Fixes flicker, may change visuals.',
    // GBA / GB
    'mgba_use_bios': 'Uses your gba_bios.bin if you imported one.',
    'mgba_skip_bios': 'Skips the Game Boy Advance logo on start.',
    'mgba_interframe_blending': 'Blends frames to fix flicker in some games.',
    'mgba_color_correction':
        'Makes colours look like the real handheld screen.',
    'gambatte_gb_colorization': 'Adds colour to original Game Boy games.',
  };

  static const List<(List<String>, String)> _rules = [
    (
      ['resolution', 'internal_res'],
      'Higher looks sharper but needs a faster phone.',
    ),
    (['frameskip'], 'Skips frames to keep speed up on slower phones.'),
    (
      ['jit', 'dynarec', 'drc'],
      'Faster CPU emulation. Leave on unless a game crashes.',
    ),
    (['thread'], 'Uses extra CPU cores. Usually faster.'),
    (['anisotropic'], 'Sharper textures at an angle. Small cost.'),
    (
      ['bilinear', 'texture_filter', 'texture filter'],
      'Smooths textures. Changes the look more than the speed.',
    ),
    (['interpolation'], 'Audio smoothing. Higher is cleaner and a bit slower.'),
    (['language'], 'In-game language, for games that support it.'),
    (['async'], 'Reduces stutter while shaders compile.'),
    (
      ['bios'],
      'Uses your BIOS file if one is installed (see BIOS & System Files).',
    ),
    (['overclock'], 'Runs the emulated CPU faster. Can break game timing.'),
    (['deadzone'], 'Ignores small stick movements.'),
    (
      ['sprite', 'sprlim'],
      'Removes the original sprite limit. Fixes flicker, may change visuals.',
    ),
    (['aspect'], 'Picture shape. Original is 4:3 for most systems.'),
    (['gap'], 'Space between the two screens.'),
  ];

  static String? of(CoreOption o) {
    final exact = _exact[o.key];
    if (exact != null) return exact;
    final s = '${o.key} ${o.label}'.toLowerCase();
    for (final r in _rules) {
      if (r.$1.any(s.contains)) return r.$2;
    }
    return null;
  }
}
