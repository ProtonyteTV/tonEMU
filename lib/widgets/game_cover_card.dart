// lib/widgets/game_cover_card.dart
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/console_system.dart';
import '../services/box_art_service.dart';
import '../services/theme_service.dart';

/// Displays a game's cached or auto-fetched box art cover in a rounded grid tile,
/// with a styled fallback cover when offline/unmatched and long-press actions.
class GameCoverCard extends StatefulWidget {
  final File romFile;
  final ConsoleSystem system;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const GameCoverCard({
    super.key,
    required this.romFile,
    required this.system,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<GameCoverCard> createState() => _GameCoverCardState();
}

class _GameCoverCardState extends State<GameCoverCard> {
  File? _coverFile;
  bool _loading = true;
  bool _pressed = false;
  int _loadToken = 0; // ignores a slow, outdated load when the card is reused for another game

  String get _romFileName => widget.romFile.uri.pathSegments.last;
  String get _title => ConsoleSystem.cleanTitle(_romFileName);

  @override
  void initState() {
    super.initState();
    _loadCover();
  }

  @override
  void didUpdateWidget(covariant GameCoverCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.romFile.path != widget.romFile.path ||
        oldWidget.system.shortName != widget.system.shortName) {
      _loadCover();
    }
  }

  Future<void> _loadCover() async {
    final token = ++_loadToken;
    setState(() => _loading = true);
    final file = await BoxArtService.instance.getOrFetchCover(
      widget.system,
      _romFileName,
    );
    if (!mounted || token != _loadToken) return;
    setState(() {
      _coverFile = file;
      _loading = false;
    });
  }

  /// Refreshes the card image after setting or clearing a custom cover.
  Future<void> reloadCover() => _loadCover();

  Color _systemAccent(String shortName) {
    switch (shortName.toUpperCase()) {
      case 'PSP':
        return const Color(0xFF38BDF8);
      case 'PS1':
        return const Color(0xFF818CF8);
      case 'NDS':
        return const Color(0xFF34D399);
      case '3DS':
        return const Color(0xFFF87171);
      case 'GBA':
        return const Color(0xFFA78BFA);
      case 'GBC':
        return const Color(0xFFFBBF24);
      case 'N64':
        return const Color(0xFF2ECC71);
      case 'SMS':
        return const Color(0xFFF472B6);
      case 'GG':
        return const Color(0xFFFFC107);
      case 'MD':
        return const Color(0xFF60A5FA);
      case 'SATURN':
        return const Color(0xFFC084FC);
      default:
        return const Color(0xFF94A3B8);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _systemAccent(widget.system.shortName);
    final c = XEmuColors.of(context);
    final radius = c.isDot ? 24.0 : 18.0;

    return Semantics(
      button: true,
      label: '$_title, ${widget.system.shortName}',
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: ExcludeSemantics(child: _card(context, accent, c, radius)),
    );
  }

  Widget _card(
    BuildContext context,
    Color accent,
    XEmuColors c,
    double radius,
  ) {
    return AnimatedScale(
      scale: _pressed ? 0.965 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: c.cardShadow,
        ),
        child: Material(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress == null
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    widget.onLongPress!();
                  },
            onHighlightChanged: (v) => setState(() => _pressed = v),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: c.hairline, width: c.hairlineWidth),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Cover Art Area ──
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_coverFile != null)
                          Image.file(
                            _coverFile!,
                            fit: BoxFit.cover,
                            // Decode near tile size, not full art: far less memory in big libraries.
                            cacheWidth: 400,
                            gaplessPlayback: true,
                            frameBuilder: (_, child, frame, sync) => sync
                                ? child
                                : AnimatedOpacity(
                                    opacity: frame == null ? 0 : 1,
                                    duration: const Duration(milliseconds: 220),
                                    child: child,
                                  ),
                            errorBuilder: (_, _, _) => _fallbackArt(accent, c),
                          )
                        else
                          _fallbackArt(accent, c),

                        // Subtle bottom gradient for clean contrast
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.45),
                                ],
                                stops: const [0.65, 1.0],
                              ),
                            ),
                          ),
                        ),

                        // Console pill badge (top-right)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(
                                c.isDot ? 99 : 8,
                              ),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.55),
                              ),
                            ),
                            child: Text(
                              widget.system.shortName,
                              style: TextStyle(
                                fontFamily: c.labelFont,
                                color: accent,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),

                        if (_loading)
                          const Positioned(
                            bottom: 8,
                            right: 8,
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // ── Game Title Footer ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                    child: Text(
                      _title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.primaryText,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallbackArt(Color accent, XEmuColors c) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.22), c.secondaryFill],
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _title.isEmpty
                ? '?'
                : String.fromCharCode(_title.runes.first).toUpperCase(),
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              height: 1,
              color: accent.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
