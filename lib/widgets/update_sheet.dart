// lib/widgets/update_sheet.dart
import 'dart:io';

import 'package:flutter/widgets.dart' show ValueListenableBuilder;
import 'package:material_ui/material_ui.dart';

import '../services/theme_service.dart';
import '../services/update_service.dart';
import 'settings_kit.dart' show kSettingsDanger;

Future<void> showUpdateSheet(BuildContext context, UpdateInfo info) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _UpdateSheet(info: info),
  );
}

class _UpdateSheet extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateSheet({required this.info});

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet>
    with WidgetsBindingObserver {
  final UpdateService _svc = UpdateService.instance;
  bool _busy = false;
  bool _needsPermission = false;
  String? _error;
  File? _downloaded;

  UpdateInfo get _u => widget.info;
  bool get _canInApp => kInAppUpdates && _u.apkUrl != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from Android's "Install unknown apps" screen: continue by itself when it was allowed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state != AppLifecycleState.resumed || !_needsPermission) return;
    if (await _svc.canInstall() && mounted) {
      setState(() => _needsPermission = false);
      _start();
    }
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    if (!await _svc.canInstall()) {
      // Ask BEFORE the download so a big file is not fetched for nothing.
      final opened = await _svc.openInstallSettings();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _needsPermission = opened;
        _error = opened ? null : 'Allow tonEMU to install apps in Android Settings, then try again.';
      });
      return;
    }
    final file = _downloaded ?? await _svc.download(_u);
    if (!mounted) return;
    if (file == null) {
      setState(() {
        _busy = false;
        _error = _svc.lastError; // null when the user cancelled
      });
      return;
    }
    _downloaded = file;
    final r = await _svc.install(file, _u.sha256);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r == 'permission') {
        _needsPermission = true;
      } else if (r != 'ok') {
        _error = UpdateService.installError(r);
        if (r == 'hash' || r == 'wrongapp' || r == 'notapk')
          _downloaded = null; // fetch again
      }
    });
    if (r == 'ok') Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final maxH = MediaQuery.of(context).size.height * 0.85;
    final mb = _u.apkSize > 0
        ? ' · ${(_u.apkSize / 1048576).toStringAsFixed(0)} MB'
        : '';
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(c.isDot ? 28 : 22),
          border: c.isDot ? Border.all(color: c.hairline) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Update available',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: c.primaryText,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'tonEMU ${_u.version}$mb  (you have ${_svc.installedVersion})',
              style: TextStyle(fontSize: 13, color: c.secondaryText),
            ),
            const SizedBox(height: 12),
            if (_u.notes.isNotEmpty)
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    _plain(_u.notes),
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: c.primaryText,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            ValueListenableBuilder<double?>(
              valueListenable: _svc.progress,
              builder: (_, p, _) => p == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(child: LinearProgressIndicator(value: p)),
                          const SizedBox(width: 10),
                          Text(
                            '${(p * 100).round()}%',
                            style: TextStyle(color: c.secondaryText),
                          ),
                        ],
                      ),
                    ),
            ),
            if (_needsPermission)
              _note(
                c,
                'Turn on "Allow from this source" for tonEMU, then come back. The update continues by itself.',
              ),
            if (_error != null) _note(c, _error!, bad: true),
            if (_canInApp)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  autofocus: true,
                  onPressed: _busy ? _svc.cancelDownload : _start,
                  child: Text(
                    _busy
                        ? 'Cancel'
                        : (_downloaded != null
                              ? 'Install'
                              : 'Download & install'),
                  ),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  autofocus: true,
                  onPressed: () => _svc.openReleasePage(_u),
                  child: Text(
                    kInAppUpdates ? 'Open release page' : 'Get the update',
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          _svc.skipVersion(_u.version);
                          Navigator.of(context).pop();
                        },
                  child: const Text('Skip this version'),
                ),
                if (_canInApp)
                  TextButton(
                    onPressed: () => _svc.openReleasePage(_u),
                    child: const Text('Release page'),
                  ),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Later'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _note(XEmuColors c, String text, {bool bad = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: bad ? kSettingsDanger : c.secondaryText,
      ),
    ),
  );

  /// GitHub release bodies are markdown: drop the markup so the sheet reads as plain text.
  static String _plain(String md) => md
      .replaceAll(RegExp(r'\[\[([^\]]*)\]\([^)]*\)\]\([^)]*\)'), r'$1')
      .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
      .replaceAll('**', '')
      .replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '• ');
}
