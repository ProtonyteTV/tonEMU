// lib/widgets/transitions.dart

import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoPageTransitionsBuilder;
import 'package:material_ui/material_ui.dart';

import '../services/theme_service.dart';

/// Page transitions for every normal screen. main.dart rebuilds on theme changes, so this is a
/// getter and follows the chosen [AppStyle].
///  - Classic: iOS slide with parallax + edge-swipe back.
///  - Dot: the same slide (keeps edge-swipe back) but the page also fades in, and the page
///    underneath dims, like a display refreshing.
PageTransitionsTheme get appPageTransitions {
  final dot = ThemeService.instance.style == AppStyle.dot;
  const cupertino = CupertinoPageTransitionsBuilder();
  const dotBuilder = _DotPageTransitionsBuilder();
  return PageTransitionsTheme(
    builders: {
      for (final p in const [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ])
        p: dot ? dotBuilder : cupertino,
    },
  );
}

class _DotPageTransitionsBuilder extends PageTransitionsBuilder {
  const _DotPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final slide = const CupertinoPageTransitionsBuilder().buildTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
      ),
      child: slide,
    );
  }
}

/// "Power on" transition for the game screen.
///
/// The library fades to black first (see _LibraryScreenState._openGame), then this route plays
/// a power-on effect ON TOP of the game while the core loads, and the reverse when leaving:
///  Both themes use the dot-matrix reveal: an accent dot blinks on the black screen, then the
///  black is punched out dot by dot in a wave from the centre. Dot uses the tight 22px grid
///  and the red logo dot; Classic uses larger, softer dots and the app's blue.
/// Only a Flutter layer is animated over the game: the game screen itself is never faded or scaled,
/// because opacity and transforms do not work reliably on the emulator's native GL surface.
/// There is no swipe-back, so a stray edge swipe can never quit a running game.
class GameLaunchRoute<T> extends PageRouteBuilder<T> {
  GameLaunchRoute({required WidgetBuilder builder})
    : super(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 1600),
        reverseTransitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (context, _, _) => builder(context),
        transitionsBuilder: (context, animation, _, child) {
          final dot = ThemeService.instance.style == AppStyle.dot;
          final accent = XEmuColors.of(context).accent;
          return Stack(
            fit: StackFit.expand,
            children: [
              child,
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: animation,
                      builder: (_, _) => animation.value >= 1
                          ? const SizedBox.shrink()
                          : CustomPaint(
                              painter: _DotRevealPainter(
                                _effectT(animation.value),
                                accent: dot
                                    ? const Color(0xFFD71921)
                                    : accent,
                                // Dot: tight 22px grid like the page background.
                                // Classic: larger, softer dots in the app's blue.
                                step: dot ? 22 : 28,
                                soft: !dot,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
}

/// The first 50% of the route animation is a plain black hold: the game screen and its native
/// surface are being built then, and frames dropped in that moment would swallow the start of the
/// effect. The visible effect plays over the remaining time.
double _effectT(double routeT) => _span(routeT, 0.50, 1.0);

double _span(double t, double a, double b) =>
    ((t - a) / (b - a)).clamp(0.0, 1.0);

/// Dot-matrix reveal: an accent dot blinks on black, then dots punch holes in the black in a wave
/// from the centre. Used by both themes (red + tight grid for Dot, blue + soft for Classic).
class _DotRevealPainter extends CustomPainter {
  final double t;
  final Color accent;
  final double step;
  final bool soft;
  const _DotRevealPainter(
    this.t, {
    required this.accent,
    required this.step,
    required this.soft,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxDist =
        math.sqrt(size.width * size.width + size.height * size.height) / 2;
    final bounds = Offset.zero & size;

    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..color = Colors.black);

    final clear = Paint()
      ..blendMode = BlendMode.clear
      ..maskFilter = soft ? const MaskFilter.blur(BlurStyle.normal, 2.5) : null;
    final progress =
        _span(t, 0.12, 1.0) * 1.5; // 0 -> 1.5 so far dots finish too
    final fullR = step * 0.78; // overlaps neighbours = fully open
    for (double y = step / 2; y < size.height + step; y += step) {
      for (double x = step / 2; x < size.width + step; x += step) {
        final d =
            (Offset(x, y) - center).distance / maxDist; // 0 centre .. 1 corner
        final local = (progress - d * 0.9).clamp(0.0, 1.0);
        if (local <= 0) continue;
        canvas.drawCircle(
          Offset(x, y),
          fullR * Curves.easeOutCubic.transform(local),
          clear,
        );
      }
    }
    canvas.restore();

    // The logo's red dot blinks twice on the black, then fades as the wave starts.
    final blinkA =
        (1 - _span(t, 0.0, 0.3)) *
        (math.sin(t * math.pi * 12) > -0.2 ? 1.0 : 0.15);
    if (blinkA > 0.01) {
      canvas.drawCircle(
        center,
        6,
        Paint()
          ..color = accent.withValues(alpha: blinkA)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(
        center,
        4.5,
        Paint()..color = accent.withValues(alpha: blinkA),
      );
    }
  }

  @override
  bool shouldRepaint(_DotRevealPainter old) =>
      old.t != t ||
      old.accent != accent ||
      old.step != step ||
      old.soft != soft;
}
