// lib/screens/core_list_screens.dart
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/console_system.dart';
import '../services/app_settings.dart';
import '../services/bios_registry.dart';
import '../services/core_presets.dart';
import '../services/core_settings.dart';
import '../services/emulator_bridge.dart';
import '../services/storage_service.dart';
import '../services/theme_service.dart';
import 'about_screen.dart';
import 'bios_screen.dart';
import 'core_settings_screen.dart';
import '../widgets/library_settings_group.dart';
import '../widgets/settings_kit.dart';
import '../widgets/update_rows.dart';
import 'general_settings_screen.dart';

/// iOS-styled Settings hub with full Light & Dark mode support and landscape centering.
class CoreListScreen extends StatefulWidget {
  const CoreListScreen({super.key});

  @override
  State<CoreListScreen> createState() => _CoreListScreenState();
}

class _CoreListScreenState extends State<CoreListScreen> {
  int _pane = 0; // selected section in the landscape layout
  final Map<String, int> _modified = {};
  final AppSettings _settings = AppSettings.instance;
  Map<String, String> _activePreset = {};
  int _biosNeedFiles = 0;
  int _biosRecommended = 0;

  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// Opens the link (or mail app for mailto:). Only if nothing can open it, the address is
  /// copied instead so the user is never left with a dead tap.
  Future<void> _openLink(String label, String url) async {
    if (await EmulatorBridge.openUrl(url)) return;
    final text = url.startsWith('mailto:')
        ? url.substring(7).split('?').first
        : url;
    await Clipboard.setData(ClipboardData(text: text));
    _snack('Couldn\'t open $label, copied: $text');
  }

  /// Opens the tonEMU Developers & Credits modal.
  Future<void> _showDevelopersModal() async {
    if (!mounted) return;

    final c = XEmuColors.of(context);

    const coreCredits = <({String core, String authors, String system})>[
      (
        core: 'Libretro & RetroArch',
        authors: 'Libretro Team & Contributors',
        system: 'Libretro API, Core Infrastructure & Thumbnail Database',
      ),
      (
        core: 'LibretroDroid',
        authors: 'Filippo Scognamiglio (Swordfish90)',
        system: 'Android Libretro Frontend Bridge',
      ),
      (
        core: 'PPSSPP',
        authors: 'Henrik Rydgård & PPSSPP Contributors',
        system: 'Sony PlayStation Portable (PSP)',
      ),
      (
        core: 'SwanStation',
        authors: 'Stenzek & SwanStation Contributors',
        system: 'Sony PlayStation (PS1)',
      ),
      (
        core: 'melonDS',
        authors: 'Arisotura & melonDS Contributors',
        system: 'Nintendo DS (NDS)',
      ),
      (
        core: 'Azahar',
        authors: 'Azahar Team · PabloMK7 · OpenSauce04',
        system: 'Nintendo 3DS (3DS)',
      ),
      (
        core: 'mGBA',
        authors: 'Vicki Pfau (endrift) & mGBA Contributors',
        system: 'Nintendo Game Boy Advance (GBA)',
      ),
      (
        core: 'Gambatte',
        authors: 'Sinamas & Gambatte Contributors',
        system: 'Nintendo Game Boy / Game Boy Color (GB / GBC)',
      ),
      (
        core: 'FCEUmm',
        authors: 'FCEU Team · CaH4e3 & Contributors',
        system: 'Nintendo Entertainment System / Famicom (NES)',
      ),
      (
        core: 'bsnes',
        authors: 'Near, byuu & bsnes Contributors',
        system: 'Super Nintendo Entertainment System (SNES)',
      ),
      (
        core: 'Mupen64Plus-Next',
        authors: 'Mupen64Plus Team · libretro Contributors',
        system: 'Nintendo 64 (N64)',
      ),
      (
        core: 'BlastEm',
        authors: 'Mike Pavone & BlastEm Contributors',
        system: 'Sega Genesis / Mega Drive (MD)',
      ),
      (
        core: 'Gearsystem',
        authors: 'Ignacio Sanchez & Gearsystem Contributors',
        system: 'Sega Master System / Game Gear (SMS / GG)',
      ),
      (
        core: 'Yabause',
        authors: 'Yabause Team & Contributors',
        system: 'Sega Saturn',
      ),
      (
        core: 'PokeMini',
        authors: 'JustBurn & PokeMini Contributors',
        system: 'Nintendo Pokémon Mini',
      ),
      (
        core: 'Beetle Cygne',
        authors: 'Dox · Mednafen Team',
        system: 'Bandai WonderSwan / WonderSwan Color',
      ),
    ];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.groupedBg,
      showDragHandle: false,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 680),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.80,
        minChildSize: 0.50,
        maxChildSize: 0.94,
        builder: (_, scrollController) => Column(
          children: [
            const SizedBox(height: 10),

            // iOS-style drag indicator
            Container(
              width: 38,
              height: 5,
              decoration: BoxDecoration(
                color: c.tertiaryText.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
              ),
            ),

            // Modal navigation header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Developers & Credits',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            color: c.primaryText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'The people and projects behind tonEMU',
                          style: TextStyle(
                            fontSize: 12,
                            color: c.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(ctx),
                    icon: Icon(
                      CupertinoIcons.xmark_circle_fill,
                      color: c.secondaryText,
                      size: 25,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                controller: scrollController,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  // MARK: tonEMU Team
                  _sectionHeader('tonEMU Team', c),

                  _groupCard([
                    ListTile(
                      leading: _iosIconBadge(
                        CupertinoIcons.person_fill,
                        const Color(0xFF007AFF),
                      ),
                      title: Text(
                        'Kyle Genesis F. Lambot',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.primaryText,
                        ),
                      ),
                      subtitle: Text(
                        'Founder',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.secondaryText,
                        ),
                      ),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 5,
                      ),
                      leading: _iosIconBadge(
                        Icons.pets_rounded,
                        const Color(0xFFFFB63D),
                      ),
                      title: Text(
                        kTontonName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.primaryText,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              kTontonTitle,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: c.secondaryText,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Inspiration & Beloved Companion · $kTontonDates',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: c.tertiaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      isThreeLine: true,
                    ),
                  ], c),

                  // MARK: Core Developers
                  _sectionHeader('Emulator Core Developers', c),

                  _groupCard([
                    for (final item in coreCredits.skip(2))
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 5,
                        ),
                        leading: _iosIconBadge(
                          CupertinoIcons.gamecontroller_fill,
                          const Color(0xFF5856D6),
                        ),
                        title: Text(
                          item.core,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.primaryText,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.authors,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.3,
                                  color: c.secondaryText,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                item.system,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: c.tertiaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        isThreeLine: true,
                      ),
                  ], c),

                  // MARK: Infrastructure
                  _sectionHeader('Libraries & Infrastructure', c),

                  _groupCard([
                    for (final item in coreCredits.take(2))
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 5,
                        ),
                        leading: _iosIconBadge(
                          CupertinoIcons.wrench_fill,
                          const Color(0xFF8E8E93),
                        ),
                        title: Text(
                          item.core,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.primaryText,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.authors,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: c.secondaryText,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                item.system,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: c.tertiaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                        isThreeLine: true,
                      ),
                  ], c),

                  const SizedBox(height: 24),
                  const TontonTribute(),
                  const SizedBox(height: 24),

                  Center(
                    child: Column(
                      children: [
                        Text(
                          'tonEMU',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: c.primaryText,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Made with dedication by jedPlatforms',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: c.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    await _settings.load();

    // Start the (disk) BIOS scan first and read every core's overrides at the same time,
    // instead of waiting for them one after another.
    final biosFuture = BiosRegistry.scan();
    final coreKeys = <String>{
      for (final s in ConsoleSystem.allSystems) s.coreLibName,
    };
    final overridesByCore = <String, Map<String, String>>{};
    await Future.wait([
      for (final key in coreKeys)
        CoreSettings.loadOverrides(key).then((m) => overridesByCore[key] = m),
    ]);
    final counts = <String, int>{
      for (final key in coreKeys) key: overridesByCore[key]!.length,
    };

    final presetLabels = <String, String>{};
    for (final key in coreKeys) {
      if (!CorePresets.hasPresets(key)) continue;
      final active = CorePresets.activeLevels(
        key,
        overridesByCore[key]!,
        applied: await CorePresets.loadApplied(key),
      );
      if (active.length == 1) {
        // A stored preset id that no longer exists must not break the whole page
        // (firstWhere without orElse threw a StateError here).
        for (final p in CorePresets.presets) {
          if (p.id == active.first) {
            presetLabels[key] = p.label;
            break;
          }
        }
      }
    }

    final bios = await biosFuture;

    if (!mounted) return;
    setState(() {
      _modified
        ..clear()
        ..addAll(counts);
      _activePreset = presetLabels;
      _biosNeedFiles = bios
          .where((g) => g.level == GroupLevel.needsFiles)
          .length;
      _biosRecommended = bios
          .where(
            (g) =>
                g.level == GroupLevel.recommended ||
                g.level == GroupLevel.incomplete,
          )
          .length;
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  int _daysInMonth(int month) {
    if (month == 2) return 29;
    if (month == 4 || month == 6 || month == 9 || month == 11) return 30;
    return 31;
  }

  String _formatBirthday(int month, int day) {
    final mName = _monthNames[(month - 1).clamp(0, 11)];
    return '$mName $day';
  }

  String _themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'System',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  String _friendlyCoreLabel(String coreLibName, List<String> systems) {
    final key = coreLibName.toLowerCase();
    if (key.contains('melonds')) return 'Nintendo DS · melonDS';
    if (key.contains('ppsspp')) return 'PlayStation Portable · PPSSPP';
    if (key.contains('azahar') || key.contains('citra')) {
      return 'Nintendo 3DS · Azahar';
    }
    if (key.contains('swanstation') || key.contains('duckstation')) {
      return 'PlayStation 1 · SwanStation';
    }
    if (key.contains('mupen64plus')) return 'Nintendo 64 · Mupen64Plus-Next';
    if (key.contains('blastem')) return 'Sega Genesis / Mega Drive · BlastEm';
    if (key.contains('gearsystem'))
      return 'Sega Master System / Game Gear · Gearsystem';
    if (key.contains('bsnes')) return 'Super Nintendo · bsnes';
    if (key.contains('yabause')) return 'Sega Saturn · Yabause';
    if (key.contains('pokemini')) return 'Pokémon Mini · PokeMini';
    if (key.contains('wswan')) return 'WonderSwan / Color · Beetle Cygne';
    if (key.contains('fceumm')) return 'Nintendo Entertainment System · FCEUmm';
    if (key.contains('mgba')) return 'Game Boy Advance · mGBA';
    if (key.contains('gambatte')) return 'Game Boy / Color · Gambatte';
    return '${systems.join(' / ')} · ${CoreSettings.coreTitle(coreLibName)}';
  }

  IconData _coreIcon(String coreLibName) {
    final key = coreLibName.toLowerCase();
    if (key.contains('ppsspp') || key.contains('swanstation')) {
      return CupertinoIcons.game_controller_solid;
    }
    if (key.contains('melonds') || key.contains('azahar')) {
      return CupertinoIcons.device_phone_portrait;
    }
    return CupertinoIcons.sparkles;
  }

  Future<void> _editPlayerProfile() async {
    final c = XEmuColors.of(context);
    final nickCtrl = TextEditingController(text: _settings.nickname);
    var selectedMonth = _settings.birthMonth.clamp(1, 12);
    var selectedDay = _settings.birthDay.clamp(1, _daysInMonth(selectedMonth));

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final maxDays = _daysInMonth(selectedMonth);
          if (selectedDay > maxDays) selectedDay = maxDays;

          return AlertDialog(
            backgroundColor: c.cardBg,
            title: Text(
              '3DS & NDS Profile',
              style: TextStyle(
                color: c.primaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nickCtrl,
                    maxLength: 10,
                    textCapitalization: TextCapitalization.words,
                    style: TextStyle(color: c.primaryText),
                    decoration: const InputDecoration(
                      labelText: 'Nickname',
                      hintText: 'Up to 10 characters',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Birthday',
                    style: TextStyle(fontSize: 12, color: c.secondaryText),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<int>(
                          initialValue: selectedMonth,
                          dropdownColor: c.cardBg,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (var m = 1; m <= 12; m++)
                              DropdownMenuItem(
                                value: m,
                                child: Text(
                                  _monthNames[m - 1],
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: c.primaryText),
                                ),
                              ),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setDlg(() {
                                selectedMonth = v;
                                final limit = _daysInMonth(v);
                                if (selectedDay > limit) selectedDay = limit;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<int>(
                          initialValue: selectedDay,
                          dropdownColor: c.cardBg,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (var d = 1; d <= maxDays; d++)
                              DropdownMenuItem(
                                value: d,
                                child: Text(
                                  '$d',
                                  style: TextStyle(color: c.primaryText),
                                ),
                              ),
                          ],
                          onChanged: (v) {
                            if (v != null) setDlg(() => selectedDay = v);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (saved == true) {
      final raw = nickCtrl.text.trim();
      _settings.nickname = raw.isEmpty ? 'tonEMU' : raw;
      _settings.birthMonth = selectedMonth;
      _settings.birthDay = selectedDay;
      await _settings.save();
      if (mounted) setState(() {});
      _snack(
        'Saved profile: ${_settings.nickname} (${_formatBirthday(_settings.birthMonth, _settings.birthDay)})',
      );
    }
    nickCtrl.dispose();
  }

  Future<void> _confirmResetAllCores(Iterable<String> coreKeys) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Reset All Core Options?'),
        content: const Text(
          'This restores every emulator core back to its default settings.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset All'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    for (final k in coreKeys) {
      await prefs.remove('core_opts_$k');
    }
    await _refresh();
    _snack('All core options restored to defaults');
  }

  // ───────────────────────── iOS UI Builders ─────────────────────────

  Future<void> _onStorageFolderTap() async {
    final storage = StorageService.instance;
    String msg;
    if (storage.canRequestAllFilesAccess) {
      final granted = await storage.requestAllFilesAccess();
      msg = granted
          ? 'Using ${storage.displayPath}'
          : 'All files access not granted - using app-private storage';
    } else {
      await Clipboard.setData(ClipboardData(text: storage.displayPath));
      msg = 'Path copied';
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _sectionHeader(String title, XEmuColors c, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: c.secondaryText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }

  Widget _groupCard(List<Widget> children, XEmuColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.hairline, width: 0.5),
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
                  indent: 56,
                  color: c.hairline,
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }

  /// Authentic solid rounded-square iOS Settings icon badge.
  Widget _iosIconBadge(IconData icon, Color bg) {
    // Dot theme: reuse the Settings glyph badge (outlined circle, monochrome).
    if (XEmuColors.of(context).isDot) {
      return SettingsBadge(icon: icon, color: bg);
    }
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, color: Colors.white, size: 17),
    );
  }

  /// Landscape: navigation rail on the left (profile, alerts, sections), selected section on the
  /// right. Same structure as the core options screen.
  Widget _wideSettings(
    XEmuColors c,
    List<Widget> header,
    List<({String label, IconData icon, Widget child})> panes,
  ) {
    final size = MediaQuery.sizeOf(context);
    final sideW = (size.width * 0.32).clamp(260.0, 360.0);
    final sel = _pane.clamp(0, panes.length - 1);
    return SafeArea(
      top: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: sideW,
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Column(children: header),
                ),
                for (var i = 0; i < panes.length; i++)
                  SideRailItem(
                    icon: panes[i].icon,
                    label: panes[i].label,
                    selected: i == sel,
                    onTap: () => setState(() => _pane = i),
                  ),
              ],
            ),
          ),
          VerticalDivider(width: 0.5, thickness: 0.5, color: c.hairline),
          Expanded(
            child: ListView(
              key: ValueKey(sel),
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              children: [panes[sel].child],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final cores = <String, List<String>>{};
    for (final s in ConsoleSystem.allSystems) {
      cores.putIfAbsent(s.coreLibName, () => []).add(s.shortName);
    }
    final totalModified = _modified.values.fold<int>(0, (sum, v) => sum + v);
    final storage = StorageService.instance;
    final needsStorageAccess = storage.canRequestAllFilesAccess;

    Widget linkRow(
      IconData icon,
      Color color,
      String title,
      String sub,
      String label,
      String url,
    ) {
      return SettingsRow(
        icon: icon,
        color: color,
        title: title,
        subtitle: sub,
        chevron: false,
        trailing: Icon(
          url.startsWith('mailto:')
              ? CupertinoIcons.paperplane
              : CupertinoIcons.arrow_up_right_square,
          size: 16,
          color: c.tertiaryText,
        ),
        onTap: () => _openLink(label, url),
      );
    }

    return c.dotted(
      Scaffold(
        backgroundColor: c.pageBg,
        appBar: AppBar(
          backgroundColor: c.pageBg,
          centerTitle: true,
          toolbarHeight:
              MediaQuery.sizeOf(context).width >
                  MediaQuery.sizeOf(context).height
              ? 44
              : null,
          title: const Text(
            'Settings',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: ListenableBuilder(
            listenable: ThemeService.instance,
            builder: (context, _) {
              final headerWidgets = <Widget>[
                ProfileHeaderCard(
                  name: _settings.nickname,
                  subtitle:
                      'Birthday  ·  ${_formatBirthday(_settings.birthMonth, _settings.birthDay)}',
                  onTap: _editPlayerProfile,
                ),

                // ── Needs attention ──
                if (_biosNeedFiles > 0)
                  AttentionBanner(
                    icon: CupertinoIcons.exclamationmark_triangle_fill,
                    title:
                        '$_biosNeedFiles ${_biosNeedFiles == 1 ? 'system needs' : 'systems need'} BIOS files',
                    subtitle: 'Tap to import them',
                    onTap: () async {
                      await Navigator.push(
                        context,
                        CupertinoPageRoute(builder: (_) => const BiosScreen()),
                      );
                      _refresh();
                    },
                  ),
                if (needsStorageAccess)
                  AttentionBanner(
                    icon: CupertinoIcons.folder_badge_plus,
                    title: 'Allow access to all files',
                    subtitle:
                        'Keeps your games and saves in a shared tonEMU folder',
                    onTap: _onStorageFolderTap,
                  ),
              ];
              final general = SettingsGroup(
                title: 'General',
                children: [
                  SettingsRow(
                    icon: CupertinoIcons.slider_horizontal_3,
                    color: const Color(0xFF007AFF),
                    title: 'Display & Controls',
                    subtitle: 'Video filter, touch buttons, gamepad, saves',
                    value: _themeLabel(ThemeService.instance.mode),
                    onTap: () => Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => const GeneralSettingsScreen(),
                      ),
                    ),
                  ),
                  SettingsRow(
                    icon: CupertinoIcons.folder_fill,
                    color: kSettingsWarn,
                    title: 'Storage folder',
                    subtitle: storage.displayPath,
                    trailing: needsStorageAccess
                        ? const StatusPill(
                            text: 'Limited',
                            color: kSettingsWarn,
                          )
                        : Icon(
                            CupertinoIcons.doc_on_clipboard,
                            size: 17,
                            color: c.accent,
                          ),
                    chevron: false,
                    onTap: _onStorageFolderTap,
                  ),
                  SettingsRow(
                    icon: CupertinoIcons.cube_box_fill,
                    color: _biosNeedFiles > 0 ? kSettingsWarn : kSettingsOk,
                    title: 'BIOS & firmware files',
                    subtitle: _biosRecommended > 0 && _biosNeedFiles == 0
                        ? '$_biosRecommended recommended'
                        : 'Import system files for each console',
                    trailing: _biosNeedFiles > 0
                        ? StatusPill(
                            text: '$_biosNeedFiles missing',
                            color: kSettingsWarn,
                          )
                        : const StatusPill(text: 'Ready', color: kSettingsOk),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        CupertinoPageRoute(builder: (_) => const BiosScreen()),
                      );
                      _refresh();
                    },
                  ),
                ],
              );
              final coreGroup = SettingsGroup(
                title: 'Emulator Cores',
                footer: 'Per-core options. Open a core to pick a preset or fine-tune graphics, speed and more.',
                trailing: totalModified > 0
                    ? GestureDetector(
                        onTap: () => _confirmResetAllCores(cores.keys),
                        child: Text(
                          'Reset All',
                          style: TextStyle(
                            color: c.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : null,
                children: [
                  for (final e in cores.entries)
                    SettingsRow(
                      icon: _coreIcon(e.key),
                      color: const Color(0xFF32ADE6),
                      title: _friendlyCoreLabel(e.key, e.value),
                      subtitle: e.value.join(' / '),
                      trailing: _activePreset[e.key] != null
                          ? StatusPill(
                              text: _activePreset[e.key]!,
                              color: c.accent,
                            )
                          : (_modified[e.key] ?? 0) > 0
                          ? StatusPill(
                              text: '${_modified[e.key]} custom',
                              color: kSettingsWarn,
                            )
                          : Text(
                              'Default',
                              style: TextStyle(
                                fontSize: 13,
                                color: c.tertiaryText,
                              ),
                            ),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) =>
                                CoreSettingsScreen(coreLibName: e.key),
                          ),
                        );
                        _refresh();
                      },
                    ),
                ],
              );
              final about = SettingsGroup(
                title: 'About',
                children: [
                  SettingsRow(
                    icon: Icons.gamepad_rounded,
                    color: kSettingsOk,
                    title: 'About tonEMU',
                    subtitle: 'Version, supported systems and credits',
                    value: 'v$kAppVersion',
                    onTap: () => Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) =>
                            AboutScreen(onDevelopers: _showDevelopersModal),
                      ),
                    ),
                  ),
                  SettingsRow(
                    icon: CupertinoIcons.person_2_fill,
                    color: kSettingsWarn,
                    title: 'Developers',
                    subtitle: 'The team behind tonEMU and its emulator cores',
                    onTap: _showDevelopersModal,
                  ),
                  linkRow(
                    CupertinoIcons.heart_fill,
                    const Color(0xFFFF2D55),
                    'Support tonEMU',
                    'Buy me a coffee. tonEMU stays free either way',
                    'Support page',
                    kSupportUrl,
                  ),
                  SettingsRow(
                    icon: CupertinoIcons.hand_raised_fill,
                    color: kSettingsOk,
                    title: 'Privacy Policy',
                    subtitle: 'What tonEMU stores and what it sends',
                    onTap: () => Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => const PrivacyPolicyScreen(),
                      ),
                    ),
                  ),
                  SettingsRow(
                    icon: CupertinoIcons.doc_text_fill,
                    color: const Color(0xFF8E8E93),
                    title: 'Open-source licenses',
                    subtitle:
                        'Emulator cores, libraries and fonts used by tonEMU',
                    onTap: () => Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => const OpenSourceLicensesScreen(),
                      ),
                    ),
                  ),
                ],
              );
              final more = SettingsGroup(
                title: 'More by jedPlatforms',
                children: [
                  linkRow(
                    CupertinoIcons.wrench_fill,
                    const Color(0xFF007AFF),
                    'jedToolKit',
                    'github.com/ProtonyteTV/jedToolKit',
                    'jedToolKit URL',
                    'https://github.com/ProtonyteTV/jedToolKit',
                  ),
                  linkRow(
                    CupertinoIcons.cube_box_fill,
                    const Color(0xFF5856D6),
                    'jedLoft',
                    'github.com/ProtonyteTV/jedLoft',
                    'jedLoft URL',
                    'https://github.com/ProtonyteTV/jedLoft',
                  ),
                  linkRow(
                    CupertinoIcons.waveform,
                    const Color(0xFFFF2D55),
                    'jedReverb',
                    'github.com/ProtonyteTV/jedReverb',
                    'jedReverb URL',
                    'https://github.com/ProtonyteTV/jedReverb',
                  ),
                ],
              );
              final connect = SettingsGroup(
                title: 'Connect & Contact',
                children: [
                  linkRow(
                    CupertinoIcons.globe,
                    kSettingsOk,
                    'Official Website',
                    'jedplatforms.vercel.app',
                    'Website URL',
                    'https://jedplatforms.vercel.app',
                  ),
                  linkRow(
                    CupertinoIcons.heart_fill,
                    const Color(0xFFFF2D55),
                    'Support tonEMU',
                    'buymeacoffee.com/jedplatforms',
                    'Support page',
                    kSupportUrl,
                  ),
                  linkRow(
                    CupertinoIcons.at,
                    const Color(0xFF1C1C1E),
                    'X (Twitter)',
                    '@ProtonyteTV',
                    'X profile',
                    'https://x.com/ProtonyteTV',
                  ),
                  linkRow(
                    CupertinoIcons.chevron_left_slash_chevron_right,
                    const Color(0xFF8E8E93),
                    'GitHub',
                    'github.com/ProtonyteTV',
                    'GitHub URL',
                    'https://github.com/ProtonyteTV',
                  ),
                  linkRow(
                    CupertinoIcons.mail_solid,
                    kSettingsWarn,
                    'Contact Email',
                    'jedplatforms@gmail.com',
                    'Email',
                    'mailto:jedplatforms@gmail.com?subject=tonEMU',
                  ),
                ],
              );
              final panes = <({String label, IconData icon, Widget child})>[
                (
                  label: 'General',
                  icon: CupertinoIcons.slider_horizontal_3,
                  child: general,
                ),
                (
                  label: 'Library',
                  icon: CupertinoIcons.square_grid_2x2_fill,
                  child: const LibrarySettingsGroup(),
                ),
                (
                  label: 'Emulator Cores',
                  icon: CupertinoIcons.square_stack_3d_up_fill,
                  child: coreGroup,
                ),
                (
                  label: 'Updates',
                  icon: CupertinoIcons.arrow_down_circle,
                  child: const UpdatesGroup(),
                ),
                (
                  label: 'About',
                  icon: CupertinoIcons.info_circle,
                  child: about,
                ),
                (
                  label: 'More by jedPlatforms',
                  icon: CupertinoIcons.sparkles,
                  child: more,
                ),
                (
                  label: 'Connect & Contact',
                  icon: CupertinoIcons.chat_bubble_2,
                  child: connect,
                ),
              ];
              final sz = MediaQuery.sizeOf(context);
              if (sz.width >= 640 && sz.width > sz.height) {
                return _wideSettings(c, headerWidgets, panes);
              }
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: ListView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                    children: [
                      ...headerWidgets,
                      for (final p in panes) p.child,
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
