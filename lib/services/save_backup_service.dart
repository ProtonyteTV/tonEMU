// lib/services/save_backup_service.dart
import 'dart:convert';
import 'dart:io';

import 'storage_service.dart';

/// One file inside a backup. [rel] is the path under the tonEMU root, e.g. "saves/Game.gba.srm".
class BackupEntry {
  const BackupEntry(this.rel, this.bytes);
  final String rel;
  final int bytes;

  String get name => rel.split('/').last;
  bool get isState => rel.startsWith('states/');
}

/// A finished backup: a folder <tonEMU>/backups/<id>/ with a manifest.json and a copy of the files.
class BackupInfo {
  BackupInfo({
    required this.id,
    required this.dir,
    required this.createdAt,
    required this.label,
    required this.includesStates,
    required this.files,
  });

  final String id;
  final Directory dir;
  final DateTime createdAt;

  /// "" for a normal backup, "Before restore" for the safety copy made by [SaveBackupService.restore].
  final String label;
  final bool includesStates;
  final List<BackupEntry> files;

  int get fileCount => files.length;
  int get bytes => files.fold(0, (a, e) => a + e.bytes);
  bool get isSafetyCopy => label == SaveBackupService.safetyLabel;

  /// Entries whose file name belongs to [romName] ("<rom>.srm", "<rom>.state", ...).
  List<BackupEntry> entriesFor(String romName) => [
    for (final e in files)
      if (e.name.startsWith('$romName.')) e,
  ];
}

/// What a backup / restore is about to touch (shown in the confirmation dialog).
class BackupPlan {
  const BackupPlan(this.files, this.bytes);
  final int files;
  final int bytes;
}

class BackupProgress {
  const BackupProgress({
    required this.done,
    required this.total,
    required this.bytesDone,
    required this.bytesTotal,
    required this.current,
  });
  final int done, total, bytesDone, bytesTotal;
  final String current;

  double? get fraction {
    if (bytesTotal > 0) return (bytesDone / bytesTotal).clamp(0.0, 1.0);
    if (total > 0) return (done / total).clamp(0.0, 1.0);
    return null;
  }
}

class RestoreResult {
  RestoreResult({
    this.restored = 0,
    this.failed = 0,
    this.missing = 0,
    this.cancelled = false,
    this.safetyCopy,
  });
  int restored;
  int failed;

  /// Files listed in the manifest that are no longer in the backup folder.
  int missing;
  bool cancelled;

  /// The "Before restore" backup that holds what was replaced (null if nothing was replaced).
  BackupInfo? safetyCopy;
}

typedef BackupProgressCallback = void Function(BackupProgress p);

class _Src {
  _Src(this.file, this.rel, this.bytes);
  final File file;
  final String rel;
  final int bytes;
}

/// Save backup + restore manager (shown inside jedManager).
///
/// Backups live in <tonEMU>/backups/<yyyyMMdd-HHmmss>/ so they show up in the Files app and survive
/// a library clean-up. A backup is built in a hidden ".building-<id>" folder and renamed only when
/// every file and the manifest are written, so a killed app or a full disk never leaves a backup
/// that looks complete but is not. Restoring first copies the files it is about to replace into a
/// "Before restore" backup, so a restore can always be undone with another restore.
class SaveBackupService {
  SaveBackupService._();
  static final SaveBackupService instance = SaveBackupService._();

  static const String safetyLabel = 'Before restore';
  static const String _manifestName = 'manifest.json';

  /// The newest "Before restore" copies that are kept; older ones are removed automatically.
  static const int _keepSafetyCopies = 5;

  bool _cancel = false;
  String? lastError;

  void cancel() => _cancel = true;

  Directory get backupsDir =>
      Directory('${StorageService.instance.rootDir.path}/backups');

  Future<void> _ensureStorage() async {
    if (!StorageService.instance.isInitialized) {
      await StorageService.instance.init();
    }
  }

  static bool _isTemp(String n) =>
      n.endsWith('.tmp') || n.endsWith('.part') || n.endsWith('.cp');

  // ───────────────────────── What would be backed up ─────────────────────────

  Future<List<_Src>> _collect(bool includeStates) async {
    final out = <_Src>[];
    Future<void> walk(Directory dir, String prefix) async {
      try {
        if (!await dir.exists()) return;
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is! File) continue;
          final rel = e.path
              .substring(dir.path.length + 1)
              .replaceAll('\\', '/');
          final segs = rel.split('/');
          // ".timemachine", ".nomedia" and other hidden session files are never worth keeping.
          if (segs.any((s) => s.startsWith('.'))) continue;
          final name = segs.last;
          // ".bak" files are older copies the app made itself; skipping them keeps a backup lean.
          if (_isTemp(name) || name.endsWith('.bak')) continue;
          int len;
          try {
            len = await e.length();
          } catch (_) {
            continue;
          }
          if (len <= 0) continue;
          out.add(_Src(e, '$prefix/$rel', len));
        }
      } catch (_) {}
    }

    final s = StorageService.instance;
    await walk(s.savesDir, 'saves');
    if (includeStates) await walk(s.statesDir, 'states');
    return out;
  }

  Future<BackupPlan> plan({required bool includeStates, String? onlyGame}) async {
    await _ensureStorage();
    var src = await _collect(includeStates);
    if (onlyGame != null) {
      src = [
        for (final s in src)
          if (s.rel.split('/').last.startsWith('$onlyGame.')) s,
      ];
    }
    return BackupPlan(src.length, src.fold(0, (a, e) => a + e.bytes));
  }

  // ───────────────────────── Create ─────────────────────────

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _stamp(DateTime d) =>
      '${d.year}${_two(d.month)}${_two(d.day)}-${_two(d.hour)}${_two(d.minute)}${_two(d.second)}';

  /// Backs up the saves (and optionally the save states). Returns null when there was nothing to
  /// back up, the user cancelled, or a write failed (see [lastError]).
  Future<BackupInfo?> create({
    bool includeStates = false,
    String? onlyGame,
    String label = '',
    BackupProgressCallback? onProgress,
  }) async {
    await _ensureStorage();
    lastError = null;
    _cancel = false;
    var srcs = await _collect(includeStates);
    if (onlyGame != null) {
      srcs = [
        for (final s in srcs)
          if (s.rel.split('/').last.startsWith('$onlyGame.')) s,
      ];
    }
    if (srcs.isEmpty) {
      lastError = 'There are no saves to back up yet.';
      return null;
    }
    final info = await _write(
      srcs,
      label: label,
      includesStates: includeStates,
      onProgress: onProgress,
    );
    return info;
  }

  Future<BackupInfo?> _write(
    List<_Src> srcs, {
    required String label,
    required bool includesStates,
    BackupProgressCallback? onProgress,
  }) async {
    final root = backupsDir;
    try {
      await root.create(recursive: true);
      // Keep gallery apps out of the folder.
      final nomedia = File('${root.path}/.nomedia');
      if (!await nomedia.exists()) await nomedia.create();
    } catch (e) {
      lastError = 'Could not create the backups folder.';
      return null;
    }

    final now = DateTime.now();
    var id = _stamp(now);
    var n = 1;
    while (await Directory('${root.path}/$id').exists()) {
      id = '${_stamp(now)}-${n++}';
    }
    final building = Directory('${root.path}/.building-$id');
    final finalDir = Directory('${root.path}/$id');

    final totalBytes = srcs.fold<int>(0, (a, e) => a + e.bytes);
    var doneBytes = 0;
    var done = 0;
    final entries = <BackupEntry>[];

    Future<void> cleanup() async {
      try {
        if (await building.exists()) await building.delete(recursive: true);
      } catch (_) {}
    }

    try {
      await building.create(recursive: true);
      for (final s in srcs) {
        if (_cancel) {
          await cleanup();
          lastError = 'Cancelled.';
          return null;
        }
        onProgress?.call(
          BackupProgress(
            done: done,
            total: srcs.length,
            bytesDone: doneBytes,
            bytesTotal: totalBytes,
            current: s.rel,
          ),
        );
        final dst = File('${building.path}/${s.rel}');
        await dst.parent.create(recursive: true);
        final part = File('${dst.path}.part');
        try {
          await s.file.copy(part.path);
          await part.rename(dst.path);
        } catch (_) {
          // A save the running core is rewriting right now can vanish; one file must not
          // sink the whole backup, but a full disk should (checked below).
          try {
            if (await part.exists()) await part.delete();
          } catch (_) {}
          if (!await s.file.exists()) {
            done++;
            continue;
          }
          rethrow;
        }
        entries.add(BackupEntry(s.rel, s.bytes));
        doneBytes += s.bytes;
        done++;
      }

      final manifest = {
        'format': 'jedBackup',
        'version': 1,
        'id': id,
        'createdAt': now.toUtc().toIso8601String(),
        'label': label,
        'includesStates': includesStates,
        'files': [
          for (final e in entries) {'p': e.rel, 's': e.bytes},
        ],
      };
      final mf = File('${building.path}/$_manifestName');
      final tmp = File('${mf.path}.tmp');
      await tmp.writeAsString(jsonEncode(manifest), flush: true);
      await tmp.rename(mf.path);
      await building.rename(finalDir.path);
      onProgress?.call(
        BackupProgress(
          done: srcs.length,
          total: srcs.length,
          bytesDone: totalBytes,
          bytesTotal: totalBytes,
          current: '',
        ),
      );
      return BackupInfo(
        id: id,
        dir: finalDir,
        createdAt: now,
        label: label,
        includesStates: includesStates,
        files: entries,
      );
    } catch (e) {
      await cleanup();
      lastError = e is FileSystemException && (e.osError?.errorCode == 28)
          ? 'Not enough free storage for this backup.'
          : 'The backup could not be written.';
      return null;
    }
  }

  // ───────────────────────── List / delete ─────────────────────────

  /// Every complete backup, newest first. Half-built ones are ignored (and cleaned up when stale).
  Future<List<BackupInfo>> list() async {
    await _ensureStorage();
    final out = <BackupInfo>[];
    final root = backupsDir;
    try {
      if (!await root.exists()) return out;
      await for (final e in root.list(followLinks: false)) {
        if (e is! Directory) continue;
        final name = e.path.split(Platform.pathSeparator).last;
        if (name.startsWith('.building-')) {
          try {
            final age = DateTime.now().difference((await e.stat()).modified);
            if (age.inHours >= 1) await e.delete(recursive: true);
          } catch (_) {}
          continue;
        }
        if (name.startsWith('.')) continue;
        final info = await _read(e);
        if (info != null) out.add(info);
      }
    } catch (_) {}
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<BackupInfo?> _read(Directory dir) async {
    try {
      final f = File('${dir.path}/$_manifestName');
      if (!await f.exists()) return null;
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map || raw['format'] != 'jedBackup') return null;
      final files = <BackupEntry>[];
      final list = raw['files'];
      if (list is List) {
        for (final it in list) {
          if (it is! Map) continue;
          final p = '${it['p'] ?? ''}';
          if (!_safeRel(p)) continue;
          files.add(BackupEntry(p, (it['s'] as num?)?.toInt() ?? 0));
        }
      }
      DateTime created;
      try {
        created = DateTime.parse('${raw['createdAt']}').toLocal();
      } catch (_) {
        created = (await dir.stat()).modified;
      }
      return BackupInfo(
        id: '${raw['id'] ?? dir.path.split(Platform.pathSeparator).last}',
        dir: dir,
        createdAt: created,
        label: '${raw['label'] ?? ''}',
        includesStates: raw['includesStates'] == true,
        files: files,
      );
    } catch (_) {
      return null;
    }
  }

  /// Only "saves/..." and "states/..." with no "..", so a hand-edited manifest can never make a
  /// restore write outside those two folders.
  static bool _safeRel(String rel) {
    if (rel.isEmpty || rel.contains('\\') || rel.startsWith('/')) return false;
    final segs = rel.split('/');
    if (segs.length < 2) return false;
    if (segs.first != 'saves' && segs.first != 'states') return false;
    return !segs.any((s) => s.isEmpty || s == '.' || s == '..');
  }

  Future<bool> delete(BackupInfo b) async {
    try {
      if (await b.dir.exists()) await b.dir.delete(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int> totalBytes() async {
    var t = 0;
    for (final b in await list()) {
      t += b.bytes;
    }
    return t;
  }

  // ───────────────────────── Restore ─────────────────────────

  /// Puts the files of [b] back. [onlyGame] restores just the files of that ROM name. Anything that
  /// is about to be replaced is first copied into a "Before restore" backup (when [safetyCopy]).
  Future<RestoreResult> restore(
    BackupInfo b, {
    String? onlyGame,
    bool safetyCopy = true,
    BackupProgressCallback? onProgress,
  }) async {
    await _ensureStorage();
    _cancel = false;
    lastError = null;
    final result = RestoreResult();
    final root = StorageService.instance.rootDir;

    final wanted = onlyGame == null ? b.files : b.entriesFor(onlyGame);

    // 1) Safety copy of what will be replaced.
    if (safetyCopy) {
      final existing = <_Src>[];
      var hasStates = false;
      for (final e in wanted) {
        final cur = File('${root.path}/${e.rel}');
        try {
          if (await cur.exists()) {
            final len = await cur.length();
            if (len > 0) {
              existing.add(_Src(cur, e.rel, len));
              if (e.isState) hasStates = true;
            }
          }
        } catch (_) {}
      }
      if (existing.isNotEmpty) {
        result.safetyCopy = await _write(
          existing,
          label: safetyLabel,
          includesStates: hasStates,
        );
        if (result.safetyCopy == null) {
          // Never overwrite files we could not keep a copy of.
          lastError = 'Could not make a safety copy first. ${lastError ?? ''}'
              .trim();
          result.cancelled = _cancel;
          return result;
        }
        await _pruneSafetyCopies();
      }
    }

    // 2) Copy the backed up files back.
    final totalBytes = wanted.fold<int>(0, (a, e) => a + e.bytes);
    var doneBytes = 0;
    var done = 0;
    for (final e in wanted) {
      if (_cancel) {
        result.cancelled = true;
        break;
      }
      onProgress?.call(
        BackupProgress(
          done: done,
          total: wanted.length,
          bytesDone: doneBytes,
          bytesTotal: totalBytes,
          current: e.rel,
        ),
      );
      final src = File('${b.dir.path}/${e.rel}');
      final dst = File('${root.path}/${e.rel}');
      try {
        if (!await src.exists()) {
          result.missing++;
        } else {
          await dst.parent.create(recursive: true);
          final part = File('${dst.path}.cp');
          try {
            await src.copy(part.path);
            await part.rename(dst.path);
            result.restored++;
          } catch (_) {
            try {
              if (await part.exists()) await part.delete();
            } catch (_) {}
            result.failed++;
          }
        }
      } catch (_) {
        result.failed++;
      }
      doneBytes += e.bytes;
      done++;
    }
    onProgress?.call(
      BackupProgress(
        done: done,
        total: wanted.length,
        bytesDone: totalBytes,
        bytesTotal: totalBytes,
        current: '',
      ),
    );
    return result;
  }

  Future<void> _pruneSafetyCopies() async {
    try {
      final safety = (await list()).where((b) => b.isSafetyCopy).toList();
      for (var i = _keepSafetyCopies; i < safety.length; i++) {
        await delete(safety[i]);
      }
    } catch (_) {}
  }
}
