// lib/services/jed_time_machine.dart
import 'dart:io';

import 'emulator_bridge.dart';
import 'storage_service.dart';

/// One recorded moment: a save state plus a small picture of what was on screen.
class JedTimeMachineEntry {
  JedTimeMachineEntry({
    required this.state,
    required this.thumb,
    required this.playSec,
    required this.bytes,
  });

  final File state;
  final File thumb;

  /// Seconds of actual play (menu / background time excluded) when this was recorded.
  final int playSec;
  final int bytes;
}

/// Rolling history of the current play session ("jedTimeMachine").
///
/// Every few seconds of play a snapshot is written; the player can later jump back to any of
/// them from the in-game menu. Memory of the past is thinned instead of simply cut off: when
/// there are too many snapshots the one whose neighbours are closest together is dropped, so
/// the last moments stay dense (every interval) while older ones get sparser but reach far back.
///
/// Snapshots live in <states>/.timemachine/<rom>/ and are wiped when a game starts and when it
/// ends: this is a session safety net, not a replacement for save slots.
class JedTimeMachine {
  JedTimeMachine({
    required this.romName,
    this.maxEntries = 12,
    this.maxTotalBytes = 256 << 20,
    this.maxStateBytes = 48 << 20,
  });

  final String romName;
  final int maxEntries;
  final int maxTotalBytes;

  /// A single state bigger than this (PSP, 3DS...) would hitch the game on every snapshot and
  /// fill the storage: the jedTimeMachine switches itself off for that game instead.
  final int maxStateBytes;

  /// Oldest first.
  final List<JedTimeMachineEntry> entries = [];

  /// Set when the jedTimeMachine stopped itself; shown to the player.
  String? disabledReason;
  bool get disabled => disabledReason != null;

  /// Snapshots that failed one after another. A core that cannot save states would otherwise be
  /// asked every few seconds for the whole session.
  static const int _maxFailStreak = 4;
  int _failStreak = 0;

  /// A snapshot that takes long makes the game hitch. After one, the next few ticks are skipped,
  /// so a heavy game gets a sparser history instead of constant stutter.
  static const int _slowMs = 1500;
  int _skipTicks = 0;

  /// How long the last snapshot took, in milliseconds (0 before the first one).
  int lastCaptureMs = 0;

  Directory? _dir;
  bool _busy = false;
  bool _disposed = false;
  int _seq = 0;

  static Directory get _root =>
      Directory('${StorageService.instance.statesDir.path}/.timemachine');

  static String _safe(String s) {
    final t = s.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return t.length > 80 ? t.substring(0, 80) : t;
  }

  /// Wipes leftovers of earlier sessions (only one game runs at a time) and prepares the folder.
  Future<void> init() async {
    try {
      if (await _root.exists()) await _root.delete(recursive: true);
    } catch (_) {}
    final d = Directory('${_root.path}/${_safe(romName)}');
    await d.create(recursive: true);
    _dir = d;
    // Keep gallery apps and media scanners out of the thumbnails.
    try {
      await File('${_root.path}/.nomedia').create();
    } catch (_) {}
  }

  int get totalBytes => entries.fold<int>(0, (a, e) => a + e.bytes);

  /// Records the current moment. Returns true if a snapshot was stored.
  Future<bool> capture(int playSec) async {
    final dir = _dir;
    if (dir == null || _disposed || disabled || _busy) return false;
    if (_skipTicks > 0) {
      _skipTicks--; // easing off after a slow snapshot, not a failure
      return false;
    }
    _busy = true;
    final clock = Stopwatch()..start();
    final id = '${_seq++}';
    final state = File('${dir.path}/$id.state');
    final thumb = File('${dir.path}/$id.jpg');
    try {
      final ok = await EmulatorBridge.saveState(state.path);
      if (_disposed) {
        await _delete(state);
        return false;
      }
      if (!ok || !await state.exists()) {
        await _delete(state);
        await _noteFailure();
        return false;
      }
      final len = await state.length();
      if (len <= 0) {
        await _delete(state);
        await _noteFailure();
        return false;
      }
      if (len > maxStateBytes) {
        await _delete(state);
        disabledReason = 'jedTimeMachine is off for this game: its snapshots are too large for a phone.';
        await _clearEntries();
        return false;
      }
      try {
        await EmulatorBridge.takeScreenshot(
          thumb.path,
          maxWidth: 240,
        ).timeout(const Duration(milliseconds: 900), onTimeout: () => false);
      } catch (_) {}
      entries.add(
        JedTimeMachineEntry(
          state: state,
          thumb: thumb,
          playSec: playSec,
          bytes: len,
        ),
      );
      _failStreak = 0;
      lastCaptureMs = clock.elapsedMilliseconds;
      if (lastCaptureMs > _slowMs) _skipTicks = lastCaptureMs > 4000 ? 3 : 1;
      await _thin();
      return true;
    } catch (_) {
      await _delete(state);
      await _noteFailure();
      return false;
    } finally {
      _busy = false;
    }
  }

  /// Counts a failed snapshot and switches the feature off after a few in a row.
  Future<void> _noteFailure() async {
    _failStreak++;
    if (_failStreak >= _maxFailStreak && !disabled) {
      disabledReason = 'jedTimeMachine is off for this game: its core could not create snapshots.';
      await _clearEntries();
    }
  }

  /// How far back the history reaches, in seconds of play (0 with fewer than two snapshots).
  int get spanSec =>
      entries.length < 2 ? 0 : entries.last.playSec - entries.first.playSec;

  /// Drops snapshots until the history fits: always the one that leaves the smallest hole in
  /// the timeline. The oldest and the newest are never chosen while anything else can go.
  Future<void> _thin() async {
    while (entries.length > maxEntries ||
        (entries.length > 2 && totalBytes > maxTotalBytes)) {
      var drop = 0;
      if (entries.length > 2) {
        var best = 1 << 30;
        for (var i = 1; i < entries.length - 1; i++) {
          final gap = entries[i + 1].playSec - entries[i - 1].playSec;
          if (gap < best) {
            best = gap;
            drop = i;
          }
        }
      }
      final e = entries.removeAt(drop);
      await _delete(e.state);
      await _delete(e.thumb);
    }
  }

  Future<void> _clearEntries() async {
    for (final e in entries) {
      await _delete(e.state);
      await _delete(e.thumb);
    }
    entries.clear();
  }

  static Future<void> _delete(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Ends the session: removes every snapshot.
  Future<void> dispose() async {
    _disposed = true;
    entries.clear();
    try {
      if (await _root.exists()) await _root.delete(recursive: true);
    } catch (_) {}
  }
}
