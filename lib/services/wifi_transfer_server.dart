// lib/services/wifi_transfer_server.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'import_service.dart';
import 'wifi_transfer_page.dart';

/// One address the phone can be reached on, e.g. http://192.168.1.23:8080
class WifiAddress {
  final String interfaceName;
  final String ip;
  const WifiAddress(this.interfaceName, this.ip);
}

/// Small HTTP server that lets a PC browser on the same Wi-Fi send games to the phone.
///
///   GET  /         the upload page
///   POST /upload   raw file body, ?path=<relative path>  -> staged under [stagingDir]
///   POST /finish   sorts the staged files into the library, returns a JSON summary
///
/// Files are only ever written inside [stagingDir] (paths are sanitised), and only supported
/// game files are moved into the library afterwards. The server runs only while the import
/// screen is open.
class WifiTransferServer extends ChangeNotifier {
  WifiTransferServer({required this.romsDir, this.onLibraryChanged});

  final Directory romsDir;
  final VoidCallback? onLibraryChanged;

  Directory get stagingDir => Directory('${romsDir.parent.path}/wifi_incoming');

  HttpServer? _server;
  bool _processing = false;
  bool _disposed = false;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// Random access code, part of the address shown in the app (?k=...). Requests without it are
  /// refused, so other people on the same Wi-Fi cannot push files to the phone.
  String token = '';

  static String _newToken() {
    const chars = 'abcdefghijkmnpqrstuvwxyz23456789';
    final r = Random.secure();
    return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Largest single file accepted (no game is bigger; stops a runaway upload filling the phone).
  static const int maxFileBytes = 8 << 30;

  /// A transfer that sends nothing for this long is dropped.
  static const Duration stallTimeout = Duration(seconds: 60);

  /// Wrong-code requests tolerated per address before it is blocked for [blockFor].
  static const int _maxBadTries = 8;
  static const Duration _badWindow = Duration(minutes: 1);
  static const Duration blockFor = Duration(minutes: 1);
  final Map<String, ({int count, DateTime first, DateTime? until})> _bad = {};

  /// Compares the access code without stopping at the first wrong character, so response time
  /// gives nothing away about how much of a guess was right.
  bool _tokenOk(String? given) {
    if (token.isEmpty || given == null || given.length != token.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < token.length; i++) {
      diff |= token.codeUnitAt(i) ^ given.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// True when [ip] is currently blocked; otherwise records the failure (if [failed]).
  bool _blocked(String ip, {bool failed = false}) {
    final now = DateTime.now();
    var st = _bad[ip];
    if (st?.until != null) {
      if (now.isBefore(st!.until!)) return true;
      _bad.remove(ip);
      st = null;
    }
    if (!failed) return false;
    if (st == null || now.difference(st.first) > _badWindow) {
      _bad[ip] = (count: 1, first: now, until: null);
      return false;
    }
    final c = st.count + 1;
    _bad[ip] = (
      count: c,
      first: st.first,
      until: c >= _maxBadTries ? now.add(blockFor) : null,
    );
    return c >= _maxBadTries;
  }

  bool get running => _server != null;

  /// True while the received files are being sorted into the library.
  bool get processing => _processing;
  int get port => _server?.port ?? 0;
  List<WifiAddress> addresses = const [];
  String? error;

  /// Files currently being received: relative path -> (received, total) bytes.
  final Map<String, ({int received, int total})> active = {};
  int filesReceived = 0;
  int bytesReceived = 0;
  ImportSummary? lastSummary;

  /// Best address first (a typical home / hotspot LAN address).
  List<String> get urls => [
    for (final a in addresses) 'http://${a.ip}:$port/?k=$token',
  ];

  // ───────── lifecycle ─────────

  Future<void> start() async {
    if (_server != null) return;
    error = null;
    token = _newToken();
    lastSummary = null;
    filesReceived = 0;
    bytesReceived = 0;
    active.clear();
    try {
      addresses = await localAddresses();
      if (addresses.isEmpty) {
        error =
            'No Wi-Fi network found. Connect to Wi-Fi or turn on your hotspot.';
        notifyListeners();
        return;
      }
      await _clearStaging();
      HttpServer? server;
      for (final p in [8080, 8081, 8888, 0]) {
        try {
          server = await HttpServer.bind(InternetAddress.anyIPv4, p);
          break;
        } on SocketException {
          continue;
        }
      }
      if (server == null) {
        error = 'Could not open a port for the transfer server.';
        notifyListeners();
        return;
      }
      if (_disposed) {
        // The screen was closed while the port was being opened: don't leave a server running.
        await server.close(force: true);
        return;
      }
      _server = server;
      server.listen(_handle, onError: (_) {});
    } catch (e) {
      error = 'Could not start the transfer server: $e';
    }
    notifyListeners();
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    active.clear();
    try {
      await s?.close(force: true);
    } catch (_) {}
    await _clearStaging();
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final s = _server;
    _server = null;
    s?.close(force: true);
    try {
      stagingDir.deleteSync(recursive: true);
    } catch (_) {}
    super.dispose();
  }

  Future<void> _clearStaging() async {
    try {
      if (await stagingDir.exists()) await stagingDir.delete(recursive: true);
    } catch (_) {}
  }

  /// Throttled so a fast upload doesn't rebuild the UI on every chunk.
  void _tick({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastNotify).inMilliseconds < 200) return;
    _lastNotify = now;
    notifyListeners();
  }

  // ───────── network addresses ─────────

  static bool _isPrivate(String ip) {
    if (ip.startsWith('192.168.') || ip.startsWith('10.')) return true;
    final m = RegExp(r'^172\.(\d+)\.').firstMatch(ip);
    final n = m == null ? 0 : int.parse(m.group(1)!);
    return n >= 16 && n <= 31;
  }

  /// Non-loopback IPv4 addresses on Wi-Fi / hotspot / ethernet, most likely one first.
  static Future<List<WifiAddress>> localAddresses() async {
    final out = <({WifiAddress a, int rank})>[];
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final i in ifaces) {
        final name = i.name.toLowerCase();
        // mobile data / VPN / virtual interfaces can't be reached from a PC
        if (RegExp(r'rmnet|ccmni|dummy|tun|ppp|lo$|v4-|clat').hasMatch(name)) {
          continue;
        }
        for (final addr in i.addresses) {
          if (!_isPrivate(addr.address)) continue;
          final wifi = name.startsWith('wlan') || name.startsWith('swlan');
          final hotspot = name.startsWith('ap') || name.contains('softap');
          final rank = wifi ? 0 : (hotspot ? 1 : 2);
          out.add((a: WifiAddress(i.name, addr.address), rank: rank));
        }
      }
    } catch (_) {}
    out.sort((x, y) => x.rank.compareTo(y.rank));
    return [for (final e in out) e.a];
  }

  // ───────── request handling ─────────

  Future<void> _handle(HttpRequest req) async {
    try {
      final path = req.uri.path;
      final res = req.response;
      // Never let a browser or proxy keep a copy, and never guess the file type.
      res.headers
        ..set('Cache-Control', 'no-store')
        ..set('X-Content-Type-Options', 'nosniff')
        ..set('Referrer-Policy', 'no-referrer');
      final ip = req.connectionInfo?.remoteAddress.address ?? '?';
      if (_blocked(ip)) {
        res.statusCode = HttpStatus.tooManyRequests;
        res.headers.set('Retry-After', '${blockFor.inSeconds}');
        await res.close();
        return;
      }
      if (!_tokenOk(req.uri.queryParameters['k'])) {
        // Browsers ask for /favicon.ico without the code: that is not a guess.
        if (path != '/favicon.ico') _blocked(ip, failed: true);
        req.response.statusCode = HttpStatus.forbidden;
        req.response.headers.contentType = ContentType.text;
        req.response.write('Open the address shown in the tonEMU app.');
        await req.response.close();
        return;
      }
      if (req.method == 'GET' && (path == '/' || path == '/index.html')) {
        req.response.headers.contentType = ContentType.html;
        req.response.write(kWifiTransferPage);
        await req.response.close();
      } else if (req.method == 'POST' && path == '/upload') {
        await _upload(req);
      } else if (req.method == 'POST' && path == '/finish') {
        await _finish(req);
      } else {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      }
    } catch (_) {
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  /// Turns a browser path like "Game/sce_sys/param.sfo" into a safe relative path, or null.
  static String? cleanRelativePath(String raw) {
    final parts = <String>[];
    for (var seg in raw.replaceAll('\\', '/').split('/')) {
      seg = seg.replaceAll(RegExp(r'[\x00-\x1F:*?"<>|]'), '_').trim();
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') return null;
      parts.add(seg);
    }
    if (parts.isEmpty || parts.length > 40) return null;
    return parts.join('/');
  }

  Future<void> _upload(HttpRequest req) async {
    final rel = cleanRelativePath(req.uri.queryParameters['path'] ?? '');
    if (rel == null) {
      req.response.statusCode = HttpStatus.badRequest;
      await req.response.close();
      return;
    }
    if (req.contentLength > maxFileBytes) {
      req.response.statusCode = HttpStatus.requestEntityTooLarge;
      await req.response.close();
      return;
    }
    final target = File('${stagingDir.path}/$rel');
    await target.parent.create(recursive: true);
    // Unique per request: a retried upload must never share a file with the old, still-writing one.
    final part = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.part',
    );
    final total = req.contentLength < 0 ? 0 : req.contentLength;
    var received = 0;
    active[rel] = (received: 0, total: total);
    _tick(force: true);

    final sink = part.openWrite();
    try {
      await sink.addStream(
        req.timeout(stallTimeout).map((chunk) {
          received += chunk.length;
          if (received > maxFileBytes) {
            throw const FileSystemException('upload too large');
          }
          bytesReceived += chunk.length;
          active[rel] = (received: received, total: total);
          _tick();
          return chunk;
        }),
      );
      await sink.flush();
      await sink.close();
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      filesReceived++;
      req.response.statusCode = HttpStatus.ok;
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      try {
        await part.delete();
      } catch (_) {}
      req.response.statusCode = HttpStatus.internalServerError;
    } finally {
      active.remove(rel);
      _tick(force: true);
    }
    await req.response.close();
  }

  Future<void> _finish(HttpRequest req) async {
    await req.drain<void>();
    if (_processing) {
      req.response.statusCode = HttpStatus.conflict;
      await req.response.close();
      return;
    }
    _processing = true;
    _tick(force: true);
    try {
      final summary = await ImportService.organize(stagingDir, romsDir);
      lastSummary = summary;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(summary.toJson()));
      await req.response.close();
      if (summary.total > 0) onLibraryChanged?.call();
    } catch (_) {
      req.response.statusCode = HttpStatus.internalServerError;
      await req.response.close();
    } finally {
      _processing = false;
      _tick(force: true);
    }
  }
}
