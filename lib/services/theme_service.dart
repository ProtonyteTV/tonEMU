// lib/services/theme_service.dart
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';

import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which visual language the app uses. Independent of Light / Dark / System.
///  - classic: the original iOS-style look (blue accent, grouped cards).
///  - dot: matches the tonEMU website: dot grid, Doto headings, Space Mono labels, outlined pill/round cards, red dot.
enum AppStyle { classic, dot }

extension AppStyleX on AppStyle {
  String get label => switch (this) {
    AppStyle.classic => 'Classic',
    AppStyle.dot => 'Dot',
  };
}

/// Font families declared in pubspec.yaml (see README). If a family is missing Flutter silently
/// falls back to the default font, so the theme still works without the files.
const String kDotFont = 'Doto'; // dot-matrix display font (OFL)
const String kMonoFont = 'SpaceMono'; // small caps labels (OFL)
const String kSansFont = 'SpaceGrotesk'; // body text (OFL)

/// Classic uses the phone's own default font (e.g. Samsung One UI's chosen font) instead of
/// Flutter's built-in Roboto. On Android the generic "sans-serif" family is whatever font the
/// user picked in system settings; other platforms keep their native default (SF on iOS).
final String? kSystemFont = defaultTargetPlatform == TargetPlatform.android
    ? 'sans-serif'
    : null;

/// Persists and broadcasts the app's ThemeMode (System, Light, or Dark) and its [AppStyle].
class ThemeService extends ChangeNotifier {
  ThemeService._();
  static final ThemeService instance = ThemeService._();

  static const _prefKey = 'app_theme_mode';
  static const _styleKey = 'app_style';
  ThemeMode _mode = ThemeMode.system;
  AppStyle _style = AppStyle.classic;

  ThemeMode get mode => _mode;
  AppStyle get style => _style;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    _mode = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    var savedStyle = prefs.getString(_styleKey);
    if (savedStyle == 'nothing')
      savedStyle = 'dot'; // renamed; keep users' saved choice
    _style = AppStyle.values.firstWhere(
      (s) => s.name == savedStyle,
      orElse: () => AppStyle.classic,
    );
    notifyListeners();
  }

  Future<void> setMode(ThemeMode newMode) async {
    if (_mode == newMode) return;
    _mode = newMode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final raw = switch (newMode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString(_prefKey, raw);
  }

  Future<void> setStyle(AppStyle newStyle) async {
    if (_style == newStyle) return;
    _style = newStyle;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_styleKey, newStyle.name);
  }

  /// Quick toggle between Light and Dark mode from the home navigation bar.
  Future<void> toggleLightDark(Brightness currentBrightness) {
    final next = currentBrightness == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    return setMode(next);
  }

  static ThemeData lightTheme() {
    if (instance._style == AppStyle.dot) return _dot(Brightness.light);
    return _classicRefine(_classicLight(), false);
  }

  static ThemeData darkTheme() {
    if (instance._style == AppStyle.dot) return _dot(Brightness.dark);
    return _classicRefine(_classicDark(), true);
  }

  static ThemeData _classicLight() {
    if (instance._style == AppStyle.dot) return _dot(Brightness.light);
    const bg = Color(0xFFF2F2F7);
    const card = Color(0xFFFFFFFF);
    const accent = Color(0xFF007AFF);

    return ThemeData(
      useMaterial3: true,
      fontFamily: kSystemFont,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.light,
        primary: accent,
        surface: card,
      ),
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Color(0xFF000000),
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1C1C1E),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
    );
  }

  static ThemeData _classicDark() {
    const bg = Color(0xFF000000);
    const card = Color(0xFF1C1C1E);
    const accent = Color(0xFF0A84FF);

    return ThemeData(
      useMaterial3: true,
      fontFamily: kSystemFont,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        primary: accent,
        surface: card,
      ),
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Color(0xFFFFFFFF),
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2C2C2E),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
    );
  }

  // ───────────────────── Classic: component refinements ─────────────────────

  /// iOS-flavoured details on top of the base Classic theme: green switches, grabber sheets,
  /// rounded buttons, Cupertino page transitions and quieter ripples.
  static ThemeData _classicRefine(ThemeData base, bool dark) {
    final accent = base.colorScheme.primary;
    final card = base.colorScheme.surface;
    const green = Color(0xFF34C759);
    final fg = dark ? Colors.white : Colors.black;

    return base.copyWith(
      splashFactory: InkRipple.splashFactory,
      highlightColor: fg.withValues(alpha: 0.04),
      dividerColor: fg.withValues(alpha: dark ? 0.12 : 0.10),
      dividerTheme: DividerThemeData(
        color: fg.withValues(alpha: dark ? 0.12 : 0.10),
        thickness: 0.5,
        space: 0.5,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? green
              : (dark ? const Color(0xFF39393D) : const Color(0xFFE5E5EA)),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: accent,
        inactiveTrackColor: fg.withValues(alpha: 0.14),
        thumbColor: Colors.white,
        overlayColor: accent.withValues(alpha: 0.12),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: fg.withValues(alpha: 0.25),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: fg.withValues(alpha: 0.10),
        linearMinHeight: 4,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF3A3A3C) : const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionHandleColor: accent,
        selectionColor: accent.withValues(alpha: 0.25),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        hintStyle: TextStyle(
          color: dark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const CircleBorder(),
        side: BorderSide(color: fg.withValues(alpha: 0.35), width: 1.5),
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accent : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: fg.withValues(alpha: 0.55),
        textColor: fg,
        subtitleTextStyle: TextStyle(
          color: dark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
          fontSize: 12,
        ),
      ),
    );
  }

  // ───────────────────────── "Dot" style ─────────────────────────

  static ThemeData _dot(Brightness b) => _dotRefine(_dotBase(b), b);

  static ThemeData _dotBase(Brightness b) {
    final dark = b == Brightness.dark;
    final c = XEmuColors._(dark, AppStyle.dot);
    final scheme = (dark ? const ColorScheme.dark() : const ColorScheme.light())
        .copyWith(
          primary: c.accent,
          onPrimary: Colors.white,
          secondary: c.primaryText,
          onSecondary: c.groupedBg,
          surface: c.cardBg,
          onSurface: c.primaryText,
          error: c.accent,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      fontFamily: kSansFont,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.groupedBg,
      dividerColor: c.hairline,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primaryText,
          foregroundColor: c.groupedBg,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: kMonoFont,
            fontSize: 12,
            letterSpacing: 0.7,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.primaryText,
          side: BorderSide(color: c.primaryText),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontFamily: kMonoFont,
            fontSize: 12,
            letterSpacing: 0.7,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primaryText,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: kMonoFont,
            fontSize: 12,
            letterSpacing: 0.7,
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: c.primaryText,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: kDotFont,
          fontWeight: FontWeight.w900,
          fontSize: 22,
          letterSpacing: 0.5,
          color: c.primaryText,
        ),
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 2,
        activeTrackColor: c.accent,
        inactiveTrackColor: c.primaryText.withValues(alpha: 0.16),
        thumbColor: c.accent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark
            ? const Color(0xFF1E1E1E)
            : const Color(0xFF0B0B0B),
        contentTextStyle: const TextStyle(
          fontFamily: kMonoFont,
          fontSize: 13,
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: c.hairline),
        ),
      ),
    );
  }
}

/// Extra component styling for the Dot look: outlined square-dot switches, hairline sheets,
/// mono tooltips, a thin red progress line and a fade page transition (no sliding, like a display

ThemeData _dotRefine(ThemeData base, Brightness b) {
  final dark = b == Brightness.dark;
  final c = XEmuColors._(dark, AppStyle.dot);
  const mono = TextStyle(
    fontFamily: kMonoFont,
    fontSize: 11.5,
    letterSpacing: 0.4,
  );

  return base.copyWith(
    splashFactory: NoSplash.splashFactory,
    highlightColor: c.primaryText.withValues(alpha: 0.05),
    dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : c.primaryText,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : Colors.transparent,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : c.primaryText,
      ),
      trackOutlineWidth: const WidgetStatePropertyAll(1.5),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: const CircleBorder(),
      side: BorderSide(color: c.primaryText, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(Colors.white),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.cardBg,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: c.primaryText.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        side: BorderSide(color: c.hairline),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accent,
      linearTrackColor: c.primaryText.withValues(alpha: 0.12),
      linearMinHeight: 2,
      circularTrackColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.cardBg,
      surfaceTintColor: Colors.transparent,
      textStyle: mono.copyWith(color: c.primaryText, fontSize: 12.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: c.hairline),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.primaryText,
        borderRadius: BorderRadius.circular(99),
      ),
      textStyle: mono.copyWith(color: c.groupedBg),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.accent,
      selectionHandleColor: c.accent,
      selectionColor: c.accent.withValues(alpha: 0.25),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      hintStyle: mono.copyWith(color: c.tertiaryText, fontSize: 12.5),
      labelStyle: mono.copyWith(color: c.secondaryText),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(99),
        borderSide: BorderSide(color: c.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(99),
        borderSide: BorderSide(color: c.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(99),
        borderSide: BorderSide(color: c.accent, width: 1.5),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.secondaryText,
      textColor: c.primaryText,
      titleTextStyle: TextStyle(
        fontFamily: kSansFont,
        fontSize: 14,
        color: c.primaryText,
      ),
      subtitleTextStyle: mono.copyWith(color: c.secondaryText, fontSize: 11),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.cardBg,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: kDotFont,
        fontWeight: FontWeight.w900,
        fontSize: 22,
        color: c.primaryText,
      ),
      contentTextStyle: TextStyle(
        fontFamily: kSansFont,
        fontSize: 14,
        color: c.secondaryText,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: c.hairline),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: c.primaryText,
      side: BorderSide(color: c.primaryText.withValues(alpha: 0.5)),
      shape: const StadiumBorder(),
      labelStyle: mono.copyWith(color: c.primaryText),
      secondaryLabelStyle: mono.copyWith(color: c.groupedBg),
      checkmarkColor: c.groupedBg,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: mono.copyWith(color: c.primaryText),
    ),
  );
}

/// Semantic palette helper that adapts automatically to Light / Dark mode AND to the chosen
/// [AppStyle]. Every screen already reads its colors from here, so most of the UI re-skins for free.
class XEmuColors {
  final bool isDark;
  final AppStyle style;
  const XEmuColors._(this.isDark, this.style);

  factory XEmuColors.of(BuildContext context) {
    return XEmuColors._(
      Theme.of(context).brightness == Brightness.dark,
      ThemeService.instance.style,
    );
  }

  bool get isDot => style == AppStyle.dot;

  Color _pick(int classicDark, int classicLight, int dotDark, int dotLight) =>
      Color(
        isDot
            ? (isDark ? dotDark : dotLight)
            : (isDark ? classicDark : classicLight),
      );

  Color get groupedBg => _pick(0xFF000000, 0xFFF2F2F7, 0xFF0A0A0A, 0xFFE9E9E7);
  Color get cardBg => _pick(0xFF1C1C1E, 0xFFFFFFFF, 0xFF131313, 0xFFF4F4F2);
  Color get secondaryFill =>
      _pick(0xFF2C2C2E, 0xFFE5E5EA, 0xFF1C1C1C, 0xFFDEDEDC);
  Color get frostedBar => isDot
      ? (isDark ? const Color(0xFF0A0A0A) : const Color(0xFFE9E9E7)).withValues(
          alpha: 0.78,
        )
      : (isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF9F9F9)).withValues(
          alpha: isDark ? 0.82 : 0.85,
        );
  Color get hairline => isDark
      ? Colors.white.withValues(alpha: isDot ? 0.18 : 0.12)
      : Colors.black.withValues(alpha: isDot ? 0.14 : 0.10);
  Color get primaryText =>
      _pick(0xFFFFFFFF, 0xFF000000, 0xFFF2F2F0, 0xFF0A0A0A);
  Color get secondaryText =>
      _pick(0xFF8E8E93, 0xFF6C6C70, 0xFF8A8A86, 0xFF6E6E6A);
  Color get tertiaryText =>
      _pick(0xFF636366, 0xFFAEAEB2, 0xFF5C5C58, 0xFFA5A5A1);
  Color get accent => _pick(0xFF0A84FF, 0xFF007AFF, 0xFFD71921, 0xFFD71921);

  /// Status colors. Dot has ONE accent (the red dot), so warnings and destructive actions use it
  /// instead of iOS orange / red.
  Color get warn => isDot ? accent : const Color(0xFFFF9500);
  Color get danger => isDot ? accent : const Color(0xFFFF3B30);
  Color get ok => isDot ? primaryText : const Color(0xFF34C759);

  // Shape + type helpers used by the shared widgets.
  double get cardRadius => isDot ? 24 : 20;

  /// Soft elevation for cards in Classic + light mode (dark mode and Dot stay flat/outlined).
  List<BoxShadow> get cardShadow => (isDot || isDark)
      ? const []
      : const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ];
  double get hairlineWidth => isDot ? 1 : 0.5;
  String? get labelFont => isDot ? kMonoFont : null;
  String? get displayFont => isDot ? kDotFont : null;

  /// Text style for every button and tappable label (Cupertino buttons, dock labels, "Start
  /// Wi-Fi Transfer"...). Cupertino widgets ignore the ThemeData font, so without this they
  /// fell back to the platform font in the Dot style. Dot: mono label font; Classic: the system font.
  TextStyle buttonText({
    double size = 14.5,
    FontWeight? weight,
    Color? color,
  }) => TextStyle(
    fontFamily: isDot ? kMonoFont : kSystemFont,
    fontSize: size,
    fontWeight: isDot ? FontWeight.w400 : (weight ?? FontWeight.w600),
    letterSpacing: isDot ? 0.5 : null,
    color: color,
  );

  /// Scaffold / AppBar background. Transparent in the Dot style so the dot grid from
  /// [dotted] shows through (the page itself stays opaque, so route transitions look normal).
  Color get pageBg => isDot ? Colors.transparent : groupedBg;

  /// Wraps a whole page (a Scaffold using [pageBg]) in the website's dot-grid background.
  Widget dotted(Widget page) => isDot
      ? DotGrid(
          bg: groupedBg,
          dot: isDark
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.black.withValues(alpha: 0.16),
          child: page,
        )
      : page;
}

/// Solid background + 22px dot grid, same as the website's body background.
class DotGrid extends StatelessWidget {
  final Color bg;
  final Color dot;
  final Widget child;
  const DotGrid({
    super.key,
    required this.bg,
    required this.dot,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: bg,
    child: Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(painter: _DotGridPainter(dot), isComplex: true),
          ),
        ),
        child,
      ],
    ),
  );
}

class _DotGridPainter extends CustomPainter {
  final Color color;
  const _DotGridPainter(this.color);

  static const double _step = 22;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final pts = <Offset>[];
    for (double y = _step / 2; y < size.height; y += _step) {
      for (double x = _step / 2; x < size.width; x += _step) {
        pts.add(Offset(x, y));
      }
    }
    canvas.drawPoints(ui.PointMode.points, pts, paint);
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => old.color != color;
}

/// The website logo's blinking red dot (steps animation, 1.6 s).
class BlinkingDot extends StatefulWidget {
  final double size;
  const BlinkingDot({super.key, this.size = 9});

  @override
  State<BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<BlinkingDot> {
  // The blink is a hard on/off step every 800 ms, so a timer is enough. The old repeating
  // AnimationController forced a rebuild + frame 60 times a second, forever, for a dot that only
  // changes twice per cycle (and kept the GPU awake behind the header).
  Timer? _timer;
  bool _on = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (mounted) setState(() => _on = !_on);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Opacity(
      opacity: _on ? 1 : 0.15,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: const Color(0xFFD71921),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD71921).withValues(alpha: 0.55),
              blurRadius: widget.size * 0.9,
            ),
          ],
        ),
      ),
    ),
  );
}
