// lib/services/import_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../models/console_system.dart';

/// What an import run did, shown to the user and sent back to the browser.
class ImportSummary {
  final List<String> imported = [];
  final List<String> ignored = [];
  final List<String> warnings = [];
  int duplicates = 0;

  int get total => imported.length;
  bool get isEmpty => total == 0 && duplicates == 0 && ignored.isEmpty;

  Map<String, dynamic> toJson() => {
    'imported': imported,
    'ignored': ignored.take(12).toList(),
    'ignoredCount': ignored.length,
    'warnings': warnings,
    'duplicates': duplicates,
  };
}

/// Thrown from inside a copy when the user pressed Cancel.
class ImportCancelled implements Exception {
  const ImportCancelled();
  @override
  String toString() => 'Import cancelled';
}

/// "12.3 MB", "1.45 GB" ...
String fmtBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// "about 40 s left", "3 min left", "1 h 5 min left"
String fmtEta(Duration d) {
  final s = d.inSeconds;
  if (s < 5) return 'almost done';
  if (s < 60) return '${(s / 5).ceil() * 5} s left';
  if (s < 3600) return '${(s / 60).ceil()} min left';
  return '${d.inHours} h ${d.inMinutes % 60} min left';
}

/// Smoothed bytes-per-second from a growing byte counter. Samples at most every 500 ms.
class SpeedMeter {
  int _lastBytes = 0;
  int _lastMs = 0;
  double bps = 0;

  double add(int totalBytes) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastMs == 0) {
      _lastMs = now;
      _lastBytes = totalBytes;
      return bps;
    }
    final dt = now - _lastMs;
    if (dt < 500) return bps;
    final inst = (totalBytes - _lastBytes) * 1000 / dt;
    bps = bps == 0 ? inst : bps * 0.7 + inst * 0.3;
    _lastMs = now;
    _lastBytes = totalBytes;
    return bps;
  }

  void reset() {
    _lastBytes = 0;
    _lastMs = 0;
    bps = 0;
  }
}

enum ImportPhase { preparing, scanning, copying, checking, finishing }

/// Live state of one local import (Game Files / Folder). [ImportCopier.put] feeds it while it
/// copies, and the progress card listens to it. Notifications are throttled to ~10 per second.
class ImportProgress extends ChangeNotifier {
  ImportPhase phase = ImportPhase.preparing;
  int totalFiles = 0;
  int doneFiles = 0;
  int totalBytes = 0;
  int scanned = 0;
  String currentName = '';
  bool cancelled = false;

  int _doneBytes = 0;
  int _currentBytes = 0;
  int _currentTotal = 0;
  int _lastNotifyMs = 0;
  bool _disposed = false;
  final SpeedMeter _meter = SpeedMeter();

  int get bytesDone => _doneBytes + _currentBytes;
  double get bytesPerSecond => _meter.bps;

  /// 0..1, or null while the amount of work is not known yet (moving bar).
  double? get fraction {
    if (phase == ImportPhase.preparing ||
        phase == ImportPhase.scanning ||
        phase == ImportPhase.finishing) {
      return null;
    }
    if (totalBytes > 0) return (bytesDone / totalBytes).clamp(0.0, 1.0);
    if (totalFiles > 0) return (doneFiles / totalFiles).clamp(0.0, 1.0);
    return null;
  }

  Duration? get eta {
    final left = totalBytes - bytesDone;
    final bps = _meter.bps;
    if (phase != ImportPhase.copying || bps < 1 || left <= 0) return null;
    return Duration(seconds: (left / bps).ceil());
  }

  void reset() {
    phase = ImportPhase.preparing;
    totalFiles = doneFiles = totalBytes = scanned = 0;
    _doneBytes = _currentBytes = _currentTotal = 0;
    currentName = '';
    cancelled = false;
    _meter.reset();
    _tick(force: true);
  }

  void setPhase(ImportPhase p) {
    if (phase == p) return;
    phase = p;
    _tick(force: true);
  }

  void noteScanned(int n) {
    scanned = n;
    _tick();
  }

  void beginCopy({required int files, required int bytes}) {
    totalFiles = files;
    totalBytes = bytes;
    phase = ImportPhase.copying;
    _tick(force: true);
  }

  void startFile(String name, int size) {
    currentName = name;
    _currentTotal = size;
    _currentBytes = 0;
    _tick(force: true);
  }

  void fileBytes(int copied) {
    _currentBytes = copied;
    _meter.add(bytesDone);
    _tick();
  }

  void endFile() {
    _doneBytes += _currentTotal;
    _currentBytes = 0;
    _currentTotal = 0;
    doneFiles++;
    _meter.add(bytesDone);
    _tick(force: true);
  }

  void cancel() {
    cancelled = true;
    _tick(force: true);
  }

  void _tick({bool force = false}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastNotifyMs < 100) return;
    _lastNotifyMs = now;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

enum CopyOutcome { copied, duplicate }

class CopyResult {
  final CopyOutcome outcome;
  final String
  name; // final file name in the library (can differ from the source name)
  const CopyResult(this.outcome, this.name);
}

/// Puts files into the library without ever overwriting a different file and without ever
/// leaving a half-written one behind:
///  - a file is written under a temporary name outside the library and renamed at the end, so a
///    killed app leaves nothing partial in the game list;
///  - if the name is taken by a DIFFERENT file it gets "(2)", "(3)"... and the .cue sheets of the
///    same import are rewritten to point at the renamed track files;
///  - a file counts as a duplicate only when its contents match, not just its size.
class ImportCopier {
  ImportCopier(this.dest);
  final Directory dest;

  final Map<String, String> _finalNames =
      {}; // lower-case source path -> name in library
  final List<({String srcDir, File out})> _cues = [];
  int _seq = 0;

  Directory get _tmpDir => Directory('${dest.parent.path}/.import_tmp');

  /// Call once before the first [put]: makes sure the library exists and clears leftovers.
  Future<void> begin() async {
    try {
      if (await _tmpDir.exists()) await _tmpDir.delete(recursive: true);
    } catch (_) {}
    await dest.create(recursive: true);
  }

  static String _numbered(String name, int i) {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    return '$stem ($i)$ext';
  }

  /// [move] renames the source into the library (used for staged Wi-Fi uploads).
  /// [progress] receives byte-level progress and lets the user cancel (throws [ImportCancelled]).
  Future<CopyResult> put(
    File src,
    String name, {
    bool move = false,
    ImportProgress? progress,
  }) async {
    final srcDir = src.parent.path;
    final srcKey = src.path.toLowerCase();
    String? chosen;
    for (var i = 1; i < 1000; i++) {
      final cand = i == 1 ? name : _numbered(name, i);
      final f = File('${dest.path}/$cand');
      if (!await f.exists()) {
        chosen = cand;
        break;
      }
      progress?.setPhase(ImportPhase.checking);
      final same = await ImportService.sameContent(src, f);
      progress?.setPhase(ImportPhase.copying);
      if (same) {
        _finalNames[srcKey] = cand;
        if (move) {
          try {
            await src.delete();
          } catch (_) {}
        }
        return CopyResult(CopyOutcome.duplicate, cand);
      }
    }
    chosen ??= _numbered(name, DateTime.now().millisecondsSinceEpoch);

    await _tmpDir.create(recursive: true);
    // Short, unique temp name: a file name near the 255-byte limit plus a prefix would fail to
    // be created at all.
    final tmp = File(
      '${_tmpDir.path}/${DateTime.now().microsecondsSinceEpoch}_${_seq++}.tmp',
    );
    final target = File('${dest.path}/$chosen');
    try {
      final expected = await src.length();
      if (move) {
        try {
          await src.rename(tmp.path);
        } catch (_) {
          await src.copy(tmp.path);
        }
      } else if (progress != null) {
        await _copyStreamed(src, tmp, progress);
      } else {
        await src.copy(tmp.path);
      }
      if (await tmp.length() != expected) {
        throw const FileSystemException('Copy was cut short');
      }
      await tmp.rename(target.path);
      if (move && await src.exists()) {
        try {
          await src.delete();
        } catch (_) {}
      }
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
    _finalNames[srcKey] = chosen;
    if (chosen.toLowerCase().endsWith('.cue')) {
      _cues.add((srcDir: srcDir, out: target));
    }
    return CopyResult(CopyOutcome.copied, chosen);
  }

  static const int _chunk = 1 << 20; // 1 MiB

  /// Copies in 1 MiB blocks so the UI can show real byte progress and the user can cancel.
  Future<void> _copyStreamed(File src, File tmp, ImportProgress p) async {
    final input = await src.open();
    final out = await tmp.open(mode: FileMode.write);
    try {
      var copied = 0;
      while (true) {
        if (p.cancelled) throw const ImportCancelled();
        final block = await input.read(_chunk);
        if (block.isEmpty) break;
        await out.writeFrom(block);
        copied += block.length;
        p.fileBytes(copied);
      }
      await out.flush();
    } finally {
      await input.close();
      await out.close();
    }
  }

  /// Call after the last [put]: points copied .cue sheets at renamed track files, cleans up.
  Future<void> finish() async {
    for (final c in _cues) {
      try {
        var text = utf8.decode(await c.out.readAsBytes(), allowMalformed: true);
        var changed = false;
        final renames =
            <String, String>{}; // old track name (lower-case) -> new name
        for (final t in ImportService.cueTracks(c.out)) {
          final now = _finalNames['${c.srcDir}/$t'.toLowerCase()];
          if (now != null && now != t) renames[t.toLowerCase()] = now;
        }
        if (renames.isNotEmpty) {
          // Only the file name inside FILE lines is rewritten, never other text in the sheet
          // (renaming a.bin must not touch data.bin).
          final fileLine = RegExp(
            r'^(\s*FILE\s+)(?:"([^"]+)"|(\S+))',
            multiLine: true,
            caseSensitive: false,
          );
          text = text.replaceAllMapped(fileLine, (m) {
            final quoted = m.group(2) != null;
            final full = (m.group(2) ?? m.group(3)!).replaceAll('\\', '/');
            final slash = full.lastIndexOf('/');
            final now = renames[full.substring(slash + 1).toLowerCase()];
            if (now == null) return m[0]!;
            changed = true;
            final name = '${full.substring(0, slash + 1)}$now';
            return '${m.group(1)}${quoted ? '"$name"' : name}';
          });
        }
        if (changed) await c.out.writeAsString(text);
      } catch (_) {}
    }
    _cues.clear();
    try {
      if (await _tmpDir.exists()) await _tmpDir.delete(recursive: true);
    } catch (_) {}
  }
}

/// Everything about turning loose files / folders into library entries. Used by the in-app
/// pickers and by the Wi-Fi transfer, so both behave exactly the same.
class ImportService {
  ImportService._();

  static String baseName(String path) {
    final p = path.replaceAll('\\', '/');
    final i = p.lastIndexOf('/');
    return i < 0 ? p : p.substring(i + 1);
  }

  // ───────── .cue sheets ─────────

  /// Track files a .cue sheet points to (FILE "name.bin" BINARY), as bare file names.
  /// Redump-style sheets use names like "Game (Track 01).bin", not "Game.bin".
  static List<String> cueTracks(File cue) {
    try {
      // Cue sheets are often UTF-8 (accented game names); decoding as Latin-1 broke the track match.
      final text = utf8.decode(cue.readAsBytesSync(), allowMalformed: true);
      final re = RegExp(
        r'^\s*FILE\s+(?:"([^"]+)"|(\S+))',
        multiLine: true,
        caseSensitive: false,
      );
      return [
        for (final m in re.allMatches(text))
          baseName(m.group(1) ?? m.group(2)!),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Companion files of a .gdi (track01.bin, track02.raw...), .ccd (.img/.sub) or .mds (.mdf),
  /// as bare file names. These have no system of their own and must travel with the game.
  static List<String> discCompanions(File f) {
    final lower = f.path.toLowerCase();
    final base = baseName(f.path);
    final dot = base.lastIndexOf('.');
    final stem = dot > 0 ? base.substring(0, dot) : base;
    try {
      if (lower.endsWith('.gdi')) {
        final text = utf8.decode(f.readAsBytesSync(), allowMalformed: true);
        // "<track> <lba> <type> <sector size> <file> <offset>", file may be quoted.
        final re = RegExp(
          // [ \t] instead of \s: \s ran across the newline after the track-count header line,
          // so the first match was "2352" and track01.bin was never listed (nor imported).
          r'^[ \t]*\d+[ \t]+\d+[ \t]+\d+[ \t]+\d+[ \t]+(?:"([^"]+)"|(\S+))',
          multiLine: true,
        );
        return [
          for (final m in re.allMatches(text))
            baseName(m.group(1) ?? m.group(2)!),
        ];
      }
      if (lower.endsWith('.ccd')) return ['$stem.img', '$stem.sub'];
      if (lower.endsWith('.mds')) return ['$stem.mdf'];
    } catch (_) {}
    return const [];
  }

  /// Lower-case paths of every file referenced by a .cue/.gdi/.ccd/.mds in [files].
  static Set<String> cueReferenced(Iterable<File> files) {
    final out = <String>{};
    for (final f in files) {
      final lower = f.path.toLowerCase();
      final dir = f.parent.path;
      if (lower.endsWith('.cue')) {
        for (final t in cueTracks(f)) {
          out.add('$dir/$t'.toLowerCase());
        }
      } else if (lower.endsWith('.gdi') ||
          lower.endsWith('.ccd') ||
          lower.endsWith('.mds')) {
        for (final t in discCompanions(f)) {
          out.add('$dir/$t'.toLowerCase());
        }
      }
    }
    return out;
  }

  // ───────── file helpers ─────────

  /// Same size AND same bytes at the start, middle and end (cheap enough for multi-GB images).
  static Future<bool> sameContent(File a, File b) async {
    try {
      final la = await a.length();
      if (la != await b.length()) return false;
      if (la == 0) return true;
      // Same size and name is not enough: a patched or translated ROM differs only in a few
      // places. Compare every byte (in blocks), stopping at the first difference.
      const n = 1 << 20;
      final ra = await a.open();
      final rb = await b.open();
      try {
        while (true) {
          final x = await ra.read(n);
          final y = await rb.read(n);
          if (x.length != y.length) return false;
          if (x.isEmpty) return true;
          for (var i = 0; i < x.length; i++) {
            if (x[i] != y[i]) return false;
          }
        }
      } finally {
        await ra.close();
        await rb.close();
      }
    } catch (_) {
      return false;
    }
  }

  static Future<void> _moveFile(File src, File dest) async {
    try {
      await src.rename(dest.path);
    } catch (_) {
      await src.copy(dest.path);
      await src.delete();
    }
  }

  // ───────── staged import (Wi-Fi) ─────────

  /// Sorts everything uploaded into [staging] into [romsDir]: .cue tracks stay
  /// with their sheet, supported files are moved in flat, anything else is reported as
  /// ignored. [staging] is emptied afterwards.
  static Future<ImportSummary> organize(
    Directory staging,
    Directory romsDir,
  ) async {
    final s = ImportSummary();
    if (!await staging.exists()) return s;
    await romsDir.create(recursive: true);

    // 1. loose files
    final files = <File>[];
    await for (final e in staging.list(recursive: true, followLinks: false)) {
      if (e is File && !e.path.endsWith('.part')) files.add(e);
    }
    final referenced = cueReferenced(files);
    final movedCues = <String>[];
    final copier = ImportCopier(romsDir);
    await copier.begin();
    for (final f in files) {
      final name = baseName(f.path);
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
      final isTrack = referenced.contains(f.path.toLowerCase());
      if (!isTrack) {
        if (ConsoleSystem.fromExtension(ext) == null) {
          s.ignored.add(name);
          continue;
        }
        if (ext == 'bin') {
          s.ignored.add('$name (no .cue sheet uses it)');
          continue;
        }
      }
      try {
        final r = await copier.put(f, name, move: true);
        if (r.outcome == CopyOutcome.duplicate) {
          s.duplicates++;
          continue;
        }
        if (ext == 'cue') movedCues.add(r.name);
        if (!isTrack) s.imported.add(r.name);
      } catch (_) {
        s.warnings.add('Could not store $name');
      }
    }
    await copier.finish();

    // 2. every .cue needs its track files
    for (final cueName in movedCues) {
      final cue = File('${romsDir.path}/$cueName');
      final missing = [
        for (final t in cueTracks(cue))
          if (!File('${romsDir.path}/$t').existsSync()) t,
      ];
      if (missing.isNotEmpty) {
        s.warnings.add(
          '$cueName is missing ${missing.take(2).join(', ')}'
          '${missing.length > 2 ? '…' : ''}. Send the .bin files with it.',
        );
      }
    }

    // 3. clean up
    try {
      await staging.delete(recursive: true);
    } catch (_) {}
    return s;
  }
}
