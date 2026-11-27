// lib/screens/jed_manager_screen.dart
import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../models/console_system.dart';
import '../services/jed_manager_service.dart';
import '../services/save_backup_service.dart';
import '../services/storage_service.dart';
import '../services/theme_service.dart';
import '../widgets/settings_kit.dart';

/// jedManager: every ROM with its saves, states and play time in one place, plus the import of
/// the old (non-Google-Play) tonEMU folder. Every color, radius and font comes from
/// [XEmuColors] / the shared settings widgets, so Classic and Dot, light and dark all work.
class JedManagerScreen extends StatefulWidget {
  const JedManagerScreen({super.key});

  @override
  State<JedManagerScreen> createState() => _JedManagerScreenState();
}

class _JedManagerScreenState extends State<JedManagerScreen> {
  final _svc = JedManagerService.instance;

  ManagerSnapshot? _snap;
  bool _loading = true;

  // Library list
  int _sort = 0; // 0 = A-Z, 1 = play time, 2 = size
  String _query = '';

  // Old-folder import
  bool _overwrite = false;
  bool _importing = false;
  LegacyProgress? _progress;
  LegacyImportReport? _report;
  String? _importNote;
  Timer? _poll;
  _Eta? _etaCalc;
  Duration? _eta; // time left for the old-folder import (null while still estimating)

  // Save backups
  final _bk = SaveBackupService.instance;
  List<BackupInfo> _backups = const [];
  bool _bkIncludeStates = false;
  bool _bkBusy = false;

  @override
  void initState() {
    super.initState();
    _reload();
    // Keeps a fresh copy of play time + favorites next to the folder (visible in the Files app).
    _svc.exportStats();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    final s = await _svc.scan();
    final bk = await _bk.list();
    if (!mounted) return;
    setState(() {
      _snap = s;
      _backups = bk;
      _loading = false;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _confirm(
    String title,
    String message,
    String action, {
    bool destructive = true,
  }) async {
    final r = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: destructive,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return r == true;
  }

  // ───────────────────────── Old folder import ─────────────────────────

  Future<void> _importOldFolder() async {
    if (_importing) return;
    final uri = await _svc.pickLegacyFolder();
    if (uri == null || !mounted) return;
    setState(() {
      _importing = true;
      _report = null;
      _importNote = null;
      _progress = null;
      _eta = null;
    });
    _etaCalc = _Eta();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      final p = await _svc.legacyProgress();
      if (mounted && p != null && p.running) {
        // Bytes when the size is known, otherwise count files.
        final byBytes = p.bytesTotal > 0;
        final left = _etaCalc?.update(
          byBytes ? p.bytesDone : p.filesDone,
          byBytes ? p.bytesTotal : p.filesTotal,
        );
        setState(() {
          _progress = p;
          _eta = left;
        });
      }
    });
    final r = await _svc.importLegacyFolder(uri, overwrite: _overwrite);
    _poll?.cancel();
    if (!mounted) return;
    setState(() {
      _importing = false;
      _progress = null;
      _eta = null;
      _report = r;
      if (r == null) {
        _importNote = 'The import could not run. Please try again.';
      }
    });
    await _reload();
  }

  // ───────────────────────── Save backups ─────────────────────────

  Future<void> _createBackup() async {
    if (_bkBusy) return;
    setState(() => _bkBusy = true);
    final plan = await _bk.plan(includeStates: _bkIncludeStates);
    if (!mounted) return;
    if (plan.files == 0) {
      setState(() => _bkBusy = false);
      _toast('There are no saves to back up yet.');
      return;
    }
    final ok = await _confirm(
      'Back up saves?',
      '${plan.files} files (${JedManagerService.formatBytes(plan.bytes)}) are copied into '
          'the "backups" folder inside tonEMU. Nothing is changed or deleted.',
      'Back up',
      destructive: false,
    );
    if (!ok || !mounted) {
      if (mounted) setState(() => _bkBusy = false);
      return;
    }
    final info = await _runProgress<BackupInfo?>(
      context,
      title: 'Backing up saves',
      onCancel: _bk.cancel,
      job: (report) =>
          _bk.create(includeStates: _bkIncludeStates, onProgress: report),
    );
    if (!mounted) return;
    setState(() => _bkBusy = false);
    _toast(
      info != null
          ? 'Backed up ${info.fileCount} files (${JedManagerService.formatBytes(info.bytes)})'
          : (_bk.lastError ?? 'The backup did not finish'),
    );
    await _reload();
  }

  Future<void> _openBackup(BackupInfo b) async {
    HapticFeedback.selectionClick();
    final names = [for (final g in _snap?.games ?? const <ManagedGame>[]) g.name];
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) =>
          _BackupSheet(backup: b, gameNames: names, onChanged: _reload),
    );
    await _reload();
  }

  Widget _backupGroup(XEmuColors c, ManagerSnapshot s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SettingsGroup(
        title: 'Save backups (${_backups.length})',
        footer:
            'Backups are plain copies in tonEMU/backups (you can see them in the Files app). '
            'Tap one to restore a single game or everything. A restore first keeps what it '
            'replaces as a "Before restore" backup, so it can always be undone.',
        children: [
          SettingsRow(
            icon: CupertinoIcons.archivebox_fill,
            color: c.accent,
            title: 'Back up saves now',
            subtitle: _bkIncludeStates
                ? 'Battery saves, memory cards and save states'
                : 'Battery saves and memory cards',
            chevron: false,
            trailing: _bkBusy ? const CupertinoActivityIndicator() : null,
            onTap: _bkBusy ? null : _createBackup,
          ),
          SettingsSwitchRow(
            icon: CupertinoIcons.camera_fill,
            color: c.accent,
            title: 'Include save states',
            subtitle: 'Bigger backups, but keeps your quick-save slots',
            value: _bkIncludeStates,
            onChanged: (v) => setState(() => _bkIncludeStates = v),
          ),
          if (_backups.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No backups yet. Make one before you update, move to a new phone or '
                'clean up files.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: c.secondaryText,
                ),
              ),
            ),
          for (final b in _backups)
            SettingsRow(
              icon: b.isSafetyCopy
                  ? CupertinoIcons.shield_fill
                  : CupertinoIcons.clock_fill,
              color: b.isSafetyCopy ? c.warn : c.accent,
              title: b.isSafetyCopy
                  ? 'Before restore'
                  : (b.label.isEmpty ? 'Backup' : b.label),
              subtitle:
                  '${_fmtDateTime(b.createdAt)} · ${b.fileCount} files · '
                  '${JedManagerService.formatBytes(b.bytes)}',
              onTap: () => _openBackup(b),
            ),
        ],
      ),
    );
  }

  // ───────────────────────── Actions ─────────────────────────

  Future<void> _exportStats() async {
    final f = await _svc.exportStats();
    _toast(
      f == null
          ? 'Could not write the stats file'
          : 'Saved ${JedManagerService.statsFileName} in the tonEMU folder',
    );
  }

  Future<void> _openFiles() async {
    final ok = await StorageService.instance.openInFilesApp();
    if (!ok) _toast('No Files app could open the tonEMU folder');
  }

  Future<void> _openGame(ManagedGame g) async {
    HapticFeedback.selectionClick();
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => _GameSheet(
        game: g,
        reload: () async {
          await _reload();
          final list = _snap?.games ?? const <ManagedGame>[];
          for (final x in list) {
            if (x.name == g.name) return x;
          }
          return null;
        },
      ),
    );
    await _reload();
  }

  Future<void> _deleteOrphan(SaveItem it) async {
    final ok = await _confirm(
      'Delete this file?',
      '${it.name} (${JedManagerService.formatBytes(it.bytes)}) belongs to no game in the library.',
      'Delete',
    );
    if (!ok) return;
    await _svc.deleteItem(it);
    await _reload();
  }

  Future<void> _deleteAllOrphans() async {
    final s = _snap;
    if (s == null || s.orphans.isEmpty) return;
    final ok = await _confirm(
      'Delete ${s.orphans.length} unmatched files?',
      'Frees ${JedManagerService.formatBytes(s.orphanBytes)}. These saves and states belong '
          'to no game that is in the library right now. If you plan to add those games '
          'again, keep them.',
      'Delete all',
    );
    if (!ok) return;
    for (final it in List<SaveItem>.from(s.orphans)) {
      await _svc.deleteItem(it);
    }
    await _reload();
  }

  // ───────────────────────── UI pieces ─────────────────────────

  BoxDecoration _card(XEmuColors c) => BoxDecoration(
    color: c.cardBg,
    borderRadius: BorderRadius.circular(c.cardRadius),
    border: Border.all(color: c.hairline, width: c.hairlineWidth),
    boxShadow: c.cardShadow,
  );

  // FittedBox shrinks the text to the width of its quarter instead of cutting it with "...",
  // so "1.25 GB" and "System" stay whole in the wide Dot fonts and on narrow phones.
  Widget _stat(XEmuColors c, String value, String label) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontFamily: c.displayFont,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: c.primaryText,
              ),
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontFamily: c.labelFont,
                fontSize: 11.5,
                color: c.secondaryText,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _summary(XEmuColors c, ManagerSnapshot s) {
    final played = s.games.where((g) => g.playSeconds > 0).length;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: _card(c),
      child: Column(
        children: [
          Text(
            JedManagerService.formatPlayTime(s.totalPlaySeconds),
            style: TextStyle(
              fontFamily: c.displayFont,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: c.primaryText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'total play time · $played ${played == 1 ? 'game' : 'games'}',
            style: TextStyle(
              fontFamily: c.labelFont,
              fontSize: 12.5,
              color: c.secondaryText,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _stat(
                c,
                JedManagerService.formatBytes(s.folderBytes['roms'] ?? 0),
                'ROMs',
              ),
              _stat(
                c,
                JedManagerService.formatBytes(s.folderBytes['saves'] ?? 0),
                'Saves',
              ),
              _stat(
                c,
                JedManagerService.formatBytes(s.folderBytes['states'] ?? 0),
                'States',
              ),
              _stat(
                c,
                JedManagerService.formatBytes(s.folderBytes['system'] ?? 0),
                'System',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _line(XEmuColors c, IconData icon, Color color, String text) =>
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.3,
                  color: c.primaryText,
                ),
              ),
            ),
          ],
        ),
      );

  List<Widget> _reportLines(XEmuColors c, LegacyImportReport r) {
    final out = <Widget>[];
    if (r.notTonEmu) {
      out.add(
        _line(
          c,
          CupertinoIcons.exclamationmark_triangle_fill,
          c.warn,
          'That does not look like a tonEMU folder. Pick the folder named "tonEMU" '
          '(the one that holds roms, saves, states...).',
        ),
      );
      return out;
    }
    if (r.cancelled) {
      out.add(
        _line(
          c,
          CupertinoIcons.stop_circle_fill,
          c.warn,
          'Import cancelled. What was already copied is kept.',
        ),
      );
    }
    out.add(
      _line(
        c,
        CupertinoIcons.checkmark_circle_fill,
        c.ok,
        '${r.copied} files copied (${JedManagerService.formatBytes(r.bytes)})'
        '${r.replaced > 0 ? ', ${r.replaced} replaced (old copies kept as .bak)' : ''}',
      ),
    );
    if (r.alreadyThere > 0) {
      out.add(
        _line(
          c,
          CupertinoIcons.doc_on_doc_fill,
          c.secondaryText,
          '${r.alreadyThere} files were already here',
        ),
      );
    }
    if (r.kept > 0) {
      out.add(
        _line(
          c,
          CupertinoIcons.info_circle_fill,
          c.secondaryText,
          '${r.kept} files differ from the ones already here and were left as they are. '
          'Turn on "Replace existing files" to use the old ones instead.',
        ),
      );
    }
    if (r.noSpace > 0) {
      out.add(
        _line(
          c,
          CupertinoIcons.exclamationmark_triangle_fill,
          c.warn,
          '${r.noSpace} files skipped: not enough free storage',
        ),
      );
    }
    if (r.failed > 0) {
      out.add(
        _line(
          c,
          CupertinoIcons.xmark_circle_fill,
          c.danger,
          '${r.failed} files could not be copied'
          '${r.failedNames.isEmpty ? '' : ': ${r.failedNames.take(3).join(', ')}${r.failedNames.length > 3 ? '…' : ''}'}',
        ),
      );
    }
    final st = r.stats;
    if (st != null && !st.invalid && !st.alreadyImported) {
      out.add(
        _line(
          c,
          CupertinoIcons.time_solid,
          c.ok,
          'Play time added: ${JedManagerService.formatPlayTime(st.addedSeconds)} '
          'across ${st.games} ${st.games == 1 ? 'game' : 'games'}',
        ),
      );
    } else if (st != null && st.alreadyImported) {
      out.add(
        _line(
          c,
          CupertinoIcons.time_solid,
          c.secondaryText,
          'The play time in that folder was already imported before, so it was not added again.',
        ),
      );
    } else if (st != null && st.invalid) {
      out.add(
        _line(
          c,
          CupertinoIcons.exclamationmark_triangle_fill,
          c.warn,
          'jed_stats.json could not be read.',
        ),
      );
    } else if (!r.cancelled) {
      out.add(
        _line(
          c,
          CupertinoIcons.time_solid,
          c.secondaryText,
          'Play time is not stored in the old folder, so it could not be copied. '
          'Open a game below and use "Edit play time" to type it in.',
        ),
      );
    }
    if (r.estimatedGames > 0) {
      out.add(
        _line(
          c,
          CupertinoIcons.calendar,
          c.ok,
          '${r.estimatedGames} games got an estimated "last played" date from their save files',
        ),
      );
    }
    return out;
  }

  Widget _importCard(XEmuColors c) {
    final p = _progress;
    final r = _report;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: _card(c),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                CupertinoIcons.tray_arrow_down_fill,
                color: c.accent,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Import old tonEMU folder',
                  style: TextStyle(
                    fontFamily: c.displayFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: c.primaryText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Coming from the old beta? Pick its tonEMU folder (usually "tonEMU" in your '
            'phone storage). ROMs, saves, states and BIOS are copied into the new location '
            'and each game gets an estimated last-played date. Play time can be typed in per game. '
            'Nothing is deleted from the old folder.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: c.secondaryText,
            ),
          ),
          const SizedBox(height: 12),
          if (_importing) ...[
            _BigBar(fraction: p?.fraction),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    p == null
                        ? 'Looking through the folder…'
                        : '${p.filesDone} / ${p.filesTotal} files · '
                              '${JedManagerService.formatBytes(p.bytesDone)} of ${JedManagerService.formatBytes(p.bytesTotal)}',
                    style: TextStyle(fontSize: 12.5, color: c.primaryText),
                  ),
                ),
                if (p?.fraction != null)
                  Text(
                    '${(p!.fraction! * 100).floor()}%',
                    style: TextStyle(
                      fontFamily: c.labelFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: c.accent,
                    ),
                  ),
              ],
            ),
            if (p != null && p.current.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  p.current,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: c.secondaryText),
                ),
              ),
            const SizedBox(height: 14),
            Center(child: _Countdown(left: _eta)),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _svc.cancelLegacyImport,
                child: Text(
                  'Cancel',
                  style: c.buttonText(size: 14, color: c.danger),
                ),
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                color: c.accent,
                padding: const EdgeInsets.symmetric(vertical: 12),
                borderRadius: BorderRadius.circular(12),
                onPressed: _importOldFolder,
                child: Text(
                  'Choose old folder…',
                  style: c.buttonText(size: 14.5, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Replace existing files',
                    style: TextStyle(
                      fontFamily: c.labelFont,
                      fontSize: 13.5,
                      color: c.primaryText,
                    ),
                  ),
                ),
                c.isDot
                    ? Switch(
                        value: _overwrite,
                        onChanged: (v) => setState(() => _overwrite = v),
                      )
                    : CupertinoSwitch(
                        value: _overwrite,
                        activeTrackColor: c.accent,
                        onChanged: (v) => setState(() => _overwrite = v),
                      ),
              ],
            ),
          ],
          if (_importNote != null)
            _line(c, CupertinoIcons.xmark_circle_fill, c.danger, _importNote!),
          if (r != null && !_importing) ..._reportLines(c, r),
        ],
      ),
    );
  }

  String _gameSubtitle(ManagedGame g) {
    final parts = <String>[
      if (g.system != null) g.system!.shortName else 'Not in library',
      if (g.inLibrary) JedManagerService.formatBytes(g.romBytes),
      if (g.saves.isNotEmpty)
        '${g.saves.length} ${g.saves.length == 1 ? 'save' : 'saves'}',
      if (g.states.isNotEmpty)
        '${g.states.length} ${g.states.length == 1 ? 'state' : 'states'}',
    ];
    return parts.join(' · ');
  }

  List<ManagedGame> _visibleGames(ManagerSnapshot s) {
    final q = _query.trim().toLowerCase();
    final list = [
      for (final g in s.games)
        if (q.isEmpty ||
            g.title.toLowerCase().contains(q) ||
            g.name.toLowerCase().contains(q))
          g,
    ];
    switch (_sort) {
      case 1:
        list.sort((a, b) => b.playSeconds.compareTo(a.playSeconds));
      case 2:
        list.sort(
          (a, b) =>
              (b.romBytes + b.dataBytes).compareTo(a.romBytes + a.dataBytes),
        );
      default:
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    }
    return list;
  }

  Widget _gamesGroup(XEmuColors c, ManagerSnapshot s) {
    final games = _visibleGames(s);
    if (s.games.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 40, 32, 8),
        child: Text(
          'No games yet. Add ROMs from the Library, or import your old tonEMU folder above.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.35,
            color: c.secondaryText,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SettingsGroup(
        title: 'Games (${games.length})',
        dividerIndent: 58,
        children: [
          if (games.isEmpty)
            Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                'No game matches "$_query".',
                style: TextStyle(color: c.secondaryText),
              ),
            ),
          for (final g in games)
            SettingsRow(
              icon: g.favorite
                  ? CupertinoIcons.heart_fill
                  : CupertinoIcons.game_controller_solid,
              color: g.inLibrary ? c.accent : c.secondaryText,
              title: g.title,
              subtitle: _gameSubtitle(g),
              value: g.playSeconds > 0
                  ? JedManagerService.formatPlayTime(g.playSeconds)
                  : null,
              onTap: () => _openGame(g),
            ),
        ],
      ),
    );
  }

  Widget _orphansGroup(XEmuColors c, ManagerSnapshot s) {
    if (s.orphans.isEmpty) return const SizedBox.shrink();
    final shown = s.orphans.take(25).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SettingsGroup(
        title: 'Unmatched files (${s.orphans.length})',
        footer:
            'Saves and states whose game is not in the library. They are kept in case you add '
            'the game again; delete them to free ${JedManagerService.formatBytes(s.orphanBytes)}.',
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _deleteAllOrphans,
          child: Text(
            'Delete all',
            style: c.buttonText(size: 13, color: c.danger),
          ),
        ),
        children: [
          for (final it in shown)
            SettingsRow(
              icon: it.kind == SaveKind.battery
                  ? CupertinoIcons.floppy_disk
                  : CupertinoIcons.doc_fill,
              color: c.secondaryText,
              title: it.name,
              subtitle: JedManagerService.formatBytes(it.bytes),
              chevron: false,
              trailing: InkResponse(
                onTap: () => _deleteOrphan(it),
                radius: 22,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(CupertinoIcons.trash, size: 19, color: c.danger),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _toolsGroup(XEmuColors c) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: SettingsGroup(
      title: 'Tools',
      children: [
        SettingsRow(
          icon: CupertinoIcons.time,
          color: c.accent,
          title: 'Export play time & favorites',
          subtitle:
              'Writes ${JedManagerService.statsFileName} into the tonEMU folder',
          onTap: _exportStats,
        ),
        SettingsRow(
          icon: CupertinoIcons.folder_fill,
          color: c.accent,
          title: 'Open tonEMU in Files',
          subtitle: StorageService.instance.displayPath,
          onTap: _openFiles,
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final s = _snap;
    return c.dotted(
      Scaffold(
        backgroundColor: c.pageBg,
        appBar: AppBar(
          backgroundColor: c.pageBg,
          centerTitle: true,
          title: Text(
            'jedManager',
            style: TextStyle(
              fontFamily: c.displayFont,
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: c.primaryText,
            ),
          ),
        ),
        body: _loading || s == null
            ? const Center(child: CupertinoActivityIndicator())
            : SafeArea(
                top: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView(
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        padding: const EdgeInsets.only(bottom: 36),
                        children: [
                          _summary(c, s),
                          _importCard(c),
                          _backupGroup(c, s),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                            child: CupertinoSearchTextField(
                              placeholder: 'Search games',
                              onChanged: (v) => setState(() => _query = v),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: SettingsGroup(
                              children: [
                                SettingsSegmentedRow<int>(
                                  title: 'Sort by',
                                  value: _sort,
                                  options: const {
                                    0: 'A–Z',
                                    1: 'Play time',
                                    2: 'Size',
                                  },
                                  onChanged: (v) => setState(() => _sort = v),
                                ),
                              ],
                            ),
                          ),
                          _gamesGroup(c, s),
                          _orphansGroup(c, s),
                          _toolsGroup(c),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

// ═══════════════════════════ Per-game sheet ═══════════════════════════

class _GameSheet extends StatefulWidget {
  const _GameSheet({required this.game, required this.reload});
  final ManagedGame game;
  final Future<ManagedGame?> Function() reload;

  @override
  State<_GameSheet> createState() => _GameSheetState();
}

class _GameSheetState extends State<_GameSheet> {
  final _svc = JedManagerService.instance;
  final _bk = SaveBackupService.instance;
  late ManagedGame _g = widget.game;

  /// Backups that contain files of this game.
  List<BackupInfo> _gameBackups = const [];

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    final all = await _bk.list();
    if (!mounted) return;
    setState(() {
      _gameBackups = [
        for (final b in all)
          if (b.entriesFor(_g.name).isNotEmpty) b,
      ];
    });
  }

  Future<void> _refresh() async {
    final g = await widget.reload();
    if (!mounted) return;
    if (g == null) {
      Navigator.pop(context); // nothing left of this game
      return;
    }
    setState(() => _g = g);
    unawaited(_loadBackups());
  }

  Future<void> _backupGame() async {
    final plan = await _bk.plan(includeStates: true, onlyGame: _g.name);
    if (!mounted) return;
    if (plan.files == 0) {
      _toast('This game has no saves or states to back up.');
      return;
    }
    final ok = await _askDialog(
      context,
      'Back up ${_g.title}?',
      '${plan.files} files (${JedManagerService.formatBytes(plan.bytes)}) are copied into '
          'tonEMU/backups.',
      'Back up',
      destructive: false,
    );
    if (!ok || !mounted) return;
    final info = await _runProgress<BackupInfo?>(
      context,
      title: 'Backing up',
      onCancel: _bk.cancel,
      job: (report) => _bk.create(
        includeStates: true,
        onlyGame: _g.name,
        label: _g.title,
        onProgress: report,
      ),
    );
    if (!mounted) return;
    _toast(
      info != null
          ? 'Backed up ${info.fileCount} files'
          : (_bk.lastError ?? 'The backup did not finish'),
    );
    await _loadBackups();
  }

  Future<void> _pickRestore() async {
    final picked = await showCupertinoModalPopup<BackupInfo>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text('Restore ${_g.title} from…'),
        actions: [
          for (final b in _gameBackups)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, b),
              child: Text(
                '${_fmtDateTime(b.createdAt)} · ${b.entriesFor(_g.name).length} files'
                '${b.isSafetyCopy ? ' · before restore' : ''}',
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final n = picked.entriesFor(_g.name).length;
    final ok = await _askDialog(
      context,
      'Restore ${_g.title}?',
      '$n files from ${_fmtDateTime(picked.createdAt)} replace the current saves of this '
          'game. What gets replaced is kept as a "Before restore" backup first.',
      'Restore',
      destructive: false,
    );
    if (!ok || !mounted) return;
    final r = await _runProgress<RestoreResult>(
      context,
      title: 'Restoring',
      onCancel: _bk.cancel,
      job: (report) =>
          _bk.restore(picked, onlyGame: _g.name, onProgress: report),
    );
    if (!mounted || r == null) return;
    await _refresh();
    if (!mounted) return;
    await _infoDialog(context, _restoreTitle(r), _restoreMessage(r));
  }

  Future<bool> _confirm(String title, String message, String action) async {
    final r = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return r == true;
  }

  void _toast(String m) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _delete(SaveItem it) async {
    if (!await _confirm(
      'Delete ${it.label}?',
      'This cannot be undone.',
      'Delete',
    ))
      return;
    await _svc.deleteItem(it);
    await _refresh();
  }

  Future<void> _restore(SaveItem it) async {
    if (!await _confirm(
      'Restore this backup?',
      'It replaces the current file it was made from. Do this only while the game is closed.',
      'Restore',
    )) {
      return;
    }
    final ok = await _svc.restoreBackup(it);
    _toast(ok ? 'Backup restored' : 'Could not restore the backup');
    await _refresh();
  }

  Future<void> _deleteAllData() async {
    if (!await _confirm(
      'Delete all saves and states?',
      '${_g.title}: ${_g.items.length} files (${JedManagerService.formatBytes(_g.dataBytes)}). '
          'Battery saves are included, so in-game progress is lost.',
      'Delete all',
    )) {
      return;
    }
    await _svc.deleteGameData(_g);
    await _refresh();
  }

  Future<void> _deleteStatesOnly() async {
    if (!await _confirm(
      'Delete save states?',
      'Frees ${JedManagerService.formatBytes(_g.stateBytes)}. In-game (battery) saves stay.',
      'Delete states',
    )) {
      return;
    }
    for (final it in List<SaveItem>.from(_g.states)) {
      await _svc.deleteItem(it);
    }
    await _refresh();
  }

  Future<void> _editPlayTime() async {
    final hCtl = TextEditingController(text: '${_g.playSeconds ~/ 3600}');
    final mCtl = TextEditingController(
      text: '${(_g.playSeconds % 3600) ~/ 60}',
    );
    final c = XEmuColors.of(context);
    Widget field(TextEditingController ctl, String suffix) => Expanded(
      child: CupertinoTextField(
        controller: ctl,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: 5,
        suffix: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Text(suffix, style: TextStyle(color: c.secondaryText)),
        ),
      ),
    );
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Edit play time'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              field(hCtl, 'h'),
              const SizedBox(width: 10),
              field(mCtl, 'm'),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final h = int.tryParse(hCtl.text) ?? 0;
    final m = int.tryParse(mCtl.text) ?? 0;
    hCtl.dispose();
    mCtl.dispose();
    if (ok != true) return;
    await _svc.setPlayTime(_g.name, h * 3600 + m * 60);
    await _refresh();
  }

  Future<void> _resetStats() async {
    if (!await _confirm(
      'Reset play time?',
      'Sets the play time of ${_g.title} back to zero.',
      'Reset',
    )) {
      return;
    }
    await _svc.resetStats(_g);
    await _refresh();
  }

  Future<void> _deleteRom() async {
    if (!await _confirm(
      'Delete this game?',
      'Removes the ROM, its saves, states and play time from this phone.',
      'Delete game',
    )) {
      return;
    }
    final ok = await _svc.deleteRom(_g);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      _toast('Could not delete the ROM');
    }
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

  Widget _itemRow(XEmuColors c, SaveItem it) {
    final IconData icon = switch (it.kind) {
      SaveKind.battery => CupertinoIcons.floppy_disk,
      SaveKind.state => CupertinoIcons.camera_fill,
      SaveKind.autoState => CupertinoIcons.arrow_2_circlepath,
      SaveKind.undoState => CupertinoIcons.arrow_uturn_left,
      SaveKind.backup => CupertinoIcons.clock_fill,
      SaveKind.other => CupertinoIcons.doc_fill,
    };
    return SettingsRow(
      icon: icon,
      color: it.kind == SaveKind.backup ? c.secondaryText : c.accent,
      title: it.label,
      subtitle:
          '${JedManagerService.formatBytes(it.bytes)} · ${_date(it.modified)}',
      chevron: false,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (it.kind == SaveKind.backup)
            InkResponse(
              onTap: () => _restore(it),
              radius: 22,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  CupertinoIcons.arrow_counterclockwise,
                  size: 19,
                  color: c.accent,
                ),
              ),
            ),
          InkResponse(
            onTap: () => _delete(it),
            radius: 22,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(CupertinoIcons.trash, size: 19, color: c.danger),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final g = _g;
    final h = MediaQuery.sizeOf(context).height;
    final last = g.lastPlayedMs == null
        ? 'Never'
        : '${g.lastPlayedEstimated ? '~' : ''}${_date(DateTime.fromMillisecondsSinceEpoch(g.lastPlayedMs!))}';

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: h * 0.88, maxWidth: 640),
        child: Material(
          color: c.groupedBg,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            side: BorderSide(color: c.hairline, width: c.hairlineWidth),
          ),
          child: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              shrinkWrap: true,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    g.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: c.displayFont,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: c.primaryText,
                    ),
                  ),
                ),
                SettingsGroup(
                  title: 'Info',
                  children: [
                    SettingsRow(
                      icon: CupertinoIcons.time_solid,
                      color: c.accent,
                      title: 'Play time',
                      value: JedManagerService.formatPlayTime(g.playSeconds),
                      onTap: _editPlayTime,
                    ),
                    SettingsRow(
                      icon: CupertinoIcons.calendar,
                      color: c.accent,
                      title: g.lastPlayedEstimated
                          ? 'Last played (estimated)'
                          : 'Last played',
                      value: last,
                      chevron: false,
                    ),
                    SettingsRow(
                      icon: CupertinoIcons.game_controller_solid,
                      color: g.inLibrary ? c.accent : c.secondaryText,
                      title: g.inLibrary
                          ? (g.system?.name ?? 'ROM')
                          : 'ROM not in library',
                      subtitle: g.name,
                      value: g.inLibrary
                          ? JedManagerService.formatBytes(g.romBytes)
                          : null,
                      chevron: false,
                    ),
                  ],
                ),
                if (g.items.isNotEmpty)
                  SettingsGroup(
                    title:
                        'Saves & states (${JedManagerService.formatBytes(g.dataBytes)})',
                    children: [for (final it in g.items) _itemRow(c, it)],
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: Text(
                      'No saves or states for this game.',
                      style: TextStyle(fontSize: 13, color: c.secondaryText),
                    ),
                  ),
                SettingsGroup(
                  title: 'Backup',
                  children: [
                    if (g.items.any((e) => e.kind != SaveKind.backup))
                      SettingsRow(
                        icon: CupertinoIcons.archivebox_fill,
                        color: c.accent,
                        title: 'Back up this game',
                        subtitle: 'Saves and save states',
                        chevron: false,
                        onTap: _backupGame,
                      ),
                    SettingsRow(
                      icon: CupertinoIcons.arrow_counterclockwise,
                      color: c.accent,
                      title: 'Restore from a backup',
                      subtitle: _gameBackups.isEmpty
                          ? 'No backup has this game yet'
                          : '${_gameBackups.length} available',
                      chevron: _gameBackups.isNotEmpty,
                      onTap: _gameBackups.isEmpty ? null : _pickRestore,
                    ),
                  ],
                ),
                SettingsGroup(
                  title: 'Clean up',
                  footer: g.isDiscSheet
                      ? 'Disc games (.cue / .gdi / .m3u) have extra track files. Remove them from '
                            'the Library (long-press the game) so those are cleaned up too.'
                      : null,
                  children: [
                    if (g.states.isNotEmpty)
                      SettingsRow(
                        icon: CupertinoIcons.camera_fill,
                        color: c.warn,
                        title: 'Delete save states',
                        value: JedManagerService.formatBytes(g.stateBytes),
                        chevron: false,
                        onTap: _deleteStatesOnly,
                      ),
                    if (g.items.isNotEmpty)
                      SettingsRow(
                        icon: CupertinoIcons.trash,
                        color: c.danger,
                        title: 'Delete all saves & states',
                        chevron: false,
                        danger: true,
                        onTap: _deleteAllData,
                      ),
                    if (g.playSeconds > 0)
                      SettingsRow(
                        icon: CupertinoIcons.arrow_counterclockwise,
                        color: c.warn,
                        title: 'Reset play time',
                        chevron: false,
                        onTap: _resetStats,
                      ),
                    if (g.inLibrary && !g.isDiscSheet)
                      SettingsRow(
                        icon: CupertinoIcons.delete_solid,
                        color: c.danger,
                        title: 'Delete game from phone',
                        chevron: false,
                        danger: true,
                        onTap: _deleteRom,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════ Backup details sheet ═══════════════════════════

String _restoreTitle(RestoreResult r) {
  if (r.cancelled) return 'Restore cancelled';
  if (r.failed > 0 || r.missing > 0) return 'Restore finished with problems';
  return 'Restore finished';
}

String _restoreMessage(RestoreResult r) {
  final parts = <String>[
    '${r.restored} ${r.restored == 1 ? 'file' : 'files'} restored.',
    if (r.failed > 0) '${r.failed} could not be written.',
    if (r.missing > 0) '${r.missing} were missing from the backup folder.',
    if (r.safetyCopy != null)
      'The files that were replaced are kept in a "Before restore" backup.',
  ];
  return parts.join(' ');
}

class _BackupSheet extends StatefulWidget {
  const _BackupSheet({
    required this.backup,
    required this.gameNames,
    required this.onChanged,
  });
  final BackupInfo backup;
  final List<String> gameNames;
  final Future<void> Function() onChanged;

  @override
  State<_BackupSheet> createState() => _BackupSheetState();
}

class _BackupSheetState extends State<_BackupSheet> {
  final _bk = SaveBackupService.instance;

  /// Files of the backup grouped by the game they belong to (longest game name wins, the same
  /// rule the library uses). Files of no known game land under null.
  Map<String?, List<BackupEntry>> _groups() {
    final names = [...widget.gameNames]
      ..sort((a, b) => b.length.compareTo(a.length));
    final map = <String?, List<BackupEntry>>{};
    for (final e in widget.backup.files) {
      String? owner;
      for (final n in names) {
        if (e.name.startsWith('$n.')) {
          owner = n;
          break;
        }
      }
      (map[owner] ??= []).add(e);
    }
    return map;
  }

  Future<void> _restore({String? game}) async {
    final b = widget.backup;
    final count = game == null ? b.fileCount : b.entriesFor(game).length;
    final title = game == null ? null : ConsoleSystem.cleanTitle(game);
    final ok = await _askDialog(
      context,
      game == null ? 'Restore this whole backup?' : 'Restore $title?',
      '$count files from ${_fmtDateTime(b.createdAt)} replace the current ones. What gets '
          'replaced is first kept as a "Before restore" backup, so you can undo this. '
          'Do it only while no game is running.',
      'Restore',
      destructive: false,
    );
    if (!ok || !mounted) return;
    final r = await _runProgress<RestoreResult>(
      context,
      title: 'Restoring',
      onCancel: _bk.cancel,
      job: (report) => _bk.restore(b, onlyGame: game, onProgress: report),
    );
    if (!mounted || r == null) return;
    await widget.onChanged();
    if (!mounted) return;
    await _infoDialog(context, _restoreTitle(r), _restoreMessage(r));
  }

  Future<void> _delete() async {
    final ok = await _askDialog(
      context,
      'Delete this backup?',
      'The copy from ${_fmtDateTime(widget.backup.createdAt)} '
          '(${JedManagerService.formatBytes(widget.backup.bytes)}) is removed. '
          'Your current saves are not touched.',
      'Delete',
    );
    if (!ok || !mounted) return;
    await _bk.delete(widget.backup);
    await widget.onChanged();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final b = widget.backup;
    final h = MediaQuery.sizeOf(context).height;
    final groups = _groups();
    final owners = groups.keys.whereType<String>().toList()
      ..sort(
        (x, y) => ConsoleSystem.cleanTitle(
          x,
        ).toLowerCase().compareTo(ConsoleSystem.cleanTitle(y).toLowerCase()),
      );
    final other = groups[null];

    int bytesOf(List<BackupEntry> l) => l.fold(0, (a, e) => a + e.bytes);

    Widget restoreIcon(VoidCallback onTap) => InkResponse(
      onTap: onTap,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          CupertinoIcons.arrow_counterclockwise,
          size: 20,
          color: c.accent,
        ),
      ),
    );

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: h * 0.88, maxWidth: 640),
        child: Material(
          color: c.groupedBg,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            side: BorderSide(color: c.hairline, width: c.hairlineWidth),
          ),
          child: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              shrinkWrap: true,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    b.isSafetyCopy
                        ? 'Before restore'
                        : (b.label.isEmpty ? 'Backup' : b.label),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: c.displayFont,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: c.primaryText,
                    ),
                  ),
                ),
                SettingsGroup(
                  title: 'Info',
                  children: [
                    SettingsRow(
                      icon: CupertinoIcons.calendar,
                      color: c.accent,
                      title: 'Made',
                      value: _fmtDateTime(b.createdAt),
                      chevron: false,
                    ),
                    SettingsRow(
                      icon: CupertinoIcons.doc_on_doc_fill,
                      color: c.accent,
                      title: 'Contents',
                      subtitle: b.includesStates
                          ? 'Saves and save states'
                          : 'Saves only',
                      value:
                          '${b.fileCount} files · ${JedManagerService.formatBytes(b.bytes)}',
                      chevron: false,
                    ),
                  ],
                ),
                SettingsGroup(
                  title: 'Restore',
                  footer:
                      'Restoring replaces the current files with the ones in this backup. '
                      'Whatever is replaced is saved first as a "Before restore" backup.',
                  children: [
                    SettingsRow(
                      icon: CupertinoIcons.arrow_counterclockwise,
                      color: c.accent,
                      title: 'Restore everything',
                      subtitle: '${b.fileCount} files',
                      chevron: false,
                      onTap: b.fileCount == 0 ? null : () => _restore(),
                    ),
                  ],
                ),
                if (owners.isNotEmpty || (other != null && other.isNotEmpty))
                  SettingsGroup(
                    title: 'Games in this backup',
                    children: [
                      for (final g in owners)
                        SettingsRow(
                          icon: CupertinoIcons.game_controller_solid,
                          color: c.accent,
                          title: ConsoleSystem.cleanTitle(g),
                          subtitle:
                              '${groups[g]!.length} files · ${JedManagerService.formatBytes(bytesOf(groups[g]!))}',
                          chevron: false,
                          trailing: restoreIcon(() => _restore(game: g)),
                        ),
                      if (other != null && other.isNotEmpty)
                        SettingsRow(
                          icon: CupertinoIcons.doc_fill,
                          color: c.secondaryText,
                          title: 'Other files',
                          subtitle:
                              '${other.length} files · ${JedManagerService.formatBytes(bytesOf(other))} (games not in the library, memory cards...)',
                          chevron: false,
                        ),
                    ],
                  ),
                SettingsGroup(
                  children: [
                    SettingsRow(
                      icon: CupertinoIcons.trash,
                      color: c.danger,
                      title: 'Delete this backup',
                      chevron: false,
                      danger: true,
                      onTap: _delete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════ Progress helpers (old-folder import + backups) ═══════════════════

final List<String> _monthNames = const [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Nov 26, 2026 · 3:45 PM"
String _fmtDateTime(DateTime d) {
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final mm = d.minute.toString().padLeft(2, '0');
  final ap = d.hour < 12 ? 'AM' : 'PM';
  return '${_monthNames[d.month - 1]} ${d.day}, ${d.year} · $h12:$mm $ap';
}

Future<bool> _askDialog(
  BuildContext context,
  String title,
  String message,
  String action, {
  bool destructive = true,
}) async {
  final r = await showCupertinoDialog<bool>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        CupertinoDialogAction(
          isDestructiveAction: destructive,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return r == true;
}

Future<void> _infoDialog(
  BuildContext context,
  String title,
  String message,
) async {
  await showCupertinoDialog<void>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Estimates the time left of a job from a smoothed speed. [update] returns null while it is
/// still too early to say (first ~2 seconds, or no progress yet).
class _Eta {
  final Stopwatch _w = Stopwatch()..start();
  double _rate = 0; // units per second, smoothed
  int _lastUnits = 0;
  int _lastMs = 0;

  Duration? update(int done, int total) {
    final ms = _w.elapsedMilliseconds;
    if (ms - _lastMs >= 400) {
      final dt = (ms - _lastMs) / 1000.0;
      final inst = (done - _lastUnits) / dt;
      if (inst >= 0) _rate = _rate == 0 ? inst : _rate * 0.8 + inst * 0.2;
      _lastUnits = done;
      _lastMs = ms;
    }
    if (ms < 2000 || _rate <= 0 || total <= 0 || done <= 0) return null;
    final left = (total - done) / _rate;
    return Duration(seconds: left.ceil().clamp(0, 359999));
  }
}

/// A progress bar that is easy to see: 12 px tall, a clearly darker track with an outline, a solid
/// accent fill that glides, and a moving stripe while the amount is not known yet.
class _BigBar extends StatelessWidget {
  const _BigBar({required this.fraction});
  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final track = c.primaryText.withValues(alpha: c.isDark ? 0.22 : 0.14);
    final radius = BorderRadius.circular(c.isDot ? 3 : 8);
    return Container(
      height: 12,
      decoration: BoxDecoration(
        color: track,
        borderRadius: radius,
        border: Border.all(
          color: c.primaryText.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: fraction == null
            ? LinearProgressIndicator(
                minHeight: 12,
                color: c.accent,
                backgroundColor: Colors.transparent,
              )
            : TweenAnimationBuilder<double>(
                tween: Tween<double>(end: fraction!.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                builder: (_, v, _) => Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: v <= 0 ? 0.0 : (v < 0.02 ? 0.02 : v),
                    heightFactor: 1,
                    child: ColoredBox(color: c.accent),
                  ),
                ),
              ),
      ),
    );
  }
}

/// "TIME LEFT   00 hr : 12 min : 05 sec". Shows "--" until the estimate is ready.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.left});
  final Duration? left;

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final d = left;
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d == null ? '--' : two(d.inHours);
    final m = d == null ? '--' : two(d.inMinutes % 60);
    final s = d == null ? '--' : two(d.inSeconds % 60);

    Widget seg(String v, String unit) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          v,
          style: TextStyle(
            fontFamily: c.displayFont,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: c.primaryText,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          unit,
          style: TextStyle(
            fontFamily: c.labelFont,
            fontSize: 11,
            letterSpacing: c.isDot ? 1 : 0.3,
            color: c.secondaryText,
          ),
        ),
      ],
    );

    Widget colon() => Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
      child: Text(
        ':',
        style: TextStyle(
          fontFamily: c.displayFont,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: c.tertiaryText,
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          d == null ? 'ESTIMATING TIME LEFT…' : 'TIME LEFT',
          style: TextStyle(
            fontFamily: c.labelFont,
            fontSize: 11,
            letterSpacing: c.isDot ? 1.2 : 0.6,
            color: c.secondaryText,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [seg(h, 'hr'), colon(), seg(m, 'min'), colon(), seg(s, 'sec')],
        ),
      ],
    );
  }
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({
    required this.title,
    required this.progress,
    required this.eta,
    required this.onCancel,
  });
  final String title;
  final ValueNotifier<BackupProgress?> progress;
  final ValueNotifier<Duration?> eta;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return PopScope(
      canPop: false,
      child: CupertinoAlertDialog(
        title: Text(title),
        content: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: ValueListenableBuilder<BackupProgress?>(
            valueListenable: progress,
            builder: (_, p, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _BigBar(fraction: p?.fraction),
                const SizedBox(height: 8),
                Text(
                  p == null
                      ? 'Getting ready…'
                      : '${p.done} / ${p.total} files'
                            '${p.fraction == null ? '' : ' · ${(p.fraction! * 100).floor()}%'}',
                  style: TextStyle(
                    fontFamily: c.labelFont,
                    fontSize: 12.5,
                    color: c.primaryText,
                  ),
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<Duration?>(
                  valueListenable: eta,
                  builder: (_, d, _) => _Countdown(left: d),
                ),
              ],
            ),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: onCancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

/// Shows a progress dialog (visible bar + hr/min/sec countdown) while [job] runs, then closes it.
Future<T?> _runProgress<T>(
  BuildContext context, {
  required String title,
  required VoidCallback onCancel,
  required Future<T> Function(BackupProgressCallback report) job,
}) async {
  final progress = ValueNotifier<BackupProgress?>(null);
  final eta = ValueNotifier<Duration?>(null);
  final calc = _Eta();
  void report(BackupProgress p) {
    progress.value = p;
    final byBytes = p.bytesTotal > 0;
    eta.value = calc.update(
      byBytes ? p.bytesDone : p.done,
      byBytes ? p.bytesTotal : p.total,
    );
  }

  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(
    showCupertinoDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressDialog(
        title: title,
        progress: progress,
        eta: eta,
        onCancel: onCancel,
      ),
    ),
  );
  try {
    return await job(report);
  } finally {
    if (navigator.mounted) navigator.pop();
    // The dialog is gone after its closing animation; dispose a moment later.
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      progress.dispose();
      eta.dispose();
    });
  }
}
