// lib/screens/core_settings_screen.dart
import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../services/core_catalog.dart';
import '../services/core_hints.dart';
import '../services/core_presets.dart';
import '../services/core_settings.dart';
import '../services/emulator_bridge.dart';
import '../services/theme_service.dart';

/// Edit every option of one emulator core with full Light & Dark mode support.
class CoreSettingsScreen extends StatefulWidget {
  final String coreLibName;
  final bool live;

  const CoreSettingsScreen({
    super.key,
    required this.coreLibName,
    this.live = false,
  });

  @override
  State<CoreSettingsScreen> createState() => _CoreSettingsScreenState();
}

class _CoreSettingsScreenState extends State<CoreSettingsScreen> {
  List<CoreOption> _options = [];
  Map<String, String> _overrides = {};
  AppliedPreset? _appliedPreset;
  String _query = '';
  bool _onlyModified = false;
  OptionCategory? _category;
  bool _loading = true;
  bool _fromCatalog = false;
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  /// Category of each option, worked out once. CorePresets.categoryOf is keyword matching, and
  /// the list used to repeat it for every option, for every category, on every rebuild.
  final Map<String, OptionCategory> _catCache = {};
  OptionCategory _catOf(CoreOption o) =>
      _catCache.putIfAbsent(o.key, () => CorePresets.categoryOf(o));

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final overrides = await CoreSettings.loadOverrides(widget.coreLibName);
    var options = <CoreOption>[];
    if (widget.live) {
      options = await EmulatorBridge.getCoreOptions();
      if (options.isNotEmpty) {
        await CoreSettings.saveSchema(widget.coreLibName, options);
      }
    }
    if (options.isEmpty) {
      options = await CoreSettings.loadSchema(widget.coreLibName);
    }
    var fromCatalog = false;
    if (options.isEmpty) {
      options = CoreCatalog.forCore(widget.coreLibName);
      fromCatalog = true;
    }
    options.removeWhere((o) => o.isIneffective);
    // Hide values that crash cores / exhaust GPU memory and mark restart-only options.
    options = [
      for (final o in options) CoreSettings.safeOption(o, live: widget.live),
    ];
    // Drop saved values that are empty or unsafe (older builds allowed them and they would
    // crash the core again on every launch).
    for (final k in [
      for (final e in overrides.entries)
        if (e.value.trim().isEmpty ||
            CoreSettings.isBlockedValue(e.key, e.value))
          e.key,
    ]) {
      overrides.remove(k);
      await CoreSettings.clearOverride(widget.coreLibName, k);
    }
    final renderer = CoreSettings.rendererOption(widget.coreLibName);
    if (renderer != null) {
      options.removeWhere((o) => o.key == renderer.key);
      options.add(renderer);
    }
    options.sort(
      (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );
    final applied = await CorePresets.loadApplied(widget.coreLibName);
    if (!mounted) return;
    setState(() {
      _appliedPreset = applied;
      _overrides = overrides;
      _options = options;
      _fromCatalog = fromCatalog;
      _loading = false;
    });
  }

  /// The option's real default. The first listed value is only a guess (it is wrong for e.g.
  /// Yabause frameskip / threads and Mupen64 screen size), so known defaults win.
  String _default(CoreOption o) {
    final known = CoreCatalog.defaultFor(o.key);
    if (known != null && (o.values.isEmpty || o.values.contains(known))) {
      return known;
    }
    return o.values.isNotEmpty ? o.values.first : o.current;
  }

  /// Updates the value shown for options after a reset. Without this the row kept showing the
  /// value the game had when the screen opened, as if "Reset" had done nothing.
  void _setCurrent(Map<String, String> vals) {
    _options = [
      for (final o in _options)
        vals.containsKey(o.key)
            ? CoreOption(
                key: o.key,
                current: vals[o.key]!,
                label: o.label,
                values: o.values,
              )
            : o,
    ];
  }

  Set<String> get _activePresets => CorePresets.activeLevels(
    widget.coreLibName,
    _overrides,
    applied: _appliedPreset,
  );

  String _shown(CoreOption o) =>
      _overrides[o.key] ?? (o.current.isEmpty ? _default(o) : o.current);

  /// True while a live change is being sent to the core: extra taps are ignored so changes can
  /// never pile up on a core that is still rebuilding its renderer.
  bool _applying = false;

  void _note(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(milliseconds: 2200),
        ),
      );
  }

  /// Sends [changes] to the running core in ONE call. Options that can't change mid-game are
  /// only saved. Returns a short message for the user, or null when everything applied now.
  Future<String?> _applyLive(Map<String, String> changes) async {
    if (!widget.live || changes.isEmpty) return null;
    final immediate = {
      for (final e in changes.entries)
        if (!CoreSettings.needsRestart(e.key)) e.key: e.value,
    };
    final deferred = changes.length - immediate.length;
    var ok = true;
    if (immediate.isNotEmpty) {
      // If this change takes the app down, the next launch starts with defaults.
      await CoreSettings.beginRiskyChange(widget.coreLibName);
      ok = await EmulatorBridge.setCoreOptions(immediate);
      if (ok) {
        Future<void>.delayed(
          const Duration(seconds: 8),
          () => CoreSettings.markLaunchStable(widget.coreLibName),
        );
      } else {
        await CoreSettings.markLaunchStable(widget.coreLibName);
      }
    }
    if (!ok) return 'Game is still loading - saved, applies next launch';
    if (deferred == changes.length) {
      return 'Saved - applies next time the game starts';
    }
    if (deferred > 0) {
      return '$deferred option(s) apply next time the game starts';
    }
    return null;
  }

  Future<void> _set(CoreOption o, String value) async {
    if (_applying) return;
    final v = value.trim();
    if (v.isEmpty) {
      _note('Value can\'t be empty');
      return;
    }
    if (CoreSettings.isBlockedValue(o.key, v)) {
      _note('That value is not supported on phones');
      return;
    }
    _applying = true;
    try {
      await CoreSettings.setOverride(widget.coreLibName, o.key, v);
      if (mounted) setState(() => _overrides[o.key] = v);
      final msg = await _applyLive({o.key: v});
      if (msg != null) _note(msg);
    } finally {
      _applying = false;
    }
  }

  Future<void> _reset(CoreOption o) async {
    if (_applying) return;
    _applying = true;
    try {
      await CoreSettings.clearOverride(widget.coreLibName, o.key);
      final d = _default(o);
      if (mounted) {
        setState(() {
          _overrides.remove(o.key);
          if (d.isNotEmpty) _setCurrent({o.key: d});
        });
      }
      if (d.isNotEmpty) {
        final msg = await _applyLive({o.key: d});
        if (msg != null) _note(msg);
      }
    } finally {
      _applying = false;
    }
  }

  Future<void> _resetAll() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Reset All Options?'),
        content: Text(
          'Restore ${CoreSettings.coreTitle(widget.coreLibName)} to its defaults.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true || _applying) return;
    _applying = true;
    try {
      final defaults = <String, String>{
        for (final o in _options)
          if (_overrides.containsKey(o.key) && _default(o).isNotEmpty)
            o.key: _default(o),
      };
      await CoreSettings.clearAll(widget.coreLibName);
      if (mounted) {
        setState(() {
          _overrides.clear();
          _setCurrent(defaults);
        });
      }
      // One combined update instead of dozens of separate changes.
      final msg = await _applyLive(defaults);
      if (msg != null) _note(msg);
    } finally {
      _applying = false;
    }
  }

  Future<void> _applyPreset(CorePreset p) async {
    if (_applying) return;
    _applying = true;
    try {
      final wanted = CorePresets.forCore(widget.coreLibName, p.id);
      final byKey = {for (final o in _options) o.key: o};
      final chosen = <String, String>{};
      for (final e in wanted.entries) {
        final o = byKey[e.key];
        if (o == null || o.isRegion) continue;
        if (e.value.trim().isEmpty ||
            CoreSettings.isBlockedValue(e.key, e.value)) {
          continue;
        }
        var value = e.value;
        if (!_fromCatalog) {
          final m = CorePresets.matchValue(o, e.value);
          if (m == null) continue;
          value = m;
        }
        if (CoreSettings.isBlockedValue(e.key, value)) continue;
        chosen[e.key] = value;
      }
      if (chosen.isNotEmpty) {
        await CoreSettings.setOverrides(widget.coreLibName, chosen);
        await CorePresets.rememberApplied(widget.coreLibName, p.id, chosen);
      }
      if (!mounted) return;
      setState(() {
        _overrides.addAll(chosen);
        if (chosen.isNotEmpty) _appliedPreset = AppliedPreset(p.id, chosen);
      });
      // All live-safe options go to the core together, in a single update.
      final liveMsg = await _applyLive(chosen);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              chosen.isEmpty
                  ? 'No matching options in this core yet. Launch a game once and try again.'
                  : '${p.label}: ${chosen.length} options set'
                        '${widget.live ? (liveMsg == null ? '' : ' - $liveMsg') : ' (applies on next launch)'}',
            ),
          ),
        );
    } finally {
      _applying = false;
    }
  }

  Future<void> _edit(CoreOption o, XEmuColors c) async {
    final shown = _shown(o);
    if (o.values.isNotEmpty) {
      final size = MediaQuery.sizeOf(context);
      final landscape = size.width > size.height;
      final picked = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        // Landscape: a narrow, centered, taller sheet instead of a full-width 60% one.
        constraints: BoxConstraints(
          maxWidth: landscape ? 560 : double.infinity,
        ),
        backgroundColor: c.cardBg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) =>
            _PickerSheet(option: o, selected: shown, landscape: landscape),
      );
      if (picked != null) await _set(o, picked);
    } else {
      final ctrl = TextEditingController(text: shown);
      final text = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: c.cardBg,
          title: Text(o.label, style: TextStyle(color: c.primaryText)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            style: TextStyle(color: c.primaryText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (text != null) await _set(o, text);
    }
  }

  // ───────── Widgets ─────────

  IconData _presetIcon(String id) => switch (id) {
    'perf' => CupertinoIcons.bolt_fill,
    'balanced' => CupertinoIcons.slider_horizontal_3,
    _ => CupertinoIcons.sparkles,
  };

  Widget _presetBar(XEmuColors c) {
    IconData icon(String id) => _presetIcon(id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          for (final p in CorePresets.presets)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => _applyPreset(p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _activePresets.contains(p.id)
                          ? c.accent.withValues(alpha: 0.12)
                          : c.cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _activePresets.contains(p.id)
                            ? c.accent
                            : c.hairline,
                        width: _activePresets.contains(p.id) ? 1.4 : 0.6,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon(p.id), size: 19, color: c.accent),
                        const SizedBox(height: 3),
                        Text(
                          p.label,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: c.primaryText,
                          ),
                        ),
                        Text(
                          p.hint,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: c.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterRow(XEmuColors c) {
    final present = OptionCategory.values
        .where((cat) => _options.any((o) => _catOf(o) == cat))
        .toList();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        children: [
          ChoiceChip(
            label: const Text('All'),
            selected: _category == null && !_onlyModified,
            onSelected: (_) => setState(() {
              _category = null;
              _onlyModified = false;
            }),
          ),
          const SizedBox(width: 6),
          FilterChip(
            avatar: const Icon(CupertinoIcons.pencil, size: 14),
            label: Text('Modified (${_overrides.length})'),
            selected: _onlyModified,
            onSelected: (v) => setState(() => _onlyModified = v),
          ),
          for (final cat in present) ...[
            const SizedBox(width: 6),
            ChoiceChip(
              avatar: Icon(cat.icon, size: 15),
              label: Text(cat.label),
              selected: _category == cat,
              onSelected: (v) => setState(() => _category = v ? cat : null),
            ),
          ],
        ],
      ),
    );
  }

  // ───────── Landscape helpers ─────────

  Widget _searchField(XEmuColors c, {EdgeInsets? padding}) => Padding(
    padding: padding ?? const EdgeInsets.fromLTRB(16, 10, 16, 2),
    child: Container(
      height: 38,
      decoration: BoxDecoration(
        color: c.secondaryFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) {
          _searchDebounce?.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 140), () {
            if (mounted) setState(() => _query = v.trim());
          });
        },
        style: TextStyle(color: c.primaryText, fontSize: 15),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          prefixIcon: Icon(
            CupertinoIcons.search,
            size: 18,
            color: c.secondaryText,
          ),
          hintText: 'Search options',
          hintStyle: TextStyle(color: c.secondaryText, fontSize: 15),
        ),
      ),
    ),
  );

  String get _infoText => _fromCatalog
      ? 'Common options. The full list appears after you play a game with this core once. Region is always US.'
      : widget.live
      ? 'Region is always US. Changes apply to the running game and are saved for this core.'
      : 'Region is always US. Saved for every game on this core; some only apply after restarting the game.';

  Widget _presetList(XEmuColors c) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
    child: Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.hairline, width: 0.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < CorePresets.presets.length; i++) ...[
            if (i > 0)
              Divider(
                height: 0.5,
                thickness: 0.5,
                indent: 40,
                color: c.hairline,
              ),
            InkWell(
              onTap: () => _applyPreset(CorePresets.presets[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Icon(
                      _presetIcon(CorePresets.presets[i].id),
                      size: 18,
                      color: c.accent,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        CorePresets.presets[i].label,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: c.primaryText,
                        ),
                      ),
                    ),
                    Text(
                      CorePresets.presets[i].hint,
                      style: TextStyle(fontSize: 11, color: c.secondaryText),
                    ),
                    if (_activePresets.contains(CorePresets.presets[i].id)) ...[
                      const SizedBox(width: 8),
                      Icon(
                        CupertinoIcons.checkmark_alt,
                        size: 16,
                        color: c.accent,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _sideItem({
    required IconData icon,
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
    required XEmuColors c,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1.5),
      child: Material(
        color: selected ? c.accent.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? c.accent : c.secondaryText,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? c.accent : c.primaryText,
                    ),
                  ),
                ),
                Text(
                  '$count',
                  style: TextStyle(fontSize: 12, color: c.secondaryText),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Landscape left pane: search, presets, category navigation. Scrolls on its own.
  Widget _sidebar(XEmuColors c) {
    final present = OptionCategory.values
        .where((cat) => _options.any((o) => _catOf(o) == cat))
        .toList();
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _searchField(c, padding: const EdgeInsets.fromLTRB(12, 8, 12, 2)),
          if (CorePresets.hasPresets(widget.coreLibName)) _presetList(c),
          const SizedBox(height: 10),
          _sideItem(
            icon: CupertinoIcons.square_grid_2x2,
            label: 'All',
            count: _options.length,
            selected: _category == null && !_onlyModified,
            onTap: () => setState(() {
              _category = null;
              _onlyModified = false;
            }),
            c: c,
          ),
          _sideItem(
            icon: CupertinoIcons.pencil,
            label: 'Modified',
            count: _overrides.length,
            selected: _onlyModified,
            onTap: () => setState(() => _onlyModified = !_onlyModified),
            c: c,
          ),
          for (final cat in present)
            _sideItem(
              icon: cat.icon,
              label: cat.label,
              count: _options.where((o) => _catOf(o) == cat).length,
              selected: _category == cat,
              onTap: () =>
                  setState(() => _category = _category == cat ? null : cat),
              c: c,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 14, 0),
            child: Text(
              _infoText,
              style: TextStyle(color: c.secondaryText, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }

  /// Only the rows on screen are built and laid out (a core can have 100+ options; the old
  /// ListView(children: ...) built every one of them on every rebuild).
  Widget _lazyList(List<Widget> items, {EdgeInsetsGeometry? padding}) =>
      ListView.builder(
        physics: const BouncingScrollPhysics(),
        padding: padding,
        itemCount: items.length,
        itemBuilder: (_, i) => items[i],
      );

  /// Option groups as cards; [columns] > 1 lays tiles out side by side.
  /// Each row is its own list item that draws its slice of the group card ([_CardSegment]),
  /// so the card look is unchanged but the list can be lazy.
  List<Widget> _groupWidgets(
    List<CoreOption> visible,
    XEmuColors c, {
    required int columns,
    required double margin,
  }) {
    final out = <Widget>[];
    final byCat = <OptionCategory, List<CoreOption>>{};
    for (final o in visible) {
      byCat.putIfAbsent(_catOf(o), () => []).add(o);
    }
    for (final cat in OptionCategory.values) {
      final group = byCat[cat];
      if (group == null || group.isEmpty) continue;
      out.add(_header(cat, c));
      final rowCount = (group.length + columns - 1) ~/ columns;
      for (var r = 0; r < rowCount; r++) {
        final i = r * columns;
        Widget row;
        if (columns == 1) {
          row = _tile(group[i], c);
        } else {
          final cells = <Widget>[];
          for (var j = 0; j < columns; j++) {
            if (j > 0) {
              cells.add(
                VerticalDivider(width: 0.5, thickness: 0.5, color: c.hairline),
              );
            }
            final idx = i + j;
            cells.add(
              Expanded(
                child: idx < group.length
                    ? _tile(group[idx], c)
                    : const SizedBox.shrink(),
              ),
            );
          }
          row = IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: cells,
            ),
          );
        }
        out.add(
          _CardSegment(
            first: r == 0,
            last: r == rowCount - 1,
            margin: margin,
            fill: c.cardBg,
            line: c.hairline,
            dividerIndent: columns == 1 ? 16 : 0,
            child: row,
          ),
        );
      }
    }
    if (out.isEmpty) {
      out.add(
        Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Text(
              'Nothing matches.',
              style: TextStyle(color: c.secondaryText),
            ),
          ),
        ),
      );
    }
    out.add(const SizedBox(height: 32));
    return out;
  }

  Widget _header(OptionCategory cat, XEmuColors c) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 16, 6),
    child: Row(
      children: [
        Icon(cat.icon, size: 15, color: c.accent),
        const SizedBox(width: 7),
        Text(
          cat.label.toUpperCase(),
          style: TextStyle(
            color: c.secondaryText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.7,
          ),
        ),
      ],
    ),
  );

  Widget _tile(CoreOption o, XEmuColors c) {
    if (o.isRegion) {
      return ListTile(
        enabled: false,
        leading: Icon(CupertinoIcons.lock, size: 18, color: c.secondaryText),
        title: Text(o.label, style: TextStyle(color: c.secondaryText)),
        subtitle: Text(
          CoreSettings.usValue(o) ?? 'US (always)',
          style: TextStyle(color: c.tertiaryText),
        ),
      );
    }
    final overridden = _overrides.containsKey(o.key);
    final shown = _shown(o);
    final undo = overridden
        ? IconButton(
            tooltip: 'Reset to default',
            icon: Icon(
              CupertinoIcons.arrow_uturn_left,
              size: 18,
              color: c.accent,
            ),
            onPressed: () => _reset(o),
          )
        : null;

    if (o.values.length >= 2 && o.values.length <= 3) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    o.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: overridden ? c.accent : c.primaryText,
                    ),
                  ),
                ),
                ?undo,
              ],
            ),
            if (CoreHints.of(o) != null)
              Text(
                CoreHints.of(o)!,
                style: TextStyle(fontSize: 12, color: c.secondaryText),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final v in o.values)
                  ChoiceChip(
                    label: Text(v),
                    selected: shown == v,
                    onSelected: (_) => _set(o, v),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return ListTile(
      title: Text(
        o.label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: c.primaryText,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            overridden
                ? shown
                : (o.current.isEmpty ? '$shown  ·  default' : shown),
            style: TextStyle(
              color: overridden ? c.accent : c.secondaryText,
              fontSize: 13,
            ),
          ),
          if (CoreHints.of(o) != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                CoreHints.of(o)!,
                style: TextStyle(color: c.tertiaryText, fontSize: 11.5),
              ),
            ),
        ],
      ),
      trailing:
          undo ??
          Icon(CupertinoIcons.chevron_right, size: 16, color: c.tertiaryText),
      onTap: () => _edit(o, c),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final q = _query.toLowerCase();
    final visible = _options.where((o) {
      if (_onlyModified && !_overrides.containsKey(o.key)) return false;
      if (_category != null && _catOf(o) != _category) {
        return false;
      }
      return q.isEmpty ||
          o.label.toLowerCase().contains(q) ||
          o.key.toLowerCase().contains(q);
    }).toList();

    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 640 && size.width > size.height;

    final emptyState = Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No options known for this core yet.\nLaunch any game with it once and they will appear here.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.secondaryText),
        ),
      ),
    );

    Widget body;
    if (_loading) {
      body = const Center(child: CupertinoActivityIndicator());
    } else if (_options.isEmpty) {
      body = emptyState;
    } else if (wide) {
      // Landscape: persistent sidebar on the left, options (2 columns when roomy) on the right.
      final sidebarWidth = (size.width * 0.32).clamp(250.0, 340.0);
      body = SafeArea(
        top: false,
        bottom: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: sidebarWidth, child: _sidebar(c)),
            VerticalDivider(width: 0.5, thickness: 0.5, color: c.hairline),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final columns = box.maxWidth >= 640 ? 2 : 1;
                  return _lazyList(
                    _groupWidgets(visible, c, columns: columns, margin: 12),
                    padding: const EdgeInsets.only(bottom: 8),
                  );
                },
              ),
            ),
          ],
        ),
      );
    } else {
      body = Column(
        children: [
          if (CorePresets.hasPresets(widget.coreLibName)) _presetBar(c),
          _searchField(c),
          _filterRow(c),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 4),
            child: Text(
              _infoText,
              style: TextStyle(color: c.secondaryText, fontSize: 12),
            ),
          ),
          Expanded(
            child: _lazyList(_groupWidgets(visible, c, columns: 1, margin: 16)),
          ),
        ],
      );
    }

    return c.dotted(
      Scaffold(
        backgroundColor: c.pageBg,
        appBar: AppBar(
          backgroundColor: c.pageBg,
          centerTitle: true,
          toolbarHeight: wide ? 44 : null,
          title: Text(
            '${CoreSettings.coreTitle(widget.coreLibName)} Options',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
          actions: [
            IconButton(
              tooltip: 'Reset all',
              onPressed: _overrides.isEmpty ? null : _resetAll,
              icon: const Icon(CupertinoIcons.arrow_counterclockwise, size: 20),
            ),
          ],
        ),
        body: body,
      ),
    );
  }
}

class _PickerSheet extends StatefulWidget {
  final CoreOption option;
  final String selected;
  final bool landscape;
  const _PickerSheet({
    required this.option,
    required this.selected,
    this.landscape = false,
  });

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final values = widget.option.values
        .where((v) => _q.isEmpty || v.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return SafeArea(
      child: SizedBox(
        height:
            MediaQuery.of(context).size.height *
            (widget.landscape ? 0.78 : 0.6),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.tertiaryText,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.option.label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: c.primaryText,
                  ),
                ),
              ),
            ),
            if (widget.option.values.length > 12)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: c.secondaryFill,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    onChanged: (v) => setState(() => _q = v),
                    style: TextStyle(color: c.primaryText),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 9),
                      prefixIcon: Icon(
                        CupertinoIcons.search,
                        size: 18,
                        color: c.secondaryText,
                      ),
                      hintText: 'Filter',
                      hintStyle: TextStyle(color: c.secondaryText),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                itemCount: values.length,
                separatorBuilder: (_, _) => Divider(
                  height: 0.5,
                  thickness: 0.5,
                  indent: 20,
                  color: c.hairline,
                ),
                itemBuilder: (_, i) {
                  final v = values[i];
                  return ListTile(
                    title: Text(v, style: TextStyle(color: c.primaryText)),
                    trailing: v == widget.selected
                        ? Icon(CupertinoIcons.checkmark_alt, color: c.accent)
                        : null,
                    onTap: () => Navigator.pop(context, v),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of an options card. Stacked back to back, the segments look exactly like the old
/// single rounded card (same fill, 0.5 hairline outline, 14 radius, dividers between rows) but
/// each row can be built lazily by the list.
class _CardSegment extends StatelessWidget {
  final bool first;
  final bool last;
  final double margin;
  final Color fill;
  final Color line;
  final double dividerIndent;
  final Widget child;

  const _CardSegment({
    required this.first,
    required this.last,
    required this.margin,
    required this.fill,
    required this.line,
    required this.dividerIndent,
    required this.child,
  });

  static const double _radius = 14;

  @override
  Widget build(BuildContext context) {
    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!first)
          Divider(
            height: 0.5,
            thickness: 0.5,
            indent: dividerIndent,
            color: line,
          ),
        child,
      ],
    );
    // Only the first / last row have rounded corners to clip to.
    if (first || last) {
      content = ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: first ? const Radius.circular(_radius) : Radius.zero,
          bottom: last ? const Radius.circular(_radius) : Radius.zero,
        ),
        child: content,
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: margin),
      child: CustomPaint(
        painter: _SegmentPainter(first, last, fill, line),
        child: content,
      ),
    );
  }
}

class _SegmentPainter extends CustomPainter {
  final bool first;
  final bool last;
  final Color fill;
  final Color line;
  const _SegmentPainter(this.first, this.last, this.fill, this.line);

  static const double _w = 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    const r = Radius.circular(_CardSegment._radius);
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndCorners(
      rect,
      topLeft: first ? r : Radius.zero,
      topRight: first ? r : Radius.zero,
      bottomLeft: last ? r : Radius.zero,
      bottomRight: last ? r : Radius.zero,
    );
    canvas.drawRRect(rrect, Paint()..color = fill);

    // Outline: left / right sides always, top only on the first row, bottom only on the last
    // (rows in between are separated by the Divider instead).
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        0,
        first ? 0 : _w,
        size.width,
        last ? size.height : size.height - _w,
      ),
    );
    canvas.drawRRect(
      rrect.deflate(_w / 2),
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = _w,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SegmentPainter old) =>
      old.first != first ||
      old.last != last ||
      old.fill != fill ||
      old.line != line;
}
