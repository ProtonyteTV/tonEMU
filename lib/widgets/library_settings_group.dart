// lib/widgets/library_settings_group.dart
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../services/app_settings.dart';
import 'settings_kit.dart';

/// The "Library" section of the settings home page (which shelves the library shows, cover art).
/// Moved out of Display & Controls. Self-contained: it loads and saves [AppSettings] itself.
class LibrarySettingsGroup extends StatefulWidget {
  const LibrarySettingsGroup({super.key});

  @override
  State<LibrarySettingsGroup> createState() => _LibrarySettingsGroupState();
}

class _LibrarySettingsGroupState extends State<LibrarySettingsGroup> {
  final AppSettings _s = AppSettings.instance;
  bool _loaded = false;

  static const _indigo = Color(0xFF5E5CE6);
  static const _teal = Color(0xFF32ADE6);
  static const _pink = Color(0xFFFF2D55);

  @override
  void initState() {
    super.initState();
    _s.load().then((_) {
      if (mounted) setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _s.flush(); // a change still waiting for its debounced save is written now
    super.dispose();
  }

  void _change(VoidCallback fn) {
    setState(fn);
    _s.scheduleSave();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return SettingsGroup(
      title: 'Library',
      children: [
        SettingsSwitchRow(
          icon: CupertinoIcons.chart_bar_fill,
          color: _indigo,
          title: 'Show stats & Surprise Me',
          subtitle: 'Game count, play time and the random-game button',
          value: _s.showStats,
          onChanged: (v) => _change(() => _s.showStats = v),
        ),
        SettingsSwitchRow(
          icon: CupertinoIcons.clock_fill,
          color: _teal,
          title: 'Show Continue Playing',
          subtitle: 'Shelf of the games you played last',
          value: _s.showRecent,
          onChanged: (v) => _change(() => _s.showRecent = v),
        ),
        SettingsSwitchRow(
          icon: CupertinoIcons.heart_fill,
          color: _pink,
          title: 'Show Favorites',
          subtitle: 'Shelf of the games you starred',
          value: _s.showFavorites,
          onChanged: (v) => _change(() => _s.showFavorites = v),
        ),
        SettingsSwitchRow(
          icon: CupertinoIcons.flame_fill,
          color: _pink,
          title: 'Show Most Played',
          subtitle: 'Shelf of the games you play the most',
          value: _s.showMostPlayed,
          onChanged: (v) => _change(() => _s.showMostPlayed = v),
        ),
        SettingsSwitchRow(
          icon: CupertinoIcons.sparkles,
          color: _indigo,
          title: 'Show New Additions',
          subtitle: 'Shelf of games you added and have not played yet',
          value: _s.showNewAdditions,
          onChanged: (v) => _change(() => _s.showNewAdditions = v),
        ),
        SettingsSwitchRow(
          icon: CupertinoIcons.photo_on_rectangle,
          color: _teal,
          title: 'Download cover art',
          subtitle:
              'Fetches missing box art from GitHub (libretro-thumbnails). '
              'Off: nothing is sent; saved and custom covers still show.',
          value: _s.downloadCoverArt,
          onChanged: (v) => _change(() => _s.downloadCoverArt = v),
        ),
      ],
    );
  }
}
