// lib/services/onboarding_service.dart
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/about_screen.dart' show kAppVersion;
import '../screens/setup_screen.dart';
import '../widgets/whats_new_sheet.dart';
import 'changelog.dart';

/// Decides what the player sees at launch:
///  - brand-new install  -> the setup screen (once), then no "What's new" for this version
///  - updated install    -> the "What's new" sheet (once per version)
///  - same version       -> nothing
///
/// DEBUGGING (all logs use the tag "tonEmuOnboarding": `adb logcat -s flutter | grep tonEmuOnboarding`)
///  - Force a path at launch, even in a release build:
///      flutter run --dart-define=ONBOARDING=setup      always show the setup screen
///      flutter run --dart-define=ONBOARDING=whatsnew   always show the What's new sheet
///      flutter run --dart-define=ONBOARDING=off        never show either
///    (forced runs never write the "seen" flags, so they repeat on every launch.)
///  - About screen, debug builds only: "Replay setup", "Show What's new" and "Reset onboarding".
///  - [debugState] returns the stored flags for a log line or a debug screen.
class OnboardingService {
  OnboardingService._();
  static final OnboardingService instance = OnboardingService._();

  static const _doneKey = 'setup_done';
  static const _seenKey = 'last_seen_version';
  static const _force = String.fromEnvironment('ONBOARDING');

  bool _fresh = false;
  bool _ranThisSession = false;

  static void _log(String m) => debugPrint('tonEmuOnboarding: $m');

  /// Call FIRST in main(), before any other service writes to SharedPreferences: an empty
  /// store means the app was never opened before. Players who update from a build without
  /// this feature already have saved settings, so they get "What's new", not the setup.
  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _fresh = !p.containsKey(_doneKey) && p.getKeys().isEmpty;
      _log(
        'load: fresh=$_fresh keys=${p.getKeys().length} '
        'seen=${p.getString(_seenKey)} done=${p.getBool(_doneKey)} '
        'version=$kAppVersion force="${_force.isEmpty ? '-' : _force}"',
      );
    } catch (e, st) {
      _fresh = false; // when in doubt, never trap the player in a setup screen
      _log('load failed: $e\n$st');
    }
  }

  /// Stored flags, for logs / a debug screen.
  Future<Map<String, Object?>> debugState() async {
    final p = await SharedPreferences.getInstance();
    return {
      'freshThisLaunch': _fresh,
      _doneKey: p.getBool(_doneKey),
      _seenKey: p.getString(_seenKey),
      'appVersion': kAppVersion,
      'force': _force.isEmpty ? null : _force,
    };
  }

  /// Show from the library once it is on screen. Safe to call more than once. Never throws:
  /// a problem here must not stop the library from working.
  Future<void> maybeShow(BuildContext context) async {
    if (_ranThisSession) return;
    _ranThisSession = true;
    try {
      await _maybeShow(context);
    } catch (e, st) {
      _log('maybeShow failed: $e\n$st');
    }
  }

  Future<void> _maybeShow(BuildContext context) async {
    if (_force == 'off') {
      _log('forced off: nothing shown');
      return;
    }
    if (_force == 'setup') {
      _log('forced: setup');
      await _runSetup(context);
      return;
    }
    if (_force == 'whatsnew') {
      _log('forced: whatsnew');
      await showCurrent(context);
      return;
    }

    final p = await SharedPreferences.getInstance();
    if (!context.mounted) return;

    if (_fresh) {
      _log('fresh install: showing setup');
      await _runSetup(context);
      await p.setBool(_doneKey, true);
      await p.setString(_seenKey, kAppVersion);
      _fresh = false;
      _log('setup finished; seen=$kAppVersion');
      return;
    }

    final seen = p.getString(_seenKey);
    if (seen != null && compareVersions(seen, kAppVersion) >= 0) {
      _log('up to date (seen=$seen): nothing to show');
      return;
    }
    final entries = changelogSince(seen, kAppVersion);
    // Record first: a crash or a swipe-away must not make the sheet reappear forever.
    await p.setString(_seenKey, kAppVersion);
    _log(
      'update from ${seen ?? 'unknown'}: ${entries.length} changelog entries',
    );
    if (entries.isEmpty || !context.mounted) return;
    await showWhatsNew(context, entries);
  }

  Future<void> _runSetup(BuildContext context) => Navigator.of(context).push(
    CupertinoPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const SetupScreen(),
    ),
  );

  /// Manual entry points (About screen).
  Future<void> showCurrent(BuildContext context) =>
      showWhatsNew(context, kChangelog.take(3).toList());

  Future<void> replaySetup(BuildContext context) => _runSetup(context);

  /// Forgets everything: the NEXT cold start behaves like an update from an unknown version
  /// (What's new). Clear the app data for a true fresh install.
  Future<void> reset() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_doneKey);
    await p.remove(_seenKey);
    _log('reset: flags removed');
  }
}
