// lib/services/changelog.dart

/// One release in the "What's new" list.
class ChangelogEntry {
  final String version;
  final String title;
  final List<String> items;
  const ChangelogEntry(this.version, this.title, this.items);
}

/// NEWEST FIRST. When you ship an update:
///  1. bump kAppVersion in about_screen.dart,
///  2. add a [ChangelogEntry] with the same version at the TOP of this list.
/// Players then see "What's new" once on the next launch.
const List<ChangelogEntry> kChangelog = [
  ChangelogEntry('27.0', 'Initial release', [
    '16 systems in one app: NES, Super Nintendo, Nintendo 64, Game Boy, Game Boy Color, Game Boy Advance, Nintendo DS, Nintendo 3DS, PlayStation, PSP, Master System, Game Gear, Genesis / Mega Drive, Saturn (experimental), Pokémon Mini and WonderSwan / Color.',
    'jedTimeMachine: snapshots every 15, 30 or 60 seconds while you play. Open the in-game menu and jump back to any recent moment.',
    'Game library with search, favorites, grid or list view, four sort modes, a Continue Playing card, Favorites / Most Played / New Additions shelves and automatic box art.',
    'Add games from files or whole folders, or send them from your PC over Wi-Fi. Duplicates are skipped and nothing is ever overwritten.',
    'jedManager: see every game\'s saves, states and play time, back up and restore saves, and bring in the folder of an older tonEMU version.',
    'Save states: 60 slots with thumbnails, auto-save, undo for an accidental load, and battery saves written safely with a rolling backup copy.',
    'Cheats: a per-game cheat manager with a built-in cheat browser for every system.',
    'Per-core settings with one-tap Performance, Balanced and Quality presets.',
    'Touch controls with an edit mode, adjustable opacity and haptics, and a layout built for each console.',
    'Bluetooth and USB gamepads for up to four players, with optional combo hotkeys.',
    'PlayStation DualShock: PS1 games get an analog controller with two sticks, and tapping a stick presses L3 / R3.',
    'Auto-pause when a controller or headphones drop out, or when you leave the app.',
    'Fold and flip phone support across the whole app: half-open a Z Flip or Z Fold and tonEMU moves away from the crease. In games the picture stays above the hinge in tabletop posture. Turn it off in Settings → Display & Controls → Appearance → Fold & flip layout.',
    'DS and 3DS: premade and free-form dual-screen layouts, saved separately for portrait and landscape.',
    'Optional break reminder after 30 minutes, 1 hour or 1.5 hours of play. Off by default.',
    'The pause menu shows how long you have been playing this session.',
    'No storage permission needed: tonEMU keeps its files in its own folder, which you can browse from the tonEMU location in your Files app.',
    'No accounts, ads or analytics. The app goes online only for box art, cheat files and Wi-Fi transfer (local network only).',
    'Light, Dark or system themes in two styles: Classic and Dot.',
    'BIOS & System Files screen showing what each system needs. PS1 needs a BIOS file that you provide.',
    'First-run setup, an update checker with in-app download and install, and this What\'s new sheet after every update (Settings → Updates).',
    'Known limitations: Android 8.0+, arm64 and OpenGL ES 3.0 required. 3DS needs a flagship phone with 6 GB of RAM or more. Saturn is experimental, Sega CD isn\'t supported yet, and there is no camera or microphone input on DS / 3DS yet.',
    'tonEMU does not include any games, BIOS files or firmware. You must provide your own, dumped from hardware you own.',
  ]),
  // ChangelogEntry('26.0', 'Older release', ['...']),
];

/// Compares dotted versions numerically ("27.10" > "27.9"). Returns <0, 0, >0.
int compareVersions(String a, String b) {
  final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final n = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < n; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// Entries newer than [lastSeen] and not newer than [current]; at most [max]. With no
/// [lastSeen] only the current release is returned.
List<ChangelogEntry> changelogSince(
  String? lastSeen,
  String current, {
  int max = 3,
}) {
  final out = <ChangelogEntry>[];
  for (final e in kChangelog) {
    if (compareVersions(e.version, current) > 0) continue;
    if (lastSeen != null && compareVersions(e.version, lastSeen) <= 0) continue;
    out.add(e);
    if (lastSeen == null || out.length >= max) break;
  }
  return out;
}
