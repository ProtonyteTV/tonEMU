// lib/services/core_catalog.dart
import 'core_settings.dart';

/// Built-in list of the common options of every bundled core, so settings can be edited right after
/// install. Once a core has actually run, its real option list (cached by the game screen) replaces
/// this one. Keys the core doesn't know are ignored by it, so a wrong key is harmless.
class CoreCatalog {
  static CoreOption _o(String key, String label, List<String> values) =>
      CoreOption(key: key, current: '', label: label, values: values);

  static const _onOff = ['enabled', 'disabled'];
  static const _trueFalse = ['true', 'false'];
  static const _falseTrue = ['false', 'true'];

  /// Real defaults of options whose value list does NOT start with the default (or where the
  /// built-in list above is not in the core's order). The settings screen uses this for "Reset"
  /// instead of assuming "first value = default".
  static const Map<String, String> _knownDefaults = {
    'yabause_frameskip':
        'disabled', // Saturn: frameskip is OFF unless the user turns it on
    'yabause_force_hle_bios': 'disabled',
    'yabause_addon_cart': 'none',
    'yabause_numthreads': '4',
    'swanstation_BIOS_PatchFastBoot': 'false',
    'swanstation_CDROM_LoadImageToRAM':
        'false', // true would keep the whole disc in RAM
    'swanstation_GPU_WidescreenHack': 'false',
    'mupen64plus-43screensize': '640x480',
  };

  static String? defaultFor(String key) => _knownDefaults[key];

  static List<CoreOption> forCore(String coreLibName) {
    final c = coreLibName.toLowerCase();
    if (c.contains('mgba')) return _mgba();
    if (c.contains('gambatte')) return _gambatte();
    if (c.contains('fceumm')) return _fceumm();
    if (c.contains('melonds')) return _melonds();
    if (c.contains('swanstation')) return _swanstation();
    if (c.contains('ppsspp')) return _ppsspp();
    if (c.contains('azahar') || c.contains('citra')) return _azahar();
    if (c.contains('mupen64plus')) return _mupen64();
    if (c.contains('bsnes')) return _bsnes();
    if (c.contains('blastem')) return _blastem();
    if (c.contains('gearsystem')) return _gearsystem();
    if (c.contains('yabause')) return _yabause();
    if (c.contains('pokemini')) return _pokemini();
    if (c.contains('wswan')) return _wswan();
    return [];
  }

  static List<CoreOption> _mgba() => [
    _o('mgba_gb_model', 'Game Boy model', [
      'Autodetect',
      'Game Boy',
      'Super Game Boy',
      'Game Boy Color',
      'Game Boy Advance',
    ]),
    _o('mgba_use_bios', 'Use BIOS file if found', ['ON', 'OFF']),
    _o('mgba_skip_bios', 'Skip BIOS intro', ['OFF', 'ON']),
    _o('mgba_sgb_borders', 'Super Game Boy borders', ['ON', 'OFF']),
    _o('mgba_color_correction', 'Color correction', [
      'OFF',
      'GBA',
      'Game Boy Color',
      'Auto',
    ]),
    _o('mgba_interframe_blending', 'Interframe blending', [
      'OFF',
      'mix',
      'mix_smart',
      'lcd_ghosting',
      'lcd_ghosting_fast',
    ]),
    _o('mgba_frameskip', 'Frameskip', [
      'disabled',
      'auto',
      'auto_threshold',
      'fixed_interval',
    ]),
    _o('mgba_idle_optimization', 'Idle loop removal', [
      'Remove Known',
      'Detect and Remove',
      "Don't Remove",
    ]),
    _o('mgba_audio_low_pass_filter', 'Audio low-pass filter', [
      'disabled',
      'enabled',
    ]),
  ];

  static List<CoreOption> _fceumm() => [
    _o('fceumm_aspect', 'Aspect ratio', ['8:7 PAR', '4:3']),
    _o('fceumm_ntsc_filter', 'NTSC filter', [
      'disabled',
      'composite',
      'svideo',
      'rgb',
      'monochrome',
    ]),
    _o('fceumm_overscan', 'Crop overscan', ['disabled', 'enabled']),
    _o('fceumm_nospritelimit', 'No sprite limit', ['disabled', 'enabled']),
    _o('fceumm_overclocking', 'Overclocking', [
      'disabled',
      '2x-Postrender',
      '2x-VBlank',
    ]),
    _o('fceumm_sndquality', 'Sound quality', ['Low', 'High', 'Very High']),
    _o('fceumm_sndlowpass', 'Audio low-pass filter', ['disabled', 'enabled']),
    _o('fceumm_region', 'Region', ['Auto', 'NTSC', 'PAL', 'Dendy']),
    _o('fceumm_up_down_allowed', 'Allow Up+Down on D-pad', [
      'disabled',
      'enabled',
    ]),
  ];

  static List<CoreOption> _gambatte() => [
    _o('gambatte_gb_hwmode', 'Emulated hardware', ['Auto', 'GB', 'GBC', 'GBA']),
    _o('gambatte_gb_colorization', 'GB colorization', [
      'disabled',
      'auto',
      'GBC',
      'SGB',
      'internal',
      'custom',
    ]),
    _o('gambatte_gb_bootloader', 'Use official bootloader', _onOff),
    _o('gambatte_mix_frames', 'Interframe blending', [
      'disabled',
      'mix',
      'lcd_ghosting',
      'lcd_ghosting_fast',
    ]),
    _o('gambatte_up_down_allowed', 'Allow opposing directions', [
      'disabled',
      'enabled',
    ]),
  ];

  static List<CoreOption> _melonds() => [
    _o('melonds_console_mode', 'Console mode', ['DS', 'DSi']),
    _o('melonds_boot_directly', 'Boot game directly', _onOff),
    _o('melonds_threaded_renderer', 'Threaded software renderer', [
      'disabled',
      'enabled',
    ]),
    _o('melonds_audio_bitrate', 'Audio bitrate', ['10-bit', '16-bit']),
    _o('melonds_audio_interpolation', 'Audio interpolation', [
      'None',
      'Linear',
      'Cosine',
      'Cubic',
    ]),
    _o('melonds_screen_gap', 'Screen gap', [
      '0',
      '1',
      '2',
      '8',
      '16',
      '32',
      '64',
    ]),
    _o('melonds_use_fw_settings', 'Use firmware settings', [
      'disabled',
      'enabled',
    ]),
    _o('melonds_language', 'System language', [
      'English',
      'Japanese',
      'French',
      'German',
      'Italian',
      'Spanish',
    ]),
    _o('melonds_jit_enable', 'CPU JIT (faster)', _onOff),
    _o('melonds_jit_branch_optimisations', 'JIT branch optimisations', _onOff),
    _o(
      'melonds_jit_literal_optimisations',
      'JIT literal optimisations',
      _onOff,
    ),
    _o('melonds_jit_fast_memory', 'JIT fast memory', _onOff),
    _o('melonds_show_cursor', 'Touch screen cursor', [
      'always',
      'touching',
      'timeout',
      'disabled',
    ]),
    _o('melonds_hybrid_ratio', 'Hybrid layout: large screen size', ['2', '3']),
    _o('melonds_dsi_sdcard', 'Virtual DSi SD card', ['disabled', 'enabled']),
  ];

  static List<CoreOption> _swanstation() => [
    _o('swanstation_Console_Region', 'Console region', [
      'Auto',
      'NTSC-J',
      'NTSC-U',
      'PAL',
    ]),
    _o('swanstation_GPU_ResolutionScale', 'Internal resolution scale', [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '8',
      '10',
      '12',
      '16',
    ]),
    _o('swanstation_GPU_TrueColor', 'True color (24-bit)', _trueFalse),
    _o('swanstation_GPU_PGXPEnable', 'PGXP geometry correction', _trueFalse),
    _o('swanstation_GPU_TextureFilter', 'Texture filtering', [
      'Nearest',
      'Bilinear',
      'BilinearBinAlpha',
      'JINC2',
      'JINC2BinAlpha',
      'xBR',
      'xBRBinAlpha',
    ]),
    _o('swanstation_GPU_UseThread', 'Threaded GPU', _trueFalse),
    _o('swanstation_BIOS_PatchFastBoot', 'Fast boot', _falseTrue),
    _o(
      'swanstation_CDROM_LoadImageToRAM',
      'Preload disc image to RAM',
      _falseTrue,
    ),
    _o('swanstation_GPU_WidescreenHack', 'Widescreen hack', _falseTrue),
  ];

  static List<CoreOption> _ppsspp() => [
    _o('ppsspp_internal_resolution', 'Internal resolution', [
      '480x272',
      '960x544',
      '1440x816',
      '1920x1088',
      '2400x1360',
      '2880x1632',
      '3360x1904',
      '3840x2176',
    ]),
    _o('ppsspp_cpu_core', 'CPU core', ['JIT', 'IR JIT', 'Interpreter']),
    _o('ppsspp_frameskip', 'Frameskip', [
      'Off',
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
    ]),
    _o('ppsspp_auto_frameskip', 'Auto frameskip', ['disabled', 'enabled']),
    _o('ppsspp_texture_scaling_level', 'Texture scaling level', [
      'disabled',
      '2x',
      '3x',
      '4x',
      '5x',
    ]),
    _o('ppsspp_texture_filtering', 'Texture filtering', [
      'Auto',
      'Nearest',
      'Linear',
      'Auto max quality',
    ]),
    _o('ppsspp_texture_anisotropic_filtering', 'Anisotropic filtering', [
      'off',
      '2x',
      '4x',
      '8x',
      '16x',
    ]),
    _o('ppsspp_language', 'System language', [
      'Automatic',
      'English',
      'Japanese',
      'French',
      'Spanish',
      'German',
      'Italian',
      'Dutch',
      'Portuguese',
      'Russian',
      'Korean',
      'Chinese Traditional',
      'Chinese Simplified',
    ]),
    _o('ppsspp_fast_memory', 'Fast memory (unstable)', _onOff),
    _o('ppsspp_lazy_texture_caching', 'Lazy texture caching', [
      'disabled',
      'enabled',
    ]),
    _o('ppsspp_skip_buffer_effects', 'Skip buffer effects', [
      'disabled',
      'enabled',
    ]),
    _o('ppsspp_io_timing_method', 'IO timing method', [
      'Fast',
      'Host',
      'Simulate UMD delays',
    ]),
    _o('ppsspp_inflight_frames', 'Frame buffering', [
      'Up to 2',
      'Up to 1',
      'No buffering',
    ]),
    _o('ppsspp_locked_cpu_speed', 'Locked CPU speed', [
      'disabled',
      '222MHz',
      '266MHz',
      '333MHz',
    ]),
    _o('ppsspp_button_preference', 'Confirmation button', ['Cross', 'Circle']),
    _o('ppsspp_hardware_tessellation', 'Hardware tessellation', [
      'disabled',
      'enabled',
    ]),
  ];

  static List<CoreOption> _azahar() => [
    _o('citra_region_value', 'Console region', [
      'Auto',
      'Japan',
      'USA',
      'Europe',
      'Australia',
      'China',
      'Korea',
      'Taiwan',
    ]),
    _o('citra_resolution_factor', 'Internal resolution', [
      '1x (Native)',
      '2x',
      '3x',
      '4x',
      '5x',
      '6x',
      '7x',
      '8x',
      '9x',
      '10x',
    ]),
    _o('citra_is_new_3ds', '3DS model', ['New 3DS', 'Old 3DS']),
    _o('citra_language', 'System language', [
      'English',
      'Japanese',
      'French',
      'Spanish',
      'German',
      'Italian',
      'Dutch',
      'Portuguese',
      'Russian',
      'Korean',
      'Chinese (Simplified)',
      'Chinese (Traditional)',
    ]),
    _o('citra_use_cpu_jit', 'CPU JIT', _onOff),
    _o('citra_use_shader_jit', 'Shader JIT', _onOff),
    _o('citra_async_shader_compilation', 'Async shader compilation', _onOff),
    _o('citra_texture_filter', 'Texture filter', [
      'none',
      'Anime4K',
      'Bicubic',
      'ScaleForce',
      'xBRZ',
      'MMPX',
    ]),
    _o('citra_touch_touchscreen', 'Touchscreen touch input', _onOff),
    _o('citra_texture_sampling', 'Texture sampling', [
      'GameControlled',
      'NearestNeighbor',
      'Linear',
    ]),
    _o('citra_custom_textures', 'Custom textures', ['disabled', 'enabled']),
    _o('citra_preload_textures', 'Preload custom textures', [
      'disabled',
      'enabled',
    ]),
    _o('citra_use_virtual_sd', 'Virtual SD card', _onOff),
  ];

  // Sega / N64 cores: key names follow each core's published option list. As elsewhere, the core's
  // own list replaces these after the first launch, and unknown keys are ignored by the core.
  static List<CoreOption> _mupen64() => [
    _o('mupen64plus-rdp-plugin', 'Graphics plugin (RDP)', [
      'gliden64',
      'angrylion',
    ]),
    _o('mupen64plus-rsp-plugin', 'RSP plugin', ['hle', 'cxd4']),
    _o('mupen64plus-cpucore', 'CPU core', [
      'dynamic_recompiler',
      'cached_interpreter',
      'pure_interpreter',
    ]),
    _o('mupen64plus-43screensize', 'Internal resolution (4:3)', [
      '320x240',
      '640x480',
      '960x720',
      '1280x960',
      '1440x1080',
      '1600x1200',
      '1920x1440',
      '2240x1680',
      '2560x1920',
    ]),
    _o('mupen64plus-aspect', 'Aspect ratio', ['4:3', '16:9', '16:9 adjusted']),
    _o('mupen64plus-BilinearMode', 'Bilinear filtering', [
      'standard',
      '3point',
    ]),
    _o('mupen64plus-txFilterMode', 'Texture filter', [
      'None',
      'Smooth filtering 1',
      'Smooth filtering 2',
      'Smooth filtering 3',
      'Smooth filtering 4',
      'Sharp filtering 1',
      'Sharp filtering 2',
    ]),
    _o('mupen64plus-EnableFBEmulation', 'Framebuffer emulation', [
      'True',
      'False',
    ]),
    _o('mupen64plus-FrameDuping', 'Frame duplication', ['False', 'True']),
    _o('mupen64plus-Framerate', 'Framerate', ['Original', 'Fullspeed']),
    _o('mupen64plus-EnableHWLighting', 'Hardware per-pixel lighting', [
      'False',
      'True',
    ]),
    _o('mupen64plus-pak1', 'Controller pak', ['memory', 'rumble', 'none']),
    _o('mupen64plus-astick-deadzone', 'Analog deadzone (%)', [
      '0',
      '5',
      '10',
      '15',
      '20',
      '25',
      '30',
    ]),
    _o('mupen64plus-astick-sensitivity', 'Analog sensitivity (%)', [
      '50',
      '75',
      '100',
      '125',
      '150',
    ]),
  ];

  // SNES: bsnes (docs.libretro.com/library/bsnes). As elsewhere, the core's own list replaces this
  // one after the first launch, and keys it doesn't know are ignored, so a wrong key is harmless.
  static List<CoreOption> _bsnes() => [
    _o('bsnes_ppu_fast', 'Fast PPU', ['ON', 'OFF']),
    _o('bsnes_ppu_deinterlace', 'Deinterlace (PPU)', ['ON', 'OFF']),
    _o('bsnes_ppu_no_sprite_limit', 'Remove sprite limit', ['OFF', 'ON']),
    _o('bsnes_mode7_scale', 'Mode 7 scale', [
      '1x',
      '2x',
      '3x',
      '4x',
      '5x',
      '6x',
      '7x',
      '8x',
    ]),
    _o('bsnes_dsp_fast', 'Fast DSP', ['ON', 'OFF']),
    _o('bsnes_dsp_cubic', 'Cubic audio interpolation', ['OFF', 'ON']),
    _o('bsnes_cpu_fastmath', 'Fast CPU math', ['OFF', 'ON']),
    _o('bsnes_blur_emulation', 'Blur emulation', ['OFF', 'ON']),
  ];

  // Genesis / Mega Drive: BlastEm has hardly any options, so nothing is listed here. Whatever the
  // core exposes shows up after the first launch.
  static List<CoreOption> _blastem() => [];

  // Master System / Game Gear: Gearsystem (docs.libretro.com/library/gearsystem).
  // Pokemon Mini: PokeMini (docs.libretro.com/library/pokemini). Default value listed first.
  static List<CoreOption> _pokemini() => [
    _o('pokemini_video_scale', 'Video scale', [
      '4x',
      '1x',
      '2x',
      '3x',
      '5x',
      '6x',
    ]),
    _o('pokemini_lcdfilter', 'LCD filter', ['dotmatrix', 'scanline', 'none']),
    _o('pokemini_lcdmode', 'LCD mode', ['analog', '3shades', '2shades']),
    _o('pokemini_lcdcontrast', 'LCD contrast', [
      '64',
      '0',
      '16',
      '32',
      '48',
      '80',
      '96',
    ]),
    _o('pokemini_lcdbright', 'LCD brightness', [
      '0',
      '-80',
      '-60',
      '-40',
      '-20',
      '20',
      '40',
      '60',
      '80',
    ]),
    _o('pokemini_palette', 'Palette', [
      'Default',
      'Old',
      'Monochrome',
      'Green',
      'Green Vector',
      'Red',
      'Red Vector',
      'Blue LCD',
      'LEDBacklight',
      'Girl Power',
      'Blue',
      'Blue Vector',
      'Sepia',
      'Monochrome Vector',
    ]),
    _o('pokemini_piezofilter', 'Speaker filter', ['ON', 'OFF']),
    _o('pokemini_rumblelvl', 'Rumble level', ['3', '2', '1', '0']),
    _o('pokemini_controller_rumble', 'Controller rumble', ['ON', 'OFF']),
    _o('pokemini_screen_shake', 'Screen shake', ['ON', 'OFF']),
  ];

  // WonderSwan / Color: Beetle Cygne (mednafen_wswan). The core's own list replaces this once a
  // game has been started, so only options whose keys are well known are listed.
  static List<CoreOption> _wswan() => [
    _o('wswan_rotate_display', 'Rotate display', ['manual', 'enabled']),
    _o('wswan_rotate_keymap', 'Rotate button mappings', [
      'auto',
      'disabled',
      'enabled',
    ]),
    _o('wswan_frameskip', 'Frameskip', ['disabled', 'auto', 'manual']),
    _o('wswan_sound_sample_rate', 'Sound sample rate', [
      '44100',
      '11025',
      '22050',
      '48000',
      '96000',
    ]),
    _o('wswan_sound_low_pass', 'Audio filter', ['disabled', 'enabled']),
    _o('wswan_gfx_colors', 'Color depth', ['16bit', '24bit']),
  ];

  static List<CoreOption> _gearsystem() => [
    _o('gearsystem_aspect_ratio', 'Aspect ratio', [
      '1:1 PAR',
      '8:7 PAR',
      '4:3 DAR',
      '16:9 DAR',
      '16:10 DAR',
    ]),
    _o('gearsystem_overscan', 'Crop overscan', [
      'Disabled',
      'Top+Bottom',
      'Full (284 width)',
      'Full (320 width)',
    ]),
    _o('gearsystem_up_down_allowed', 'Allow Up+Down on D-pad', [
      'Disabled',
      'Enabled',
    ]),
  ];

  static List<CoreOption> _yabause() => [
    _o('yabause_frameskip', 'Frameskip', ['disabled', 'enabled']),
    _o('yabause_force_hle_bios', 'Force HLE BIOS', ['disabled', 'enabled']),
    _o('yabause_addon_cart', 'Cartridge add-on', ['none', '1M_ram', '4M_ram']),
    _o('yabause_numthreads', 'CPU threads', ['1', '2', '4', '8', '16']),
  ];
}
