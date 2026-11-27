// lib/services/box_art_service.dart
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/console_system.dart';
import 'app_settings.dart';

/// Fetches official game box art from Libretro's GitHub thumbnail repositories,
/// caches it permanently on disk under <appSupportDir>/boxart/, and supports custom covers.
class BoxArtService {
  BoxArtService._();
  static final BoxArtService instance = BoxArtService._();

  Directory? _cacheDir;
  final Map<String, Future<File?>> _inFlight = {};
  final Set<String> _sessionMisses = {};

  /// Covers already found on disk this session. Lets a card that is rebuilt after scrolling
  /// away and back show its art on the very first frame (no spinner / placeholder flash, no
  /// async file checks per card).
  final Map<String, File> _known = {};
  String _knownKey(ConsoleSystem system, String romFileName) =>
      '${system.shortName}|$romFileName';

  /// Synchronous lookup of a cover seen earlier in this session, or null.
  File? peekCover(ConsoleSystem system, String romFileName) =>
      _known[_knownKey(system, romFileName)];
  final Map<String, Future<List<String>>> _repoIndexFutures = {};

  /// Parsed title index per repo (canonical title -> file name). Built ONCE per repo in a
  /// background isolate: matching used to run thousands of RegExp replaces on the UI thread for
  /// every game without art, which froze scrolling on big libraries.
  final Map<String, Future<Map<String, String>>> _repoKeyIndex = {};
  final Map<String, DateTime> _indexFailedAt = {};

  /// At most this many covers download at once. Every card used to open its own HttpClient and
  /// fire up to ~20 requests, so a big library started hundreds of sockets at the same time.
  static const int _maxParallel = 3;
  int _active = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  /// Set when a request fails at the network level, so the other queued covers stop trying
  /// (and are not remembered as "no art exists") until the connection is back.
  DateTime _offlineUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool get _offline => DateTime.now().isBefore(_offlineUntil);

  Future<void> _acquire() async {
    if (_active < _maxParallel) {
      _active++;
      return;
    }
    final c = Completer<void>();
    _waiters.add(c);
    await c.future; // the slot is handed over with _active already counted
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _active--;
    }
  }

  /// Maps each ConsoleSystem to its exact Libretro thumbnail repository name.
  static String? _repoForSystem(ConsoleSystem system) {
    final s = system.shortName.toUpperCase();
    switch (s) {
      case 'PSP':
        return 'Sony_-_PlayStation_Portable';
      case 'PS1':
      case 'PSX':
        return 'Sony_-_PlayStation';
      case 'NDS':
      case 'DS':
        return 'Nintendo_-_Nintendo_DS';
      case '3DS':
        return 'Nintendo_-_Nintendo_3DS';
      case 'GBA':
        return 'Nintendo_-_Game_Boy_Advance';
      case 'GBC':
        return 'Nintendo_-_Game_Boy_Color';
      case 'GB':
        return 'Nintendo_-_Game_Boy';
      case 'NES':
        return 'Nintendo_-_Nintendo_Entertainment_System';
      case 'SNES':
        return 'Nintendo_-_Super_Nintendo_Entertainment_System';
      case 'N64':
        return 'Nintendo_-_Nintendo_64';
      case 'SMS':
        return 'Sega_-_Master_System_-_Mark_III';
      case 'GG':
        return 'Sega_-_Game_Gear';
      case 'MD':
        return 'Sega_-_Mega_Drive_-_Genesis';
      case 'SATURN':
        return 'Sega_-_Saturn';
      case 'MINI':
        return 'Nintendo_-_Pokemon_Mini';
      case 'WS':
        return 'Bandai_-_WonderSwan'; // see _reposFor: .wsc / .pc2 try other repos first
      default:
        return null;
    }
  }

  /// Repositories to try, in order. WonderSwan and WonderSwan Color are two thumbnail repos but
  /// one console in the app, so the ROM extension decides which is searched first and the other
  /// is the fallback (a few .ws files are colour games and vice versa).
  static List<String> _reposFor(ConsoleSystem system, String romFileName) {
    final main = _repoForSystem(system);
    if (main == null) return const <String>[];
    if (system.shortName.toUpperCase() != 'WS') return <String>[main];
    final ext = romFileName.contains('.')
        ? romFileName.substring(romFileName.lastIndexOf('.') + 1).toLowerCase()
        : '';
    const mono = 'Bandai_-_WonderSwan';
    const color = 'Bandai_-_WonderSwan_Color';
    const pocket = 'Benesse_-_Pocket_Challenge_V2';
    switch (ext) {
      case 'wsc':
        return const <String>[color, mono];
      case 'pc2':
      case 'pcv2':
        return const <String>[pocket, mono, color];
      default:
        return const <String>[mono, color];
    }
  }

  Future<Directory> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/boxart');
    if (!await dir.exists()) await dir.create(recursive: true);
    _cacheDir = dir;
    // Tidy the cache once per session, well after startup so it never competes with the
    // first screen for disk and CPU.
    unawaited(Future<void>.delayed(const Duration(seconds: 20), pruneCache));
    return dir;
  }

  /// Marker next to a cover the user chose themselves. Such covers are never evicted.
  static const String _customSuffix = '.custom';

  /// Biggest the cover cache may grow before the oldest downloaded covers are removed.
  static const int maxCacheBytes = 400 << 20;

  /// Largest image accepted as a custom cover (a phone photo can be many MB).
  static const int maxCustomCoverBytes = 20 << 20;

  /// Keeps the cover cache from growing forever: removes half-written downloads, orphaned
  /// markers and, when the cache is over [maxBytes], the oldest downloaded covers until it is
  /// back under 90% of the limit. Custom covers are never removed. Evicted covers simply
  /// download again the next time they are needed. Returns how many files were removed.
  Future<int> pruneCache({int maxBytes = maxCacheBytes}) async {
    var removed = 0;
    try {
      final dir = await _getCacheDir();
      final covers = <({File file, int size, DateTime modified})>[];
      final partCutoff = DateTime.now().subtract(const Duration(minutes: 10));
      final names = <String>{};
      final entries = await dir.list(followLinks: false).toList();
      for (final e in entries) {
        if (e is File) names.add(e.path);
      }
      var total = 0;
      for (final e in entries) {
        if (e is! File) continue;
        final path = e.path;
        try {
          final st = await e.stat();
          if (path.endsWith('.part')) {
            if (st.modified.isBefore(partCutoff)) {
              await e.delete();
              removed++;
            }
          } else if (path.endsWith(_customSuffix)) {
            final cover = path.substring(0, path.length - _customSuffix.length);
            if (!names.contains(cover)) {
              await e.delete(); // the cover is gone, so is its marker
              removed++;
            }
          } else if (path.endsWith('.png')) {
            total += st.size;
            if (!names.contains('$path$_customSuffix')) {
              covers.add((file: e, size: st.size, modified: st.modified));
            }
          }
        } catch (_) {}
      }
      if (total > maxBytes) {
        covers.sort((a, b) => a.modified.compareTo(b.modified));
        final target = (maxBytes * 0.9).round();
        final gone = <String>{};
        for (final c in covers) {
          if (total <= target) break;
          try {
            await c.file.delete();
            total -= c.size;
            gone.add(c.file.path);
            removed++;
          } catch (_) {}
        }
        // A card must never be handed a file that no longer exists.
        _known.removeWhere((_, f) => gone.contains(f.path));
      }
    } catch (_) {}
    return removed;
  }

  /// Builds a filesystem-safe cache filename keyed by system + ROM filename.
  String _cacheKey(ConsoleSystem system, String romFileName) {
    final safe = '${system.shortName}_$romFileName'.replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '_',
    );
    return '$safe.png';
  }

  /// Returns the cached cover File immediately if already downloaded or set by user.
  Future<File?> getCachedCover(ConsoleSystem system, String romFileName) async {
    final dir = await _getCacheDir();
    final file = File('${dir.path}/${_cacheKey(system, romFileName)}');
    final st = await file.stat(); // one call instead of exists() + length()
    if (st.type == FileSystemEntityType.file && st.size > 0) {
      _known[_knownKey(system, romFileName)] = file;
      return file;
    }
    _known.remove(_knownKey(system, romFileName));
    return null;
  }

  /// The player's "Download cover art" setting (on by default). Read straight from
  /// SharedPreferences so it is right even before a settings screen has been opened.
  Future<bool> _downloadsAllowed() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(AppSettings.coverArtKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Returns a cached cover or fetches it from Libretro thumbnails once.
  Future<File?> getOrFetchCover(
    ConsoleSystem system,
    String romFileName,
  ) async {
    final existing = await getCachedCover(system, romFileName);
    if (existing != null) return existing;

    // "Download cover art" is off: nothing is requested. Not remembered as a miss, so the cover
    // is looked up normally once the player turns the setting back on.
    if (!await _downloadsAllowed()) return null;

    final key = '${system.shortName}:$romFileName';
    if (_sessionMisses.contains(key)) return null;

    return _inFlight.putIfAbsent(key, () async {
      await _acquire();
      try {
        // The deadline keeps one stalled download from holding a slot forever.
        final fetched = await _downloadCover(
          system,
          romFileName,
        ).timeout(const Duration(seconds: 90), onTimeout: () => null);
        if (fetched == null && !_offline) _sessionMisses.add(key);
        return fetched;
      } catch (e) {
        debugPrint('[BoxArt] Fetch failed for $romFileName: $e');
        return null;
      } finally {
        _release();
        _inFlight.remove(key);
      }
    });
  }

  /// Lets the user pick a custom cover image from storage and saves it to cache.
  Future<File?> pickCustomCover(
    ConsoleSystem system,
    String romFileName,
  ) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final pickedPath = result?.files.single.path;
    if (pickedPath == null) return null;

    final picked = File(pickedPath);
    try {
      final size = await picked.length();
      if (size <= 0 || size > maxCustomCoverBytes) return null;
    } catch (_) {
      return null;
    }

    final dir = await _getCacheDir();
    final target = File('${dir.path}/${_cacheKey(system, romFileName)}');
    // Copy to a side file first: a failed copy must not replace a working cover with a broken one.
    final tmp = File('${target.path}.part');
    try {
      await picked.copy(tmp.path);
      await tmp.rename(target.path);
      await File('${target.path}$_customSuffix').writeAsString('1');
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      return null;
    }
    _known[_knownKey(system, romFileName)] = target;
    _sessionMisses.remove('${system.shortName}:$romFileName');
    return target;
  }

  /// Deletes a cached/custom cover so it can be re-fetched automatically.
  Future<void> clearCover(ConsoleSystem system, String romFileName) async {
    final dir = await _getCacheDir();
    final target = File('${dir.path}/${_cacheKey(system, romFileName)}');
    _known.remove(_knownKey(system, romFileName));
    if (await target.exists()) await target.delete();
    final marker = File('${target.path}$_customSuffix');
    if (await marker.exists()) await marker.delete();
    _sessionMisses.remove('${system.shortName}:$romFileName');
  }

  /// Sanitizes a title according to Libretro's thumbnail naming rules
  /// (replaces & * / : ` < > ? \ | with _).
  static String _libretroSafeName(String raw) {
    return raw.replaceAll(RegExp(r'[&*/:`<>?\\|]'), '_').trim();
  }

  /// Strips extension, underscores, [tags], (tags), -decrypted, and version numbers.
  static String _cleanBaseTitle(String romFileName) {
    var name = romFileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    name = name.replaceAll('_', ' ');
    // Titles often carry ™ ® © which the thumbnail names don't have
    name = name.replaceAll(RegExp(r'[™®©]'), '');
    // Strip all (...) and [...] blocks (e.g., (USA), [RUS], (v1.01), [!])
    name = name.replaceAll(RegExp(r'\s*[\(\[][^\)\]]*[\)\]]'), '');
    // Strip common ROM dump suffixes like "-decrypted", "-trimmed", "-patched"
    name = name.replaceAll(
      RegExp(
        r'[\s\-_]+(decrypted|encrypted|trimmed|patched|fix)$',
        caseSensitive: false,
      ),
      '',
    );
    // Strip trailing version tokens like "v1.0" or "Rev 1"
    name = name.replaceAll(
      RegExp(r'\s+(v\d+(\.\d+)*|rev\s*\d+)$', caseSensitive: false),
      '',
    );
    return name.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Normalizes accented characters (e.g., "Pokémon" -> "Pokemon").
  static String _asciiFold(String s) {
    return s
        .replaceAll('é', 'e')
        .replaceAll('É', 'E')
        .replaceAll('è', 'e')
        .replaceAll('à', 'a')
        .replaceAll('’', "'");
  }

  /// Normalizes a title into a canonical punctuation-free key so
  /// "Legend of Spyro, The - The Eternal Night" == "the legend of spyro the eternal night"
  /// and "Pokemon Mystery Dungeon_ Red Rescue Team" == "pokemon mystery dungeon red rescue team".
  static String _canonicalKey(String rawTitle) {
    var s = _asciiFold(rawTitle).toLowerCase();
    // Handle No-Intro trailing articles: "Foo, The - Bar" -> "The Foo - Bar"
    s = s.replaceFirstMapped(
      RegExp(r'^([^,-]+),\s*(the|a|an)(\s*-\s*.*)?$'),
      (m) => '${m[2]} ${m[1]}${m[3] ?? ''}',
    );
    // Replace all non-alphanumeric chars (colons, underscores, dashes, commas) with single spaces
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    return s;
  }

  /// Builds the raw.githubusercontent.com URL using HEAD (works for both master & main branches).
  Uri _rawGitHubBoxArtUri(String repo, String pngFileName) {
    final encodedFile = Uri.encodeComponent(pngFileName);
    return Uri.parse(
      'https://raw.githubusercontent.com/libretro-thumbnails/$repo/HEAD/Named_Boxarts/$encodedFile',
    );
  }

  /// Games whose common (fan-translation / English) title differs from the official No-Intro name
  /// the thumbnail repos use. Key = canonical form of the cleaned ROM title, value = official
  /// titles to look for. Region tags never matter: the index ignores them.
  static const Map<String, List<String>> _titleAliases = {
    'pokemon breeder mini': [
      'Pokemon Sodateya-san Mini',
      'Pokemon Sodateyasan Mini',
    ],
  };

  Future<File?> _downloadCover(ConsoleSystem system, String romFileName) async {
    for (final repo in _reposFor(system, romFileName)) {
      final cover = await _downloadFromRepo(system, romFileName, repo);
      if (cover != null) return cover;
      if (_offline)
        return null; // no point trying the next repo without a connection
    }
    return null;
  }

  Future<File?> _downloadFromRepo(
    ConsoleSystem system,
    String romFileName,
    String repo,
  ) async {
    final noExt = romFileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final cleaned = _cleanBaseTitle(romFileName);
    final asciiCleaned = _asciiFold(cleaned);
    final aliases = _titleAliases[_canonicalKey(cleaned)] ?? const <String>[];

    // Build title variants (handles both "Pokemon" and "Pokémon", plus " - " vs "_ ")
    final baseVariants = <String>{
      if (cleaned.isNotEmpty) cleaned,
      if (asciiCleaned.isNotEmpty) asciiCleaned,
      if (cleaned.toLowerCase().startsWith('pokemon '))
        'Pokémon ${cleaned.substring(8)}',
      ...aliases,
    };

    final expandedVariants = <String>{};
    for (final v in baseVariants) {
      expandedVariants.add(_libretroSafeName(v));
      if (v.contains(' - ')) {
        // Libretro turns ":" into "_", so "Title - Subtitle" is often "Title_ Subtitle"
        expandedVariants.add(_libretroSafeName(v.replaceFirst(' - ', '_ ')));
      }
    }

    final candidates = <String>{
      if (noExt.isNotEmpty) '${_libretroSafeName(noExt)}.png',
      for (final title in expandedVariants) ...[
        '$title (USA).png',
        '$title (USA, Europe).png',
        '$title (USA, Australia).png',
        '$title (Europe).png',
        '$title (World).png',
        '$title (Japan).png',
        '$title.png',
      ],
    };

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..userAgent = 'tonEMU/1.0 (Flutter)';

    try {
      // 0. Exact title in the repo index: one request instead of guessing ~20 file names.
      final index = await _getKeyIndex(repo);
      final exact = index[_canonicalKey(cleaned)];
      if (exact != null) {
        final bytes = await _tryGetBytes(
          client,
          _rawGitHubBoxArtUri(repo, exact),
        );
        if (_looksLikePng(bytes)) {
          debugPrint('[BoxArt] Indexed match: $exact');
          return _writeCache(system, romFileName, bytes!);
        }
      }

      // 0b. Official title of a retitled / fan-translated game. Spacing is ignored, so
      // "Sodateya-san" and "Sodateyasan" both match whichever one the repo uses.
      if (aliases.isNotEmpty && index.isNotEmpty) {
        final wanted = {
          for (final a in aliases) _canonicalKey(a).replaceAll(' ', ''),
        };
        for (final e in index.entries) {
          if (!wanted.contains(e.key.replaceAll(' ', ''))) continue;
          final bytes = await _tryGetBytes(
            client,
            _rawGitHubBoxArtUri(repo, e.value),
          );
          if (_looksLikePng(bytes)) {
            debugPrint('[BoxArt] Alias match: ${e.value}');
            return _writeCache(system, romFileName, bytes!);
          }
        }
      }

      // 1. Fast path: try direct regional candidates on raw.githubusercontent.com
      for (final fileName in candidates) {
        if (_offline) return null;
        final uri = _rawGitHubBoxArtUri(repo, fileName);
        final bytes = await _tryGetBytes(client, uri);
        if (_looksLikePng(bytes)) {
          debugPrint('[BoxArt] Matched: $fileName');
          return _writeCache(system, romFileName, bytes!);
        }
      }

      // 2. Full Named_Boxarts subtree lookup (never truncated!) + punctuation-agnostic match
      final fuzzyFile = await _findFuzzyMatchInRepo(repo, cleaned);
      if (fuzzyFile != null) {
        final uri = _rawGitHubBoxArtUri(repo, fuzzyFile);
        final bytes = await _tryGetBytes(client, uri);
        if (_looksLikePng(bytes)) {
          debugPrint('[BoxArt] Fuzzy matched: $fuzzyFile');
          return _writeCache(system, romFileName, bytes!);
        }
      }

      debugPrint('[BoxArt] No match found for "$romFileName" ($repo)');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<File> _writeCache(
    ConsoleSystem system,
    String romFileName,
    List<int> bytes,
  ) async {
    final dir = await _getCacheDir();
    final out = File('${dir.path}/${_cacheKey(system, romFileName)}');
    // Write to a side file and rename: a kill mid-write must never leave a half-written PNG
    // that the cache check (size > 0) would accept as a valid cover forever.
    final tmp = File('${out.path}.part');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(out.path);
    _known[_knownKey(system, romFileName)] = out;
    return out;
  }

  static bool _looksLikePng(List<int>? b) =>
      b != null &&
      b.length > 512 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47;

  /// canonical title -> file name for [repo]. Retried at most every 10 minutes after a failure
  /// (the GitHub API allows only 60 unauthenticated calls per hour).
  Future<Map<String, String>> _getKeyIndex(String repo) {
    final failed = _indexFailedAt[repo];
    if (failed != null &&
        DateTime.now().difference(failed) > const Duration(minutes: 10)) {
      _indexFailedAt.remove(repo);
      _repoKeyIndex.remove(repo);
      _repoIndexFutures.remove(repo);
    }
    return _repoKeyIndex.putIfAbsent(repo, () async {
      final files = await _getRepoFileList(repo);
      if (files.isEmpty) {
        _indexFailedAt[repo] = DateTime.now();
        return const <String, String>{};
      }
      try {
        return await compute(_buildCoverIndex, files);
      } catch (_) {
        return _buildCoverIndex(files);
      }
    });
  }

  /// Fetches the complete list of PNG filenames inside Named_Boxarts/ using a
  /// two-step non-recursive GitHub Tree lookup so large repos (NDS/GBA) are NEVER truncated.
  Future<List<String>> _getRepoFileList(String repo) {
    return _repoIndexFutures.putIfAbsent(repo, () async {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 20)
        ..userAgent = 'tonEMU/1.0 (Flutter)';
      try {
        // Step A: fetch root tree (only ~5 entries) to get Named_Boxarts tree SHA
        final rootUri = Uri.parse(
          'https://api.github.com/repos/libretro-thumbnails/$repo/git/trees/HEAD',
        );
        final rootRaw = await _tryGetBytes(client, rootUri);
        if (rootRaw == null) return const <String>[];

        final rootJson =
            jsonDecode(utf8.decode(rootRaw)) as Map<String, dynamic>;
        final rootTree = (rootJson['tree'] as List?) ?? const [];
        String? boxArtsSha;
        for (final entry in rootTree) {
          if (entry['path'] == 'Named_Boxarts' && entry['type'] == 'tree') {
            boxArtsSha = entry['sha'] as String?;
            break;
          }
        }
        if (boxArtsSha == null) return const <String>[];

        // Step B: fetch Named_Boxarts subtree directly (returns 100% of files untruncated)
        final boxArtsUri = Uri.parse(
          'https://api.github.com/repos/libretro-thumbnails/$repo/git/trees/$boxArtsSha',
        );
        final boxRaw = await _tryGetBytes(
          client,
          boxArtsUri,
          timeout: const Duration(seconds: 25),
        );
        if (boxRaw == null) return const <String>[];

        final boxJson = jsonDecode(utf8.decode(boxRaw)) as Map<String, dynamic>;
        final items = (boxJson['tree'] as List?) ?? const [];
        return <String>[
          for (final item in items)
            if ((item['path'] as String?)?.endsWith('.png') == true)
              item['path'] as String,
        ];
      } catch (e) {
        debugPrint('[BoxArt] Index lookup failed for $repo: $e');
        return const <String>[];
      } finally {
        client.close(force: true);
      }
    });
  }

  Future<String?> _findFuzzyMatchInRepo(
    String repo,
    String rawCleanTitle,
  ) async {
    if (rawCleanTitle.isEmpty) return null;
    final index = await _getKeyIndex(repo);
    if (index.isEmpty) return null;

    final targetKey = _canonicalKey(rawCleanTitle);
    if (targetKey.isEmpty) return null;

    // Exact keys were already tried; this is the prefix match ("Foo" -> "Foo - The Sequel").
    for (final e in index.entries) {
      if (e.key != targetKey && e.key.startsWith(targetKey)) return e.value;
    }
    return null;
  }

  Future<List<int>?> _tryGetBytes(
    HttpClient client,
    Uri uri, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    try {
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      // BytesBuilder keeps the raw chunks; a List<int> of boxed ints was ~8x the memory and slow.
      final bytes = BytesBuilder(copy: false);
      await for (final data in res) {
        bytes.add(data);
      }
      return bytes.takeBytes();
    } on SocketException catch (e) {
      _offlineUntil = DateTime.now().add(const Duration(seconds: 20));
      debugPrint('[BoxArt] Offline? $uri -> $e');
      return null;
    } on TimeoutException catch (e) {
      _offlineUntil = DateTime.now().add(const Duration(seconds: 20));
      debugPrint('[BoxArt] Timeout $uri -> $e');
      return null;
    } catch (e) {
      debugPrint('[BoxArt] Error fetching $uri -> $e');
      return null;
    }
  }
}

/// Runs in a background isolate: canonical title -> file name, preferring "(USA" releases.
Map<String, String> _buildCoverIndex(List<String> files) {
  final out = <String, String>{};
  final tags = RegExp(r'\s*[\(\[][^\)\]]*[\)\]]');
  final png = RegExp(r'\.png$', caseSensitive: false);
  for (final f in files) {
    final base = f.replaceFirst(png, '');
    final key = BoxArtService._canonicalKey(base.replaceAll(tags, ''));
    if (key.isEmpty) continue;
    final prev = out[key];
    if (prev == null ||
        (!prev.toLowerCase().contains('(usa') &&
            f.toLowerCase().contains('(usa'))) {
      out[key] = f;
    }
  }
  return out;
}
