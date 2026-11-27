// lib/screens/bios_screen.dart
import 'package:file_picker/file_picker.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../services/bios_registry.dart';
import '../services/theme_service.dart';

/// One place for every BIOS / firmware file. The user just picks files (or a zip, or a whole
/// folder); [BiosRegistry] renames and sorts them. Each system shows what it needs, what is
/// already installed, and what happens if it is missing.
class BiosScreen extends StatefulWidget {
  const BiosScreen({super.key});

  @override
  State<BiosScreen> createState() => _BiosScreenState();
}

class _BiosScreenState extends State<BiosScreen> {
  List<GroupStatus> _status = [];
  bool _loading = true;
  bool _busy = false;

  static const _green = Color(0xFF34C759);
  static const _orange = Color(0xFFFF9500);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await BiosRegistry.scan();
    if (!mounted) return;
    setState(() {
      _status = s;
      _loading = false;
    });
  }

  // ───────────────────────── Actions ─────────────────────────

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
    );
    if (result == null || !mounted) return;
    final paths = [
      for (final f in result.files)
        if (f.path != null) f.path!,
    ];
    await _runImport(() => BiosRegistry.importPaths(paths));
    try {
      await FilePicker.platform.clearTemporaryFiles();
    } catch (_) {}
  }

  Future<void> _pickFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose your BIOS folder',
    );
    if (dir == null || !mounted) return;
    await _runImport(() => BiosRegistry.importFolder(dir));
  }

  Future<void> _runImport(Future<ImportReport> Function() job) async {
    setState(() => _busy = true);
    ImportReport report;
    try {
      report = await job();
    } catch (e) {
      report = ImportReport()..errors.add('Import failed: $e');
    }
    await _refresh();
    if (!mounted) return;
    setState(() => _busy = false);
    await _showReport(report);
  }

  Future<void> _confirmRemove(SlotStatus s) async {
    final f = s.file;
    if (f == null) return;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text('Remove ${f.name}?'),
        content: const Text('You can import it again at any time.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await BiosRegistry.remove(f);
    await _refresh();
  }

  Future<void> _showReport(ImportReport r) async {
    if (!mounted) return;
    final c = XEmuColors.of(context);
    final nothing = r.isEmpty;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.cardBg,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width > 700
            ? 560
            : double.infinity,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        Widget line(IconData icon, Color color, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(fontSize: 14, color: c.primaryText),
                ),
              ),
            ],
          ),
        );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nothing ? 'Nothing was imported' : 'Import finished',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: c.primaryText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final t in r.imported)
                    line(CupertinoIcons.checkmark_circle_fill, _green, t),
                  if (r.ppssppFonts >= 0)
                    line(
                      r.ppssppFonts > 0
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.exclamationmark_triangle_fill,
                      r.ppssppFonts > 0 ? _green : _orange,
                      r.ppssppFonts > 0
                          ? 'PPSSPP system fonts installed (${r.ppssppFonts} files)'
                          : 'That PPSSPP zip contained no font (.pgf) files',
                    ),
                  for (final t in r.badSize)
                    line(
                      CupertinoIcons.exclamationmark_triangle_fill,
                      _orange,
                      '$t has an unusual size. It may be a bad or modified dump.',
                    ),
                  for (final t in r.unknown)
                    line(
                      CupertinoIcons.question_circle_fill,
                      c.secondaryText,
                      '$t was not recognised. It was copied to the general system folder.',
                    ),
                  for (final t in r.errors)
                    line(
                      CupertinoIcons.xmark_circle_fill,
                      const Color(0xFFFF3B30),
                      t,
                    ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton.filled(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      borderRadius: BorderRadius.circular(12),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ───────────────────────── UI pieces ─────────────────────────

  ({String text, Color color}) _chip(GroupStatus g, XEmuColors c) =>
      switch (g.level) {
        GroupLevel.ready => (text: 'Ready', color: _green),
        GroupLevel.incomplete => (text: 'Incomplete', color: _orange),
        GroupLevel.needsFiles => (text: 'Needs files', color: _orange),
        GroupLevel.recommended => (text: 'Recommended', color: c.accent),
        GroupLevel.optional => (text: 'Optional', color: c.secondaryText),
      };

  Widget _summary(XEmuColors c) {
    final needs = _status.where((g) => g.level == GroupLevel.needsFiles).length;
    final ready = _status.where((g) => g.level == GroupLevel.ready).length;
    final String title;
    final String sub;
    if (needs > 0) {
      title = '$needs ${needs == 1 ? 'system needs' : 'systems need'} files';
      sub = 'Games for those systems will not start until you add them.';
    } else {
      title = 'Everything required is installed';
      sub =
          '$ready of ${_status.length} systems fully set up. The rest work without extra files.';
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.hairline, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                needs > 0
                    ? CupertinoIcons.exclamationmark_circle_fill
                    : CupertinoIcons.checkmark_seal_fill,
                color: needs > 0 ? _orange : _green,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: c.primaryText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(sub, style: TextStyle(fontSize: 13, color: c.secondaryText)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: CupertinoButton.filled(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  borderRadius: BorderRadius.circular(12),
                  onPressed: _busy ? null : _pickFiles,
                  child: Text(
                    _busy ? 'Importing…' : 'Import files',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CupertinoButton(
                  color: c.secondaryFill,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  borderRadius: BorderRadius.circular(12),
                  onPressed: _busy ? null : _pickFolder,
                  child: Text(
                    'Import folder',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: c.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Pick files, a .zip, or your whole BIOS folder. tonEMU finds the ones it knows, '
            'fixes upper/lower-case names and puts each in the right place.',
            style: TextStyle(fontSize: 12, color: c.secondaryText),
          ),
        ],
      ),
    );
  }

  String _expectedNames(BiosSlot s) {
    final names = s.files.map((f) => f.name).toList();
    if (names.length <= 3) return names.join(' or ');
    return '${names.take(3).join(', ')} +${names.length - 3} more';
  }

  Widget _slotRow(SlotStatus st, XEmuColors c) {
    final slot = st.slot;
    final IconData icon;
    final Color color;
    final String detail;
    switch (st.state) {
      case SlotState.found:
        icon = CupertinoIcons.checkmark_circle_fill;
        color = _green;
        detail =
            '${st.file!.name}  ·  ${BiosRegistry.formatSize(st.size ?? 0)}';
      case SlotState.badSize:
        icon = CupertinoIcons.exclamationmark_triangle_fill;
        color = _orange;
        detail =
            '${st.file!.name}  ·  ${BiosRegistry.formatSize(st.size ?? 0)} (unusual size, may be a bad dump)';
      case SlotState.missing:
        icon = slot.need == BiosNeed.required
            ? CupertinoIcons.exclamationmark_circle_fill
            : CupertinoIcons.circle;
        color = slot.need == BiosNeed.required ? _orange : c.tertiaryText;
        detail = _expectedNames(slot);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 9, 8, 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        slot.label,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color: c.primaryText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      slot.need.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: slot.need == BiosNeed.required
                            ? _orange
                            : c.tertiaryText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  detail,
                  style: TextStyle(fontSize: 12, color: c.secondaryText),
                ),
                if (slot.hint != null && !st.ok)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      slot.hint!,
                      style: TextStyle(fontSize: 11.5, color: c.tertiaryText),
                    ),
                  ),
              ],
            ),
          ),
          if (st.ok &&
              st.file != null &&
              st.slot.files.first.dir != 'PPSSPP/flash0/font')
            IconButton(
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              icon: Icon(CupertinoIcons.trash, size: 17, color: c.tertiaryText),
              onPressed: () => _confirmRemove(st),
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _groupCard(GroupStatus g, XEmuColors c) {
    final chip = _chip(g, c);
    final needsAttention =
        g.level == GroupLevel.needsFiles || g.level == GroupLevel.incomplete;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.hairline, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<String>('bios_${g.group.id}'),
          initiallyExpanded: needsAttention,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          childrenPadding: EdgeInsets.zero,
          shape: const Border(),
          collapsedShape: const Border(),
          iconColor: c.tertiaryText,
          collapsedIconColor: c.tertiaryText,
          leading: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: g.group.color,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(g.group.icon, color: Colors.white, size: 17),
          ),
          title: Text(
            g.group.title,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: c.primaryText,
            ),
          ),
          subtitle: Text(
            '${g.group.systems}  ·  ${g.found} of ${g.slots.length} files',
            style: TextStyle(fontSize: 12.5, color: c.secondaryText),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: chip.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              chip.text,
              style: TextStyle(
                color: chip.color,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          children: [
            Divider(height: 0.5, thickness: 0.5, color: c.hairline),
            for (var i = 0; i < g.slots.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 0.5,
                  thickness: 0.5,
                  indent: 46,
                  color: c.hairline,
                ),
              _slotRow(g.slots[i], c),
            ],
            Divider(height: 0.5, thickness: 0.5, color: c.hairline),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      g.group.without,
                      style: TextStyle(fontSize: 12, color: c.secondaryText),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _pickFiles,
                    child: const Text('Add files'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final wide = MediaQuery.sizeOf(context).width > 700;
    return c.dotted(
      Scaffold(
        backgroundColor: c.pageBg,
        appBar: AppBar(
          backgroundColor: c.pageBg,
          centerTitle: true,
          title: const Text(
            'BIOS & System Files',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
        ),
        body: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : SafeArea(
                top: false,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: wide ? 1080 : double.infinity,
                    ),
                    child: RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        padding: const EdgeInsets.only(bottom: 36),
                        children: [
                          _summary(c),
                          if (wide)
                            // Landscape / tablet: system cards in two columns.
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    children: [
                                      for (
                                        var i = 0;
                                        i < _status.length;
                                        i += 2
                                      )
                                        _groupCard(_status[i], c),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    children: [
                                      for (
                                        var i = 1;
                                        i < _status.length;
                                        i += 2
                                      )
                                        _groupCard(_status[i], c),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          else
                            for (final g in _status) _groupCard(g, c),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                            child: Text(
                              BiosRegistry.noFilesNeeded,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: c.secondaryText,
                              ),
                            ),
                          ),
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
