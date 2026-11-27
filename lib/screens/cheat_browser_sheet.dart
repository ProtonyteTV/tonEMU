// lib/screens/cheat_browser_sheet.dart
import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../models/console_system.dart';
import '../services/cheat_db.dart';
import '../services/theme_service.dart';

/// Lets the player pick cheats for the running game from the libretro cheat database.
/// Returns the chosen entries, or null if the sheet was dismissed.
Future<List<CheatEntry>?> showCheatBrowser(
  BuildContext context, {
  required ConsoleSystem system,
  required String romName,
  required bool Function(String code) alreadyAdded,
  Offset? anchorPoint, // lower half on a tabletop Flip
}) {
  return showModalBottomSheet<List<CheatEntry>>(
    context: context,
    anchorPoint: anchorPoint,
    isScrollControlled: true,
    // background, shape and drag handle come from the theme's bottomSheetTheme (Classic / Dot)
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.85,
      child: _CheatBrowser(
        system: system,
        romName: romName,
        alreadyAdded: alreadyAdded,
      ),
    ),
  );
}

class _CheatBrowser extends StatefulWidget {
  final ConsoleSystem system;
  final String romName;
  final bool Function(String code) alreadyAdded;
  const _CheatBrowser({
    required this.system,
    required this.romName,
    required this.alreadyAdded,
  });

  @override
  State<_CheatBrowser> createState() => _CheatBrowserState();
}

class _CheatBrowserState extends State<_CheatBrowser> {
  final _db = CheatDb.instance;
  final _query = TextEditingController();
  Timer? _debounce;

  bool _busy = true;
  String? _message; // empty / error text shown instead of the list
  List<String> _files = const [];
  String? _openFile;
  List<CheatEntry> _entries = const [];
  final Set<int> _picked = {};

  @override
  void initState() {
    super.initState();
    unawaited(_findForGame());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _findForGame() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final found = await _db.candidatesFor(widget.system, widget.romName);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _files = found;
      _message = found.isEmpty
          ? 'No cheats found for this game automatically.\n'
                'Search by name below, or check your internet connection.'
          : null;
    });
    // A single clear match opens straight away.
    if (found.length == 1) unawaited(_open(found.first));
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (q.trim().isEmpty) {
        unawaited(_findForGame());
        return;
      }
      setState(() => _busy = true);
      final all = await _db.indexFor(widget.system.type);
      if (!mounted || _query.text != q)
        return; // a newer search is already running
      final hits = CheatDb.search(all, q);
      setState(() {
        _busy = false;
        _files = hits;
        _message = hits.isEmpty
            ? (all.isEmpty
                  ? 'The cheat list could not be loaded. Check your connection.'
                  : 'No game matches "$q".')
            : null;
      });
    });
  }

  Future<void> _open(String file) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final entries = await _db.load(widget.system.type, file);
    if (!mounted) return;
    if (entries == null) {
      setState(() {
        _busy = false;
        _message = 'Could not load "$file". Check your connection.';
      });
      return;
    }
    setState(() {
      _busy = false;
      _openFile = file;
      _entries = entries;
      _picked.clear();
    });
  }

  String _title(String file) => file.replaceFirst(RegExp(r'\.cht$'), '');

  @override
  Widget build(BuildContext context) {
    final note = CheatDb.supportNote(widget.system.type);
    final c = XEmuColors.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        12 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_openFile != null)
                IconButton(
                  icon: Icon(Icons.arrow_back, color: c.primaryText),
                  onPressed: () => setState(() => _openFile = null),
                ),
              Expanded(
                child: Text(
                  _openFile == null ? 'Cheat database' : _title(_openFile!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.primaryText,
                    fontFamily: c.displayFont,
                    fontSize: c.isDot ? 20 : 17,
                    fontWeight: c.isDot ? FontWeight.w900 : FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                note,
                style: TextStyle(
                  color: c.warn,
                  fontFamily: c.labelFont,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (_openFile == null)
            TextField(
              controller: _query,
              onChanged: _onQuery,
              style: TextStyle(color: c.primaryText, fontFamily: c.labelFont),
              cursorColor: c.accent,
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search, color: c.secondaryText),
                hintText: 'Search ${widget.system.shortName} games',
              ),
            ),
          if (_busy)
            const LinearProgressIndicator(
              minHeight: 2,
            ), // colors: progressIndicatorTheme
          Expanded(child: _body()),
          if (_openFile != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: Text(
                  _picked.isEmpty
                      ? 'Select cheats to add'
                      : 'Add ${_picked.length} cheat${_picked.length == 1 ? '' : 's'}',
                ),
                onPressed: _picked.isEmpty
                    ? null
                    : () => Navigator.pop(context, [
                        for (final i in _picked.toList()..sort()) _entries[i],
                      ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    final c = XEmuColors.of(context);
    if (_message != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _message!,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.secondaryText, fontFamily: c.labelFont),
          ),
        ),
      );
    }
    if (_openFile == null) {
      return ListView(
        children: [
          for (final f in _files)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.sports_esports, color: c.secondaryText),
              title: Text(_title(f), style: TextStyle(color: c.primaryText)),
              onTap: () => _open(f),
            ),
        ],
      );
    }
    final all = _picked.length == _entries.length;
    return ListView(
      children: [
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: all,
          activeColor: c.accent,
          checkColor: Colors.white,
          title: Text(
            'Select all',
            style: TextStyle(color: c.secondaryText, fontFamily: c.labelFont),
          ),
          onChanged: (v) => setState(() {
            _picked.clear();
            if (v == true)
              _picked.addAll(List.generate(_entries.length, (i) => i));
          }),
        ),
        for (var i = 0; i < _entries.length; i++)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _picked.contains(i),
            activeColor: c.accent,
            checkColor: Colors.white,
            title: Text(
              _entries[i].desc,
              style: TextStyle(color: c.primaryText),
            ),
            subtitle: Text(
              widget.alreadyAdded(_entries[i].code)
                  ? 'Already in your list'
                  : _entries[i].code,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.tertiaryText,
                fontFamily: c.labelFont,
                fontSize: 11,
              ),
            ),
            onChanged: (v) => setState(() {
              if (v == true) {
                _picked.add(i);
              } else {
                _picked.remove(i);
              }
            }),
          ),
      ],
    );
  }
}
