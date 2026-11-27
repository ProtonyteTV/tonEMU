// lib/services/cheat_db.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/console_system.dart';
import 'storage_service.dart';

/// One cheat from a libretro `.cht` file.
class CheatEntry {
  final String desc;
  final String code;
  const CheatEntry({required this.desc, required this.code});
}

/// How likely a core is to actually act on libretro cheats (retro_cheat_set).
/// The libretro API cannot be asked, so this is only used to warn the player.
enum CheatSupport { likely, unsure, unlikely }

/// Cheat database for EVERY system tonEMU supports, backed by the libretro-database `cht/`
/// folder (the same files RetroArch uses; codes are already in the format each core expects).
///
/// Nothing is bundled: a game's `.cht` file is fetched the first time it is needed and cached in
/// `<tonEMU>/cheats/<system folder>/`, so it works offline afterwards. A per-system file index
/// (needed only for fuzzy matching / search) is cached for [_indexMaxAge].
class CheatDb {
  CheatDb._();
  static final CheatDb instance = CheatDb._();

  static const _repo = 'libretro/libretro-database';
  static const _userAgent = 'tonEMU/1.0 (Flutter)';
  static const _indexMaxAge = Duration(days: 14);

  /// libretro-database folder names for each system. The first entry is also the local cache
  /// folder; the rest are alternatives tried when the first is not found in the repository
  /// (folder names are resolved against the live listing, so a rename upstream still works).
  static const Map<ConsoleType, List<String>> _folders = {
    ConsoleType.nes: ['Nintendo - Nintendo Entertainment System'],
    ConsoleType.snes: ['Nintendo - Super Nintendo Entertainment System'],
    ConsoleType.gb: ['Nintendo - Game Boy'],
    ConsoleType.gbc: ['Nintendo - Game Boy Color'],
    ConsoleType.gba: ['Nintendo - Game Boy Advance'],
    ConsoleType.nds: ['Nintendo - Nintendo DS'],
    ConsoleType.n3ds: ['Nintendo - Nintendo 3DS'],
    ConsoleType.n64: ['Nintendo - Nintendo 64'],
    ConsoleType.sms: [
      'Sega - Master System - Mark III',
      'Sega - Master System',
    ],
    ConsoleType.gg: ['Sega - Game Gear'],
    ConsoleType.genesis: [
      'Sega - Mega Drive - Genesis',
      'Sega - Mega Drive',
      'Sega - Genesis',
    ],
    ConsoleType.saturn: ['Sega - Saturn'],
    ConsoleType.ps1: ['Sony - PlayStation'],
    ConsoleType.psp: ['Sony - PlayStation Portable'],
  };

  /// Best-effort knowledge of which bundled cores implement retro_cheat_set. "unsure" means the
  /// core may ignore cheats; the player is told so, nothing is blocked.
  static CheatSupport supportFor(ConsoleType t) {
    switch (t) {
      case ConsoleType.nes:
      case ConsoleType.snes:
      case ConsoleType.gb:
      case ConsoleType.gbc:
      case ConsoleType.gba:
      case ConsoleType.n64:
      case ConsoleType.sms:
      case ConsoleType.gg:
      case ConsoleType.genesis:
        return CheatSupport.likely;
      case ConsoleType.nds:
      case ConsoleType.ps1:
      case ConsoleType.psp:
        return CheatSupport.unsure;
      case ConsoleType.n3ds:
      case ConsoleType.saturn:
      case ConsoleType
          .pokemini: // libretro docs: neither core implements native cheats
      case ConsoleType.wonderswan:
        return CheatSupport.unlikely;
    }
  }

  static String supportNote(ConsoleType t) {
    switch (supportFor(t)) {
      case CheatSupport.likely:
        return '';
      case CheatSupport.unsure:
        return 'This core may ignore cheats. If nothing changes in-game, it does '
            'not implement the libretro cheat interface.';
      case CheatSupport.unlikely:
        return 'This core is not known to support cheats. Codes can be added '
            'but will probably have no effect.';
    }
  }

  // ───────────────────────── Parsing / normalizing ─────────────────────────

  /// Parses RetroArch cheat-file text:
  ///   cheats = 2
  ///   cheat0_desc = "Infinite Lives"
  ///   cheat0_code = "AAAA-BBBB+CCCC-DDDD"
  ///   cheat0_enable = false
  static List<CheatEntry> parse(String text) {
    final fields = <int, Map<String, String>>{};
    final re = RegExp(r'^\s*cheat(\d+)_(desc|code)\s*=\s*(.*?)\s*$');
    for (final line in const LineSplitter().convert(text)) {
      final m = re.firstMatch(line);
      if (m == null) continue;
      var v = m.group(3)!;
      if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
        v = v.substring(1, v.length - 1);
      }
      // A 30-digit index in a user file must skip that line, not abort the whole file.
      final idx = int.tryParse(m.group(1)!);
      if (idx == null) continue;
      fields.putIfAbsent(idx, () => {})[m.group(2)!] = v;
    }
    final keys = fields.keys.toList()..sort();
    return [
      for (final k in keys)
        if (normalizeCode(fields[k]!['code'] ?? '').isNotEmpty)
          CheatEntry(
            desc: (fields[k]!['desc'] ?? '').trim().isEmpty
                ? 'Cheat ${k + 1}'
                : fields[k]!['desc']!.trim(),
            code: normalizeCode(fields[k]!['code']!),
          ),
    ];
  }

  /// libretro cores take several code lines as ONE string joined with '+'. A multi-line paste
  /// (what people copy from cheat sites) becomes that form, and stray quotes/whitespace go away.
  static String normalizeCode(String raw) {
    final parts = raw
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim().replaceAll('"', ''))
        .where((l) => l.isNotEmpty)
        .toList();
    return parts.join('+');
  }

  // ───────────────────────── Matching ─────────────────────────

  static String _canon(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String _stripTags(String s) =>
      s.replaceAll(RegExp(r'\s*[\(\[][^\)\]]*[\)\]]'), '');

  static String _noExt(String fileName) =>
      fileName.replaceFirst(RegExp(r'\.[^./\\]+$'), '');

  static double _dice(String a, String b) {
    if (a.length < 2 || b.length < 2) return 0;
    final grams = <String, int>{};
    for (var i = 0; i < a.length - 1; i++) {
      grams.update(a.substring(i, i + 2), (n) => n + 1, ifAbsent: () => 1);
    }
    var hits = 0;
    for (var i = 0; i < b.length - 1; i++) {
      final g = b.substring(i, i + 2);
      final n = grams[g] ?? 0;
      if (n > 0) {
        grams[g] = n - 1;
        hits++;
      }
    }
    return 2 * hits / ((a.length - 1) + (b.length - 1));
  }

  /// Ranks [files] (`.cht` names) against a ROM file name. Best first, at most [limit].
  static List<String> rank(
    List<String> files,
    String romFileName, {
    int limit = 12,
  }) {
    final romBase = _noExt(romFileName);
    final romFull = _canon(romBase);
    final target = _canon(_stripTags(romBase).replaceAll('_', ' '));
    if (target.isEmpty) return const [];
    final scored = <MapEntry<String, double>>[];
    for (final f in files) {
      final base = _noExt(f);
      final key = _canon(_stripTags(base));
      if (key.isEmpty) continue;
      double s = 0;
      if (key == target) {
        s = 100;
        if (_canon(base) == romFull) s += 50; // identical No-Intro name
        final l = base.toLowerCase();
        if (l.contains('(usa') || l.contains('(world')) s += 5;
      } else if (target.length >= 4 &&
          (key.startsWith(target) || target.startsWith(key)) &&
          key.length >= 4) {
        s = 60.0 - (key.length - target.length).abs().clamp(0, 30);
      } else {
        final d = _dice(key, target);
        if (d >= 0.7) s = d * 50;
      }
      if (s > 0) scored.add(MapEntry(f, s));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in scored.take(limit)) e.key];
  }

  /// Substring search over a system's cheat files (manual lookup).
  static List<String> search(
    List<String> files,
    String query, {
    int limit = 40,
  }) {
    final q = _canon(query);
    if (q.isEmpty) return const [];
    final hits = files.where((f) => _canon(_noExt(f)).contains(q)).toList()
      ..sort();
    return hits.take(limit).toList();
  }

  // ───────────────────────── Storage ─────────────────────────

  String _cacheFolder(ConsoleType t) => _folders[t]!.first;

  Directory _cacheDir(ConsoleType t) => Directory(
    '${StorageService.instance.rootDir.path}/cheats/${_cacheFolder(t)}',
  );

  File _indexFile(ConsoleType t) => File(
    '${StorageService.instance.rootDir.path}/cheats/.index_${t.name}.json',
  );

  /// Remote file names can never contain path separators; refuse anything that tries.
  static String? _safeName(String name) {
    if (name.isEmpty || name.contains('/') || name.contains('\\')) return null;
    if (name == '.' || name == '..' || name.contains('..')) return null;
    return name;
  }

  final Map<ConsoleType, Future<List<String>>> _indexFutures = {};

  // ───────────────────────── Public API ─────────────────────────

  /// Candidate cheat files for [romFileName], best match first. Tries the exact file first
  /// (no GitHub API call), then falls back to fuzzy matching against the system index.
  Future<List<String>> candidatesFor(
    ConsoleSystem system,
    String romFileName,
  ) async {
    final t = system.type;
    if (!_folders.containsKey(t)) return const [];
    final exact = _safeName('${_noExt(romFileName)}.cht');
    if (exact != null && await _readCached(t, exact) != null) return [exact];
    final files = await indexFor(t);
    final ranked = rank(files, romFileName);
    if (ranked.isNotEmpty) return ranked;
    // Not in the index (or the index is unavailable): the exact name may still exist remotely.
    if (exact != null && files.isEmpty && await load(t, exact) != null) {
      return [exact];
    }
    return const [];
  }

  /// Every `.cht` file name known for the system (cached; refreshed every 14 days).
  /// Falls back to whatever is already cached on disk when offline.
  Future<List<String>> indexFor(ConsoleType t, {bool forceRefresh = false}) {
    if (forceRefresh) _indexFutures.remove(t);
    return _indexFutures.putIfAbsent(t, () async {
      final cached = await _readIndex(t);
      if (cached != null && !cached.stale && !forceRefresh) return cached.files;
      final fresh = await _fetchIndex(t);
      if (fresh != null && fresh.isNotEmpty) {
        await _writeIndex(t, fresh);
        return fresh;
      }
      // Offline / rate limited: stale index, else the files already downloaded.
      if (cached != null) return cached.files;
      return _localFiles(t);
    });
  }

  /// Entries of one cheat file (from the local cache, downloading it if needed).
  /// Null when it cannot be read or downloaded.
  Future<List<CheatEntry>?> load(ConsoleType t, String fileName) async {
    final safe = _safeName(fileName);
    if (safe == null || !_folders.containsKey(t)) return null;
    var text = await _readCached(t, safe);
    if (text == null) {
      final folders = await _resolvedFolder(t);
      final bytes = await _get(
        Uri.https(
          'raw.githubusercontent.com',
          '/$_repo/HEAD/cht/${folders ?? _cacheFolder(t)}/$safe',
        ),
        timeout: const Duration(seconds: 20),
      );
      if (bytes == null || bytes.isEmpty) return null;
      text = utf8.decode(bytes, allowMalformed: true);
      try {
        final dir = _cacheDir(t);
        if (!await dir.exists()) await dir.create(recursive: true);
        final tmp = File('${dir.path}/$safe.part');
        await tmp.writeAsString(text, flush: true);
        await tmp.rename('${dir.path}/$safe');
      } catch (_) {} // cache is optional
    }
    final entries = parse(text);
    return entries.isEmpty ? null : entries;
  }

  // ───────────────────────── Internals ─────────────────────────

  Future<String?> _readCached(ConsoleType t, String safeName) async {
    try {
      final f = File('${_cacheDir(t).path}/$safeName');
      if (await f.exists() && await f.length() > 0) {
        return utf8.decode(await f.readAsBytes(), allowMalformed: true);
      }
    } catch (_) {}
    return null;
  }

  Future<List<String>> _localFiles(ConsoleType t) async {
    try {
      final dir = _cacheDir(t);
      if (!await dir.exists()) return const [];
      return [
        await for (final e in dir.list(followLinks: false))
          if (e is File && e.path.toLowerCase().endsWith('.cht'))
            e.uri.pathSegments.last,
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<({List<String> files, bool stale})?> _readIndex(ConsoleType t) async {
    try {
      final f = _indexFile(t);
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final at = DateTime.fromMillisecondsSinceEpoch(j['at'] as int);
      final files = (j['files'] as List).cast<String>();
      return (
        files: files,
        stale: DateTime.now().difference(at) > _indexMaxAge,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeIndex(ConsoleType t, List<String> files) async {
    try {
      final f = _indexFile(t);
      if (!await f.parent.exists()) await f.parent.create(recursive: true);
      final tmp = File('${f.path}.part');
      await tmp.writeAsString(
        jsonEncode({
          'at': DateTime.now().millisecondsSinceEpoch,
          'files': files,
        }),
        flush: true,
      );
      await tmp.rename(f.path);
    } catch (_) {}
  }

  final Map<ConsoleType, String?> _resolved = {};

  /// Real folder name in the repository for a system (null if it could not be determined).
  Future<String?> _resolvedFolder(ConsoleType t) async {
    if (_resolved.containsKey(t)) return _resolved[t];
    final tree = await _systemTree(t);
    return tree?.folder;
  }

  /// Walks root -> cht -> <system> with non-recursive tree calls so large folders (PS1) are
  /// never truncated.
  Future<({String folder, String sha})?> _systemTree(ConsoleType t) async {
    final root = await _getJson('git/trees/HEAD');
    final chtSha = _childSha(root, 'cht');
    if (chtSha == null) return null;
    final cht = await _getJson('git/trees/$chtSha');
    final dirs = <String, String>{};
    for (final e in (cht?['tree'] as List?) ?? const []) {
      if (e is Map && e['type'] == 'tree') {
        dirs[_canon(e['path'] as String)] = e['sha'] as String;
        if (e['path'] is String)
          _names[_canon(e['path'] as String)] = e['path'] as String;
      }
    }
    for (final want in _folders[t]!) {
      final sha = dirs[_canon(want)];
      if (sha != null) {
        final real = _names[_canon(want)] ?? want;
        _resolved[t] = real;
        return (folder: real, sha: sha);
      }
    }
    return null;
  }

  final Map<String, String> _names = {};

  static String? _childSha(Map<String, dynamic>? tree, String name) {
    for (final e in (tree?['tree'] as List?) ?? const []) {
      if (e is Map && e['path'] == name && e['type'] == 'tree') {
        return e['sha'] as String?;
      }
    }
    return null;
  }

  Future<List<String>?> _fetchIndex(ConsoleType t) async {
    final sys = await _systemTree(t);
    if (sys == null) return null;
    final tree = await _getJson('git/trees/${sys.sha}');
    if (tree == null) return null;
    return [
      for (final e in (tree['tree'] as List?) ?? const [])
        if (e is Map &&
            e['type'] == 'blob' &&
            (e['path'] as String).toLowerCase().endsWith('.cht'))
          e['path'] as String,
    ];
  }

  Future<Map<String, dynamic>?> _getJson(String apiPath) async {
    final bytes = await _get(
      Uri.parse('https://api.github.com/repos/$_repo/$apiPath'),
      timeout: const Duration(seconds: 25),
    );
    if (bytes == null) return null;
    try {
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _get(Uri uri, {required Duration timeout}) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..userAgent = _userAgent;
    try {
      return await () async {
        final req = await client.getUrl(uri);
        final res = await req.close();
        if (res.statusCode != 200) {
          await res.drain<void>();
          return null;
        }
        final b = BytesBuilder(copy: false);
        await for (final c in res) {
          b.add(c);
        }
        return b.takeBytes();
      }().timeout(timeout);
    } catch (e) {
      debugPrint('[CheatDb] $uri -> $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
