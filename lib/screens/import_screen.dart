// lib/screens/import_screen.dart
import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/console_system.dart';
import '../services/import_service.dart';
import '../services/theme_service.dart';
import '../services/wifi_transfer_server.dart';
import '../widgets/import_progress_card.dart';

/// One place to add games: send them from a PC over Wi-Fi, or pick them on this device.
///
/// The three local pickers live in the library (they share its progress overlay), so this screen
/// closes itself and calls them. Wi-Fi transfer runs inside this screen and refreshes the library
/// through [onLibraryChanged] whenever a transfer finishes.
class ImportScreen extends StatefulWidget {
  final Directory romsDir;
  final Future<void> Function() onPickFiles;
  final Future<void> Function() onPickFolder;
  final VoidCallback onLibraryChanged;

  const ImportScreen({
    super.key,
    required this.romsDir,
    required this.onPickFiles,
    required this.onPickFolder,
    required this.onLibraryChanged,
  });

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  late final WifiTransferServer _server;
  bool _starting = false;
  final SpeedMeter _meter = SpeedMeter(); // Wi-Fi receive speed

  @override
  void initState() {
    super.initState();
    _server = WifiTransferServer(
      romsDir: widget.romsDir,
      onLibraryChanged: widget.onLibraryChanged,
    );
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _server.dispose();
    super.dispose();
  }

  Future<void> _toggleWifi() async {
    if (_starting) return; // a second tap while the server is starting would open a second one
    if (_server.running) {
      await _server.stop();
      await WakelockPlus.disable();
      return;
    }
    setState(() => _starting = true);
    try {
      await _server.start();
      if (_server.running && mounted) {
        await WakelockPlus.enable(); // keep the screen on while sending
      }
    } finally {
      // Always reset, even if start() throws, or the Wi-Fi button stays disabled until reopened.
      if (mounted) setState(() => _starting = false);
    }
  }

  /// Closes this screen first, then runs a local picker (which shows its own progress overlay).
  void _local(Future<void> Function() action) {
    Navigator.pop(context);
    action();
  }

  // ───────── widgets ─────────

  Widget _card(XEmuColors c, {required Widget child, EdgeInsets? padding}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.cardRadius),
        border: Border.all(color: c.hairline, width: c.hairlineWidth),
        boxShadow: c.cardShadow,
      ),
      child: child,
    );
  }

  Widget _sectionTitle(XEmuColors c, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
    child: Row(
      children: [
        if (c.isDot) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              fontFamily: c.labelFont,
              fontSize: 12.5,
              fontWeight: c.isDot ? FontWeight.w400 : FontWeight.w600,
              color: c.secondaryText,
              letterSpacing: c.isDot ? 1.2 : 0.4,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _wifiCard(XEmuColors c) {
    return ListenableBuilder(
      listenable: _server,
      builder: (context, _) {
        final s = _server;
        return _card(
          c,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(CupertinoIcons.wifi, color: c.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Wi-Fi Transfer',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: c.primaryText,
                          ),
                        ),
                        Text(
                          s.running
                              ? 'Ready. Open the address below on your PC.'
                              : 'Send games from your computer, no cable needed.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: c.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (s.running) ...[
                for (final url in s.urls) _addressTile(c, url),
                const SizedBox(height: 4),
                Text(
                  'Both devices must be on the same Wi-Fi (or the phone hotspot). '
                  'The screen stays on while sending, so keep this screen open.',
                  style: TextStyle(fontSize: 12, color: c.secondaryText),
                ),
                const SizedBox(height: 12),
                _liveStatus(c, s),
                if (s.active.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  for (final e in s.active.entries.take(4))
                    TransferBar(
                      name: e.key.split('/').last,
                      received: e.value.received,
                      total: e.value.total,
                    ),
                  if (s.active.length > 4)
                    Text(
                      '+${s.active.length - 4} more',
                      style: TextStyle(fontSize: 12, color: c.secondaryText),
                    ),
                ],
                if (s.lastSummary != null) _summary(c, s),
              ],
              if (s.error != null) ...[
                const SizedBox(height: 4),
                Text(s.error!, style: TextStyle(fontSize: 13, color: c.danger)),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  borderRadius: BorderRadius.circular(12),
                  onPressed: _starting ? null : _toggleWifi,
                  child: _starting
                      ? const CupertinoActivityIndicator(color: Colors.white)
                      : Text(
                          s.running ? 'Stop Transfer' : 'Start Wi-Fi Transfer',
                          style: c.buttonText(size: 15),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _addressTile(XEmuColors c, String url) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: c.secondaryFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              url,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: c.accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: Icon(CupertinoIcons.doc_on_doc, size: 18, color: c.accent),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(content: Text('Address copied')));
            },
          ),
        ],
      ),
    );
  }

  /// One line that proves whether files are really arriving: waiting / receiving (with speed) /
  /// sorting into the library / how much has been received so far.
  Widget _liveStatus(XEmuColors c, WifiTransferServer s) {
    final receiving = s.active.isNotEmpty;
    final speed = receiving ? _meter.add(s.bytesReceived) : 0.0;
    if (!receiving) _meter.reset();

    final String text;
    if (s.processing) {
      text = 'Adding games to your library...';
    } else if (receiving) {
      text =
          'Receiving ${s.active.length} file(s)  -  ${fmtBytes(s.bytesReceived)} so far'
          '${speed > 0 ? '  -  ${fmtBytes(speed.round())}/s' : ''}';
    } else if (s.filesReceived > 0) {
      text =
          'Received ${s.filesReceived} file(s), ${fmtBytes(s.bytesReceived)}';
    } else {
      text = 'Waiting for files... nothing received yet';
    }
    final busy = receiving || s.processing;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: busy ? c.accent : c.tertiaryText,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: c.labelFont,
              fontSize: c.isDot ? 11.5 : 12.5,
              color: busy ? c.primaryText : c.secondaryText,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  Widget _summary(XEmuColors c, WifiTransferServer s) {
    final r = s.lastSummary!;
    final lines = <String>[
      if (r.total > 0) '${r.total} game(s) added to your library',
      if (r.duplicates > 0) '${r.duplicates} already in your library',
      if (r.ignored.isNotEmpty)
        '${r.ignored.length} unsupported file(s) ignored',
    ];
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.ok.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: c.isDot ? Border.all(color: c.hairline) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Last transfer',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
              color: c.primaryText,
            ),
          ),
          for (final l in lines)
            Text(l, style: TextStyle(fontSize: 12.5, color: c.primaryText)),
          for (final w in r.warnings)
            Text(w, style: TextStyle(fontSize: 12.5, color: c.warn)),
        ],
      ),
    );
  }

  Widget _localTile(
    XEmuColors c, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Future<void> Function() action,
    bool last = false,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: () => _local(action),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 22, color: c.accent),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: c.primaryText,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: c.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: c.tertiaryText,
                ),
              ],
            ),
          ),
        ),
        if (!last)
          Divider(height: 0.5, thickness: 0.5, indent: 52, color: c.hairline),
      ],
    );
  }

  Widget _formats(XEmuColors c) {
    return _card(
      c,
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            'Supported formats',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: c.primaryText,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in ConsoleSystem.allSystems)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${s.name}: ${s.extensions.map((e) => '.$e').join('  ')}',
                  style: TextStyle(fontSize: 12.5, color: c.secondaryText),
                ),
              ),
            const SizedBox(height: 6),
            Text(
              'Disc games: send the .cue together with every .bin it uses.',
              style: TextStyle(fontSize: 12.5, color: c.secondaryText),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return c.dotted(
      Scaffold(
        backgroundColor: c.pageBg,
        appBar: AppBar(
          backgroundColor: c.pageBg,
          centerTitle: true,
          title: Text(
            'Import Games',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 17,
              fontFamily: c.displayFont,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(top: 8, bottom: 36),
                children: [
                  _sectionTitle(c, 'From your computer'),
                  _wifiCard(c),
                  _sectionTitle(c, 'From this device'),
                  _card(
                    c,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _localTile(
                          c,
                          icon: CupertinoIcons.doc,
                          title: 'Game Files',
                          subtitle: 'Pick ROMs and discs (.cue + .bin)',
                          action: widget.onPickFiles,
                        ),
                        _localTile(
                          c,
                          icon: CupertinoIcons.folder,
                          title: 'Folder (with subfolders)',
                          subtitle: 'Scan a folder and import everything in it',
                          action: widget.onPickFolder,
                          last: true,
                        ),
                      ],
                    ),
                  ),
                  _formats(c),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
