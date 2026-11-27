// lib/widgets/fold_support.dart
import 'dart:math' as math;
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/theme_service.dart';

/// How the screen is currently folded.
///  - none:      flat / closed / not foldable. The app uses the whole screen.
///  - tabletop:  Z Flip style, half-open with a HORIZONTAL crease. The app moves to the lower half
///               (the half under your thumbs); the upper half shows a themed panel.
///  - book:      Z Fold style, half-open (or dual-screen hinge) with a VERTICAL crease. The app
///               fills one page; the other page shows the themed panel.
enum FoldKind { none, tabletop, book }

class FoldLayout {
  final FoldKind kind;

  /// Where the app is drawn.
  final Rect app;

  /// The other half, drawn with the companion panel (null when [kind] is none).
  final Rect? other;

  const FoldLayout(this.kind, this.app, this.other);

  static FoldLayout none(Size s) =>
      FoldLayout(FoldKind.none, Offset.zero & s, null);

  /// Works out the layout from the window's display features. A fold only splits the screen when
  /// it is half-open, or when it is a real hinge gap (dual-screen phones). A flat, unfolded
  /// foldable is just a big screen and keeps the normal wide layouts.
  static FoldLayout resolve(Size size, List<DisplayFeature> features) {
    for (final f in features) {
      if (f.type != DisplayFeatureType.hinge &&
          f.type != DisplayFeatureType.fold) {
        continue;
      }
      final splits =
          f.state == DisplayFeatureState.postureHalfOpened ||
          f.type == DisplayFeatureType.hinge;
      if (!splits) continue;
      final b = f.bounds;
      if (b.width >= b.height) {
        // Horizontal crease -> tabletop. Needs a sensible lower half to be worth it.
        if (b.top <= 0 || size.height - b.bottom < 240 || b.top < 120) continue;
        return FoldLayout(
          FoldKind.tabletop,
          Rect.fromLTRB(0, b.bottom, size.width, size.height),
          Rect.fromLTRB(0, 0, size.width, b.top),
        );
      } else {
        if (b.left < 280 || size.width - b.right < 280) continue;
        final left = Rect.fromLTRB(0, 0, b.left, size.height);
        final right = Rect.fromLTRB(b.right, 0, size.width, size.height);
        // Bigger page runs the app (left on a tie).
        return left.width >= right.width
            ? FoldLayout(FoldKind.book, left, right)
            : FoldLayout(FoldKind.book, right, left);
      }
    }
    return none(size);
  }
}

/// Sits above the Navigator (MaterialApp.builder) and keeps the app clear of the crease.
///
/// The widget tree has the SAME shape in every posture (only the rectangle and the MediaQuery
/// change), so folding / unfolding while a screen is open never rebuilds the Navigator or loses
/// the current page. The game screen opts out with [suspend] / [resume] because it lays out its
/// own screen and controls around the hinge.
class FoldShell extends StatelessWidget {
  final Widget child;
  const FoldShell({super.key, required this.child});

  static const _prefKey = 'fold_layout';

  /// Settings switch: lets people turn the fold layout off if their phone reports it wrongly.
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);
  static final ValueNotifier<int> _suspended = ValueNotifier<int>(0);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled.value = prefs.getBool(_prefKey) ?? true;
    } catch (_) {}
  }

  static Future<void> setEnabled(bool v) async {
    enabled.value = v;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, v);
    } catch (_) {}
  }

  /// Full-screen screens (the game) call this in initState and [resume] in dispose.
  static void suspend() => _bump(1);
  static void resume() => _bump(-1);

  static void _bump(int delta) {
    void apply() => _suspended.value = math.max(0, _suspended.value + delta);
    // initState / dispose run while the tree is building: notify listeners after the frame.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  static MediaQueryData _forPane(MediaQueryData m, Rect r) {
    final w = m.size.width, h = m.size.height;
    EdgeInsets cut(EdgeInsets e) => EdgeInsets.fromLTRB(
      r.left > 0 ? 0 : e.left,
      r.top > 0 ? 0 : e.top,
      r.right < w ? 0 : e.right,
      r.bottom < h ? 0 : e.bottom,
    );
    return m.copyWith(
      size: r.size,
      padding: cut(m.padding),
      viewPadding: cut(m.viewPadding),
      viewInsets: cut(m.viewInsets),
      systemGestureInsets: cut(m.systemGestureInsets),
      displayFeatures: const <DisplayFeature>[],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: enabled,
      builder: (context, on, _) => ValueListenableBuilder<int>(
        valueListenable: _suspended,
        builder: (context, suspended, _) {
          final layout = (!on || suspended > 0)
              ? FoldLayout.none(mq.size)
              : FoldLayout.resolve(mq.size, mq.displayFeatures);
          final split = layout.kind != FoldKind.none;
          return Stack(
            children: [
              Positioned.fill(
                child: split
                    ? _FoldCompanion(layout: layout)
                    : const SizedBox.shrink(),
              ),
              Positioned.fromRect(
                rect: layout.app,
                child: MediaQuery(
                  data: split ? _forPane(mq, layout.app) : mq,
                  child: child,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The half of the screen the app is not using. Themed for Classic and Dot, Light and Dark.
class _FoldCompanion extends StatelessWidget {
  final FoldLayout layout;
  const _FoldCompanion({required this.layout});

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final other = layout.other!;
    final tabletop = layout.kind == FoldKind.tabletop;
    final body = Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fromRect(
            rect: other,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (c.isDot)
                      const BlinkingDot(size: 12)
                    else
                      Icon(
                        Icons.sports_esports_rounded,
                        size: 44,
                        color: c.accent,
                      ),
                    const SizedBox(height: 14),
                    Text(
                      'tonEMU',
                      style: TextStyle(
                        fontFamily: c.displayFont,
                        fontSize: 34,
                        fontWeight: c.isDot ? FontWeight.w900 : FontWeight.w700,
                        color: c.primaryText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tabletop
                          ? 'Tabletop mode: use the lower half'
                          : 'Book mode: the app sits on one page',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: c.labelFont,
                        fontSize: 12,
                        letterSpacing: c.isDot ? 0.4 : 0,
                        color: c.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return c.isDot
        ? c.dotted(body)
        : ColoredBox(color: c.groupedBg, child: body);
  }
}
