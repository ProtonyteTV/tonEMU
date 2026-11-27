// lib/models/screen_layout.dart
import 'dart:convert';
import 'dart:ui' show Rect;

import 'package:shared_preferences/shared_preferences.dart';

import 'console_system.dart';

/// The four "views" a dual-screen game can be in. Each one has its own screen layout, so a
/// portrait choice never overwrites a landscape one, and a controller gets its own setup.
enum ScreenContext { portrait, landscape, portraitPad, landscapePad }

extension ScreenContextX on ScreenContext {
  bool get isPortrait =>
      this == ScreenContext.portrait || this == ScreenContext.portraitPad;
  bool get isController =>
      this == ScreenContext.portraitPad || this == ScreenContext.landscapePad;

  String get label => switch (this) {
    ScreenContext.portrait => 'Portrait',
    ScreenContext.landscape => 'Landscape',
    ScreenContext.portraitPad => 'Portrait · Controller',
    ScreenContext.landscapePad => 'Landscape · Controller',
  };
}

/// What the user chose for one view. `modeId == null` means "Recommended" (follows the premade
/// layout for that view); a non-null id is the user's own arrangement.
class ScreenProfile {
  final String? modeId;

  /// 0.5 .. 1.0 – how much of the available space the picture uses.
  final double scale;

  /// Free placement: offset of the picture from its automatic position, as a fraction of the
  /// screen width / height (0 = automatic).
  final double dx;
  final double dy;

  /// Free-form mode: where each screen sits, as fractions of the display
  /// (left, top, width, height). null = automatic.
  final Rect? topRect;
  final Rect? bottomRect;

  const ScreenProfile({
    this.modeId,
    this.scale = 1.0,
    this.dx = 0,
    this.dy = 0,
    this.topRect,
    this.bottomRect,
  });

  ScreenProfile copyWith({
    String? modeId,
    bool clearMode = false,
    double? scale,
    double? dx,
    double? dy,
    Rect? topRect,
    Rect? bottomRect,
    bool clearFree = false,
  }) => ScreenProfile(
    modeId: clearMode ? null : (modeId ?? this.modeId),
    scale: scale ?? this.scale,
    dx: dx ?? this.dx,
    dy: dy ?? this.dy,
    topRect: clearFree ? null : (topRect ?? this.topRect),
    bottomRect: clearFree ? null : (bottomRect ?? this.bottomRect),
  );

  static List<double>? _r(Rect? r) =>
      r == null ? null : [r.left, r.top, r.width, r.height];
  static Rect? _unr(dynamic v) {
    if (v is! List || v.length != 4) return null;
    final n = v.map((e) => (e as num).toDouble()).toList();
    return Rect.fromLTWH(n[0], n[1], n[2], n[3]);
  }

  Map<String, dynamic> toJson() => {
    'm': modeId,
    's': scale,
    'x': dx,
    'y': dy,
    'ft': _r(topRect),
    'fb': _r(bottomRect),
  };

  factory ScreenProfile.fromJson(Map<String, dynamic> j) => ScreenProfile(
    modeId: j['m'] as String?,
    scale: ((j['s'] as num?)?.toDouble() ?? 1.0).clamp(
      ScreenLayouts.minScale,
      1.0,
    ),
    dx: (j['x'] as num?)?.toDouble() ?? 0,
    dy: (j['y'] as num?)?.toDouble() ?? 0,
    topRect: _unr(j['ft']),
    bottomRect: _unr(j['fb']),
  );
}

class ScreenLayouts {
  static const double minScale = 0.5;

  static ScreenContext contextOf({
    required bool portrait,
    required bool gamepad,
  }) {
    if (portrait) {
      return gamepad ? ScreenContext.portraitPad : ScreenContext.portrait;
    }
    return gamepad ? ScreenContext.landscapePad : ScreenContext.landscape;
  }

  /// Premade default for each view.
  ///  * Portrait: stacked screens fill the width.
  ///  * Landscape (touch controls or controller): side by side, the widest picture.
  static String recommended({required bool portrait, required bool gamepad}) {
    // Landscape: side by side (wide picture). Portrait: stacked.
    if (!portrait) return 'left_right';
    return 'top_bottom';
  }

  /// Curated arrangements shown first for a view (best first). Everything else the system
  /// supports is listed under "More arrangements".
  static List<String> premade(ConsoleSystem system, ScreenContext c) {
    final wanted = switch (c) {
      ScreenContext.portrait || ScreenContext.portraitPad => const [
        'top_bottom',
        'hybrid_top',
        'hybrid_bottom',
      ],
      ScreenContext.landscape => const [
        'left_right',
        'top_bottom',
        'hybrid_top',
      ],
      ScreenContext.landscapePad => const [
        'left_right',
        'hybrid_top',
        'top_bottom',
        'hybrid_bottom',
      ],
    };
    final ids = system.screenModes.map((m) => m.id).toSet();
    return [
      for (final id in wanted)
        if (ids.contains(id)) id,
    ];
  }

  static String name(String id) => switch (id) {
    'top_bottom' => 'Stacked',
    'bottom_top' => 'Stacked (flipped)',
    'left_right' => 'Side by side',
    'right_left' => 'Side by side (flipped)',
    'hybrid_top' => 'Big top screen',
    'hybrid_bottom' => 'Big bottom screen',
    'top_only' => 'Top screen only',
    'bottom_only' => 'Bottom screen only',
    'free' => 'Free form',
    _ => id,
  };

  static String blurb(String id, ScreenContext c) {
    switch (id) {
      case 'top_bottom':
        return switch (c) {
          ScreenContext.portrait => 'Fills the width, controls below',
          ScreenContext.landscape =>
            'Centered picture, buttons in the side margins',
          ScreenContext.portraitPad => 'Largest picture in portrait',
          ScreenContext.landscapePad => 'Classic look, tall and centered',
        };
      case 'left_right':
        return switch (c) {
          ScreenContext.landscapePad => 'Biggest screens on a wide display',
          ScreenContext.landscape => 'Wide picture, buttons overlap the edges',
          _ => 'Screens get small in portrait',
        };
      case 'hybrid_top':
        return 'One large screen plus a compact second screen';
      case 'hybrid_bottom':
        return 'Large touch screen plus a compact top screen';
      case 'top_only':
        return 'Hide the touch screen';
      case 'bottom_only':
        return 'Hide the top screen';
      case 'free':
        return 'Move and resize each screen separately, anywhere';
      case 'bottom_top':
        return 'Touch screen on top';
      case 'right_left':
        return 'Swapped sides';
      default:
        return '';
    }
  }

  static String _key(String sys, ScreenContext c) =>
      'screenprof_${sys}_${c.name}';

  /// Loads all four views. A view with nothing saved honours the old single-mode preference
  /// (`screen_<sys>`) if the user had picked something other than the default.
  static Future<Map<ScreenContext, ScreenProfile>> load(
    SharedPreferences p,
    String sys,
  ) async {
    final legacy = p.getString('screen_$sys');
    final out = <ScreenContext, ScreenProfile>{};
    for (final c in ScreenContext.values) {
      final raw = p.getString(_key(sys, c));
      if (raw != null) {
        try {
          out[c] = ScreenProfile.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map),
          );
          continue;
        } catch (_) {}
      }
      out[c] = ScreenProfile(
        modeId: (legacy != null && legacy != 'top_bottom') ? legacy : null,
      );
    }
    return out;
  }

  static Future<void> save(
    SharedPreferences p,
    String sys,
    ScreenContext c,
    ScreenProfile profile,
  ) => p.setString(_key(sys, c), jsonEncode(profile.toJson()));
}