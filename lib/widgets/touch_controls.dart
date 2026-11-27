// lib/widgets/touch_controls.dart
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../services/emulator_bridge.dart';

enum PadShape { circle, pill, shoulder }

/// Shared smoked-glass tactile cap used by both gamepad buttons and top utility
/// buttons (Menu, Fast Forward, Screenshot) so every control shares one unified UI.
class ControlCapSurface extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  final bool pressed;
  final bool active;
  final Color accent;
  final Widget child;

  const ControlCapSurface({
    super.key,
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.child,
    this.pressed = false,
    this.active = false,
    this.accent = const Color(0xFF0A84FF),
  });

  @override
  Widget build(BuildContext context) {
    final lit = pressed || active;
    return AnimatedContainer(
      duration: pressed ? Duration.zero : const Duration(milliseconds: 55),
      curve: Curves.easeOut,
      transformAlignment: Alignment.center,
      transform: pressed
          ? (Matrix4.identity()
              ..translate(0.0, 1.3)
              ..scale(0.92))
          : Matrix4.identity(),
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: lit
              ? [
                  accent.withValues(alpha: pressed ? 0.72 : 0.48),
                  accent.withValues(alpha: pressed ? 0.36 : 0.24),
                ]
              : [
                  const Color(0xFF2C2C32).withValues(alpha: 0.62),
                  const Color(0xFF101014).withValues(alpha: 0.72),
                ],
        ),
        border: Border.all(
          color: lit
              ? Color.lerp(accent, Colors.white, 0.42)!
              : Colors.white.withValues(alpha: 0.28),
          width: lit ? 1.9 : 1.2,
        ),
        boxShadow: [
          if (lit)
            BoxShadow(
              color: accent.withValues(alpha: 0.45),
              blurRadius: 12,
              spreadRadius: 0.5,
            )
          else
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.42),
              blurRadius: 7,
              offset: const Offset(0, 2.5),
            ),
        ],
      ),
      child: Container(
        margin: const EdgeInsets.all(2.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(math.max(0, borderRadius - 2.0)),
          border: Border.all(
            color: Colors.white.withValues(alpha: lit ? 0.26 : 0.10),
            width: 0.8,
          ),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

/// Describes one button inside a [FaceButtonCluster] (e.g. A, B, X, Y or ✕, ○, □, △).
class FaceButtonSpec {
  final String id;
  final String label;
  final int keyCode;
  final Offset center; // local offset inside the cluster box
  final double radius;

  const FaceButtonSpec({
    required this.id,
    required this.label,
    required this.keyCode,
    required this.center,
    required this.radius,
  });
}

/// Multi-touch, zero-latency face button pad for A/B/X/Y and ✕/○/□/△.
/// Uses a raw [Listener] (bypassing Flutter's GestureDetector arena) so rapid
/// button mashing, simultaneous chords (e.g. Y+B), and thumb-rolling never drop inputs.
class FaceButtonCluster extends StatefulWidget {
  final double width;
  final double height;
  final List<FaceButtonSpec> buttons;
  final bool haptics;

  /// Which player this pad drives (0 = P1 .. 3 = P4). null = P1.
  final int? playerPort;

  const FaceButtonCluster({
    super.key,
    required this.width,
    required this.height,
    required this.buttons,
    this.haptics = true,
    this.playerPort,
  });

  @override
  State<FaceButtonCluster> createState() => _FaceButtonClusterState();
}

class _FaceButtonClusterState extends State<FaceButtonCluster> {
  final Map<int, int?> _pointerKeys = {};
  final Map<int, int> _keyRefCounts = {};

  void _send(int keyCode, bool isDown) =>
      EmulatorBridge.sendButton(keyCode, isDown, port: widget.playerPort ?? 0);

  @override
  void dispose() {
    for (final keyCode in _keyRefCounts.keys) {
      _send(keyCode, false);
    }
    _pointerKeys.clear();
    _keyRefCounts.clear();
    super.dispose();
  }

  /// Finds the button whose hit-zone contains [localPos] (with a generous 1.28x mash radius).
  FaceButtonSpec? _hitTestButton(Offset localPos) {
    FaceButtonSpec? closest;
    double bestDist = double.infinity;

    for (final btn in widget.buttons) {
      final dist = (localPos - btn.center).distance;
      if (dist <= btn.radius * 1.28 && dist < bestDist) {
        bestDist = dist;
        closest = btn;
      }
    }
    return closest;
  }

  void _pressKey(int keyCode) {
    final count = (_keyRefCounts[keyCode] ?? 0) + 1;
    _keyRefCounts[keyCode] = count;
    if (count == 1) {
      _send(keyCode, true);
      if (widget.haptics) HapticFeedback.lightImpact();
    }
  }

  void _releaseKey(int keyCode) {
    final current = _keyRefCounts[keyCode] ?? 0;
    if (current <= 1) {
      _keyRefCounts.remove(keyCode);
      _send(keyCode, false);
    } else {
      _keyRefCounts[keyCode] = current - 1;
    }
  }

  void _updatePointer(int pointer, Offset localPos) {
    final hit = _hitTestButton(localPos);
    final newKey = hit?.keyCode;
    final prevKey = _pointerKeys[pointer];

    if (newKey == prevKey) return;

    if (prevKey != null) _releaseKey(prevKey);
    if (newKey != null) _pressKey(newKey);
    _pointerKeys[pointer] = newKey;
    if (mounted) setState(() {});
  }

  void _removePointer(int pointer) {
    final prevKey = _pointerKeys.remove(pointer);
    if (prevKey != null) {
      _releaseKey(prevKey);
      if (mounted) setState(() {});
    }
  }

  Color _accentForLabel(String label) => switch (label) {
    'A' || '○' => const Color(0xFFFF453A), // Crimson / PlayStation Circle
    'B' || '✕' => const Color(0xFF30D158), // Emerald / PlayStation Cross
    'X' || '△' => const Color(0xFF0A84FF), // Cobalt / PlayStation Triangle
    'Y' || '□' => const Color(0xFFFFD60A), // Amber / PlayStation Square
    _ => const Color(0xFF64D2FF),
  };

  bool _isPlayStationSymbol(String label) =>
      label == '○' || label == '✕' || label == '□' || label == '△';

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _updatePointer(e.pointer, e.localPosition),
        onPointerMove: (e) => _updatePointer(e.pointer, e.localPosition),
        onPointerUp: (e) => _removePointer(e.pointer),
        onPointerCancel: (e) => _removePointer(e.pointer),
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final btn in widget.buttons)
                _buildButtonCap(
                  btn,
                  pressed: (_keyRefCounts[btn.keyCode] ?? 0) > 0,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButtonCap(FaceButtonSpec btn, {required bool pressed}) {
    final diameter = btn.radius * 2;
    final accent = _accentForLabel(btn.label);
    final glyphColor = pressed
        ? Colors.white
        : Color.lerp(Colors.white, accent, 0.32)!;

    return Positioned(
      left: btn.center.dx - btn.radius,
      top: btn.center.dy - btn.radius,
      child: ControlCapSurface(
        width: diameter,
        height: diameter,
        borderRadius: btn.radius,
        pressed: pressed,
        accent: accent,
        child: _isPlayStationSymbol(btn.label)
            ? CustomPaint(
                size: Size.square(diameter * 0.44),
                painter: _PlayStationGlyphPainter(
                  symbol: btn.label,
                  color: glyphColor,
                ),
              )
            : Text(
                btn.label,
                style: TextStyle(
                  color: glyphColor,
                  fontSize: diameter * 0.37,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.65),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Vector painter for PlayStation symbols (○, ✕, □, △) so every glyph shares
/// the exact same optical bounding box and stroke thickness.
class _PlayStationGlyphPainter extends CustomPainter {
  final String symbol;
  final Color color;

  const _PlayStationGlyphPainter({required this.symbol, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);

    final shadowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.black.withValues(alpha: 0.55);

    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    void drawWithShadow(void Function(Paint p, Offset offset) drawFn) {
      drawFn(shadowPaint, const Offset(0, 1.0));
      drawFn(strokePaint, Offset.zero);
    }

    switch (symbol) {
      case '○':
        final r = s * 0.42;
        drawWithShadow((p, off) => canvas.drawCircle(c + off, r, p));
        break;
      case '✕':
        final d = s * 0.37;
        drawWithShadow((p, off) {
          canvas.drawLine(c + Offset(-d, -d) + off, c + Offset(d, d) + off, p);
          canvas.drawLine(c + Offset(d, -d) + off, c + Offset(-d, d) + off, p);
        });
        break;
      case '□':
        final half = s * 0.37;
        drawWithShadow((p, off) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: c + off,
                width: half * 2,
                height: half * 2,
              ),
              const Radius.circular(2.2),
            ),
            p,
          );
        });
        break;
      case '△':
        final top = Offset(c.dx, c.dy - s * 0.41);
        final botLeft = Offset(c.dx - s * 0.41, c.dy + s * 0.34);
        final botRight = Offset(c.dx + s * 0.41, c.dy + s * 0.34);
        drawWithShadow((p, off) {
          final path = Path()
            ..moveTo(top.dx + off.dx, top.dy + off.dy)
            ..lineTo(botRight.dx + off.dx, botRight.dy + off.dy)
            ..lineTo(botLeft.dx + off.dx, botLeft.dy + off.dy)
            ..close();
          canvas.drawPath(path, p);
        });
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _PlayStationGlyphPainter old) =>
      old.symbol != symbol || old.color != color;
}

/// Zero-latency single button (L1 / R1 / L2 / R2 / Start / Select) using a raw [Listener].
class PressButton extends StatefulWidget {
  final String label;
  final int keyCode;
  final double width;
  final double height;
  final PadShape shape;
  final bool haptics;
  final int? playerPort;

  const PressButton({
    super.key,
    required this.label,
    required this.keyCode,
    required this.width,
    required this.height,
    this.shape = PadShape.circle,
    this.haptics = true,
    this.playerPort,
  });

  @override
  State<PressButton> createState() => _PressButtonState();
}

class _PressButtonState extends State<PressButton> {
  final Set<int> _pointers = {};

  bool get _pressed => _pointers.isNotEmpty;

  void _send(bool isDown) => EmulatorBridge.sendButton(
    widget.keyCode,
    isDown,
    port: widget.playerPort ?? 0,
  );

  @override
  void dispose() {
    if (_pressed) {
      _send(false);
    }
    super.dispose();
  }

  void _onDown(int pointer) {
    final wasPressed = _pressed;
    _pointers.add(pointer);
    if (!wasPressed) {
      _send(true);
      if (widget.haptics) HapticFeedback.lightImpact();
      if (mounted) setState(() {});
    }
  }

  void _onUp(int pointer) {
    if (_pointers.remove(pointer) && !_pressed) {
      _send(false);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = switch (widget.shape) {
      PadShape.circle => widget.width / 2,
      PadShape.pill => widget.height / 2,
      PadShape.shoulder => 13.0,
    };

    final isPill = widget.shape == PadShape.pill;

    return RepaintBoundary(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _onDown(e.pointer),
        onPointerUp: (e) => _onUp(e.pointer),
        onPointerCancel: (e) => _onUp(e.pointer),
        child: ControlCapSurface(
          width: widget.width,
          height: widget.height,
          borderRadius: radius,
          pressed: _pressed,
          child: Text(
            widget.label,
            style: TextStyle(
              color: _pressed
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.88),
              fontSize: isPill ? 10.0 : 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: isPill ? 0.7 : 0.4,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.65),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 8-way multi-touch sculpted D-Pad with zero gesture delay and directional glow feedback.
class DPadControl extends StatefulWidget {
  final double size;
  final bool haptics;
  final int? playerPort;

  const DPadControl({
    super.key,
    required this.size,
    this.haptics = true,
    this.playerPort,
  });

  @override
  State<DPadControl> createState() => _DPadControlState();
}

class _DPadControlState extends State<DPadControl> {
  int? _pointer;
  bool _up = false;
  bool _down = false;
  bool _left = false;
  bool _right = false;

  void _send(int keyCode, bool isDown) =>
      EmulatorBridge.sendButton(keyCode, isDown, port: widget.playerPort ?? 0);

  @override
  void dispose() {
    _applyDirections(false, false, false, false, updateUi: false);
    super.dispose();
  }

  void _applyDirections(
    bool up,
    bool down,
    bool left,
    bool right, {
    bool updateUi = true,
  }) {
    final changed =
        up != _up || down != _down || left != _left || right != _right;
    if (!changed) return;

    if (up != _up) _send(EmulatorBridge.keyUp, up);
    if (down != _down) _send(EmulatorBridge.keyDown, down);
    if (left != _left) _send(EmulatorBridge.keyLeft, left);
    if (right != _right) _send(EmulatorBridge.keyRight, right);

    if (widget.haptics &&
        ((up && !_up) ||
            (down && !_down) ||
            (left && !_left) ||
            (right && !_right))) {
      HapticFeedback.selectionClick();
    }

    _up = up;
    _down = down;
    _left = left;
    _right = right;
    if (updateUi && mounted) setState(() {});
  }

  void _handlePos(Offset pos) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final delta = pos - center;
    final deadzone = widget.size * 0.14;
    if (delta.distance < deadzone) {
      _applyDirections(false, false, false, false);
      return;
    }

    final angle = math.atan2(delta.dy, delta.dx); // -pi .. pi
    const eighth = math.pi / 8;

    final right = angle > -3 * eighth && angle < 3 * eighth;
    final left = angle > 5 * eighth || angle < -5 * eighth;
    final down = angle > eighth && angle < 7 * eighth;
    final up = angle < -eighth && angle > -7 * eighth;

    _applyDirections(up, down, left, right);
  }

  @override
  Widget build(BuildContext context) {
    final anyActive = _up || _down || _left || _right;

    return RepaintBoundary(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (_pointer != null) return;
          _pointer = e.pointer;
          _handlePos(e.localPosition);
        },
        onPointerMove: (e) {
          if (e.pointer == _pointer) _handlePos(e.localPosition);
        },
        onPointerUp: (e) {
          if (e.pointer == _pointer) {
            _pointer = null;
            _applyDirections(false, false, false, false);
          }
        },
        onPointerCancel: (e) {
          if (e.pointer == _pointer) {
            _pointer = null;
            _applyDirections(false, false, false, false);
          }
        },
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFF141418).withValues(alpha: 0.45),
                const Color(0xFF0A0A0D).withValues(alpha: 0.62),
              ],
            ),
            border: Border.all(
              color: anyActive
                  ? Colors.white.withValues(alpha: 0.34)
                  : Colors.white.withValues(alpha: 0.18),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.38),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _SculptedDPadPainter(
              up: _up,
              down: _down,
              left: _left,
              right: _right,
            ),
          ),
        ),
      ),
    );
  }
}

class _SculptedDPadPainter extends CustomPainter {
  final bool up;
  final bool down;
  final bool left;
  final bool right;

  const _SculptedDPadPainter({
    required this.up,
    required this.down,
    required this.left,
    required this.right,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = Offset(s / 2, s / 2);
    final armWidth = s * 0.31;
    final crossSpan = s * 0.84;
    final halfArm = armWidth / 2;
    final halfSpan = crossSpan / 2;

    // Path.combine is a native boolean op: build it once per size, not on every repaint.
    final crossPath = _crossPathFor(s);

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF34343B).withValues(alpha: 0.78),
          const Color(0xFF18181D).withValues(alpha: 0.86),
        ],
      ).createShader(Rect.fromLTWH(0, 0, s, s));
    canvas.drawPath(crossPath, fillPaint);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..color = Colors.white.withValues(alpha: 0.28);
    canvas.drawPath(crossPath, borderPaint);

    canvas.save();
    canvas.clipPath(crossPath);

    const glowColor = Color(0xFF0A84FF);
    void drawArmGlow(Offset tipCenter, bool active) {
      if (!active) return;
      final glowPaint = Paint()
        ..shader =
            RadialGradient(
              colors: [
                glowColor.withValues(alpha: 0.72),
                glowColor.withValues(alpha: 0.0),
              ],
            ).createShader(
              Rect.fromCircle(center: tipCenter, radius: armWidth * 0.9),
            );
      canvas.drawCircle(tipCenter, armWidth * 0.9, glowPaint);
    }

    drawArmGlow(Offset(c.dx, c.dy - halfSpan * 0.72), up);
    drawArmGlow(Offset(c.dx, c.dy + halfSpan * 0.72), down);
    drawArmGlow(Offset(c.dx - halfSpan * 0.72, c.dy), left);
    drawArmGlow(Offset(c.dx + halfSpan * 0.72, c.dy), right);

    final pivotPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.black.withValues(alpha: 0.45),
          Colors.white.withValues(alpha: 0.06),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: halfArm * 0.75));
    canvas.drawCircle(c, halfArm * 0.75, pivotPaint);

    void drawChevron(Offset tip, double angleRad, bool active) {
      canvas.save();
      canvas.translate(tip.dx, tip.dy);
      canvas.rotate(angleRad);
      final tri = Path()
        ..moveTo(0, -s * 0.036)
        ..lineTo(s * 0.032, s * 0.022)
        ..lineTo(-s * 0.032, s * 0.022)
        ..close();
      canvas.drawPath(
        tri,
        Paint()
          ..color = active
              ? Colors.white
              : Colors.white.withValues(alpha: 0.34),
      );
      canvas.restore();
    }

    final arrowOffset = halfSpan * 0.74;
    drawChevron(Offset(c.dx, c.dy - arrowOffset), 0, up);
    drawChevron(Offset(c.dx, c.dy + arrowOffset), math.pi, down);
    drawChevron(Offset(c.dx - arrowOffset, c.dy), -math.pi / 2, left);
    drawChevron(Offset(c.dx + arrowOffset, c.dy), math.pi / 2, right);

    canvas.restore();
  }

  static final Map<double, Path> _crossPaths = {};

  static Path _crossPathFor(double s) {
    final cached = _crossPaths[s];
    if (cached != null) return cached;
    if (_crossPaths.length > 8)
      _crossPaths.clear(); // sizes only change while editing layouts
    final c = Offset(s / 2, s / 2);
    final armWidth = s * 0.31;
    final crossSpan = s * 0.84;
    final r = Radius.circular(s * 0.065);
    final path = Path.combine(
      PathOperation.union,
      Path()..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: armWidth, height: crossSpan),
          r,
        ),
      ),
      Path()..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: crossSpan, height: armWidth),
          r,
        ),
      ),
    );
    _crossPaths[s] = path;
    return path;
  }

  @override
  bool shouldRepaint(covariant _SculptedDPadPainter old) =>
      old.up != up ||
      old.down != down ||
      old.left != left ||
      old.right != right;
}

/// Analog thumbstick for PSP / 3DS / PS1 with recessed gate ring and concave cap.
class StickControl extends StatefulWidget {
  final double size;
  final int? playerPort;

  /// Which analog axis this stick drives (left stick by default; N64's C buttons use the right).
  final int source;

  /// Key sent when the stick is tapped without being pushed (PS1 L3 / R3). Null = no click.
  final int? clickKeyCode;
  const StickControl({
    super.key,
    required this.size,
    this.playerPort,
    this.source = EmulatorBridge.analogLeft,
    this.clickKeyCode,
  });

  @override
  State<StickControl> createState() => _StickControlState();
}

class _StickControlState extends State<StickControl> {
  int? _pointer;
  Offset _knob = Offset.zero; // normalized -1..1
  double _sentX = 0, _sentY = 0;
  DateTime _downAt = DateTime.fromMillisecondsSinceEpoch(0);
  double _maxPush = 0;

  /// A quick tap that never pushed the stick = a press on the stick (L3 / R3).
  void _maybeClick() {
    final key = widget.clickKeyCode;
    if (key == null) return;
    final quick = DateTime.now().difference(_downAt).inMilliseconds < 280;
    if (!quick || _maxPush > 0.35) return;
    final port = widget.playerPort ?? 0;
    EmulatorBridge.sendButton(key, true, port: port);
    Future.delayed(
      const Duration(milliseconds: 70),
      () => EmulatorBridge.sendButton(key, false, port: port),
    );
  }

  /// Skips values that barely changed (finger jitter): each send is a platform-channel message
  /// plus a native call. A release ([force]) is always sent.
  void _sendStick(double x, double y, {bool force = false}) {
    if (!force && (x - _sentX).abs() < 0.015 && (y - _sentY).abs() < 0.015) {
      return;
    }
    _sentX = x;
    _sentY = y;
    EmulatorBridge.sendAnalog(
      widget.source,
      x,
      y,
      port: widget.playerPort ?? 0,
    );
  }

  @override
  void dispose() {
    _sendStick(0, 0, force: true);
    super.dispose();
  }

  void _update(Offset pos) {
    final radius = widget.size / 2;
    final delta = pos - Offset(radius, radius);
    final maxTravel = radius * 0.65;
    final clamped = delta.distance > maxTravel
        ? Offset.fromDirection(delta.direction, maxTravel)
        : delta;
    final nx = (clamped.dx / maxTravel).clamp(-1.0, 1.0);
    final ny = (clamped.dy / maxTravel).clamp(-1.0, 1.0);
    _sendStick(nx, ny);
    _maxPush = math.max(_maxPush, math.sqrt(nx * nx + ny * ny));
    final moved =
        (nx - _knob.dx).abs() > 0.004 || (ny - _knob.dy).abs() > 0.004;
    if (moved && mounted) setState(() => _knob = Offset(nx, ny));
  }

  void _reset() {
    _pointer = null;
    _sendStick(0, 0, force: true);
    if (mounted) setState(() => _knob = Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final knobSize = widget.size * 0.46;
    final travel = (widget.size - knobSize) * 0.42;
    final active = _pointer != null;
    const accent = Color(0xFF0A84FF);

    return RepaintBoundary(
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (_pointer != null) return;
          _pointer = e.pointer;
          _downAt = DateTime.now();
          _maxPush = 0;
          _update(e.localPosition);
        },
        onPointerMove: (e) {
          if (e.pointer == _pointer) _update(e.localPosition);
        },
        onPointerUp: (e) {
          if (e.pointer != _pointer) return;
          _maybeClick();
          _reset();
        },
        onPointerCancel: (e) {
          if (e.pointer == _pointer) _reset();
        },
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFF0B0B0E).withValues(alpha: 0.66),
                const Color(0xFF1E1E24).withValues(alpha: 0.52),
              ],
            ),
            border: Border.all(
              color: active
                  ? accent.withValues(alpha: 0.72)
                  : Colors.white.withValues(alpha: 0.24),
              width: active ? 1.6 : 1.25,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.42),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: widget.size * 0.72,
                height: widget.size * 0.72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                    width: 1.0,
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(_knob.dx * travel, _knob.dy * travel),
                child: Container(
                  width: knobSize,
                  height: knobSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: active
                          ? [
                              const Color(0xFF484852).withValues(alpha: 0.92),
                              const Color(0xFF1F1F26).withValues(alpha: 0.95),
                            ]
                          : [
                              const Color(0xFF3A3A42).withValues(alpha: 0.80),
                              const Color(0xFF18181E).withValues(alpha: 0.86),
                            ],
                    ),
                    border: Border.all(
                      color: active
                          ? const Color(0xFF64D2FF)
                          : Colors.white.withValues(alpha: 0.55),
                      width: active ? 1.8 : 1.3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: active
                            ? accent.withValues(alpha: 0.35)
                            : Colors.black.withValues(alpha: 0.55),
                        blurRadius: active ? 10 : 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: knobSize * 0.64,
                    height: knobSize * 0.64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(
                          alpha: active ? 0.32 : 0.16,
                        ),
                        width: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
