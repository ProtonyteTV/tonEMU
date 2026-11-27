// lib/screens/general_settings_screen.dart
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../services/app_settings.dart';
import '../services/theme_service.dart';
import '../widgets/fold_support.dart';
import '../widgets/settings_kit.dart';

/// iOS-styled app-wide settings: appearance, video & audio, touch controls, gamepad and saves.
class GeneralSettingsScreen extends StatefulWidget {
  const GeneralSettingsScreen({super.key});

  @override
  State<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends State<GeneralSettingsScreen> {
  final AppSettings _s = AppSettings.instance;
  bool _loaded = false;

  static const _blue = Color(0xFF007AFF);
  static const _purple = Color(0xFF5856D6);
  static const _pink = Color(0xFFFF2D55);
  static const _teal = Color(0xFF32ADE6);
  static const _indigo = Color(0xFF5E5CE6);
  static const _gray = Color(0xFF8E8E93);

  @override
  void initState() {
    super.initState();
    _s.load().then((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  void _change(VoidCallback fn) {
    setState(fn);
    // Debounced: dragging a slider used to write every setting to disk on every tick.
    _s.scheduleSave();
  }

  @override
  void dispose() {
    _s.flush(); // anything still waiting is written as the screen closes
    super.dispose();
  }

  String _filterHint(VideoFilter f) => switch (f) {
    VideoFilter.none => 'Raw picture, no post-processing.',
    VideoFilter.sharp => 'Crisp edges when the picture is scaled up.',
    VideoFilter.crt => 'Old-TV look with scanlines.',
    VideoFilter.lcd => 'Handheld LCD pixel grid.',
  };

  Future<void> _confirmReset() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Reset Display & Controls?'),
        content: const Text(
          'Video, touch, controller and save options go back to their defaults. '
          'Theme, player profile and per-core options are not changed.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _change(() {
      _s.filter = VideoFilter.none;
      _s.portraitMaxHeight = 0.62;
      _s.lowLatencyAudio = false;
      _s.opacity = 1.0;
      _s.haptics = true;
      _s.autoHideTouch = true;
      _s.swapAB = false;
      _s.swapXY = false;
      _s.deadzone = 0.12;
      _s.comboHotkeys = false;
      _s.autoSaveOnQuit = true;
      _s.resumeMode = ResumeMode.smart;
      _s.pauseOnDisconnect = true;
      _s.pauseOnLeave = true;
      _s.fastForwardSpeed = 2;
      _s.autoSaveMinutes = 0;
      _s.breakReminderMinutes = 0;
      _s.jedTimeMachineSeconds = 30;
      _s.screenshotToGallery = false;
      _s.showStats = true;
      _s.showRecent = true;
      _s.showFavorites = true;
      _s.showMostPlayed = true;
      _s.showNewAdditions = true;
      _s.downloadCoverArt = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);

    return c.dotted(
      Scaffold(
        backgroundColor: c.pageBg,
        appBar: AppBar(
          backgroundColor: c.pageBg,
          centerTitle: true,
          title: const Text(
            'Display & Controls',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
        ),
        body: !_loaded
            ? const Center(child: CupertinoActivityIndicator())
            : ListenableBuilder(
                listenable: ThemeService.instance,
                builder: (context, _) {
                  // Landscape / tablet: two columns, and keep clear of notches & the nav bar.
                  final wide = MediaQuery.sizeOf(context).width >= 720;
                  return SafeArea(
                    top: false,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: wide ? 1080 : 680,
                        ),
                        child: ListView(
                          physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          padding: EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            wide ? 24 : 40,
                          ),
                          children: _arrange(wide, [
                            // ── Appearance ──
                            SettingsGroup(
                              title: 'Appearance',
                              dividerIndent: 16,
                              children: [
                                _ThemePicker(
                                  mode: ThemeService.instance.mode,
                                  onChanged: ThemeService.instance.setMode,
                                ),
                                SettingsSegmentedRow<AppStyle>(
                                  icon: CupertinoIcons.paintbrush_fill,
                                  color: _pink,
                                  title: 'Style',
                                  subtitle: switch (ThemeService
                                      .instance
                                      .style) {
                                    AppStyle.dot =>
                                      'Monochrome, dot-matrix type, red accent',
                                    AppStyle.classic =>
                                      'The original tonEMU look',
                                  },
                                  value: ThemeService.instance.style,
                                  options: {
                                    for (final s in AppStyle.values) s: s.label,
                                  },
                                  onChanged: ThemeService.instance.setStyle,
                                ),
                                ValueListenableBuilder<bool>(
                                  valueListenable: FoldShell.enabled,
                                  builder: (_, on, _) => SettingsSwitchRow(
                                    icon: CupertinoIcons.device_phone_portrait,
                                    color: _teal,
                                    title: 'Fold & flip layout',
                                    subtitle: 'Keeps screens clear of the crease on foldable phones',
                                    value: on,
                                    onChanged: FoldShell.setEnabled,
                                  ),
                                ),
                              ],
                            ),

                            // ── Video & Audio ──
                            SettingsGroup(
                              title: 'Video & Audio',
                              footer: 'Filter changes apply to the next game you start.',
                              children: [
                                SettingsSegmentedRow<VideoFilter>(
                                  icon: CupertinoIcons.sparkles,
                                  color: _purple,
                                  title: 'Video filter',
                                  subtitle: _filterHint(_s.filter),
                                  value: _s.filter,
                                  options: {
                                    for (final f in VideoFilter.values)
                                      f: f.label,
                                  },
                                  onChanged: (f) =>
                                      _change(() => _s.filter = f),
                                ),
                                SettingsSliderRow(
                                  icon: CupertinoIcons.device_phone_portrait,
                                  color: _teal,
                                  title: 'Portrait picture height',
                                  subtitle:
                                      'Share of the screen the game may use',
                                  value: _s.portraitMaxHeight,
                                  min: 0.30,
                                  max: 0.80,
                                  divisions: 10,
                                  format: (v) => '${(v * 100).round()}%',
                                  onChanged: (v) =>
                                      _change(() => _s.portraitMaxHeight = v),
                                ),
                                _PortraitPreviewRow(
                                  fraction: _s.portraitMaxHeight,
                                ),
                                SettingsSegmentedRow<int>(
                                  icon: CupertinoIcons.forward_fill,
                                  color: _blue,
                                  title: 'Fast-forward speed',
                                  subtitle: 'Used by the fast-forward button and hotkey',
                                  value: _s.fastForwardSpeed,
                                  options: const {2: '2x', 3: '3x', 4: '4x'},
                                  onChanged: (v) =>
                                      _change(() => _s.fastForwardSpeed = v),
                                ),
                                SettingsSwitchRow(
                                  icon: CupertinoIcons.speaker_2_fill,
                                  color: _pink,
                                  title: 'Low-latency audio',
                                  subtitle:
                                      'Less delay; may crackle on slow devices',
                                  value: _s.lowLatencyAudio,
                                  onChanged: (v) =>
                                      _change(() => _s.lowLatencyAudio = v),
                                ),
                              ],
                            ),

                            // ── Touch controls ──
                            SettingsGroup(
                              title: 'Touch Controls',
                              children: [
                                SettingsSliderRow(
                                  icon: CupertinoIcons.circle_lefthalf_fill,
                                  color: _blue,
                                  title: 'Button opacity',
                                  subtitle:
                                      'How visible the on-screen buttons are',
                                  value: _s.opacity,
                                  min: 0.2,
                                  max: 1.0,
                                  divisions: 8,
                                  format: (v) => '${(v * 100).round()}%',
                                  preview: _ButtonsPreview(opacity: _s.opacity),
                                  onChanged: (v) =>
                                      _change(() => _s.opacity = v),
                                ),
                                SettingsSwitchRow(
                                  icon: CupertinoIcons.waveform_path,
                                  color: _indigo,
                                  title: 'Haptic feedback',
                                  subtitle: 'Vibrate lightly on button press',
                                  value: _s.haptics,
                                  onChanged: (v) =>
                                      _change(() => _s.haptics = v),
                                ),
                                SettingsSwitchRow(
                                  icon: CupertinoIcons.eye_slash_fill,
                                  color: _gray,
                                  title: 'Hide when gamepad connected',
                                  subtitle: 'Auto-hide the on-screen buttons',
                                  value: _s.autoHideTouch,
                                  onChanged: (v) =>
                                      _change(() => _s.autoHideTouch = v),
                                ),
                              ],
                            ),

                            // ── Physical controller ──
                            SettingsGroup(
                              title: 'Physical Controller',
                              footer: _s.comboHotkeys
                                  ? 'Hold Select, then press: Start = menu, R1 = quick save, '
                                        'L1 = quick load, Y = fast-forward, X = next save slot, '
                                        'R3 = screenshot, L3 = mute.'
                                  : 'Turn on combo hotkeys to open the menu, quick save/load '
                                        'and fast-forward straight from your controller.',
                              children: [
                                SettingsSwitchRow(
                                  icon: CupertinoIcons.arrow_right_arrow_left,
                                  color: kSettingsOk,
                                  title: 'Swap A / B',
                                  subtitle:
                                      'For pads with Nintendo-style labels',
                                  value: _s.swapAB,
                                  onChanged: (v) =>
                                      _change(() => _s.swapAB = v),
                                ),
                                SettingsSwitchRow(
                                  icon: CupertinoIcons.arrow_right_arrow_left,
                                  color: kSettingsWarn,
                                  title: 'Swap X / Y',
                                  value: _s.swapXY,
                                  onChanged: (v) =>
                                      _change(() => _s.swapXY = v),
                                ),
                                SettingsSliderRow(
                                  icon:
                                      CupertinoIcons.dot_radiowaves_left_right,
                                  color: _teal,
                                  title: 'Stick deadzone',
                                  subtitle: 'Ignore small stick movements',
                                  value: _s.deadzone,
                                  min: 0.0,
                                  max: 0.5,
                                  divisions: 25,
                                  format: (v) => '${(v * 100).round()}%',
                                  onChanged: (v) =>
                                      _change(() => _s.deadzone = v),
                                ),
                                SettingsSwitchRow(
                                  icon: CupertinoIcons.pause_circle_fill,
                                  color: kSettingsWarn,
                                  title: 'Pause when disconnected',
                                  subtitle: 'Open the menu if the controller or headphones drop out',
                                  value: _s.pauseOnDisconnect,
                                  onChanged: (v) =>
                                      _change(() => _s.pauseOnDisconnect = v),
                                ),
                                SettingsSwitchRow(
                                  icon: CupertinoIcons.pause_circle_fill,
                                  color: kSettingsWarn,
                                  title: 'Pause when leaving the game',
                                  subtitle:
                                      'Pauses when you leave the app or pull down the notifications. '
                                      'Press A or B to continue',
                                  value: _s.pauseOnLeave,
                                  onChanged: (v) =>
                                      _change(() => _s.pauseOnLeave = v),
                                ),
                                SettingsSwitchRow(
                                  icon: CupertinoIcons.command,
                                  color: _purple,
                                  title: 'Combo hotkeys',
                                  subtitle: 'Select + Start / R1 / L1 / Y / X / L3 / R3',
                                  value: _s.comboHotkeys,
                                  onChanged: (v) =>
                                      _change(() => _s.comboHotkeys = v),
                                ),
                              ],
                            ),

                            // ── Saves ──
                            SettingsGroup(
                              title: 'Saves',
                              children: [
                                SettingsSwitchRow(
                                  icon: CupertinoIcons.tray_arrow_down_fill,
                                  color: _blue,
                                  title: 'Auto-save on quit',
                                  subtitle: 'Save a state when leaving a game',
                                  value: _s.autoSaveOnQuit,
                                  onChanged: (v) =>
                                      _change(() => _s.autoSaveOnQuit = v),
                                ),
                                SettingsSegmentedRow<int>(
                                  icon: CupertinoIcons.timer,
                                  color: _teal,
                                  title: 'Periodic auto-save',
                                  subtitle: 'Silently refresh the auto-save while you play',
                                  value: _s.autoSaveMinutes,
                                  options: const {
                                    0: 'Off',
                                    2: '2 min',
                                    5: '5 min',
                                    10: '10 min',
                                  },
                                  onChanged: (v) =>
                                      _change(() => _s.autoSaveMinutes = v),
                                ),
                                SettingsSegmentedRow<int>(
                                  icon: CupertinoIcons.hourglass,
                                  color: _purple,
                                  title: 'Break reminder',
                                  subtitle: 'A gentle note after this long in one play session',
                                  value: _s.breakReminderMinutes,
                                  options: const {
                                    0: 'Off',
                                    30: '30 min',
                                    60: '1 h',
                                    90: '1.5 h',
                                  },
                                  onChanged: (v) => _change(
                                    () => _s.breakReminderMinutes = v,
                                  ),
                                ),
                                SettingsSegmentedRow<int>(
                                  icon: CupertinoIcons.time,
                                  color: _teal,
                                  title: 'jedTimeMachine',
                                  subtitle:
                                      'Records the last minutes of play so you can jump back to any '
                                      'moment from the in-game menu. Off for games with huge states.',
                                  value: _s.jedTimeMachineSeconds,
                                  options: const {
                                    0: 'Off',
                                    15: '15 s',
                                    30: '30 s',
                                    60: '60 s',
                                  },
                                  onChanged: (v) => _change(
                                    () => _s.jedTimeMachineSeconds = v,
                                  ),
                                ),
                                SettingsSwitchRow(
                                  icon: CupertinoIcons.photo_fill,
                                  color: _pink,
                                  title: 'Screenshots to Gallery',
                                  subtitle: 'Also copy screenshots to Pictures/tonEMU',
                                  value: _s.screenshotToGallery,
                                  onChanged: (v) =>
                                      _change(() => _s.screenshotToGallery = v),
                                ),
                                SettingsSegmentedRow<ResumeMode>(
                                  icon: CupertinoIcons.play_circle_fill,
                                  color: kSettingsOk,
                                  title: 'When a game has an auto-save',
                                  subtitle:
                                      'Continue jumps straight back in and offers "Start over" for a few seconds. '
                                      'Long-press a game for "Start Fresh".',
                                  value: _s.resumeMode,
                                  options: const {
                                    ResumeMode.smart: 'Continue',
                                    ResumeMode.ask: 'Ask me',
                                    ResumeMode.fresh: 'New game',
                                  },
                                  onChanged: (v) =>
                                      _change(() => _s.resumeMode = v),
                                ),
                              ],
                            ),

                            // ── Reset ──
                            SettingsGroup(
                              dividerIndent: 16,
                              children: [
                                SettingsRow(
                                  title: 'Reset to defaults',
                                  danger: true,
                                  chevron: false,
                                  onTap: _confirmReset,
                                ),
                              ],
                            ),
                          ]),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  /// Wide screens split the six groups into two balanced columns (display + touch on the
  /// left, controller + saves + reset on the right); narrow screens keep the single column.
  List<Widget> _arrange(bool wide, List<Widget> groups) {
    if (!wide || groups.length < 4) return groups;
    const split = 3;
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Column(children: groups.sublist(0, split))),
          const SizedBox(width: 16),
          Expanded(child: Column(children: groups.sublist(split))),
        ],
      ),
    ];
  }
}

// ───────────────────────── Theme picker ─────────────────────────

class _ThemePicker extends StatelessWidget {
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;
  const _ThemePicker({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Row(
        children: [
          for (final m in ThemeMode.values) ...[
            if (m != ThemeMode.values.first) const SizedBox(width: 10),
            Expanded(
              child: _ThemeCard(
                mode: m,
                selected: m == mode,
                onTap: () => onChanged(m),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  Widget _mini(bool dark) {
    final bg = dark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final card = dark ? const Color(0xFF2C2C2E) : Colors.white;
    final bar = dark ? const Color(0xFF636366) : const Color(0xFFC7C7CC);
    return Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(8, 9, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 5,
            decoration: BoxDecoration(
              color: bar,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: card,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
              ),
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26,
                    height: 4,
                    decoration: BoxDecoration(
                      color: bar,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 16,
                    height: 4,
                    decoration: BoxDecoration(
                      color: bar.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final label = switch (mode) {
      ThemeMode.system => 'System',
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
    };
    final preview = switch (mode) {
      ThemeMode.light => _mini(false),
      ThemeMode.dark => _mini(true),
      ThemeMode.system => Row(
        children: [
          Expanded(child: ClipRect(child: _mini(false))),
          Expanded(child: ClipRect(child: _mini(true))),
        ],
      ),
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 74,
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: selected ? c.accent : c.hairline,
                width: selected ? 2 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9.5),
              child: SizedBox.expand(child: preview),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (selected) ...[
                Icon(
                  CupertinoIcons.checkmark_alt_circle_fill,
                  size: 15,
                  color: c.accent,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? c.accent : c.secondaryText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── Live previews ─────────────────────────

/// Mini phone showing how much of the screen the picture will use in portrait.
class _PortraitPreviewRow extends StatelessWidget {
  final double fraction;
  const _PortraitPreviewRow({required this.fraction});

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    const phoneH = 92.0;
    const phoneW = 46.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Center(
        child: Container(
          width: phoneW,
          height: phoneH,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: c.secondaryFill,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: c.hairline),
          ),
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: (phoneH - 6) * fraction,
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  CupertinoIcons.game_controller_solid,
                  size: 14,
                  color: Colors.white,
                ),
              ),
              Expanded(
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var i = 0; i < 2; i++)
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.tertiaryText,
                          ),
                        ),
                    ],
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

/// 2x2 face-button preview that follows the opacity slider.
class _ButtonsPreview extends StatelessWidget {
  final double opacity;
  const _ButtonsPreview({required this.opacity});

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    Widget btn(String t) => Opacity(
      opacity: opacity,
      child: Container(
        width: 19,
        height: 19,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.isDark ? const Color(0xFF48484A) : const Color(0xFF3A3A3C),
        ),
        child: Text(
          t,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
    return Container(
      width: 66,
      height: 66,
      decoration: BoxDecoration(
        color: c.secondaryFill,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          btn('Y'),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [btn('X'), const SizedBox(width: 8), btn('B')],
          ),
          btn('A'),
        ],
      ),
    );
  }
}
