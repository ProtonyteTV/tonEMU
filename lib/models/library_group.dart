// lib/models/library_group.dart
import 'package:material_ui/material_ui.dart';

import 'console_system.dart';

/// A shelf on the home screen. Games are placed on a shelf automatically from their file extension,
/// so nothing has to be sorted by hand. GB and GBC share one shelf.
class LibraryGroup {
  final String id;
  final String title;
  final String shortName;
  final IconData icon;
  final Color color;
  final List<ConsoleType> types;

  const LibraryGroup({
    required this.id,
    required this.title,
    required this.shortName,
    required this.icon,
    required this.color,
    required this.types,
  });

  /// Display order of the shelves.
  static const List<LibraryGroup> all = [
    LibraryGroup(
      id: '3ds',
      title: 'Nintendo 3DS',
      shortName: '3DS',
      icon: Icons.view_agenda_outlined,
      color: Color(0xFFE5484D),
      types: [ConsoleType.n3ds],
    ),
    LibraryGroup(
      id: 'nds',
      title: 'Nintendo DS',
      shortName: 'NDS',
      icon: Icons.splitscreen,
      color: Color(0xFF4DA3FF),
      types: [ConsoleType.nds],
    ),
    LibraryGroup(
      id: 'n64',
      title: 'Nintendo 64',
      shortName: 'N64',
      icon: Icons.gamepad,
      color: Color(0xFF2ECC71),
      types: [ConsoleType.n64],
    ),
    LibraryGroup(
      id: 'snes',
      title: 'Super Nintendo',
      shortName: 'SNES',
      icon: Icons.sports_esports_outlined,
      color: Color(0xFFB39DDB),
      types: [ConsoleType.snes],
    ),
    LibraryGroup(
      id: 'nes',
      title: 'Nintendo Entertainment System',
      shortName: 'NES',
      icon: Icons.videogame_asset,
      color: Color(0xFFEF5350),
      types: [ConsoleType.nes],
    ),
    LibraryGroup(
      id: 'gba',
      title: 'Game Boy Advance',
      shortName: 'GBA',
      icon: Icons.videogame_asset_outlined,
      color: Color(0xFF9B7BFF),
      types: [ConsoleType.gba],
    ),
    LibraryGroup(
      id: 'gb',
      title: 'Game Boy / Color',
      shortName: 'GB/C',
      icon: Icons.gamepad_outlined,
      color: Color(0xFF6BCB77),
      types: [ConsoleType.gb, ConsoleType.gbc],
    ),
    LibraryGroup(
      id: 'psp',
      title: 'PlayStation Portable',
      shortName: 'PSP',
      icon: Icons.tablet_android,
      color: Color(0xFF2EC4B6),
      types: [ConsoleType.psp],
    ),
    LibraryGroup(
      id: 'ps1',
      title: 'PlayStation',
      shortName: 'PS1',
      icon: Icons.album_outlined,
      color: Color(0xFFF5A524),
      types: [ConsoleType.ps1],
    ),
    LibraryGroup(
      id: 'saturn',
      title: 'Sega Saturn',
      shortName: 'Saturn',
      icon: Icons.public,
      color: Color(0xFF9C27B0),
      types: [ConsoleType.saturn],
    ),
    LibraryGroup(
      id: 'md',
      title: 'Sega Genesis / Mega Drive',
      shortName: 'MD',
      icon: Icons.games_outlined,
      color: Color(0xFF1E6BFF),
      types: [ConsoleType.genesis],
    ),
    LibraryGroup(
      id: 'sms',
      title: 'Sega Master System',
      shortName: 'SMS',
      icon: Icons.toys_outlined,
      color: Color(0xFFD81B60),
      types: [ConsoleType.sms],
    ),
    LibraryGroup(
      id: 'gg',
      title: 'Sega Game Gear',
      shortName: 'GG',
      icon: Icons.smartphone,
      color: Color(0xFFFFC107),
      types: [ConsoleType.gg],
    ),
    LibraryGroup(
      id: 'pokemini',
      title: 'Pokémon Mini',
      shortName: 'Mini',
      icon: Icons.gamepad_outlined,
      color: Color(0xFF29B6F6),
      types: [ConsoleType.pokemini],
    ),
    LibraryGroup(
      id: 'wonderswan',
      title: 'WonderSwan / Color',
      shortName: 'WS',
      icon: Icons.sports_esports_outlined,
      color: Color(0xFF5C6BC0),
      types: [ConsoleType.wonderswan],
    ),
  ];

  static LibraryGroup? of(ConsoleType type) {
    for (final g in all) {
      if (g.types.contains(type)) return g;
    }
    return null;
  }
}