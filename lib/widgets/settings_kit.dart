// lib/widgets/settings_kit.dart
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../services/theme_service.dart';

const Color kSettingsDanger = Color(0xFFFF3B30);
const Color kSettingsWarn = Color(0xFFFF9500);
const Color kSettingsOk = Color(0xFF34C759);

/// Rounded-square icon badge with a subtle top-to-bottom gradient.
class SettingsBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const SettingsBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 30,
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    if (c.isDot) {
      // Flat outlined circle, monochrome glyph (red only for danger).
      final tint = color == kSettingsDanger ? c.accent : c.primaryText;
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: tint.withValues(alpha: 0.4), width: 1),
        ),
        child: Icon(icon, size: size * 0.52, color: tint),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(color, Colors.white, 0.24)!, color],
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, size: size * 0.57, color: Colors.white),
    );
  }
}

/// Small tinted capsule used for statuses ("Ready", "3 tweaks", ...).
class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  const StatusPill({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: c.isDot ? Colors.transparent : color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: c.isDot ? Border.all(color: color, width: 1) : null,
      ),
      child: Text(
        c.isDot ? text.toUpperCase() : text,
        style: TextStyle(
          fontFamily: c.labelFont,
          fontSize: c.isDot ? 10.5 : 11.5,
          fontWeight: c.isDot ? FontWeight.w400 : FontWeight.w700,
          letterSpacing: c.isDot ? 0.8 : 0,
          color: color,
        ),
      ),
    );
  }
}

/// Section: small caps header (+ optional trailing action), rounded card, optional footer note.
class SettingsGroup extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final String? footer;
  final double dividerIndent;
  final List<Widget> children;

  const SettingsGroup({
    super.key,
    required this.children,
    this.title,
    this.trailing,
    this.footer,
    this.dividerIndent = 58,
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 6, 8),
            child: Row(
              children: [
                if (c.isDot) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title!.toUpperCase(),
                    style: TextStyle(
                      fontFamily: c.labelFont,
                      color: c.secondaryText,
                      fontSize: 12,
                      fontWeight: c.isDot ? FontWeight.w400 : FontWeight.w600,
                      letterSpacing: c.isDot ? 1.2 : 0.6,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          )
        else
          const SizedBox(height: 16),
        // Material (not Container) so InkWell splashes stay visible on rows.
        RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(c.cardRadius),
              boxShadow: c.cardShadow,
            ),
            child: Material(
              color: c.cardBg,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(c.cardRadius),
                side: BorderSide(color: c.hairline, width: c.hairlineWidth),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 0.5,
                        thickness: 0.5,
                        indent: dividerIndent,
                        color: c.hairline,
                      ),
                    children[i],
                  ],
                ],
              ),
            ),
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 0),
            child: Text(
              footer!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: c.secondaryText,
              ),
            ),
          ),
      ],
    );
  }
}

/// Generic row: [badge] title / subtitle ... value [trailing] >
class SettingsRow extends StatelessWidget {
  final IconData? icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  final bool danger;

  const SettingsRow({
    super.key,
    required this.title,
    this.icon,
    this.color = const Color(0xFF007AFF),
    this.subtitle,
    this.subtitleColor,
    this.value,
    this.trailing,
    this.onTap,
    this.chevron = true,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          if (icon != null) ...[
            SettingsBadge(icon: icon!, color: color),
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
                    color: danger ? kSettingsDanger : c.primaryText,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.25,
                      color: subtitleColor ?? c.secondaryText,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: 8),
            Text(
              value!,
              style: TextStyle(fontSize: 14, color: c.secondaryText),
            ),
          ],
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (chevron && onTap != null) ...[
            const SizedBox(width: 6),
            Icon(CupertinoIcons.chevron_right, size: 15, color: c.tertiaryText),
          ],
        ],
      ),
    );
    return onTap == null ? content : InkWell(onTap: onTap, child: content);
  }
}

/// Whole row toggles; switch on the right.
class SettingsSwitchRow extends StatelessWidget {
  final IconData? icon;
  final Color color;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.icon,
    this.color = const Color(0xFF007AFF),
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return SettingsRow(
      icon: icon,
      color: color,
      title: title,
      subtitle: subtitle,
      chevron: false,
      onTap: () => onChanged(!value),
      trailing: c.isDot
          ? Switch(
              value: value,
              onChanged: onChanged,
            ) // outlined dot switch from the Dot theme
          : CupertinoSwitch(
              value: value,
              activeTrackColor: c.accent,
              onChanged: onChanged,
            ),
    );
  }
}

/// Slider with title, live value capsule and an optional preview on the left.
class SettingsSliderRow extends StatelessWidget {
  final IconData? icon;
  final Color color;
  final String title;
  final String? subtitle;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  final Widget? preview;

  const SettingsSliderRow({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
    this.icon,
    this.color = const Color(0xFF007AFF),
    this.subtitle,
    this.divisions,
    this.preview,
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              SettingsBadge(icon: icon!, color: color),
              const SizedBox(width: 12),
            ],
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: c.secondaryFill,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                format(value),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.primaryText,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.25,
              color: c.secondaryText,
            ),
          ),
        ],
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: c.accent,
            inactiveTrackColor: c.secondaryFill,
            thumbColor: Colors.white,
            overlayColor: c.accent.withValues(alpha: 0.12),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 2),
      child: preview == null
          ? body
          : Row(
              children: [
                preview!,
                const SizedBox(width: 16),
                Expanded(child: body),
              ],
            ),
    );
  }
}

/// iOS sliding segmented control with title and a subtitle that can react to the choice.
class SettingsSegmentedRow<T extends Object> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color color;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  const SettingsSegmentedRow({
    super.key,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.color = const Color(0xFF007AFF),
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                SettingsBadge(icon: icon!, color: color),
                const SizedBox(width: 12),
              ],
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
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.25,
                color: c.secondaryText,
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: CupertinoSlidingSegmentedControl<T>(
              groupValue: value,
              backgroundColor: c.secondaryFill,
              thumbColor: c.isDark ? const Color(0xFF636366) : Colors.white,
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

/// Big header card at the top of the Settings hub (player avatar, name, birthday, edit).
class ProfileHeaderCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final VoidCallback onTap;
  const ProfileHeaderCard({
    super.key,
    required this.name,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final initial = name.trim().isEmpty
        ? '?'
        : String.fromCharCode(name.trim().runes.first).toUpperCase();
    return Material(
      color: c.cardBg,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.hairline, width: 0.5),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [c.accent, const Color(0xFF5856D6)],
                  ),
                ),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: c.primaryText,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: c.secondaryText),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Used by Nintendo DS & 3DS games',
                      style: TextStyle(fontSize: 12, color: c.tertiaryText),
                    ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.pencil_circle_fill,
                size: 26,
                color: c.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tinted call-to-action card ("2 systems need BIOS files").
class AttentionBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const AttentionBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color = kSettingsWarn,
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: color.withValues(alpha: c.isDark ? 0.18 : 0.12),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withValues(alpha: 0.35), width: 0.5),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: c.primaryText,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 15,
                  color: c.tertiaryText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Landscape navigation rail entry (same look as the core-options category list).
class SideRailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool danger;
  final String? trailing;
  final VoidCallback onTap;

  const SideRailItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.danger = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final base = danger ? kSettingsDanger : c.accent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1.5),
      child: Material(
        color: selected ? base.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: danger
                      ? kSettingsDanger
                      : (selected ? c.accent : c.secondaryText),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: danger
                          ? kSettingsDanger
                          : (selected ? c.accent : c.primaryText),
                    ),
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing!,
                    style: TextStyle(fontSize: 12, color: c.secondaryText),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
