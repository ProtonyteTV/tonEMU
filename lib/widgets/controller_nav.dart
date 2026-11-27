// lib/widgets/controller_nav.dart
//
// Gamepad / keyboard navigation for the app UI (library, settings, dialogs, in-game menu).
//   D-pad / arrows : move focus        A / Enter : activate
//   B              : back / close      L1 / R1   : previous / next console filter (library)

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../services/theme_service.dart';

/// Lets a gamepad button pop the current route (dialogs, sheets, settings screens).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class PadBackIntent extends Intent {
  const PadBackIntent();
}

/// Flutter's default shortcuts plus the gamepad buttons.
Map<ShortcutActivator, Intent> padShortcuts() => {
  ...WidgetsApp.defaultShortcuts,
  const SingleActivator(LogicalKeyboardKey.gameButtonA): const ActivateIntent(),
  const SingleActivator(LogicalKeyboardKey.gameButtonB): const PadBackIntent(),
};

Map<Type, Action<Intent>> padActions() => {
  PadBackIntent: CallbackAction<PadBackIntent>(
    onInvoke: (_) {
      appNavigatorKey.currentState?.maybePop();
      return null;
    },
  ),
};

/// Makes a plain tap target (GestureDetector style) reachable with a gamepad:
/// it can take focus, A / Enter triggers [onTap], and an accent ring shows where the focus is.
class PadFocusable extends StatefulWidget {
  final VoidCallback? onTap;
  final HitTestBehavior? behavior;
  final double radius;
  final bool circle;
  final Widget child;

  const PadFocusable({
    super.key,
    required this.onTap,
    required this.child,
    this.behavior,
    this.radius = 12,
    this.circle = false,
  });

  @override
  State<PadFocusable> createState() => _PadFocusableState();
}

class _PadFocusableState extends State<PadFocusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return FocusableActionDetector(
      enabled: widget.onTap != null,
      onShowFocusHighlight: (v) {
        if (mounted && v != _focused) setState(() => _focused = v);
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: widget.behavior,
        onTap: widget.onTap,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.circle
                ? null
                : BorderRadius.circular(widget.radius),
            border: _focused ? Border.all(color: c.accent, width: 2.5) : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
