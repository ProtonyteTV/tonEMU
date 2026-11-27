// lib/services/storage_service.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Central place for tonEMU's on-disk folders. EVERYTHING lives under one root:
///
///   <root>/roms  <root>/saves  <root>/states  <root>/system  <root>/screenshots
///
///  - Android                    -> <external app files dir>/tonEMU, i.e.
///                                  Android/data/<package>/files/tonEMU (no storage permission
///                                  needed; also shown by TonEmuDocumentsProvider)
///  - iOS / macOS / Windows / Linux -> <Documents>/tonEMU
///
/// The native side (MainActivity.getTonEmuRootDir) uses the exact same rule, so the cores
/// read/write BIOS, battery saves and memory cards in the same folders shown here.
///
/// Call `await StorageService.instance.init()` once in main() before runApp.
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const MethodChannel _channel = MethodChannel(
    'com.jedplatforms.jedEmu/core',
  );

  Directory? _root;
  bool _hasAllFiles = false;
  bool _usingPublicRoot = false;

  bool get isInitialized => _root != null;
  bool get hasAllFilesAccess => _hasAllFiles;

  /// Always false: tonEMU no longer asks for "All files access" (Google Play policy). Kept so
  /// older call sites compile; they simply never show the permission prompt.
  bool get canRequestAllFilesAccess => false;

  /// Opens the tonEMU location in the system Files app (Android only). False if no app could open it.
  Future<bool> openInFilesApp() async {
    if (!Platform.isAndroid) return false;
    try {
      return (await _channel.invokeMethod<bool>('openStorageInFiles')) == true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Re-checks All Files Access (e.g. the user granted it in Android Settings while the app was
  /// open). When it just became available this switches to /storage/emulated/0/tonEMU and
  /// moves the old files over. Returns true when the storage root changed.
  Future<bool> refreshIfPermissionChanged() async {
    if (!Platform.isAndroid || _usingPublicRoot) return false;
    final before = _root?.path;
    await init();
    return _root?.path != before;
  }

  Future<void> init({bool requestPermission = false}) async {
    // Never run two inits (and two migrations) at the same time.
    final running = _initRun;
    if (running != null) {
      await running;
      if (!requestPermission) return;
    }
    final run = _init(requestPermission);
    _initRun = run;
    try {
      await run;
    } finally {
      if (identical(_initRun, run)) _initRun = null;
    }
  }

  Future<void>? _initRun;

  Future<void> _init(bool requestPermission) async {
    Directory? root;

    if (Platform.isAndroid) {
      // App-specific EXTERNAL folder (Android/data/<package>/files/tonEMU): no permission to
      // grant, and Samsung My Files / a PC over USB can browse it. Same folder as native
      // StorageRoot.get() (getExternalFilesDir(null)); both fall back to filesDir if unavailable.
      _hasAllFiles = true;
      _usingPublicRoot = true; // there is no later switch to make
      final ext = await getExternalStorageDirectory();
      final base = ext ?? await getApplicationSupportDirectory();
      root = Directory('${base.path}/tonEMU');
    } else {
      _hasAllFiles = true; // nothing to grant on these platforms
      final docs = await getApplicationDocumentsDirectory();
      root = Directory('${docs.path}/tonEMU');
    }

    if (!await root.exists()) await root.create(recursive: true);
    _root = root;

    for (final d in [statesDir, savesDir, systemDir, romsDir, screenshotsDir]) {
      try {
        if (!await d.exists()) await d.create(recursive: true);
      } catch (_) {}
    }

    // Moving old files can take minutes for a big library (always a full copy across volumes),
    // so it runs in the background: the app starts immediately and listens to [migration].
    _migration = (_migration ?? Future<void>.value())
        .then((_) => _migrateLegacy(root!))
        .then((_) => cleanStaleTempFiles());
  }

  /// Names the app and the native side use for files that are still being written.
  static final RegExp _tempName = RegExp(r'\.(tmp|part|cp)$|\.\d+\.part$');

  /// Removes half-written leftovers of an interrupted save, BIOS import or file move (low
  /// storage, app killed). Only files older than [minAge] go, and only in saves / states /
  /// system (never the ROM library). Returns how many were removed.
  Future<int> cleanStaleTempFiles({
    Duration minAge = const Duration(minutes: 10),
  }) async {
    if (_root == null) return 0;
    var removed = 0;
    final cutoff = DateTime.now().subtract(minAge);
    for (final dir in [savesDir, statesDir, systemDir]) {
      try {
        if (!await dir.exists()) continue;
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is! File || !_tempName.hasMatch(e.path)) continue;
          try {
            if ((await e.lastModified()).isAfter(cutoff)) continue;
            await e.delete();
            removed++;
          } catch (_) {}
        }
      } catch (_) {}
    }
    // The cross-volume move staging folder is empty after a finished migration.
    try {
      final tmp = Directory('${rootDir.path}/.migrate_tmp');
      if (await tmp.exists()) await tmp.delete(recursive: true);
    } catch (_) {}
    return removed;
  }

  /// Bytes used by each tonEMU folder (roms, saves, states, system, screenshots), for a
  /// "Storage" readout in settings. Runs in the background; a folder that cannot be read counts as 0.
  Future<Map<String, int>> folderSizes() async {
    final out = <String, int>{};
    final dirs = {
      'roms': romsDir,
      'saves': savesDir,
      'states': statesDir,
      'system': systemDir,
      'screenshots': screenshotsDir,
    };
    for (final e in dirs.entries) {
      var total = 0;
      try {
        if (await e.value.exists()) {
          await for (final f in e.value.list(
            recursive: true,
            followLinks: false,
          )) {
            if (f is File) {
              try {
                total += await f.length();
              } catch (_) {}
            }
          }
        }
      } catch (_) {}
      out[e.key] = total;
    }
    return out;
  }

  Future<void>? _migration;

  /// Completes when the move of old files into the current root has finished.
  /// Await it (without blocking the UI) to refresh the library afterwards.
  Future<void> get migration => _migration ?? Future<void>.value();

  /// Alias in case other code calls load().
  Future<void> load() => init();

  /// No-op: no storage permission is needed any more. Always true.
  Future<bool> requestAllFilesAccess() async => true;

  // ───────────────────────── Legacy migration ─────────────────────────

  /// Older builds kept ROMs in <app_flutter>/roms, BIOS / saves in <filesDir>/system|saves, and
  /// the private fallback in <filesDir>/tonEMU. Everything found there is MOVED into the current
  /// root automatically on start .
  /// An existing file at the destination is never overwritten; the old copy stays in that case.
  /// Safe to run on every start: once the old folders are empty they are removed.
  Future<void> _migrateLegacy(Directory root) async {
    if (!Platform.isAndroid) return;
    try {
      final support =
          await getApplicationSupportDirectory(); // == filesDir on Android
      final docs = await getApplicationDocumentsDirectory();
      final pairs = <List<Directory>>[
        [Directory('${support.path}/system'), Directory('${root.path}/system')],
        [Directory('${support.path}/saves'), Directory('${root.path}/saves')],
        [Directory('${support.path}/states'), Directory('${root.path}/states')],
        [Directory('${docs.path}/roms'), Directory('${root.path}/roms')],
        // Old Wi-Fi staging folder (uploads that never got sorted).
        [
          Directory('${docs.path}/wifi_incoming'),
          Directory('${root.path}/roms'),
        ],
      ];
      final privateRoot = Directory('${support.path}/tonEMU');
      if (privateRoot.path != root.path) {
        for (final n in ['roms', 'saves', 'states', 'system', 'screenshots']) {
          pairs.add([
            Directory('${privateRoot.path}/$n'),
            Directory('${root.path}/$n'),
          ]);
        }
        pairs.add([
          Directory('${privateRoot.path}/wifi_incoming'),
          Directory('${root.path}/roms'),
        ]);
      }
      for (final p in pairs) {
        if (await p[0].exists()) await _mergeDir(p[0], p[1]);
      }
      if (privateRoot.path != root.path) {
        try {
          await privateRoot.delete(); // only succeeds when empty
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _mergeDir(Directory src, Directory dst) async {
    if (!await dst.exists()) await dst.create(recursive: true);
    final items = await src.list(followLinks: false).toList();
    for (final e in items) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final target = '${dst.path}/$name';
      if (e is Directory) {
        await _mergeDir(e, Directory(target));
      } else if (e is File) {
        if (name.endsWith('.tmp') ||
            name.endsWith('.part') ||
            name.endsWith('.cp')) {
          continue; // half-written leftovers are never moved
        }
        if (await File(target).exists()) continue;
        await _moveFile(e, target);
      }
    }
    try {
      await src.delete(); // only succeeds when empty
    } catch (_) {}
  }

  /// Rename when possible; across storage volumes copy to a temp file, verify the size, rename,
  /// then delete the original (so an interrupted copy never leaves a half-written ROM/save).
  Future<void> _moveFile(File src, String target) async {
    try {
      await src.rename(target);
      return;
    } catch (_) {}
    final tmpDir = Directory('${rootDir.path}/.migrate_tmp');
    if (!await tmpDir.exists()) await tmpDir.create(recursive: true);
    final tmp = File('${tmpDir.path}/${target.split('/').last}');
    try {
      await src.copy(tmp.path);
      if (await tmp.length() != await src.length()) {
        await tmp.delete();
        return;
      }
      await tmp.rename(target);
      await src.delete();
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  // ───────────────────────── Paths ─────────────────────────

  /// Human-readable folder path for the Settings screen.
  String get displayPath {
    if (Platform.isAndroid) {
      return 'Android/data/com.jedplatforms.jedEmu/files/tonEMU';
    }
    return 'Documents/tonEMU';
  }

  Directory get rootDir {
    final r = _root;
    if (r == null) {
      throw StateError('StorageService.init() must be awaited before use.');
    }
    return r;
  }

  Directory get statesDir => Directory('${rootDir.path}/states');
  Directory get savesDir => Directory('${rootDir.path}/saves');
  Directory get systemDir => Directory('${rootDir.path}/system');
  Directory get romsDir => Directory('${rootDir.path}/roms');
  Directory get screenshotsDir => Directory('${rootDir.path}/screenshots');
}
