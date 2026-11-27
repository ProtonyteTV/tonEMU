import '../services/emulator_bridge.dart';

enum ConsoleType {
  nes,
  snes,
  gb,
  gbc,
  gba,
  nds,
  ps1,
  psp,
  n3ds,
  n64,
  sms,
  gg,
  genesis,
  saturn,
  pokemini,
  wonderswan,
}

enum FaceStyle { nintendo, playstation }

/// One touch button on a system's pad. For face buttons [x]/[y] are the button's centre as a
/// fraction (0..1) of the face cluster; shoulder buttons ignore them.
class PadButton {
  final String id;
  final String label;
  final int
  key; // Android keycode (see EmulatorBridge) = the RetroPad button it drives
  final double x;
  final double y;
  const PadButton(this.id, this.label, this.key, [this.x = 0.5, this.y = 0.5]);
}

/// Touch layout of a system that doesn't use the built-in Nintendo / PlayStation style layouts.
/// `ConsoleSystem.pad == null` keeps the original layout code path unchanged.
class PadSpec {
  final List<PadButton> face;
  final double faceRadius; // fraction of the cluster size
  final double faceScale; // 1.0 = standard cluster size
  final List<PadButton> left; // shoulder buttons, outermost first
  final List<PadButton> right;
  final bool hasSelect;
  final String selectLabel;
  final String startLabel;
  final bool
  cStick; // N64: second stick driving the right analog axis (C buttons)
  final bool hasStart; // false = the system has no Start button (the pill is not drawn)

  const PadSpec({
    required this.face,
    this.faceRadius = 0.185,
    this.faceScale = 1.0,
    this.left = const [],
    this.right = const [],
    this.hasSelect = true,
    this.selectLabel = 'SELECT',
    this.startLabel = 'START',
    this.cStick = false,
    this.hasStart = true,
  });
}

// BlastEm maps the Mega Drive pad onto the RetroPad by position:
//   A B C  = RetroPad Y B A      X Y Z = RetroPad L X R      MODE = Select
// (Master System / Game Gear buttons 1 and 2 are RetroPad B and A.)
const PadSpec _twoButtonPad = PadSpec(
  face: [
    PadButton('b', '1', EmulatorBridge.keyB, 0.28, 0.60),
    PadButton('a', '2', EmulatorBridge.keyA, 0.72, 0.40),
  ],
  faceRadius: 0.22,
  faceScale: 0.9,
  hasSelect: false,
);

const PadSpec _smsPad = PadSpec(
  face: [
    PadButton('b', '1', EmulatorBridge.keyB, 0.28, 0.60),
    PadButton('a', '2', EmulatorBridge.keyA, 0.72, 0.40),
  ],
  faceRadius: 0.22,
  faceScale: 0.9,
  hasSelect: false,
  startLabel: 'PAUSE',
);

// Pokemon Mini (PokeMini core, docs.libretro.com/library/pokemini):
//   A = RetroPad A   B = RetroPad B   C = R1   Shake = L1   Power = Select   (no Start button)
const PadSpec _pokeMiniPad = PadSpec(
  face: [
    PadButton('b', 'B', EmulatorBridge.keyB, 0.28, 0.60),
    PadButton('a', 'A', EmulatorBridge.keyA, 0.72, 0.40),
  ],
  faceRadius: 0.22,
  faceScale: 0.9,
  left: [PadButton('shake', 'SHAKE', EmulatorBridge.keyL1)],
  right: [PadButton('c', 'C', EmulatorBridge.keyR1)],
  selectLabel: 'POWER',
  hasStart: false,
);

// WonderSwan / Color (Beetle Cygne, docs.libretro.com/library/beetle_cygne):
//   A = RetroPad A   B = RetroPad B   Start = Start   D-Pad = the X cursor
//   Select = "Rotate screen + active D-Pad" (vertical games). The Y cursor sits on L1 / R1 / L2 / R2
//   but the core's "Rotate Button Mappings: Auto" already routes the D-Pad to it when rotated.
const PadSpec _wonderSwanPad = PadSpec(
  face: [
    PadButton('b', 'B', EmulatorBridge.keyB, 0.28, 0.60),
    PadButton('a', 'A', EmulatorBridge.keyA, 0.72, 0.40),
  ],
  faceRadius: 0.22,
  faceScale: 0.9,
  selectLabel: 'ROTATE',
);

const List<PadButton> _sixFace = [
  PadButton('a', 'A', EmulatorBridge.keyY, 0.17, 0.68),
  PadButton('b', 'B', EmulatorBridge.keyB, 0.50, 0.68),
  PadButton('c', 'C', EmulatorBridge.keyA, 0.83, 0.68),
  PadButton('x', 'X', EmulatorBridge.keyL1, 0.17, 0.32),
  PadButton('y', 'Y', EmulatorBridge.keyX, 0.50, 0.32),
  PadButton('z', 'Z', EmulatorBridge.keyR1, 0.83, 0.32),
];

const PadSpec _genesisPad = PadSpec(
  face: _sixFace,
  faceRadius: 0.14,
  faceScale: 1.2,
  selectLabel: 'MODE',
);

// Saturn (Yabause) maps the Saturn pad onto the RetroPad like this (docs.libretro.com/library/yabause):
//   A = B   B = A   C = R1      X = Y   Y = X   Z = L1      L = L2   R = R2
// This is NOT the Mega Drive mapping above, so the Genesis face list can't be reused.
const List<PadButton> _saturnFace = [
  PadButton('a', 'A', EmulatorBridge.keyB, 0.17, 0.68),
  PadButton('b', 'B', EmulatorBridge.keyA, 0.50, 0.68),
  PadButton('c', 'C', EmulatorBridge.keyR1, 0.83, 0.68),
  PadButton('x', 'X', EmulatorBridge.keyY, 0.17, 0.32),
  PadButton('y', 'Y', EmulatorBridge.keyX, 0.50, 0.32),
  PadButton('z', 'Z', EmulatorBridge.keyL1, 0.83, 0.32),
];

// Saturn: L / R triggers on the shoulders.
const PadSpec _saturnPad = PadSpec(
  face: _saturnFace,
  faceRadius: 0.14,
  faceScale: 1.2,
  hasSelect: false,
  left: [PadButton('l1', 'L', EmulatorBridge.keyL2)],
  right: [PadButton('r1', 'R', EmulatorBridge.keyR2)],
);

// N64 (Mupen64Plus-Next): N64 A = RetroPad B, N64 B = RetroPad Y, Z = L2, C buttons = right stick.
const PadSpec _n64Pad = PadSpec(
  face: [
    PadButton('b', 'B', EmulatorBridge.keyY, 0.30, 0.36),
    PadButton('a', 'A', EmulatorBridge.keyB, 0.68, 0.64),
  ],
  faceRadius: 0.2,
  hasSelect: false,
  left: [
    PadButton('l1', 'L', EmulatorBridge.keyL1),
    PadButton('z', 'Z', EmulatorBridge.keyL2),
  ],
  right: [PadButton('r1', 'R', EmulatorBridge.keyR1)],
  cStick: true,
);

class ScreenMode {
  final String id;
  final String label;
  const ScreenMode(this.id, this.label);
}

const List<ScreenMode> _ndsModes = [
  ScreenMode('top_bottom', 'Top / Bottom'),
  ScreenMode('bottom_top', 'Bottom / Top'),
  ScreenMode('left_right', 'Left / Right'),
  ScreenMode('right_left', 'Right / Left'),
  ScreenMode('hybrid_top', 'Hybrid (big top)'),
  ScreenMode('hybrid_bottom', 'Hybrid (big bottom)'),
  ScreenMode('top_only', 'Top only'),
  ScreenMode('bottom_only', 'Bottom only'),
];

const List<ScreenMode> _n3dsModes = [
  ScreenMode('top_bottom', 'Top / Bottom'),
  ScreenMode('left_right', 'Side by side'),
  ScreenMode('hybrid_top', 'Large top, small bottom'),
  ScreenMode('top_only', 'Top only'),
  ScreenMode('bottom_only', 'Bottom only'),
];

class ConsoleSystem {
  final ConsoleType type;
  final String name;
  final String shortName;
  final String coreLibName;
  final List<String> extensions;
  final bool supportsVulkan;
  final bool isDualScreen;

  /// Width / height of the picture (used to size the game view in portrait).
  final double aspect;
  final bool hasAnalog;
  final bool hasL2R2;
  final FaceStyle faceStyle;
  final List<ScreenMode> screenModes;

  /// Custom touch layout (null = the original Nintendo / PlayStation style layouts).
  final PadSpec? pad;

  const ConsoleSystem({
    required this.type,
    required this.name,
    required this.shortName,
    required this.coreLibName,
    required this.extensions,
    this.supportsVulkan = false,
    this.isDualScreen = false,
    this.aspect = 4 / 3,
    this.hasAnalog = false,
    this.hasL2R2 = false,
    this.faceStyle = FaceStyle.nintendo,
    this.screenModes = const [],
    this.pad,
  });

  String get defaultScreenMode => 'top_bottom';

  /// Aspect ratio of the picture for a given dual-screen layout.
  double aspectFor(String? modeId) {
    if (!isDualScreen) return aspect;
    final is3ds = type == ConsoleType.n3ds;
    switch (modeId) {
      case 'left_right':
      case 'right_left':
        return is3ds ? 3.0 : 2.667;
      case 'hybrid_top':
      case 'hybrid_bottom':
        return 1.25;
      case 'top_only':
        return is3ds ? 1.667 : 1.333;
      case 'bottom_only':
        return 1.333;
      default: // top_bottom / bottom_top
        return is3ds ? 0.833 : 0.667;
    }
  }

  static const List<ConsoleSystem> allSystems = [
    ConsoleSystem(
      type: ConsoleType.nes,
      name: 'Nintendo Entertainment System',
      shortName: 'NES',
      coreLibName: 'libfceumm_libretro_android.so',
      extensions: ['nes', 'unf', 'unif'],
      aspect: 4 / 3,
    ),
    ConsoleSystem(
      type: ConsoleType.snes,
      name: 'Super Nintendo',
      shortName: 'SNES',
      coreLibName: 'libbsnes_libretro_android.so',
      extensions: ['sfc', 'smc', 'swc', 'fig'],
      aspect: 4 / 3,
    ),
    ConsoleSystem(
      type: ConsoleType.gb,
      name: 'Game Boy',
      shortName: 'GB',
      coreLibName: 'libgambatte_libretro_android.so',
      extensions: ['gb'],
      aspect: 160 / 144,
    ),
    ConsoleSystem(
      type: ConsoleType.gbc,
      name: 'Game Boy Color',
      shortName: 'GBC',
      coreLibName: 'libgambatte_libretro_android.so',
      extensions: ['gbc'],
      aspect: 160 / 144,
    ),
    ConsoleSystem(
      type: ConsoleType.gba,
      name: 'Game Boy Advance',
      shortName: 'GBA',
      coreLibName: 'libmgba_libretro_android.so',
      extensions: ['gba'],
      aspect: 3 / 2,
    ),
    ConsoleSystem(
      type: ConsoleType.nds,
      name: 'Nintendo DS',
      shortName: 'NDS',
      coreLibName: 'libmelonds_libretro_android.so',
      extensions: ['nds'],
      isDualScreen: true,
      screenModes: _ndsModes,
    ),
    ConsoleSystem(
      type: ConsoleType.ps1,
      name: 'PlayStation 1',
      shortName: 'PS1',
      coreLibName: 'libswanstation_libretro_android.so',
      extensions: ['chd', 'cue', 'pbp', 'bin'],
      supportsVulkan: true,
      aspect: 4 / 3,
      hasAnalog: true,
      hasL2R2: true,
      faceStyle: FaceStyle.playstation,
    ),
    ConsoleSystem(
      type: ConsoleType.psp,
      name: 'PlayStation Portable',
      shortName: 'PSP',
      coreLibName: 'libppsspp_libretro_android.so',
      extensions: ['iso', 'cso'],
      supportsVulkan: true,
      aspect: 480 / 272,
      hasAnalog: true,
      faceStyle: FaceStyle.playstation,
    ),
    ConsoleSystem(
      type: ConsoleType.n3ds,
      name: 'Nintendo 3DS',
      shortName: '3DS',
      // If this exact file isn't in jniLibs the native side also tries any
      // "*azahar_libretro*" / "*citra_libretro*" library, and reports a clear error otherwise.
      coreLibName: 'libazahar_libretro_android.so',
      extensions: ['3ds', 'cci', 'cxi', 'app', '3dsx', 'cia'],
      // Vulkan was a main cause of 3DS launch crashes -> OpenGL ES only.
      supportsVulkan: false,
      isDualScreen: true,
      hasAnalog: true,
      screenModes: _n3dsModes,
    ),
    ConsoleSystem(
      type: ConsoleType.n64,
      name: 'Nintendo 64',
      shortName: 'N64',
      coreLibName: 'libmupen64plus_next_gles3_libretro_android.so',
      extensions: ['n64', 'z64', 'v64'],
      aspect: 4 / 3,
      hasAnalog: true,
      pad: _n64Pad,
    ),
    ConsoleSystem(
      type: ConsoleType.sms,
      name: 'Sega Master System',
      shortName: 'SMS',
      coreLibName: 'libgearsystem_libretro_android.so',
      extensions: ['sms'],
      aspect: 4 / 3,
      pad: _smsPad,
    ),
    ConsoleSystem(
      type: ConsoleType.gg,
      name: 'Sega Game Gear',
      shortName: 'GG',
      coreLibName: 'libgearsystem_libretro_android.so',
      extensions: ['gg'],
      aspect: 160 / 144,
      pad: _twoButtonPad,
    ),
    ConsoleSystem(
      type: ConsoleType.genesis,
      name: 'Sega Genesis / Mega Drive',
      shortName: 'MD',
      coreLibName: 'libblastem_libretro_android.so',
      // "bin" is left to PS1 (it is also a disc image extension).
      extensions: ['md', 'gen', 'smd'],
      aspect: 4 / 3,
      pad: _genesisPad,
    ),
    ConsoleSystem(
      type: ConsoleType.saturn,
      name: 'Sega Saturn',
      shortName: 'Saturn',
      coreLibName: 'libyabause_libretro_android.so',
      // .chd / .cue are assigned to Saturn per file through the import picker.
      extensions: ['ccd', 'mds'],
      aspect: 4 / 3,
      pad: _saturnPad,
    ),
    ConsoleSystem(
      type: ConsoleType.pokemini,
      name: 'Pokémon Mini',
      shortName: 'Mini',
      coreLibName: 'libpokemini_libretro_android.so',
      extensions: ['min'],
      aspect: 3 / 2, // 96 x 64
      pad: _pokeMiniPad,
    ),
    ConsoleSystem(
      type: ConsoleType.wonderswan,
      name: 'WonderSwan / Color',
      shortName: 'WS',
      coreLibName: 'libmednafen_wswan_libretro_android.so',
      // pc2 / pcv2 = Benesse Pocket Challenge V2 (a WonderSwan in disguise).
      extensions: ['ws', 'wsc', 'pc2', 'pcv2'],
      aspect: 14 / 9, // 224 x 144
      pad: _wonderSwanPad,
    ),
  ];

  /// Disc image extensions shared by several consoles: the user picks the console per file.
  static const Set<String> pickableExts = {'cue', 'chd'};

  /// Consoles a .cue / .chd can belong to (shown in the picker, in this order).
  static const List<ConsoleType> discTypes = [
    ConsoleType.ps1,
    ConsoleType.saturn,
  ];

  /// Per-file console chosen by the user, keyed by lower-case file name.
  static final Map<String, ConsoleType> fileOverrides = {};

  static ConsoleSystem? ofType(ConsoleType t) {
    for (final system in allSystems) {
      if (system.type == t) return system;
    }
    return null;
  }

  static String _extOf(String fileName) {
    final i = fileName.lastIndexOf('.');
    return i < 0 ? '' : fileName.substring(i + 1).toLowerCase();
  }

  static bool isPickable(String fileName) =>
      pickableExts.contains(_extOf(fileName));

  /// Console for a library file: the user's choice for .cue/.chd, otherwise by extension.
  static ConsoleSystem? forFile(String fileName) {
    final ext = _extOf(fileName);
    if (pickableExts.contains(ext)) {
      final o = fileOverrides[fileName.toLowerCase()];
      if (o != null) return ofType(o);
    }
    return fromExtension(ext);
  }

  static ConsoleSystem? fromExtension(String ext) {
    final cleanExt = ext.toLowerCase().replaceAll('.', '');
    for (final system in allSystems) {
      if (system.extensions.contains(cleanExt)) {
        return system;
      }
    }
    return null;
  }

  /// "Pokemon_Emerald (USA) [!].gba" -> "Pokemon Emerald"
  static String cleanTitle(String fileName) {
    var t = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    t = t.replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), '');
    t = t.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.isEmpty ? fileName : t;
  }
}