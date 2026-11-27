// lib/widgets/menu_widgets.dart
import 'dart:typed_data';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../services/theme_service.dart';

enum QuickAction {
  resume,
  save,
  load,
  loadAuto,
  jedTimeMachine,
  cheats,
  coreOptions,
  layout,
  reset,
  customize,
  quit,
}

const Color _kDanger = Color(0xFFFF3B30);

/// Section header. Same type style and 4px inset (relative to the card) as GeneralSettingsScreen.
class MenuSection extends StatelessWidget {
  final String title;
  final Widget child;
  const MenuSection({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                color: c.secondaryText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// iOS grouped card: rounded 14, hairline border, inset dividers. Identical to the Settings card.
class MenuGroupCard extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  const MenuGroupCard({super.key, required this.children, this.padding});

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.isDot ? c.cardRadius : 18),
        border: Border.all(color: c.hairline, width: c.hairlineWidth),
        boxShadow: c.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      // ListTile paints its ink on the nearest Material; this card has its own background colour.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 0.5,
                  thickness: 0.5,
                  indent: 16,
                  color: c.hairline,
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Rounded-square icon badge used in rows (same look as the old tile badge).
class _Badge extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _Badge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    if (c.isDot) {
      // Outlined circle + monochrome glyph. The row's own color (red when active/danger) is kept.
      final tint = (color == c.accent || color == _kDanger)
          ? c.accent
          : c.primaryText;
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: tint.withValues(alpha: 0.4), width: 1),
        ),
        child: Icon(icon, size: 16, color: tint),
      );
    }
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: 17, color: Colors.white),
    );
  }
}

/// Tappable settings-style row: [badge] title (+subtitle)  value  >
/// Focusable (InkWell) so gamepad navigation keeps working.
class MenuRow extends StatelessWidget {
  final IconData icon;
  final Color badgeColor;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback onTap;
  final bool active;
  final bool danger;
  final bool autofocus;
  final bool showChevron;

  const MenuRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.badgeColor = const Color(0xFF007AFF),
    this.subtitle,
    this.value,
    this.active = false,
    this.danger = false,
    this.autofocus = false,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final badge = danger ? _kDanger : (active ? c.accent : badgeColor);
    final textColor = danger ? _kDanger : c.primaryText;

    return InkWell(
      onTap: onTap,
      autofocus: autofocus,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _Badge(icon: icon, color: badge),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 12.5, color: c.secondaryText),
                    ),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 8),
              Text(
                value!,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: active ? c.accent : c.secondaryText,
                ),
              ),
            ],
            if (showChevron && !danger) ...[
              const SizedBox(width: 6),
              Icon(
                CupertinoIcons.chevron_forward,
                size: 15,
                color: c.tertiaryText,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Single-choice row: title, optional blurb, optional tag pill ("Recommended") and a checkmark.
class MenuCheckRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? tag;
  final bool selected;
  final VoidCallback onTap;

  const MenuCheckRow({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.tag,
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w500,
                            color: selected ? c.accent : c.primaryText,
                          ),
                        ),
                      ),
                      if (tag != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: c.accent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tag!,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: c.accent,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 12.5, color: c.secondaryText),
                    ),
                  ],
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 10),
              Icon(CupertinoIcons.checkmark_alt, size: 18, color: c.accent),
            ],
          ],
        ),
      ),
    );
  }
}

/// Switch row, identical metrics to GeneralSettingsScreen._iosSwitch (+ optional badge).
class MenuSwitchRow extends StatelessWidget {
  final IconData? icon;
  final Color badgeColor;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const MenuSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.badgeColor = const Color(0xFF007AFF),
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (icon != null) ...[
            _Badge(icon: icon!, color: badgeColor),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w500,
                    color: c.primaryText,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 12.5, color: c.secondaryText),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          c.isDot
              ? Switch(
                  value: value,
                  onChanged: onChanged,
                ) // outlined dot switch from the Dot theme
              : CupertinoSwitch(
                  value: value,
                  activeTrackColor: c.accent,
                  onChanged: onChanged,
                ),
        ],
      ),
    );
  }
}

/// Slider row, identical metrics to GeneralSettingsScreen._slider.
class MenuSliderRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const MenuSliderRow({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
    this.onChangeEnd,
    this.subtitle,
    this.divisions,
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w500,
                    color: c.primaryText,
                  ),
                ),
              ),
              Text(
                format(value),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: c.secondaryText,
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 12.5, color: c.secondaryText),
            ),
          ],
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: c.accent,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }
}

/// iOS sliding segmented control row (same styling as the Theme Mode picker in Settings).
class MenuSegmentedRow<T extends Object> extends StatelessWidget {
  final String title;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  const MenuSegmentedRow({
    super.key,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w500,
              color: c.primaryText,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: CupertinoSlidingSegmentedControl<T>(
              groupValue: value,
              backgroundColor: c.secondaryFill,
              thumbColor: c.cardBg,
              children: {
                for (final e in options.entries)
                  e.key: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Text(
                      e.value,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: c.primaryText,
                      ),
                    ),
                  ),
              },
              onValueChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Header row for the sheet: title + iOS-style "Resume" pill. Gamepad autofocus lands on Resume.
class MenuSheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onResume;
  const MenuSheetHeader({
    super.key,
    required this.title,
    required this.onResume,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: c.primaryText,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: c.labelFont,
                    color: c.secondaryText,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          autofocus: true,
          style: FilledButton.styleFrom(
            backgroundColor: c.accent,
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          icon: const Icon(Icons.play_arrow_rounded, size: 20),
          label: const Text(
            'Resume',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          onPressed: onResume,
        ),
      ],
    );
  }
}

/// Kept for compatibility: compact grid tile in the same card style. Prefer [MenuRow].
class MenuTile extends StatelessWidget {
  final IconData icon;
  final Color badgeColor;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool danger;

  const MenuTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badgeColor = const Color(0xFF007AFF),
    this.active = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final effectiveBadge = danger ? _kDanger : (active ? c.accent : badgeColor);
    final textColor = danger ? _kDanger : (active ? c.accent : c.primaryText);
    final radius = BorderRadius.circular(14);

    return SizedBox(
      width: 102,
      height: 84,
      child: Material(
        color: active ? c.accent.withValues(alpha: 0.12) : c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: active ? c.accent : c.hairline,
            width: active ? 1.4 : 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Badge(icon: icon, color: effectiveBadge),
                const SizedBox(height: 7),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 11.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    height: 1.15,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String formatSlotTime(DateTime? t) {
  if (t == null) return 'Empty';
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final hm = '${two(t.hour)}:${two(t.minute)}';
  final today = t.year == now.year && t.month == now.month && t.day == now.day;
  return today ? 'Today $hm' : '${t.month}/${t.day} $hm';
}

/// How many manual save-state slots every game has (slot 0 is the auto-save, kept separate).
const int kSaveSlots = 60;

/// Save-slot picker. Wrapped in a grouped card so it sits in the sheet like any other section.
/// With 60 slots it is a horizontally scrolling strip that keeps the selected slot centred,
/// with step buttons and a "next empty" shortcut so a free slot is never a long swipe away.
class SlotPicker extends StatefulWidget {
  final int selected;
  final int count;
  final Map<int, DateTime?> times;
  final Map<int, Uint8List?> thumbs;
  final ValueChanged<int> onSelect;

  const SlotPicker({
    super.key,
    required this.selected,
    required this.times,
    required this.onSelect,
    this.thumbs = const {},
    this.count = kSaveSlots,
  });

  @override
  State<SlotPicker> createState() => _SlotPickerState();
}

class _SlotPickerState extends State<SlotPicker> {
  static const double _cardW = 104;
  static const double _gap = 8;
  static const double _stripH = 124;

  final ScrollController _ctl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _reveal(animate: false),
    );
  }

  @override
  void didUpdateWidget(SlotPicker old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) _reveal(animate: true);
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  /// Scrolls so the selected slot sits in the middle of the strip.
  void _reveal({required bool animate}) {
    if (!mounted || !_ctl.hasClients) return;
    final pos = _ctl.position;
    final target =
        ((widget.selected - 1) * (_cardW + _gap) -
                (pos.viewportDimension - _cardW) / 2)
            .clamp(0.0, pos.maxScrollExtent);
    if (animate) {
      _ctl.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      _ctl.jumpTo(target);
    }
  }

  void _step(int delta) {
    final n = widget.count;
    final next = ((widget.selected - 1 + delta) % n + n) % n + 1;
    widget.onSelect(next);
  }

  /// First empty slot after the selected one (wraps around); stays put if every slot is full.
  void _jumpToEmpty() {
    final n = widget.count;
    for (var k = 1; k <= n; k++) {
      final s = (widget.selected - 1 + k) % n + 1;
      if (widget.times[s] == null) {
        widget.onSelect(s);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final radius = BorderRadius.circular(10);
    final used = widget.times.values.where((t) => t != null).length;

    Widget stepBtn(IconData icon, int delta, String label) => Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _step(delta),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: c.accent),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 8, 6),
            child: Row(
              children: [
                stepBtn(CupertinoIcons.chevron_left, -1, 'Previous slot'),
                stepBtn(CupertinoIcons.chevron_right, 1, 'Next slot'),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Slot ${widget.selected} of ${widget.count} · $used used',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c.secondaryText,
                    ),
                  ),
                ),
                if (used < widget.count)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _jumpToEmpty,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Text(
                        'Next empty',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: c.accent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: _stripH,
            child: ListView.builder(
              controller: _ctl,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: widget.count,
              itemBuilder: (context, index) {
                final i = index + 1;
                final sel = i == widget.selected;
                return Padding(
                  padding: EdgeInsets.only(right: i < widget.count ? _gap : 0),
                  child: SizedBox(
                    width: _cardW,
                    child: Material(
                      clipBehavior: Clip.antiAlias,
                      color: sel
                          ? c.accent.withValues(alpha: 0.12)
                          : c.secondaryFill.withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: radius,
                        side: BorderSide(
                          color: sel ? c.accent : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: InkWell(
                        onTap: () => widget.onSelect(i),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 7, 0, 9),
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(7, 0, 7, 6),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(7),
                                  child: AspectRatio(
                                    aspectRatio: 16 / 10,
                                    child: widget.thumbs[i] != null
                                        ? Image.memory(
                                            widget.thumbs[i]!,
                                            fit: BoxFit.cover,
                                            gaplessPlayback: true,
                                            cacheWidth: 240,
                                          )
                                        : Container(
                                            color: c.secondaryFill,
                                            child: Icon(
                                              CupertinoIcons.photo,
                                              size: 16,
                                              color: c.tertiaryText,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                              Text(
                                'Slot $i',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                  letterSpacing: -0.2,
                                  color: sel ? c.accent : c.primaryText,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formatSlotTime(widget.times[i]),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: widget.times[i] == null
                                      ? c.tertiaryText
                                      : c.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
