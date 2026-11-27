// lib/widgets/library_motion.dart

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../services/theme_service.dart';

/// Which side an item slides in from (Classic theme only; Dot never slides).
enum RevealFrom { bottom, left, right, none }

/// Entrance animation for everything on the library page. It follows the chosen [AppStyle]:
///
///  - Classic: iOS-like. Fade + soft slide + a tiny "pop" (easeOutBack), items cascade in.
///  - Dot: a display refresh. Stepped (non-smooth) flicker, a top-to-bottom scan wipe and a
///    thin red scan line, in the same dot-matrix spirit as the game launch effect.
///
/// Each [id] plays ONCE per theme. Lazy grid/list items that are built again after scrolling
/// away and back do not replay, and switching theme replays the whole page (nice showcase).
/// Honors the system "remove animations" setting.
///
/// The child's element tree never changes shape (finished state = identity transforms), so
/// cover-art loading state inside cards is never reset.
class LibraryReveal extends StatefulWidget {
  final String id;
  final int index;
  final RevealFrom from;
  final Widget child;

  const LibraryReveal({
    super.key,
    required this.id,
    required this.child,
    this.index = 0,
    this.from = RevealFrom.bottom,
  });

  static final Set<String> _seen = <String>{};

  /// Forget what was already shown, so the next build plays the entrance again.
  static void replay() => _seen.clear();

  /// Stagger index that cascades the first screenful but never makes a card that scrolls into
  /// view later wait for a long delay.
  static int staggerFor(int i) => i < 12 ? i : i % 4;

  @override
  State<LibraryReveal> createState() => _LibraryRevealState();
}

class _LibraryRevealState extends State<LibraryReveal>
    with SingleTickerProviderStateMixin {
  static const _maxStagger = 9;
  static const _dotRed = Color(0xFFD71921);

  late final bool _dot;
  late final AnimationController _c;
  late final double _startFrac;

  @override
  void initState() {
    super.initState();
    final style = ThemeService.instance.style;
    _dot = style == AppStyle.dot;
    final first = LibraryReveal._seen.add('${style.name}|${widget.id}');

    final base = _dot ? 460 : 560;
    final step = _dot ? 40 : 55;
    final delay = math.min(widget.index, _maxStagger) * step;
    final total = base + delay;
    _startFrac = delay / total;
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: total),
    );
    if (first) {
      _c.forward();
    } else {
      _c.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) && !_c.isCompleted) {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double get _p => _startFrac >= 1
      ? 1
      : ((_c.value - _startFrac) / (1 - _startFrac)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (_, child) =>
        _dot ? _dotFx(_p, child!) : _classicFx(_p, child!),
  );

  // ───────────────────────────── Classic ─────────────────────────────

  Widget _classicFx(double p, Widget child) {
    final slide = Curves.easeOutCubic.transform(p);
    final pop = Curves.easeOutBack.transform(p);
    final fade = Curves.easeOut.transform(math.min(1.0, p * 1.6));
    final left = 1 - slide;
    final offset = switch (widget.from) {
      RevealFrom.bottom => Offset(0, left * 22),
      RevealFrom.left => Offset(-left * 26, 0),
      RevealFrom.right => Offset(left * 34, 0),
      RevealFrom.none => Offset.zero,
    };
    return Opacity(
      opacity: fade,
      child: Transform.translate(
        offset: offset,
        child: Transform.scale(scale: 0.93 + 0.07 * pop, child: child),
      ),
    );
  }

  // ───────────────────────────── Dot ─────────────────────────────

  /// Opacity per 1/8 of the animation: it stutters in like a refreshing display.
  static const _flicker = [0.0, 0.55, 0.12, 0.8, 0.3, 1.0, 0.85, 1.0];

  Widget _dotFx(double p, Widget child) {
    final step = p >= 1 ? 7 : (p * 8).floor().clamp(0, 7);
    final wipe = p >= 1 ? 1.0 : (p * 8).floor() / 8;
    // Finished items keep the same widget shape (so cover loading state survives) but drop the
    // scan-line painter and the clip layer: hundreds of cards were each carrying both forever.
    return CustomPaint(
      foregroundPainter: p >= 1 ? null : _ScanLinePainter(p, wipe, _dotRed),
      child: ClipRect(
        clipper: _WipeClipper(wipe),
        clipBehavior: p >= 1 ? Clip.none : Clip.hardEdge,
        child: Opacity(opacity: p >= 1 ? 1.0 : _flicker[step], child: child),
      ),
    );
  }
}

/// Reveals the child from the top down. When finished it returns a rect larger than the child
/// so card shadows are never cut off.
class _WipeClipper extends CustomClipper<Rect> {
  final double frac;
  const _WipeClipper(this.frac);

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    -60,
    -60,
    size.width + 60,
    frac >= 1 ? size.height + 60 : size.height * frac,
  );

  @override
  bool shouldReclip(_WipeClipper old) => old.frac != frac;
}

/// Thin red line at the wipe edge that fades out as the item finishes.
class _ScanLinePainter extends CustomPainter {
  final double p;
  final double wipe;
  final Color color;
  const _ScanLinePainter(this.p, this.wipe, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (p <= 0 || p >= 1 || wipe <= 0) return;
    final y = size.height * wipe;
    final a = (1 - p).clamp(0.0, 1.0);
    canvas.drawRect(
      Rect.fromLTWH(0, y - 0.75, size.width, 1.5),
      Paint()..color = color.withValues(alpha: a),
    );
    canvas.drawCircle(
      Offset(5, y),
      2.2,
      Paint()..color = color.withValues(alpha: a),
    );
  }

  @override
  bool shouldRepaint(_ScanLinePainter old) =>
      old.p != p || old.wipe != wipe || old.color != color;
}
