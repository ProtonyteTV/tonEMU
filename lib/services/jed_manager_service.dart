// lib/services/jed_manager_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/console_system.dart';
import 'import_service.dart';
import 'storage_service.dart';

/// What a file next to a ROM is.
enum SaveKind { battery, state, autoState, undoState, backup, other }

/// One save / state / backup file that belongs to a game.
class SaveItem {
  SaveItem({
    required this.file,
    required this.kind,
    required this.label,
    required this.bytes,
    required this.modified,
  });

  final File file;
  final SaveKind kind;
  final String label;
  final int bytes;
  final DateTime modified;

  String get name => file.uri.pathSegments.where((s) => s.isNotEmpty).last;
}

/// A game as jedManager sees it: the ROM (if it is in the library), its saves and its stats.
class ManagedGame {
  ManagedGame(this.name);

  /// The ROM file name, which is also the key of every save, state and play-time entry.
  final String name;
  File? romFile;
  int romBytes = 0;
  ConsoleSystem? system;
  final List<SaveItem> items = [];
  int playSeconds = 0;
  int? lastPlayedMs;

  /// True when [lastPlayedMs] was guessed from the newest save file after an import.
  bool lastPlayedEstimated = false;
  bool favorite = false;

  bool get inLibrary => romFile != null;
  String get title => ConsoleSystem.cleanTitle(name);

  Iterable<SaveItem> get saves => items.where(
    (e) => e.kind == SaveKind.battery || e.kind == SaveKind.other,
  );
  Iterable<SaveItem> get states => items.where(
    (e) =>
        e.kind == SaveKind.state ||
        e.kind == SaveKind.autoState ||
        e.kind == SaveKind.undoState,
  );
  Iterable<SaveItem> get backups =>
      items.where((e) => e.kind == SaveKind.backup);

  int get saveBytes => saves.fold(0, (a, e) => a + e.bytes);
  int get stateBytes => states.fold(0, (a, e) => a + e.bytes);
  int get backupBytes => backups.fold(0, (a, e) => a + e.bytes);
  int get dataBytes => saveBytes + stateBytes + backupBytes;

  /// A disc sheet owns extra track files, so deleting only the sheet would leave them behind.
  bool get isDiscSheet {
    final l = name.toLowerCase();
    return l.endsWith('.cue') ||
        l.endsWith('.gdi') ||
        l.endsWith('.ccd') ||
        l.endsWith('.mds') ||
        l.endsWith('.m3u');
  }
}

class ManagerSnapshot {
  ManagerSnapshot({
    required this.games,
    required this.orphans,
    required this.folderBytes,
  });

  final List<ManagedGame> games;

  /// Files in saves/ and states/ that belong to no known game.
  final List<SaveItem> orphans;
  final Map<String, int> folderBytes;

  int get totalPlaySeconds => games.fold(0, (a, g) => a + g.playSeconds);
  int get orphanBytes => orphans.fold(0, (a, e) => a + e.bytes);
}

class LegacyImportReport {
  LegacyImportReport(this.raw);
  final Map<String, dynamic> raw;

  int _i(String k) => (raw[k] as num?)?.toInt() ?? 0;
  bool get notTonEmu => raw['notTonEmu'] == true;
  bool get cancelled => raw['cancelled'] == true;
  bool get statsFound => raw['statsFound'] == true;
  int get copied => _i('copied');
  int get replaced => _i('replaced');
  int get alreadyThere => _i('alreadyThere');
  int get kept => _i('kept');
  int get failed => _i('failed');
  int get noSpace => _i('noSpace');
  int get bytes => _i('bytes');
  List<String> get failedNames => [
    for (final n in (raw['failedNames'] as List? ?? const [])) '$n',
  ];

  /// Filled by [JedManagerService.importLegacyFolder] when the folder held a jed_stats.json.
  StatsMergeResult? stats;

  /// Games that got an estimated "last played" date from their save files.
  int estimatedGames = 0;
}

class StatsMergeResult {
  StatsMergeResult({
    this.games = 0,
    this.addedSeconds = 0,
    this.alreadyImported = false,
    this.invalid = false,
  });
  final int games;
  final int addedSeconds;
  final bool alreadyImported;
  final bool invalid;
}

class LegacyProgress {
  LegacyProgress(Map m)
    : running = m['running'] == true,
      filesTotal = (m['filesTotal'] as num?)?.toInt() ?? 0,
      filesDone = (m['filesDone'] as num?)?.toInt() ?? 0,
      bytesTotal = (m['bytesTotal'] as num?)?.toInt() ?? 0,
      bytesDone = (m['bytesDone'] as num?)?.toInt() ?? 0,
      current = '${m['current'] ?? ''}';
  final bool running;
  final int filesTotal, filesDone, bytesTotal, bytesDone;
  final String current;

  double? get fraction {
    if (bytesTotal > 0) return (bytesDone / bytesTotal).clamp(0.0, 1.0);
    if (filesTotal > 0) return (filesDone / filesTotal).clamp(0.0, 1.0);
    return null;
  }
}

/// jedManager: one place to see every ROM with its saves, states and play time, to clean them up,
/// and to bring the data of the old (non-Google-Play) tonEMU build into the new storage.
///
/// Play time lives in SharedPreferences (`playtime_<rom>`, `played_<rom>`, `fav_games`), exactly
/// like the library and the game screen use it. Because SharedPreferences is private to an app
/// install, it can't be read out of an old tonEMU FOLDER: the old build has to write it into the
/// folder as [statsFileName] first (see legacy_stats_export.dart). jedManager then merges that
/// file here, once per file, so repeating the import never counts hours twice.
class JedManagerService {
  JedManagerService._();
  static final JedManagerService instance = JedManagerService._();

  static const MethodChannel _channel = MethodChannel(
    'com.jedplatforms.jedEmu/core',
  );

  static const String statsFileName = 'jed_stats.json';
  static const String _importedKey = 'jed_imported_stats';

  /// `jed_est_played_<rom>` remembers the guessed value: a date counts as estimated only while
  /// `played_<rom>` still equals it, so real play (which overwrites it) clears the label.
  static const String _estPrefix = 'jed_est_played_';

  // ───────────────────────── Scan ─────────────────────────

  static bool _isTemp(String n) =>
      n.endsWith('.tmp') || n.endsWith('.part') || n.endsWith('.cp');

  Future<void> _ensureStorage() async {
    if (!StorageService.instance.isInitialized) {
      await StorageService.instance.init();
    }
  }

  Future<ManagerSnapshot> scan() async {
    await _ensureStorage();
    final storage = StorageService.instance;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final favorites = (prefs.getStringList('fav_games') ?? const <String>[])
        .toSet();

    final games = <String, ManagedGame>{};

    // 1) ROMs in the library (same rules as the library: known system, no disc track files).
    final romFiles = <File>[];
    try {
      if (await storage.romsDir.exists()) {
        await for (final e in storage.romsDir.list(followLinks: false)) {
          if (e is File && !_isTemp(e.path)) romFiles.add(e);
        }
      }
    } catch (_) {}
    final referenced = ImportService.cueReferenced(romFiles);
    for (final f in romFiles) {
      final name = _baseName(f.path);
      if (name.startsWith('.')) continue;
      final sys = ConsoleSystem.forFile(name);
      if (sys == null) continue;
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
      if (referenced.contains(f.path.toLowerCase()) &&
          !const {'cue', 'gdi', 'ccd', 'mds'}.contains(ext)) {
        continue;
      }
      final g = games.putIfAbsent(name, () => ManagedGame(name));
      g.romFile = f;
      g.system = sys;
      try {
        g.romBytes = await f.length();
      } catch (_) {}
    }

    // 2) Play-time entries, also for games whose ROM is not (yet) in the library: after an
    //    import of the old folder the hours are there before the ROMs are.
    for (final k in prefs.getKeys()) {
      if (k.startsWith('playtime_')) {
        final name = k.substring('playtime_'.length);
        final secs = prefs.getInt(k) ?? 0;
        if (secs > 0 || games.containsKey(name)) {
          games.putIfAbsent(name, () => ManagedGame(name)).playSeconds = secs;
        }
      } else if (k.startsWith('played_')) {
        final name = k.substring('played_'.length);
        final g = games[name];
        if (g != null) g.lastPlayedMs = prefs.getInt(k);
      }
    }
    for (final g in games.values) {
      g.favorite = favorites.contains(g.name);
      g.lastPlayedMs ??= prefs.getInt('played_${g.name}');
      final est = prefs.getInt('$_estPrefix${g.name}');
      g.lastPlayedEstimated = est != null && est == g.lastPlayedMs;
    }

    // 3) Saves and states: a file belongs to the game whose name + "." is the LONGEST prefix.
    final names = games.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final orphans = <SaveItem>[];

    Future<void> sort(Directory dir, {required bool states}) async {
      try {
        if (!await dir.exists()) return;
        await for (final e in dir.list(followLinks: false)) {
          if (e is! File) continue;
          final fn = _baseName(e.path);
          if (fn.startsWith('.') || _isTemp(fn)) continue;
          if (fn == 'wfcsettings.bin')
            continue; // DS profile, not a game's save
          String? owner;
          for (final n in names) {
            if (fn.startsWith('$n.')) {
              owner = n;
              break;
            }
          }
          final rest = owner == null ? fn : fn.substring(owner.length + 1);
          final stat = await e.stat();
          final item = SaveItem(
            file: e,
            kind: _kindOf(rest, states),
            label: _labelOf(rest, states),
            bytes: stat.size,
            modified: stat.modified,
          );
          if (owner == null) {
            orphans.add(item);
          } else {
            games[owner]!.items.add(item);
          }
        }
      } catch (_) {}
    }

    await sort(storage.savesDir, states: false);
    await sort(storage.statesDir, states: true);

    for (final g in games.values) {
      g.items.sort((a, b) => b.modified.compareTo(a.modified));
    }
    orphans.sort((a, b) => b.bytes.compareTo(a.bytes));

    final list = games.values.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return ManagerSnapshot(
      games: list,
      orphans: orphans,
      folderBytes: await storage.folderSizes(),
    );
  }

  static String _baseName(String path) =>
      path.split(Platform.pathSeparator).where((s) => s.isNotEmpty).last;

  static SaveKind _kindOf(String rest, bool inStates) {
    final l = rest.toLowerCase();
    if (l.endsWith('.bak')) return SaveKind.backup;
    if (l == 'auto.state' || l.endsWith('.auto.state')) return SaveKind.autoState;
    if (l == 'undo.state' || l.endsWith('.undo.state')) return SaveKind.undoState;
    if (l.endsWith('.state') || inStates) return SaveKind.state;
    if (l.endsWith('.srm') || l == 'srm') return SaveKind.battery;
    return SaveKind.other;
  }

  /// " · blastem" for "<core><suffix>" (the core part of a core-keyed state name), else "".
  static String _coreTag(String rest, String suffix) {
    if (rest.length <= suffix.length) return ''; // old name without a core
    final core = rest.substring(0, rest.length - suffix.length);
    return core.isEmpty ? '' : ' · $core';
  }

  static String _labelOf(String rest, bool inStates) {
    final l = rest.toLowerCase();
    if (l == 'auto.state.bak' || l.endsWith('.auto.state.bak')) {
      return 'Auto-save (before restart)${_coreTag(rest, '.auto.state.bak')}';
    }
    if (l.endsWith('.srm.bak')) return 'Battery save backup';
    if (l.endsWith('.bak'))
      return 'Backup · ${rest.substring(0, rest.length - 4)}';
    if (l == 'auto.state' || l.endsWith('.auto.state')) {
      return 'Auto-save${_coreTag(rest, '.auto.state')}';
    }
    if (l == 'undo.state' || l.endsWith('.undo.state')) {
      return 'Undo point${_coreTag(rest, '.undo.state')}';
    }
    if (l.endsWith('.state')) {
      // New names are "<core>.slotN"; old ones are just "slotN" (no core).
      var label = rest.substring(0, rest.length - '.state'.length);
      var tag = '';
      final dot = label.lastIndexOf('.');
      if (dot > 0) {
        tag = ' · ${label.substring(0, dot)}';
        label = label.substring(dot + 1);
      }
      final m = RegExp(
        r'^(?:slot)?[ _-]?(\d+)$',
        caseSensitive: false,
      ).firstMatch(label);
      if (m != null) return 'Slot ${m.group(1)}$tag';
      return label.isEmpty ? 'Save state' : '$label$tag';
    }
    if (l.endsWith('.srm')) {
      final core = rest.substring(0, rest.length - 4);
      return core.isEmpty ? 'Battery save' : 'Battery save · $core';
    }
    if (l == 'srm') return 'Battery save';
    return rest;
  }

  // ───────────────────────── Cleanup ─────────────────────────

  Future<bool> deleteItem(SaveItem item) async {
    try {
      if (await item.file.exists()) await item.file.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Deletes saves, states and backups of [g]. [keepBatterySaves] spares the in-game saves.
  Future<int> deleteGameData(
    ManagedGame g, {
    bool keepBatterySaves = false,
  }) async {
    var n = 0;
    for (final it in List<SaveItem>.from(g.items)) {
      if (keepBatterySaves &&
          (it.kind == SaveKind.battery || it.kind == SaveKind.other)) {
        continue;
      }
      if (await deleteItem(it)) n++;
    }
    return n;
  }

  /// Drops the play time / last played of [g] and removes it from favorites.
  Future<void> resetStats(ManagedGame g) async {
    final p = await SharedPreferences.getInstance();
    await p.remove('playtime_${g.name}');
    await p.remove('played_${g.name}');
  }

  /// Deletes the ROM file (single-file games only) plus everything that belongs to it, the same
  /// bookkeeping the library does when a game is removed.
  Future<bool> deleteRom(ManagedGame g, {bool alsoData = true}) async {
    final f = g.romFile;
    if (f == null || g.isDiscSheet) return false;
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {
      return false;
    }
    if (alsoData) {
      await deleteGameData(g);
      await resetStats(g);
      final p = await SharedPreferences.getInstance();
      final fav = (p.getStringList('fav_games') ?? <String>[]).toList();
      if (fav.remove(g.name)) await p.setStringList('fav_games', fav);
    }
    return true;
  }

  /// Puts a backup back in place of the file it was made from (".srm.bak" -> ".srm",
  /// ".auto.state.bak" -> ".auto.state"). Call only while no game is running.
  Future<bool> restoreBackup(SaveItem backup) async {
    try {
      final path = backup.file.path;
      if (!path.endsWith('.bak')) return false;
      final target = path.substring(0, path.length - 4);
      final tmp = File('$target.cp');
      await backup.file.copy(tmp.path);
      await tmp.rename(target);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ───────────────────────── Stats file ─────────────────────────

  File get statsFile =>
      File('${StorageService.instance.rootDir.path}/$statsFileName');

  /// Writes play time, last-played times and favorites to <tonEMU>/jed_stats.json, so they can
  /// be carried to another install together with the folder. Returns the file or null on error.
  Future<File?> exportStats() async {
    try {
      await _ensureStorage();
      final p = await SharedPreferences.getInstance();
      await p.reload();
      final playtime = <String, int>{};
      final played = <String, int>{};
      for (final k in p.getKeys()) {
        if (k.startsWith('playtime_')) {
          final v = p.getInt(k) ?? 0;
          if (v > 0) playtime[k.substring(9)] = v;
        } else if (k.startsWith('played_')) {
          final v = p.getInt(k);
          if (v != null) played[k.substring(7)] = v;
        }
      }
      final rnd = math.Random();
      final data = {
        'format': 'jedStats',
        'version': 1,
        // A new id on every export: an import is remembered by it and is never added twice.
        'id':
            '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${rnd.nextInt(1 << 31).toRadixString(36)}',
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'playtime': playtime,
        'played': played,
        'favorites': p.getStringList('fav_games') ?? const <String>[],
      };
      final out = statsFile;
      final tmp = File('${out.path}.tmp');
      await tmp.writeAsString(const JsonEncoder.withIndent(' ').convert(data));
      await tmp.rename(out.path);
      return out;
    } catch (_) {
      return null;
    }
  }

  /// Merges a stats file into this install: play time is ADDED, last played keeps the newest,
  /// favorites are united. The file's id is remembered so the same file counts only once.
  Future<StatsMergeResult> importStats(File file) async {
    try {
      if (!await file.exists()) return StatsMergeResult(invalid: true);
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map || raw['format'] != 'jedStats') {
        return StatsMergeResult(invalid: true);
      }
      final id = '${raw['id'] ?? ''}';
      final p = await SharedPreferences.getInstance();
      final done = (p.getStringList(_importedKey) ?? <String>[]).toList();
      if (id.isNotEmpty && done.contains(id)) {
        return StatsMergeResult(alreadyImported: true);
      }
      var games = 0;
      var added = 0;
      final pt = raw['playtime'];
      if (pt is Map) {
        for (final e in pt.entries) {
          final secs = (e.value as num?)?.toInt() ?? 0;
          if (secs <= 0 || '${e.key}'.isEmpty) continue;
          final key = 'playtime_${e.key}';
          await p.setInt(key, (p.getInt(key) ?? 0) + secs);
          games++;
          added += secs;
        }
      }
      final pl = raw['played'];
      if (pl is Map) {
        for (final e in pl.entries) {
          final t = (e.value as num?)?.toInt();
          if (t == null) continue;
          final key = 'played_${e.key}';
          final cur = p.getInt(key) ?? 0;
          if (t > cur) await p.setInt(key, t);
        }
      }
      final fav = raw['favorites'];
      if (fav is List) {
        final set = (p.getStringList('fav_games') ?? <String>[]).toSet()
          ..addAll(fav.map((e) => '$e'));
        await p.setStringList('fav_games', set.toList());
      }
      if (id.isNotEmpty) {
        done.add(id);
        await p.setStringList(_importedKey, done);
      }
      return StatsMergeResult(games: games, addedSeconds: added);
    } catch (_) {
      return StatsMergeResult(invalid: true);
    }
  }

  // ───────────────────────── Old tonEMU folder ─────────────────────────

  /// Opens the system folder picker. Returns the chosen folder (a content:// tree Uri) or null.
  Future<String?> pickLegacyFolder() async {
    try {
      return await _channel.invokeMethod<String>('pickLegacyFolder');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<LegacyProgress?> legacyProgress() async {
    try {
      final m = await _channel.invokeMethod<Map>('legacyImportProgress');
      return m == null ? null : LegacyProgress(m);
    } catch (_) {
      return null;
    }
  }

  Future<void> cancelLegacyImport() async {
    try {
      await _channel.invokeMethod('cancelLegacyImport');
    } catch (_) {}
  }

  /// Copies the old tonEMU folder at [treeUri] into the current storage (nothing is deleted from
  /// the old folder), then merges its play-time file. Returns null if the native side failed.
  Future<LegacyImportReport?> importLegacyFolder(
    String treeUri, {
    bool overwrite = false,
  }) async {
    await _ensureStorage();
    final Map<dynamic, dynamic>? res;
    try {
      res = await _channel.invokeMethod<Map>('importLegacyTree', {
        'uri': treeUri,
        'overwrite': overwrite,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
    if (res == null) return null;
    final report = LegacyImportReport(Map<String, dynamic>.from(res));
    if (report.statsFound && !report.cancelled) {
      report.stats = await importStats(statsFile);
    }
    if (!report.notTonEmu) report.estimatedGames = await estimateLastPlayed();
    return report;
  }

  /// The old build's play time is not recoverable from its folder, but the newest save / state
  /// file of a game shows when it was last played. Used only for games with no last-played date.
  /// Returns how many games got one.
  Future<int> estimateLastPlayed() async {
    final snap = await scan();
    final p = await SharedPreferences.getInstance();
    var n = 0;
    for (final g in snap.games) {
      if (g.lastPlayedMs != null) continue;
      SaveItem? newest;
      for (final it in g.items) {
        if (it.kind == SaveKind.backup) continue;
        if (newest == null || it.modified.isAfter(newest.modified)) newest = it;
      }
      if (newest == null) continue;
      final ms = newest.modified.millisecondsSinceEpoch;
      await p.setInt('played_${g.name}', ms);
      await p.setInt('$_estPrefix${g.name}', ms);
      n++;
    }
    return n;
  }

  /// Sets the play time of a game by hand (hours + minutes typed in jedManager).
  Future<void> setPlayTime(String romName, int seconds) async {
    final p = await SharedPreferences.getInstance();
    if (seconds <= 0) {
      await p.remove('playtime_$romName');
    } else {
      await p.setInt('playtime_$romName', seconds);
    }
  }

  // ───────────────────────── Formatting ─────────────────────────

  static String formatBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Total play time of EVERYTHING recorded in [p] (`playtime_<rom>` keys), including games whose
  /// ROM is no longer in the library. The library header and jedManager both use this one
  /// function, so the two totals can never disagree again.
  static int totalPlaySecondsOf(SharedPreferences p) {
    var total = 0;
    for (final k in p.getKeys()) {
      if (!k.startsWith('playtime_')) continue;
      final v = p.getInt(k) ?? 0;
      if (v > 0) total += v;
    }
    return total;
  }

  /// "12h 5m", "47m", "0m" (same shape the library uses).
  static String formatPlayTime(int secs) {
    if (secs <= 0) return '0m';
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    if (h == 0 && m == 0) return '<1m';
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}
