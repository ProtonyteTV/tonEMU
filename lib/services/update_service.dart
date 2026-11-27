// lib/services/update_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/about_screen.dart' show kAppVersion;
import 'changelog.dart' show compareVersions;
import 'emulator_bridge.dart';

/// false (build with --dart-define=IN_APP_UPDATES=false) for the Google Play build: Play does
/// not allow an app to update itself, so there the sheet only opens the release page.
const bool kInAppUpdates = bool.fromEnvironment(
  'IN_APP_UPDATES',
  defaultValue: true,
);

const String kReleasesPage = 'https://github.com/ProtonyteTV/tonEMU/releases';
const String _apiUrl =
    'https://api.github.com/repos/ProtonyteTV/tonEMU/releases?per_page=10';

/// A newer release found on GitHub.
class UpdateInfo {
  final String version; // "27.1"
  final String tag; // as published, e.g. "v27.1"
  final String notes; // release body (markdown)
  final String pageUrl;
  final String? apkUrl;
  final String? apkName;
  final int apkSize; // bytes, 0 when unknown
  final String? sha256; // from GitHub's asset digest, when published
  const UpdateInfo({
    required this.version,
    required this.tag,
    required this.notes,
    required this.pageUrl,
    this.apkUrl,
    this.apkName,
    this.apkSize = 0,
    this.sha256,
  });
}

enum UpdateCheck { newer, upToDate, failed }

class UpdateResult {
  final UpdateCheck status;
  final UpdateInfo? info;
  final String? error;
  const UpdateResult(this.status, {this.info, this.error});
}

/// Looks at the GitHub releases of tonEMU, downloads the APK and hands it to Android's installer.
///
/// DEBUGGING: logs use the tag "tonEmuUpdate" (`adb logcat -s flutter | grep tonEmuUpdate`, native
/// side: `adb logcat -s tonEmuUpdate`). To test without a real newer release, run
/// `flutter run --dart-define=UPDATE_TEST_VERSION=99.0` : the app then pretends it is that
/// version string "installed" instead of [kAppVersion] for the comparison only (use a LOWER one,
/// e.g. 1.0, to make the real latest release count as "newer").
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const _autoKey = 'update_auto_check';
  static const _lastCheckKey = 'update_last_check_ms';
  static const _skipKey = 'update_skipped_version';
  static const _testVersion = String.fromEnvironment('UPDATE_TEST_VERSION');
  static const _autoEvery = Duration(
    hours: 12,
  ); // GitHub allows 60 anonymous calls / hour

  static const MethodChannel _ch = MethodChannel(
    'com.jedplatforms.jedEmu/core',
  );

  static void _log(String m) => debugPrint('tonEmuUpdate: $m');

  String get installedVersion =>
      _testVersion.isEmpty ? kAppVersion : _testVersion;

  /// Download progress 0..1 while [download] runs, null otherwise.
  final ValueNotifier<double?> progress = ValueNotifier<double?>(null);
  bool _cancel = false;

  Future<bool> autoCheckEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_autoKey) ?? true;

  Future<void> setAutoCheck(bool on) async =>
      (await SharedPreferences.getInstance()).setBool(_autoKey, on);

  /// Everything that decides what the update feature does, for logs / the debug rows in About.
  Future<Map<String, Object?>> debugState() async {
    final p = await SharedPreferences.getInstance();
    final last = p.getInt(_lastCheckKey);
    return {
      'installed': installedVersion,
      'realVersion': kAppVersion,
      'inAppUpdates': kInAppUpdates,
      'autoCheck': p.getBool(_autoKey) ?? true,
      'lastCheck': last == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(last).toIso8601String(),
      'skipped': p.getString(_skipKey),
      'canInstall': await canInstall(),
    };
  }

  /// Debug: forget the 12 h throttle and any skipped version, and delete a downloaded APK.
  Future<void> debugReset() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_lastCheckKey);
    await p.remove(_skipKey);
    try {
      await _ch.invokeMethod<bool>('cleanupUpdates');
    } catch (_) {}
    _log('debug reset: throttle + skip cleared, cache cleaned');
  }

  Future<void> skipVersion(String v) async =>
      (await SharedPreferences.getInstance()).setString(_skipKey, v);

  /// Silent check for app start: respects the setting, the 12 h throttle and "skip this version".
  /// Returns the update to offer, or null.
  Future<UpdateInfo?> autoCheck() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!(p.getBool(_autoKey) ?? true)) {
        _log('auto check is off');
        return null;
      }
      final last = p.getInt(_lastCheckKey) ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - last;
      if (age >= 0 && age < _autoEvery.inMilliseconds) {
        _log('auto check skipped: last check ${age ~/ 60000} min ago');
        return null;
      }
      final r = await check();
      if (r.status != UpdateCheck.newer) return null;
      if (p.getString(_skipKey) == r.info!.version) {
        _log('v${r.info!.version} was skipped by the user');
        return null;
      }
      return r.info;
    } catch (e, st) {
      _log('autoCheck failed: $e\n$st');
      return null;
    }
  }

  /// Asks GitHub for the newest published (non-draft) release. Never throws.
  Future<UpdateResult> check() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..userAgent = 'tonEMU/$kAppVersion (Flutter)';
    try {
      final req = await client
          .getUrl(Uri.parse(_apiUrl))
          .timeout(const Duration(seconds: 15));
      req.headers.set('Accept', 'application/vnd.github+json');
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        await res.drain<void>();
        final msg = res.statusCode == 403 || res.statusCode == 429
            ? 'GitHub is limiting requests right now. Try again later.'
            : 'GitHub answered ${res.statusCode}.';
        _log('check failed: HTTP ${res.statusCode}');
        return UpdateResult(UpdateCheck.failed, error: msg);
      }
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 20));
      (await SharedPreferences.getInstance()).setInt(
        _lastCheckKey,
        DateTime.now().millisecondsSinceEpoch,
      );

      final list = jsonDecode(body) as List<dynamic>;
      UpdateInfo? best;
      for (final r in list) {
        if (r is! Map || r['draft'] == true) continue;
        final tag = (r['tag_name'] ?? '').toString();
        final v = RegExp(r'\d+(\.\d+)*').firstMatch(tag)?.group(0);
        if (v == null) continue;
        if (best != null && compareVersions(v, best.version) <= 0) continue;
        best = _parse(r, tag, v);
      }
      if (best == null) {
        _log('no usable release found');
        return const UpdateResult(
          UpdateCheck.failed,
          error: 'No release found.',
        );
      }
      final newer = compareVersions(best.version, installedVersion) > 0;
      _log(
        'installed=$installedVersion latest=${best.version} newer=$newer apk=${best.apkName} sha=${best.sha256 != null}',
      );
      return newer
          ? UpdateResult(UpdateCheck.newer, info: best)
          : const UpdateResult(UpdateCheck.upToDate);
    } on TimeoutException {
      _log('check timed out');
      return const UpdateResult(
        UpdateCheck.failed,
        error: 'The connection timed out.',
      );
    } on SocketException catch (e) {
      _log('check offline: $e');
      return const UpdateResult(
        UpdateCheck.failed,
        error: 'No internet connection.',
      );
    } catch (e, st) {
      _log('check failed: $e\n$st');
      return UpdateResult(
        UpdateCheck.failed,
        error: 'Could not read the release information.',
      );
    } finally {
      client.close(force: true);
    }
  }

  UpdateInfo _parse(Map r, String tag, String version) {
    Map? apk;
    final assets = (r['assets'] as List?) ?? const [];
    for (final a in assets) {
      if (a is! Map) continue;
      final name = (a['name'] ?? '').toString().toLowerCase();
      if (!name.endsWith('.apk')) continue;
      // Prefer an arm64 build when several are attached (tonEMU is arm64-only anyway).
      if (apk == null || name.contains('arm64') || name.contains('universal'))
        apk = a;
    }
    String? sha;
    final digest = apk?['digest']?.toString();
    if (digest != null && digest.startsWith('sha256:'))
      sha = digest.substring(7);
    final url = apk?['browser_download_url']?.toString();
    final okUrl =
        url != null &&
        Uri.tryParse(url)?.scheme == 'https' &&
        Uri.parse(url).host == 'github.com';
    return UpdateInfo(
      version: version,
      tag: tag,
      notes: (r['body'] ?? '').toString().trim(),
      pageUrl: (r['html_url'] ?? kReleasesPage).toString(),
      apkUrl: okUrl ? url : null,
      apkName: apk?['name']?.toString(),
      apkSize: (apk?['size'] as num?)?.toInt() ?? 0,
      sha256: sha,
    );
  }

  void cancelDownload() => _cancel = true;

  /// Downloads the APK into the app cache. Returns the file, or null (see [lastError]).
  String? lastError;
  Future<File?> download(UpdateInfo u) async {
    lastError = null;
    if (u.apkUrl == null) {
      lastError = 'This release has no APK file attached.';
      return null;
    }
    _cancel = false;
    progress.value = 0;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = 'tonEMU/$kAppVersion (Flutter)';
    File? part;
    try {
      final cache =
          await getTemporaryDirectory(); // == context.cacheDir on Android
      final dir = Directory('${cache.path}/updates');
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      final name = (u.apkName ?? 'tonEMU-${u.version}.apk').replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );
      final out = File('${dir.path}/$name');
      part = File('${out.path}.part');

      final req = await client.getUrl(Uri.parse(u.apkUrl!));
      final res = await req.close(); // follows GitHub's redirect to its CDN
      if (res.statusCode != 200) {
        await res.drain<void>();
        lastError = 'Download failed (HTTP ${res.statusCode}).';
        _log(lastError!);
        return null;
      }
      final total = res.contentLength > 0 ? res.contentLength : u.apkSize;
      final sink = part.openWrite();
      var got = 0;
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 30))) {
          if (_cancel) throw const _Cancelled();
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) progress.value = (got / total).clamp(0.0, 1.0);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (u.apkSize > 0 && got != u.apkSize) {
        lastError = 'The download was incomplete. Please try again.';
        _log('size mismatch: got $got expected ${u.apkSize}');
        await part.delete();
        return null;
      }
      await part.rename(out.path);
      _log('downloaded ${out.path} ($got bytes)');
      return out;
    } on _Cancelled {
      lastError = null;
      _log('download cancelled');
      try {
        await part?.delete();
      } catch (_) {}
      return null;
    } on TimeoutException {
      lastError = 'The download stalled. Check your connection and try again.';
      _log(lastError!);
      return null;
    } on SocketException catch (e) {
      lastError = 'No internet connection.';
      _log('download offline: $e');
      return null;
    } on FileSystemException catch (e) {
      lastError = 'Not enough free space to download the update.';
      _log('download file error: $e');
      return null;
    } catch (e, st) {
      lastError = 'The download failed.';
      _log('download failed: $e\n$st');
      return null;
    } finally {
      progress.value = null;
      client.close(force: true);
    }
  }

  Future<bool> canInstall() async {
    try {
      return (await _ch.invokeMethod<bool>('canInstallApks')) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openInstallSettings() async {
    try {
      return (await _ch.invokeMethod<bool>('openInstallSettings')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens Android's installer for [apk]. Returns "ok" or a code (permission, hash, wrongapp, ...).
  Future<String> install(File apk, String? sha256) async {
    try {
      final r = await _ch.invokeMethod<String>('installApk', {
        'path': apk.path,
        'sha256': sha256,
      });
      _log('install -> $r');
      return r ?? 'error';
    } catch (e) {
      _log('install channel error: $e');
      return 'error';
    }
  }

  static String installError(String code) => switch (code) {
    'hash' => 'The downloaded file does not match the published checksum, so it was not installed.',
    'wrongapp' => 'That file is not a tonEMU update.',
    'permission' => 'Allow tonEMU to install updates first.',
    'nohandler' => 'No package installer was found on this phone.',
    _ => 'The update could not be opened.',
  };

  Future<void> openReleasePage([UpdateInfo? u]) =>
      EmulatorBridge.openUrl(u?.pageUrl ?? kReleasesPage);
}

class _Cancelled implements Exception {
  const _Cancelled();
}
