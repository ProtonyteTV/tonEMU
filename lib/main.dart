import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/console_system.dart';
import 'models/library_group.dart';
import 'services/app_settings.dart';
import 'services/bios_registry.dart';
import 'screens/about_screen.dart';
import 'screens/core_list_screens.dart';
import 'screens/game_screen.dart';
import 'screens/import_screen.dart';
import 'screens/jed_manager_screen.dart';
import 'services/box_art_service.dart';
import 'services/emulator_bridge.dart';
import 'services/import_service.dart';
import 'services/jed_manager_service.dart';
import 'services/state_paths.dart';
import 'services/storage_service.dart';
import 'services/theme_service.dart';
import 'widgets/controller_nav.dart';
import 'widgets/fold_support.dart';
import 'widgets/import_progress_card.dart';
import 'widgets/library_motion.dart';
import 'widgets/menu_widgets.dart' show kSaveSlots;
import 'widgets/settings_kit.dart';
import 'widgets/transitions.dart';
import 'services/core_licenses.dart';
import 'services/onboarding_service.dart';
import 'services/update_service.dart';
import 'widgets/update_sheet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // FIRST: an empty SharedPreferences store means a brand-new install (see OnboardingService).
  await OnboardingService.instance.load();
  registerCoreLicenses();
  await ThemeService.instance.load();
  await FoldShell.load();
  await StorageService.instance.init();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const TonEmuApp());
}

class TonEmuApp extends StatelessWidget {
  const TonEmuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'tonEMU',
          debugShowCheckedModeBanner: false,
          navigatorKey: appNavigatorKey,
          shortcuts: padShortcuts(),
          actions: padActions(),
          themeMode: ThemeService.instance.mode,
          theme: ThemeService.lightTheme().copyWith(
            pageTransitionsTheme: appPageTransitions,
            focusColor: Colors.black.withValues(alpha: 0.12),
          ),
          darkTheme: ThemeService.darkTheme().copyWith(
            pageTransitionsTheme: appPageTransitions,
            focusColor: Colors.white.withValues(alpha: 0.18),
          ),
          // Keeps every screen clear of the crease on folding / flip phones.
          builder: (context, child) =>
              FoldShell(child: child ?? const SizedBox.shrink()),
          home: const LibraryScreen(),
        );
      },
    );
  }
}

/// One game on disk plus the console it belongs to (decided from its file extension).
class _Game {
  final File file;
  final String name;
  final ConsoleSystem sys;
  final LibraryGroup group;
  const _Game(this.file, this.name, this.sys, this.group);
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  List<File> _romFiles = [];
  LibraryGroup? _filter;
  bool _useVulkan = false;
  bool _importing = false;

  /// Live state of the running local import (bytes, speed, cancel); shown by [ImportProgressCard].
  final ImportProgress _import = ImportProgress();

  /// 0 = recently played, 1 = A to Z, 2 = most played.
  int _sortMode = 0;
  final AppSettings _app = AppSettings.instance;

  /// File name -> time the ROM file was added (last modified), for the "Newest" sort.
  final Map<String, int> _added = {};

  /// Library layout: 0 = grid, 1 = list, 2 = compact grid (small covers), 3 = large cards.
  int _viewMode = 0;
  bool get _listView => _viewMode == 1;
  bool _hasNdsBios = false;
  bool _hasPs1Bios = false;
  String _query = '';
  int _artRevision = 0;
  SharedPreferences? _prefs;
  Map<String, String>? _device;
  final Map<String, int> _lastPlayed = {};
  final Map<String, int> _playSeconds = {};

  /// Total play time of everything recorded (also games whose ROM is gone): same number as
  /// jedManager. [_playSeconds] only covers ROMs that are in the library right now.
  int _allPlaySeconds = 0;
  final Set<String> _favorites = {};
  final Set<String> _collapsed = {};
  final TextEditingController _searchCtl = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// Shows the floating "back to top" button once the user has scrolled a screen or so down.
  final ValueNotifier<bool> _showTop = ValueNotifier<bool>(false);

  /// True while the on-screen keyboard is up. Kept out of build() on purpose: reading
  /// MediaQuery.viewInsets there rebuilt (and re-sorted) the whole library on EVERY frame of the
  /// keyboard animation. Only the dock / back-to-top button listen to this.
  final ValueNotifier<bool> _kbOpen = ValueNotifier<bool>(false);

  /// Search text is applied a moment after the last keystroke, so typing never rebuilds the whole
  /// library once per letter.
  Timer? _searchDebounce;

  // _searchedGames() result is reused until the ROM list or the query changes.
  List<File>? _gamesMemoFiles;
  String? _gamesMemoQuery;
  List<_Game> _gamesMemo = const [];

  /// Device card: false = full (model, CPU, GPU), true = just the model line.
  bool _deviceCompact = false;
  final Map<String, GlobalKey> _chipKeys = {};

  GlobalKey _chipKey(String? id) =>
      _chipKeys.putIfAbsent(id ?? '_all', GlobalKey.new);

  /// Scrolls the filter chip row so the selected chip is fully visible (L1/R1 can move it off screen).
  void _revealChip(String? id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _chipKeys[id ?? '_all']?.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// Search box focus node. With a gamepad: D-pad up/down leaves the box, B closes the keyboard.
  late final FocusNode _searchFocus = FocusNode(
    debugLabel: 'librarySearch',
    onKeyEvent: (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      final k = event.logicalKey;
      if (k == LogicalKeyboardKey.gameButtonB) {
        node.unfocus();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowDown) {
        node.focusInDirection(TraversalDirection.down);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowUp) {
        node.focusInDirection(TraversalDirection.up);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );

  /// Filter chips currently on screen, in order (null = "All"). Used by L1 / R1.
  List<LibraryGroup?> _chipOrder = const [null];

  void _cycleFilter(int step) {
    if (_chipOrder.length < 2) return;
    var i = _chipOrder.indexWhere((g) => g?.id == _filter?.id);
    if (i < 0) i = 0;
    final next = (i + step) % _chipOrder.length;
    HapticFeedback.selectionClick();
    final target = _chipOrder[next < 0 ? next + _chipOrder.length : next];
    setState(() => _filter = target);
    _revealChip(target?.id);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  /// 1 = library visible, 0 = faded to black. Dips to 0 just before a game opens and comes back
  /// when the game closes, so launching and quitting feel like one continuous transition.
  late final AnimationController _dim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(() {
      final far = _scroll.hasClients && _scroll.offset > 700;
      if (far != _showTop.value) _showTop.value = far;
    });
    _init();
    // First-run setup (new install) or "What's new" (after an update), once the library is on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Setup / What's new first; the update check only runs after that is closed, so two
      // sheets never stack on top of each other.
      OnboardingService.instance.maybeShow(context).then((_) async {
        if (!mounted) return;
        final update = await UpdateService.instance.autoCheck();
        if (update != null && mounted) await showUpdateSheet(context, update);
      });
    });
  }

  /// If the user grants "All files access" in Android Settings while the app is open, switch to
  /// /storage/emulated/0/tonEMU, move the old files over and refresh the library.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    StorageService.instance.refreshIfPermissionChanged().then((changed) async {
      if (changed) await StorageService.instance.migration;
      if (changed && mounted) {
        await _checkNdsBios();
        await _loadImportedRoms();
      }
    });
  }

  @override
  void didChangeMetrics() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final open = views.first.viewInsets.bottom > 0;
    if (open != _kbOpen.value) _kbOpen.value = open;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    _searchCtl.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    _showTop.dispose();
    _kbOpen.dispose();
    _dim.dispose();
    _import.dispose();
    super.dispose();
  }

  /// Applies the search text now (clear button, submit, Home) and drops any pending debounce.
  void _setQueryNow(String raw) {
    _searchDebounce?.cancel();
    final q = raw.trim();
    if (q == _query) return;
    setState(() => _query = q);
  }

  void _onSearchChanged(String raw) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 160), () {
      if (!mounted) return;
      final q = raw.trim();
      if (q != _query) setState(() => _query = q);
    });
  }

  /// Dock "Home": clear search + filter and jump back to the top.
  void _goHome() {
    FocusScope.of(context).unfocus();
    _searchDebounce?.cancel();
    _searchCtl.clear();
    setState(() {
      _query = '';
      _filter = null;
    });
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Tapping the app title jumps back to the top of the library (like iOS status-bar tap).
  void _scrollToTop() {
    if (!_scroll.hasClients || _scroll.offset <= 0) return;
    HapticFeedback.selectionClick();
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  void _toggleView() {
    HapticFeedback.selectionClick();
    setState(() => _viewMode = (_viewMode + 1) % 4);
    _prefs?.setInt('lib_view_mode', _viewMode);
    _snack(switch (_viewMode) {
      0 => 'Grid view',
      1 => 'List view',
      2 => 'Compact grid view',
      _ => 'Large cards view',
    });
  }

  void _toggleSort() {
    HapticFeedback.selectionClick();
    setState(() => _sortMode = (_sortMode + 1) % 4);
    _prefs?.setInt('sort_mode', _sortMode);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _snack(switch (_sortMode) {
      0 => 'Sorted by recently played',
      1 => 'Sorted A to Z',
      2 => 'Sorted by most played',
      _ => 'Sorted by recently added',
    });
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    EmulatorBridge.getDeviceInfo().then((d) {
      if (mounted && d != null) setState(() => _device = d);
    });
    _useVulkan = prefs.getBool('use_vulkan') ?? false;
    _app.load().then((_) {
      if (mounted) setState(() {});
    });
    _sortMode =
        (prefs.getInt('sort_mode') ??
                ((prefs.getBool('sort_recent') ?? true) ? 0 : 1))
            .clamp(0, 3);
    _viewMode =
        (prefs.getInt('lib_view_mode') ??
                ((prefs.getBool('lib_list_view') ?? false) ? 1 : 0))
            .clamp(0, 3);
    _deviceCompact = prefs.getBool('lib_device_compact') ?? false;
    _collapsed.addAll(prefs.getStringList('lib_collapsed') ?? const []);
    _favorites.addAll(prefs.getStringList('fav_games') ?? const []);
    _loadDiscChoices(prefs);
    _assignNewDiscs(); // first run after the update only records existing discs
    // Old files are moved to /storage/emulated/0/tonEMU in the background; refresh when done.
    StorageService.instance.migration.then((_) async {
      if (!mounted) return;
      await _checkNdsBios();
      await _loadImportedRoms();
    });
    await _checkNdsBios();
    await _loadImportedRoms();
  }

  Future<List<String>> _missingNdsBiosFiles() async {
    final sysDir = await _storageSystemDir();
    const required = ['bios7.bin', 'bios9.bin', 'firmware.bin'];
    final missing = <String>[];
    for (final name in required) {
      if (!await File('${sysDir.path}/$name').exists()) {
        missing.add(name);
      }
    }
    return missing;
  }

  Future<void> _checkNdsBios() async {
    final missing = await _missingNdsBiosFiles();
    final ps1 = await _hasPs1BiosFile();
    if (mounted) {
      setState(() {
        _hasNdsBios = missing.isEmpty;
        _hasPs1Bios = ps1;
      });
    }
  }

  /// Any one PS1 BIOS revision is enough to boot the console shell.
  Future<bool> _hasPs1BiosFile() async {
    final sysDir = await _storageSystemDir();
    final group = BiosRegistry.groups.firstWhere((g) => g.id == 'ps1');
    for (final slot in group.slots) {
      for (final f in slot.files) {
        for (final n in [f.name, ...f.aliases]) {
          if (await File('${sysDir.path}/${f.dir.isEmpty ? '' : '${f.dir}/'}$n')
              .exists()) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// ROMs live in `<tonEMU>/roms` (/storage/emulated/0/tonEMU/roms with All Files Access).
  Future<Directory> _getRomsDir() async {
    if (!StorageService.instance.isInitialized) {
      await StorageService.instance.init();
    }
    final romsDir = StorageService.instance.romsDir;
    if (!await romsDir.exists()) await romsDir.create(recursive: true);
    return romsDir;
  }

  /// BIOS / firmware folder: `<tonEMU>/system` (same folder the native cores read).
  Future<Directory> _storageSystemDir() async {
    if (!StorageService.instance.isInitialized) {
      await StorageService.instance.init();
    }
    return StorageService.instance.systemDir;
  }

  static String _nameOf(File f) => f.uri.pathSegments.last;

  /// Library name of a game file (its file name).
  static String _gameNameOf(File f) {
    final segs = f.uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return segs.last;
  }

  /// Reports .cue sheets in the library whose track files are missing.
  Future<void> _warnMissingTracks() async {
    final dir = await _getRomsDir();
    final files = await dir
        .list()
        .where((e) => e is File)
        .cast<File>()
        .toList();
    final have = {for (final f in files) _nameOf(f).toLowerCase()};
    final problems = <String>[];
    for (final f in files) {
      if (!f.path.toLowerCase().endsWith('.cue')) continue;
      final missing = [
        for (final t in ImportService.cueTracks(f))
          if (!have.contains(t.toLowerCase())) t,
      ];
      if (missing.isNotEmpty) {
        problems.add(
          '${_nameOf(f)} is missing: ${missing.take(2).join(', ')}'
          '${missing.length > 2 ? '…' : ''}',
        );
      }
    }
    if (problems.isNotEmpty && mounted) {
      _snack('${problems.join('\n')}\nImport the .bin together with the .cue.');
    }
  }

  Future<void> _loadImportedRoms() async {
    final entities = <File>[];
    try {
      final dir = await _getRomsDir();
      await for (final e in dir.list()) {
        if (e is File) entities.add(e);
      }
    } catch (_) {
      // Folder missing / unreadable (storage permission just changed, SD card removed...):
      // show an empty library instead of an uncaught error.
    }
    for (final f in entities) {
      try {
        _added[_gameNameOf(f)] =
            (await f.lastModified()).millisecondsSinceEpoch;
      } catch (_) {}
    }
    final prefs = _prefs;
    if (prefs != null) {
      await prefs.reload();
      for (final f in entities) {
        final n = _gameNameOf(f);
        final t = prefs.getInt('played_$n');
        if (t != null) _lastPlayed[n] = t;
        final pt = prefs.getInt('playtime_$n');
        if (pt != null) _playSeconds[n] = pt;
      }
      _allPlaySeconds = JedManagerService.totalPlaySecondsOf(prefs);
    }
    if (mounted) setState(() => _romFiles = entities);
  }

  // ───────── console choice for .cue / .chd ─────────

  bool _assigningDiscs = false;

  void _loadDiscChoices(SharedPreferences prefs) {
    ConsoleSystem.fileOverrides.clear();
    try {
      final raw = prefs.getString('disc_systems');
      if (raw != null) {
        (jsonDecode(raw) as Map<String, dynamic>).forEach((k, v) {
          for (final t in ConsoleType.values) {
            if (t.name == v) ConsoleSystem.fileOverrides[k] = t;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _saveDiscChoices() async {
    await _prefs?.setString(
      'disc_systems',
      jsonEncode({
        for (final e in ConsoleSystem.fileOverrides.entries)
          e.key: e.value.name,
      }),
    );
  }

  /// Asks which console each newly imported .cue / .chd belongs to. Files that were already in
  /// the library before this feature existed are left on PS1 without asking.
  Future<void> _assignNewDiscs() async {
    final prefs = _prefs;
    if (prefs == null || _assigningDiscs) return;
    _assigningDiscs = true;
    try {
      final dir = await _getRomsDir();
      final names = <String>[
        await for (final e in dir.list())
          if (e is File && ConsoleSystem.isPickable(_gameNameOf(e)))
            _gameNameOf(e),
      ];
      final seen = (prefs.getStringList('disc_seen') ?? const <String>[])
          .toSet();
      if (!prefs.containsKey('disc_seen')) {
        await prefs.setStringList('disc_seen', names);
        return;
      }
      final pending = [
        for (final n in names)
          if (!seen.contains(n)) n,
      ]..sort();
      for (var i = 0; i < pending.length; i++) {
        if (!mounted) break;
        final type = await _askConsole(pending[i], i + 1, pending.length);
        // Closing the sheet keeps the old behavior (PS1) and does not ask again.
        ConsoleSystem.fileOverrides[pending[i].toLowerCase()] =
            type ?? ConsoleType.ps1;
        seen.add(pending[i]);
        await prefs.setStringList('disc_seen', seen.toList());
        await _saveDiscChoices();
      }
      if (pending.isNotEmpty) await _loadImportedRoms();
    } catch (_) {
    } finally {
      _assigningDiscs = false;
    }
  }

  Future<ConsoleType?> _askConsole(String fileName, int index, int total) {
    return showCupertinoModalPopup<ConsoleType>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text('Which console is this game for?'),
        message: Text(
          '${ConsoleSystem.cleanTitle(fileName)}\n$fileName'
          '${total > 1 ? '\n($index of $total)' : ''}',
        ),
        actions: [
          for (final t in ConsoleSystem.discTypes)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, t),
              child: Text(ConsoleSystem.ofType(t)?.name ?? t.name),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Skip (PlayStation 1)'),
        ),
      ),
    );
  }

  void _snack(String msg) {
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

  /// "+" button / empty-state button: opens the import screen (Wi-Fi transfer + local pickers).
  Future<void> _showImportSheet() async {
    if (_importing) return;
    // Without "All files access" everything would land in app-private storage (invisible in
    // file managers), so ask for it before importing / starting a Wi-Fi transfer.
    if (StorageService.instance.canRequestAllFilesAccess) {
      await StorageService.instance.requestAllFilesAccess();
      await _loadImportedRoms();
    }
    final romsDir = await _getRomsDir();
    if (!mounted) return;
    await Navigator.push(
      context,
      CupertinoPageRoute<void>(
        builder: (_) => ImportScreen(
          romsDir: romsDir,
          onPickFiles: _importRoms,
          onPickFolder: _importFolder,
          onLibraryChanged: () async {
            await _loadImportedRoms();
            await _assignNewDiscs();
          },
        ),
      ),
    );
    if (mounted) await _loadImportedRoms();
    if (mounted) await _assignNewDiscs();
  }

  Future<void> _importRoms() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        // Android copies every chosen file into the app cache before returning. For big discs
        // that takes a while, so show it instead of leaving the library looking frozen.
        onFileLoading: (status) {
          if (!mounted || status != FilePickerStatus.picking) return;
          _import.reset();
          setState(() => _importing = true);
        },
      );
    } catch (e) {
      if (mounted) setState(() => _importing = false);
      _snack('Could not open the file picker: $e');
      return;
    }
    if (result == null) {
      if (mounted) setState(() => _importing = false);
      return;
    }
    await _copyIn([
      for (final f in result.files)
        if (f.path != null) (path: f.path!, name: f.name),
    ]);
  }

  /// Scans a folder (and all subfolders) for supported games and imports them in one go.
  Future<void> _importFolder() async {
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null || !mounted) return;

    _import.reset();
    _import.setPhase(ImportPhase.scanning);
    setState(() => _importing = true);
    final found = <({String path, String name})>[];
    try {
      final all = <File>[];
      await for (final e in Directory(
        dirPath,
      ).list(recursive: true, followLinks: false)) {
        if (_import.cancelled) break;
        if (e is File) {
          all.add(e);
          _import.noteScanned(all.length);
        }
      }
      final referenced = ImportService.cueReferenced(all);
      for (final f in all) {
        final name = _nameOf(f);
        // Every track a .cue sheet points to belongs to that game, whatever its name.
        if (referenced.contains(f.path.toLowerCase())) {
          found.add((path: f.path, name: name));
          continue;
        }
        final ext = name.contains('.')
            ? name.split('.').last.toLowerCase()
            : '';
        if (ConsoleSystem.fromExtension(ext) == null) continue;
        // A lone .bin is usually a BIOS or data file; only take it when a .cue references it.
        if (ext == 'bin') {
          continue;
        }
        found.add((path: f.path, name: name));
      }
    } catch (e) {
      if (mounted) setState(() => _importing = false);
      _snack('Could not read that folder: $e');
      return;
    }
    if (_import.cancelled) {
      if (mounted) setState(() => _importing = false);
      _snack('Import cancelled');
      return;
    }
    if (found.isEmpty) {
      if (mounted) setState(() => _importing = false);
      _snack('No supported games found in that folder');
      return;
    }
    await _copyIn(found);
  }

  /// Copies the given files into the library, with progress and one combined summary.
  Future<void> _copyIn(List<({String path, String name})> items) async {
    if (!mounted) return;
    if (items.isEmpty) {
      setState(() => _importing = false);
      return;
    }
    // A folder scan already did reset(); only start over when nothing is running yet.
    if (!_importing) _import.reset();
    setState(() => _importing = true);
    var cancelled = false;
    try {
      final romsDir = await _getRomsDir();
      final copier = ImportCopier(romsDir);
      await copier.begin();
      // Sizes first, so the card can show "x MB of y MB" and an estimate from the start.
      final sizes = <int>[];
      for (final it in items) {
        try {
          sizes.add(await File(it.path).length());
        } catch (_) {
          sizes.add(0);
        }
      }
      _import.beginCopy(
        files: items.length,
        bytes: sizes.fold<int>(0, (a, b) => a + b),
      );
      var imported = 0;
      var duplicates = 0;
      final perGroup = <String, int>{};
      final unsupported = <String>[];
      final failed = <String>[];
      // Track files named by a picked .cue/.gdi/.ccd/.mds (track01.bin, track02.raw...) have no
      // console of their own, but must be copied along with the game.
      final referenced = ImportService.cueReferenced([
        for (final it in items) File(it.path),
      ]);

      for (var i = 0; i < items.length; i++) {
        if (_import.cancelled) {
          cancelled = true;
          break;
        }
        final it = items[i];
        _import.startFile(it.name, sizes[i]);
        final sys = ConsoleSystem.forFile(it.name);
        final isTrack = referenced.contains(it.path.toLowerCase());
        if (sys == null && !isTrack) {
          unsupported.add(it.name);
        } else {
          try {
            // Never overwrites a different file with the same name and never leaves a
            // half-copied ROM in the library (see ImportCopier).
            final r = await copier.put(
              File(it.path),
              it.name,
              progress: _import,
            );
            if (sys == null) {
              // companion track file: copied, but not counted as a game
            } else if (r.outcome == CopyOutcome.duplicate) {
              duplicates++;
            } else {
              imported++;
              final g = LibraryGroup.of(sys.type);
              if (g != null) {
                perGroup[g.shortName] = (perGroup[g.shortName] ?? 0) + 1;
              }
            }
          } on ImportCancelled {
            cancelled = true;
            break;
          } catch (_) {
            failed.add(it.name);
          }
        }
        _import.endFile();
      }

      _import.setPhase(ImportPhase.finishing);
      await copier.finish();

      try {
        await FilePicker.platform.clearTemporaryFiles();
      } catch (_) {}

      await _loadImportedRoms();
      await _warnMissingTracks();
      await _assignNewDiscs();

      String names(List<String> l) =>
          '${l.take(2).join(', ')}${l.length > 2 ? '…' : ''}';
      final parts = <String>[
        if (cancelled) 'Import cancelled',
        if (imported > 0)
          'Imported $imported game(s): ${perGroup.entries.map((e) => '${e.value} ${e.key}').join(', ')}',
        if (duplicates > 0) '$duplicates already in your library',
        if (unsupported.isNotEmpty)
          '${unsupported.length} unsupported skipped: ${names(unsupported)}',
        if (failed.isNotEmpty)
          '${failed.length} failed to copy: ${names(failed)}',
      ];
      if (parts.isNotEmpty) _snack(parts.join('\n'));
    } catch (e) {
      _snack('Import failed: $e');
    } finally {
      if (mounted) {
        setState(() => _importing = false);
      }
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      CupertinoPageRoute(builder: (_) => const CoreListScreen()),
    );
    await _app.load(); // library switches changed in Settings
    if (mounted) setState(() {});
    await _checkNdsBios();
  }

  /// jedManager: ROMs, saves, states, play time and the old-folder import. Play time, favorites
  /// and the ROM list can all change in there, so the library reloads them when it closes.
  Future<void> _openManager() async {
    await Navigator.push(
      context,
      CupertinoPageRoute(builder: (_) => const JedManagerScreen()),
    );
    if (!mounted) return;
    final prefs = _prefs;
    if (prefs != null) {
      await prefs.reload();
      _favorites
        ..clear()
        ..addAll(prefs.getStringList('fav_games') ?? const []);
      _playSeconds.clear();
      _lastPlayed.clear();
    }
    await _loadImportedRoms();
  }

  /// Opens a game with the "power on" transition: library fades to black, the game is revealed
  /// out of black, and the library fades back in once the game is closed.
  Future<void> _openGame(Widget screen) async {
    HapticFeedback.lightImpact();
    await _dim.reverse();
    if (!mounted) return;
    try {
      await Navigator.push(
        context,
        GameLaunchRoute<void>(builder: (_) => screen),
      );
    } finally {
      if (mounted) _dim.forward();
    }
  }

  Future<void> _launchNdsBios() async {
    final missing = await _missingNdsBiosFiles();
    if (missing.isNotEmpty) {
      _snack(
        'Missing DS BIOS file(s): ${missing.join(', ')}. Import them in Settings.',
      );
      return;
    }

    final ndsSys = ConsoleSystem.allSystems.firstWhere(
      (s) => s.type == ConsoleType.nds,
    );
    final core = await EmulatorBridge.resolveCore(ndsSys.coreLibName);
    if (core == null) {
      _snack(
        'Core for ${ndsSys.shortName} not found (${ndsSys.coreLibName}). '
        'Add it to android/app/src/main/jniLibs/arm64-v8a/',
      );
      return;
    }

    if (!mounted) return;
    await _openGame(
      GameScreen(
        system: ndsSys,
        useVulkan: _useVulkan,
        coreFile: core,
        bootBios: true,
      ),
    );
  }

  Future<void> _launchPs1Bios() async {
    if (!await _hasPs1BiosFile()) {
      _snack('No PlayStation BIOS found. Import one in Settings.');
      return;
    }
    final sys = ConsoleSystem.allSystems.firstWhere(
      (s) => s.type == ConsoleType.ps1,
    );
    final core = await EmulatorBridge.resolveCore(sys.coreLibName);
    if (core == null) {
      _snack(
        'Core for ${sys.shortName} not found (${sys.coreLibName}). '
        'Add it to android/app/src/main/jniLibs/arm64-v8a/',
      );
      return;
    }
    if (!mounted) return;
    await _openGame(
      GameScreen(
        system: sys,
        useVulkan: _useVulkan,
        coreFile: core,
        bootBios: true,
      ),
    );
  }

  static String _fmtStamp(DateTime t) {
    const months = [
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
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final mm = t.minute.toString().padLeft(2, '0');
    return '${months[t.month - 1]} ${t.day}, $h12:$mm ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  /// Asked BEFORE the game screen opens. Returns true = continue from the auto-save,
  /// false = fresh start, null = cancelled. Never prompts for a game that has no auto-save yet
  /// (first run).
  Future<bool?> _askResume(
    _Game g,
    String coreFile, {
    bool direct = false,
  }) async {
    try {
      if (!StorageService.instance.isInitialized) {
        await StorageService.instance.init();
      }
      final name = g.file.uri.pathSegments.last;
      final statesDir = StorageService.instance.statesDir;
      final key = StatePaths.coreKey(coreFile);
      // Old un-keyed states are copied to this core's name first (never for a core that
      // replaced an older one), so a state from another core can never be offered or loaded.
      await StatePaths.migrateLegacy(statesDir, name, key, slots: kSaveSlots);
      final f = File(StatePaths.path(statesDir, name, key, 'auto'));
      if (!await f.exists() || await f.length() == 0) return false;
      await AppSettings.instance.load();
      final mode = AppSettings.instance.resumeMode;
      if (mode == ResumeMode.fresh) return false;
      // Smart mode (and the Continue Playing card) never ask: the game offers "Start over" instead.
      if (direct || mode == ResumeMode.smart) return true;
      final stamp = await f.lastModified();
      if (!mounted) return null;
      // Tapping outside the dialog cancels. "Always continue" turns the prompt off for good.
      final answer = await showCupertinoDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text(ConsoleSystem.cleanTitle(name)),
          content: Text('\nAuto-saved ${_fmtStamp(stamp)}'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('New game'),
            ),
            CupertinoDialogAction(
              onPressed: () async {
                AppSettings.instance.resumeMode = ResumeMode.smart;
                await AppSettings.instance.save();
                if (ctx.mounted) Navigator.pop(ctx, true);
                _snack(
                  'Games now continue automatically. Change it in Settings',
                );
              },
              child: const Text('Always continue'),
            ),
          ],
        ),
      );
      return answer;
    } catch (_) {
      return false;
    }
  }

  Future<void> _launch(
    _Game g, {
    bool direct = false,
    bool fresh = false,
  }) async {
    if (!await g.file.exists()) {
      _snack('Game file is missing');
      await _loadImportedRoms();
      return;
    }
    final core = await EmulatorBridge.resolveCore(g.sys.coreLibName);
    if (core == null) {
      _snack(
        'Core for ${g.sys.shortName} not found (${g.sys.coreLibName}). '
        'Add it to android/app/src/main/jniLibs/arm64-v8a/',
      );
      return;
    }
    // Ask before anything launches (only when this game has been played before).
    final resume = fresh ? false : await _askResume(g, core, direct: direct);
    if (resume == null || !mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastPlayed[g.name] = now;
    await _prefs?.setInt('played_${g.name}', now);

    if (!mounted) return;
    await _openGame(
      GameScreen(
        romFile: g.file,
        system: g.sys,
        useVulkan: _useVulkan,
        coreFile: core,
        resumeFromAuto: resume,
      ),
    );
    if (mounted) await _loadImportedRoms();
  }

  /// Picks a random game from what is currently shown (respects search and console filter).
  Future<void> _surpriseMe() async {
    final pool = [
      for (final g in _searchedGames())
        if (_filter == null || g.group.id == _filter!.id) g,
    ];
    if (pool.isEmpty) {
      _snack('Nothing to pick from yet');
      return;
    }
    HapticFeedback.mediumImpact();
    final g = pool[math.Random().nextInt(pool.length)];
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('How about…'),
        content: Text('${ConsoleSystem.cleanTitle(g.name)}\n${g.sys.name}'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Play'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _launch(g);
  }

  static String _fmtSize(int bytes) {
    if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(2)} GB';
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  Future<void> _showGameInfo(_Game g) async {
    var size = 0;
    try {
      size = await g.file.length();
    } catch (_) {}
    final secs = _playSeconds[g.name] ?? 0;
    final last = _lastPlayed[g.name];
    final added = _added[g.name];
    final lines = <String>[
      g.sys.name,
      'File: ${g.name}',
      if (size > 0) 'Size: ${_fmtSize(size)}',
      if (added != null && added > 0) 'Added: ${_ago(added)}',
      'Play time: ${secs > 0 ? _fmtPlayTime(secs) : 'never played'}',
      if (last != null) 'Last played: ${_ago(last)}',
    ];
    if (!mounted) return;
    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(ConsoleSystem.cleanTitle(g.name)),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(lines.join('\n')),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleFavorite(_Game g) async {
    HapticFeedback.lightImpact();
    setState(() {
      if (!_favorites.remove(g.name)) _favorites.add(g.name);
    });
    await _prefs?.setStringList('fav_games', _favorites.toList());
  }

  static String _fmtPlayTime(int secs) {
    if (secs < 60) return '<1m';
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  /// "<rom>.<core>.auto.state" of the core this game runs on, or null if that core is missing.
  Future<File?> _autoStateFile(_Game g) async {
    final core = await EmulatorBridge.resolveCore(g.sys.coreLibName);
    if (core == null) return null;
    return File(
      StatePaths.path(
        StorageService.instance.statesDir,
        g.file.uri.pathSegments.last,
        StatePaths.coreKey(core),
        'auto',
      ),
    );
  }

  Future<File?> _autoBackupFile(_Game g) async {
    final auto = await _autoStateFile(g);
    return auto == null ? null : File('${auto.path}.bak');
  }

  /// Swaps the backed-up auto-save (made when a game was restarted) back in as the auto-save.
  Future<void> _restoreAutoBackup(_Game g) async {
    try {
      final bak = await _autoBackupFile(g);
      final auto = await _autoStateFile(g);
      if (bak == null || auto == null || !await bak.exists()) {
        _snack('No earlier auto-save found');
        return;
      }
      await bak.copy('${auto.path}.tmp');
      await File('${auto.path}.tmp').rename(auto.path);
      _snack('Earlier auto-save restored. Open the game to continue');
    } catch (_) {
      _snack('Could not restore the earlier auto-save');
    }
  }

  Future<void> _showGameOptions(_Game g) async {
    final title = ConsoleSystem.cleanTitle(g.name);
    var hasBackup = false;
    try {
      if (!StorageService.instance.isInitialized) {
        await StorageService.instance.init();
      }
      final bak = await _autoBackupFile(g);
      hasBackup = bak != null && await bak.exists();
    } catch (_) {}
    if (!mounted) return;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        message: Text('${g.sys.name} (${g.sys.shortName})'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _toggleFavorite(g);
            },
            child: Text(
              _favorites.contains(g.name)
                  ? 'Remove from Favorites'
                  : 'Add to Favorites',
            ),
          ),
          if (_lastPlayed.containsKey(g.name))
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _launch(g, fresh: true);
              },
              child: const Text('Start Fresh (ignore auto-save)'),
            ),
          if (hasBackup)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _restoreAutoBackup(g);
              },
              child: const Text('Restore Earlier Auto-save'),
            ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _showGameInfo(g);
            },
            child: const Text('Game Info'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              final picked = await BoxArtService.instance.pickCustomCover(
                g.sys,
                g.name,
              );
              if (picked != null && mounted) {
                imageCache.clear();
                imageCache.clearLiveImages();
                setState(() => _artRevision++);
                _snack('Updated box art for $title');
              }
            },
            child: const Text('Set Custom Box Art'),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              await BoxArtService.instance.clearCover(g.sys, g.name);
              if (mounted) {
                imageCache.clear();
                imageCache.clearLiveImages();
                setState(() => _artRevision++);
              }
            },
            child: const Text('Re-download Box Art'),
          ),
          if (_lastPlayed.containsKey(g.name) ||
              (_playSeconds[g.name] ?? 0) > 0)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _clearHistory(g);
              },
              child: const Text('Clear Play History'),
            ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              _confirmDelete(g);
            },
            child: const Text('Remove Game'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  /// Drops the last-played time and play time so the game leaves Continue Playing.
  Future<void> _clearHistory(_Game g) async {
    setState(() {
      _lastPlayed.remove(g.name);
      _playSeconds.remove(g.name);
    });
    await _prefs?.remove('played_${g.name}');
    await _prefs?.remove('playtime_${g.name}');
    _snack('Cleared play history for ${ConsoleSystem.cleanTitle(g.name)}');
  }

  Future<void> _confirmDelete(_Game g) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Remove Game?'),
        content: Text(
          'Remove "${ConsoleSystem.cleanTitle(g.name)}" from your library?',
        ),
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
    if (ok == true) {
      try {
        await BoxArtService.instance.clearCover(g.sys, g.name);
        // Track files of a .cue/.gdi/.ccd/.mds game are hidden from the library, so they would
        // stay on disk forever once the sheet is gone. Collect them first (case-insensitively),
        // but keep any that another remaining sheet still points to.
        final stale = _ownedTrackFiles(g.file);
        await g.file.delete();
        for (final t in stale) {
          try {
            await t.delete();
          } catch (_) {}
        }
        _favorites.remove(g.name);
        _playSeconds.remove(g.name);
        _lastPlayed.remove(
          g.name,
        ); // else a re-imported copy reappears under Continue Playing
        await _prefs?.setStringList('fav_games', _favorites.toList());
        await _prefs?.remove('playtime_${g.name}');
        await _prefs?.remove('played_${g.name}');
      } catch (_) {}
      await _loadImportedRoms();
    }
  }

  /// Files that belong only to [sheet] (a disc sheet's tracks), not to any other disc sheet.
  List<File> _ownedTrackFiles(File sheet) {
    final lower = sheet.path.toLowerCase();
    final isSheet =
        lower.endsWith('.cue') ||
        lower.endsWith('.gdi') ||
        lower.endsWith('.ccd') ||
        lower.endsWith('.mds');
    if (!isSheet) return const [];
    final others = [
      for (final f in _romFiles)
        if (f.path != sheet.path) f,
    ];
    final stillUsed = ImportService.cueReferenced(others);
    final mine = ImportService.cueReferenced([sheet]);
    return [
      for (final f in _romFiles)
        if (f.path != sheet.path &&
            mine.contains(f.path.toLowerCase()) &&
            !stillUsed.contains(f.path.toLowerCase()))
          f,
    ];
  }

  /// Collapses every shelf, or opens them all again when everything is already collapsed.
  void _setAllCollapsed(Iterable<LibraryGroup> groups, bool collapse) {
    HapticFeedback.selectionClick();
    setState(() {
      if (collapse) {
        _collapsed.addAll(groups.map((g) => g.id));
      } else {
        _collapsed.removeAll(groups.map((g) => g.id));
      }
    });
    _prefs?.setStringList('lib_collapsed', _collapsed.toList());
  }

  void _toggleDeviceCompact() {
    HapticFeedback.selectionClick();
    setState(() => _deviceCompact = !_deviceCompact);
    _prefs?.setBool('lib_device_compact', _deviceCompact);
  }

  void _toggleCollapsed(LibraryGroup g) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_collapsed.remove(g.id)) _collapsed.add(g.id);
    });
    _prefs?.setStringList('lib_collapsed', _collapsed.toList());
  }

  int _recency(_Game g) => _lastPlayed[g.name] ?? 0;

  int _byName(_Game a, _Game b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());

  List<_Game> _searchedGames() {
    // Same ROM list + same query = same answer. Without this every rebuild (theme toggle, a
    // favourite tap, an art refresh...) re-parsed every file name in the library.
    if (identical(_gamesMemoFiles, _romFiles) && _gamesMemoQuery == _query) {
      return _gamesMemo;
    }
    final referenced = ImportService.cueReferenced(_romFiles);
    final q = _query.toLowerCase();
    final out = <_Game>[];
    for (final file in _romFiles) {
      final name = _gameNameOf(file);
      final ext = name.split('.').last;
      final sys = ConsoleSystem.forFile(name);
      if (sys == null) continue;
      final group = LibraryGroup.of(sys.type);
      if (group == null) continue;
      if (referenced.contains(file.path.toLowerCase()) &&
          !const {"cue", "gdi", "ccd", "mds"}.contains(ext.toLowerCase())) {
        continue; // a track file of a .cue game, not a game of its own
      }
      if (q.isNotEmpty &&
          !ConsoleSystem.cleanTitle(name).toLowerCase().contains(q) &&
          !sys.shortName.toLowerCase().contains(q) &&
          !sys.name.toLowerCase().contains(q)) {
        continue;
      }
      out.add(_Game(file, name, sys, group));
    }
    _gamesMemoFiles = _romFiles;
    _gamesMemoQuery = _query;
    return _gamesMemo = out;
  }

  static String _ago(int ms) {
    final d = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(ms),
    );
    if (d.inMinutes < 1) return 'Just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    if (d.inDays < 30) return '${d.inDays}d ago';
    return '${d.inDays ~/ 30}mo ago';
  }

  // ───────── iOS Widgets ─────────

  Widget _searchField(XEmuColors c, {double height = 38}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: c.isDot ? c.cardBg : c.secondaryFill,
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: c.hairline, width: c.hairlineWidth),
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _searchCtl,
        builder: (_, _, _) => TextField(
          controller: _searchCtl,
          focusNode: _searchFocus,
          onChanged: _onSearchChanged,
          textInputAction: TextInputAction.search,
          onSubmitted: (v) {
            _setQueryNow(v);
            FocusScope.of(context).unfocus();
          },
          style: TextStyle(fontSize: 14.5, color: c.primaryText),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(
              vertical: height == 34 ? 7 : 9,
            ),
            prefixIcon: Icon(
              CupertinoIcons.search,
              size: 17,
              color: c.secondaryText,
            ),
            suffixIcon: _searchCtl.text.isNotEmpty
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _searchCtl.clear();
                      _setQueryNow('');
                    },
                    child: Icon(
                      CupertinoIcons.clear_thick_circled,
                      size: 16,
                      color: c.secondaryText,
                    ),
                  )
                : null,
            hintText: 'Search Library',
            hintStyle: TextStyle(color: c.secondaryText, fontSize: 14.5),
          ),
        ),
      ),
    );
  }

  Widget _iosSearchBar(XEmuColors c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: _searchField(c),
    );
  }

  Widget _chips(List<_Game> searched, XEmuColors c) {
    final counts = <String, int>{};
    for (final g in searched) {
      counts[g.group.id] = (counts[g.group.id] ?? 0) + 1;
    }

    Widget pill({
      required String? id,
      required String label,
      required bool selected,
      required VoidCallback onTap,
      IconData? icon,
      Color? iconColor,
    }) {
      return Padding(
        key: _chipKey(id),
        padding: const EdgeInsets.only(right: 8),
        child: PadFocusable(
          radius: 20,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
            _revealChip(id);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? c.accent : c.cardBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: selected ? c.accent : c.hairline),
              boxShadow: selected && !c.isDot
                  ? [
                      BoxShadow(
                        color: c.accent.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 14,
                    color: selected ? Colors.white : iconColor,
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: c.labelFont,
                    fontSize: c.isDot ? 11.5 : 13,
                    fontWeight: c.isDot ? FontWeight.w400 : FontWeight.w600,
                    color: selected ? Colors.white : c.primaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 46,
      // Soft fade at both ends hints that the chip row scrolls.
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => const LinearGradient(
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0.0, 0.035, 0.965, 1.0],
        ).createShader(r),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          children: [
            pill(
              id: null,
              label: 'All (${searched.length})',
              selected: _filter == null,
              onTap: () => setState(() => _filter = null),
            ),
            for (final g in LibraryGroup.all)
              if ((counts[g.id] ?? 0) > 0 ||
                  (g.id == 'nds' && _hasNdsBios) ||
                  (g.id == 'ps1' && _hasPs1Bios))
                pill(
                  id: g.id,
                  icon: g.icon,
                  iconColor: g.color,
                  label: '${g.shortName} ${counts[g.id] ?? 0}',
                  selected: _filter?.id == g.id,
                  onTap: () =>
                      setState(() => _filter = _filter?.id == g.id ? null : g),
                ),
          ],
        ),
      ),
    );
  }

  Widget _titleText(XEmuColors c, bool isLandscape) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: _scrollToTop,
    child: Text(
      'tonEMU',
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontFamily: c.displayFont,
        fontSize: (isLandscape ? 20 : 22) + (c.isDot ? 4 : 0),
        fontWeight: c.isDot ? FontWeight.w900 : FontWeight.w800,
        letterSpacing: c.isDot ? 0.5 : -0.5,
        color: c.primaryText,
      ),
    ),
  );

  Widget _sectionLabel(
    String text,
    XEmuColors c, {
    IconData? icon,
    Color? color,
    bool compact = false,
    int? count,
  }) => LibraryReveal(
    id: 'label|$text',
    from: RevealFrom.left,
    child: Padding(
      padding: EdgeInsets.fromLTRB(16, compact ? 10 : 16, 16, compact ? 8 : 10),
      child: Row(
        children: [
          if (icon != null) ...[
            // Dot theme: same flat outlined glyph badge as Settings.
            if (c.isDot)
              SettingsBadge(
                icon: icon,
                color: color ?? c.accent,
                size: compact ? 24 : 26,
              )
            else
              Icon(icon, size: compact ? 16 : 18, color: color ?? c.accent),
            SizedBox(width: c.isDot ? 9 : 7),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: compact ? 16.5 : 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: c.primaryText,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 8),
            Text(
              '$count',
              style: TextStyle(
                fontSize: compact ? 13 : 14,
                fontWeight: FontWeight.w600,
                color: c.secondaryText,
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _groupHeader(
    LibraryGroup g,
    int count,
    bool collapsed,
    bool canCollapse,
    XEmuColors c, {
    bool compact = false,
  }) {
    return LibraryReveal(
      id: 'group|${g.id}',
      from: RevealFrom.left,
      child: InkWell(
        onTap: canCollapse ? () => _toggleCollapsed(g) : null,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            compact ? 12 : 18,
            16,
            compact ? 8 : 10,
          ),
          child: Row(
            children: [
              if (c.isDot)
                SettingsBadge(
                  icon: g.icon,
                  color: g.color,
                  size: compact ? 26 : 30,
                )
              else
                Container(
                  width: compact ? 26 : 30,
                  height: compact ? 26 : 30,
                  decoration: BoxDecoration(
                    color: g.color.withValues(alpha: c.isDark ? 0.22 : 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(g.icon, color: g.color, size: compact ? 15 : 17),
                ),
              const SizedBox(width: 10),
              // Title + count take all remaining width; a long title ellipsizes instead of overflowing.
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        g.title,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 16.5 : 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: c.primaryText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: c.secondaryFill,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: c.secondaryText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (g.id == 'nds' || g.id == 'ps1')
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: PadFocusable(
                    radius: 14,
                    onTap: g.id == 'nds' ? _launchNdsBios : _launchPs1Bios,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: c.cardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: c.hairline),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.power,
                            size: 13,
                            color: (g.id == 'nds' ? _hasNdsBios : _hasPs1Bios)
                                ? g.color
                                : c.secondaryText,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'BIOS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: c.primaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (canCollapse)
                AnimatedRotation(
                  turns: collapsed ? 0 : 0.5,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    CupertinoIcons.chevron_down,
                    size: 16,
                    color: c.secondaryText,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(
    _Game g, {
    bool compact = false,
    bool dense = false,
    bool large = false,
    int index = 0,
    String scope = 'grid',
    RevealFrom from = RevealFrom.bottom,
  }) => LibraryReveal(
    id: '$scope|${g.file.path}',
    index: index,
    from: from,
    child: _BoxArtGameCard(
      key: ValueKey('${g.file.path}_$_artRevision'),
      game: g,
      compact: compact,
      dense: dense,
      large: large,
      playedAgo: _lastPlayed[g.name] == null
          ? null
          : _ago(_lastPlayed[g.name]!),
      playTime: (_playSeconds[g.name] ?? 0) <= 0
          ? null
          : _fmtPlayTime(_playSeconds[g.name]!),
      isFavorite: _favorites.contains(g.name),
      isNew: _isNew(g),
      onTap: () => _launch(g),
      onLongPress: () => _showGameOptions(g),
    ),
  );

  /// Added in the last 7 days and never played: gets a small "NEW" tag on its cover.
  bool _isNew(_Game g) {
    final added = _added[g.name];
    if (added == null || _lastPlayed.containsKey(g.name)) return false;
    if ((_playSeconds[g.name] ?? 0) > 0) return false;
    return DateTime.now().millisecondsSinceEpoch - added < 7 * 24 * 3600 * 1000;
  }

  /// Games / systems / total play time summary under the search bar.
  /// Phone model + CPU + GPU. Tap to copy (handy for bug reports / compatibility notes).
  Widget _deviceCard(Map<String, String> d, XEmuColors c) {
    final cores = d['cores'];
    final mhz = int.tryParse(d['maxMhz'] ?? '');
    final cpu = [
      d['cpu'] ?? 'Unknown',
      if (cores != null) '$cores cores',
      if (mhz != null && mhz > 0) '${(mhz / 1000).toStringAsFixed(1)} GHz',
    ].join(' · ');
    final gpu = d['gpu'];
    Widget row(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 13, color: c.secondaryText),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: c.secondaryText,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: c.primaryText),
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: Material(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            Clipboard.setData(
              ClipboardData(
                text:
                    '${d['model'] ?? ''}\nCPU: $cpu${gpu != null ? '\nGPU: $gpu' : ''}',
              ),
            );
            _snack('Device info copied');
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.hairline, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (c.isDot)
                      SettingsBadge(
                        icon: CupertinoIcons.device_phone_portrait,
                        color: c.accent,
                        size: 24,
                      )
                    else
                      Icon(
                        CupertinoIcons.device_phone_portrait,
                        size: 16,
                        color: c.accent,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        d['model'] ?? 'This device',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: c.primaryText,
                        ),
                      ),
                    ),
                    Tooltip(
                      message: _deviceCompact ? 'Show details' : 'Hide details',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _toggleDeviceCompact,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 4, 2, 4),
                          child: AnimatedRotation(
                            turns: _deviceCompact ? 0 : 0.5,
                            duration: const Duration(milliseconds: 220),
                            child: Icon(
                              CupertinoIcons.chevron_down,
                              size: 14,
                              color: c.secondaryText,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _deviceCompact
                      ? const SizedBox(width: double.infinity)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            row(Icons.memory_rounded, 'CPU', cpu),
                            if (gpu != null)
                              row(Icons.developer_board_rounded, 'GPU', gpu),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statsStrip(List<_Game> searched, XEmuColors c) {
    final systems = <String>{for (final g in searched) g.group.id}.length;
    final libSecs = _playSeconds.values.fold<int>(0, (a, b) => a + b);
    final totalSecs = _allPlaySeconds > libSecs ? _allPlaySeconds : libSecs;
    Widget tile(IconData icon, Color color, String value, String label) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
            decoration: BoxDecoration(
              color: c.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.hairline, width: 0.5),
            ),
            child: Row(
              children: [
                if (c.isDot)
                  SettingsBadge(icon: icon, color: color, size: 24)
                else
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: c.isDark ? 0.22 : 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 13, color: color),
                  ),
                const SizedBox(width: 7),
                // FittedBox shrinks the text to fit instead of cutting it ("Consol...", "12h 4...").
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color: c.primaryText,
                          ),
                        ),
                        Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 11,
                            color: c.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              tile(
                CupertinoIcons.square_grid_2x2_fill,
                c.accent,
                '${searched.length}',
                'Games',
              ),
              const SizedBox(width: 8),
              tile(
                CupertinoIcons.game_controller_solid,
                const Color(0xFF5856D6),
                '$systems',
                systems == 1 ? 'Console' : 'Consoles',
              ),
              const SizedBox(width: 8),
              tile(
                CupertinoIcons.timer_fill,
                const Color(0xFF34C759),
                totalSecs <= 0 ? '0m' : _fmtPlayTime(totalSecs),
                'Played',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            button: true,
            label: 'Surprise me with a random game',
            child: _PressScale(
              scale: 0.97,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _surpriseMe,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: c.accent.withValues(alpha: c.isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.shuffle, size: 16, color: c.accent),
                      const SizedBox(width: 6),
                      Text(
                        'Surprise Me',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: c.accent,
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

  /// Tasteful memorial footer honoring Ton at the bottom of the home screen.
  Widget _memorialFooter(XEmuColors c, {bool isLandscape = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        isLandscape ? 24 : 34,
        24,
        isLandscape ? 32 : 128,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(
            height: 1,
            thickness: 0.6,
            indent: 48,
            endIndent: 48,
            color: c.hairline,
          ),
          const SizedBox(height: 18),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: const TontonTribute(),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(XEmuColors c, {bool isLandscape = false}) =>
      SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 28,
                vertical: isLandscape ? 28 : 80,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: isLandscape ? 58 : 72,
                    height: isLandscape ? 58 : 72,
                    decoration: BoxDecoration(
                      color: c.cardBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.hairline),
                    ),
                    child: Icon(
                      CupertinoIcons.game_controller,
                      size: isLandscape ? 28 : 34,
                      color: c.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _romFiles.isEmpty
                        ? 'No Games Yet'
                        : _query.isNotEmpty
                        ? 'No results for “$_query”'
                        : 'No Matching Games',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: c.primaryText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _romFiles.isEmpty
                        ? 'Import your ROMs and they sort themselves onto shelves by console. Cover art is fetched automatically.'
                        : 'Try searching a different title or clearing your console filter.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: c.secondaryText),
                  ),
                  if (_romFiles.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    CupertinoButton(
                      onPressed: _goHome,
                      child: const Text(
                        'Clear Search & Filter',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  if (_romFiles.isEmpty) ...[
                    const SizedBox(height: 18),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final g in LibraryGroup.all)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: g.color.withValues(
                                alpha: c.isDark ? 0.22 : 0.14,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(g.icon, size: 13, color: g.color),
                                const SizedBox(width: 5),
                                Text(
                                  g.shortName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: g.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    CupertinoButton.filled(
                      borderRadius: BorderRadius.circular(14),
                      onPressed: _importing ? null : _showImportSheet,
                      child: const Text(
                        'Import Games',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _memorialFooter(c, isLandscape: isLandscape),
          ],
        ),
      );

  /// Hides [child] while the keyboard is open (the window is too short for the dock) without
  /// rebuilding the rest of the library.
  Widget _hideWithKeyboard(Widget child) => ValueListenableBuilder<bool>(
    valueListenable: _kbOpen,
    child: child,
    builder: (_, open, child) => open ? const SizedBox.shrink() : child!,
  );

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    // Targeted lookups: only rotation / safe-area changes rebuild the library. (MediaQuery.of
    // also fired on every keyboard-animation frame.)
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;

    final searched = _searchedGames();
    {
      final cnt = <String, int>{};
      for (final g in searched) {
        cnt[g.group.id] = (cnt[g.group.id] ?? 0) + 1;
      }
      _chipOrder = [
        null,
        for (final g in LibraryGroup.all)
          if ((cnt[g.id] ?? 0) > 0 ||
              (g.id == 'nds' && _hasNdsBios) ||
              (g.id == 'ps1' && _hasPs1Bios))
            g,
      ];
    }
    final shown = _filter == null
        ? searched
        : searched.where((g) => g.group.id == _filter!.id).toList();

    final byGroup = <String, List<_Game>>{};
    for (final g in shown) {
      byGroup.putIfAbsent(g.group.id, () => []).add(g);
    }
    for (final list in byGroup.values) {
      list.sort(switch (_sortMode) {
        0 => (a, b) {
          final cmp = _recency(b).compareTo(_recency(a));
          return cmp != 0 ? cmp : _byName(a, b);
        },
        2 => (a, b) {
          var cmp = (_playSeconds[b.name] ?? 0).compareTo(
            _playSeconds[a.name] ?? 0,
          );
          if (cmp == 0) cmp = _recency(b).compareTo(_recency(a));
          return cmp != 0 ? cmp : _byName(a, b);
        },
        3 => (a, b) {
          final cmp = (_added[b.name] ?? 0).compareTo(_added[a.name] ?? 0);
          return cmp != 0 ? cmp : _byName(a, b);
        },
        _ => _byName,
      });
    }

    final showNdsShelfEvenIfEmpty =
        _hasNdsBios &&
        _query.isEmpty &&
        (_filter == null || _filter?.id == 'nds');

    final showPs1ShelfEvenIfEmpty =
        _hasPs1Bios &&
        _query.isEmpty &&
        (_filter == null || _filter?.id == 'ps1');

    final recent = (_app.showRecent && _query.isEmpty && _filter == null)
        ? (searched.where((g) => _recency(g) > 0).toList()
                ..sort((a, b) => _recency(b).compareTo(_recency(a))))
              .take(10)
              .toList()
        : <_Game>[];

    final favorites = (_app.showFavorites && _query.isEmpty && _filter == null)
        ? (searched.where((g) => _favorites.contains(g.name)).toList()
            ..sort(_byName))
        : <_Game>[];

    final mostPlayed =
        (_app.showMostPlayed && _query.isEmpty && _filter == null)
        ? (searched.where((g) => (_playSeconds[g.name] ?? 0) > 0).toList()
                ..sort(
                  (a, b) => (_playSeconds[b.name] ?? 0).compareTo(
                    _playSeconds[a.name] ?? 0,
                  ),
                ))
              .take(10)
              .toList()
        : <_Game>[];

    final newAdditions =
        (_app.showNewAdditions && _query.isEmpty && _filter == null)
        ? (searched.where(_isNew).toList()..sort(
                (a, b) => (_added[b.name] ?? 0).compareTo(_added[a.name] ?? 0),
              ))
              .take(10)
              .toList()
        : <_Game>[];

    final canCollapse = _query.isEmpty && _filter == null;

    final shelfHeight = isLandscape ? 154.0 : 174.0;
    final shelfCardWidth = isLandscape ? 104.0 : 118.0;

    final slivers = <Widget>[];

    // In landscape, console filter chips scroll inside the view so they don't eat vertical space.
    if (isLandscape) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: LibraryReveal(
              id: 'chips',
              from: RevealFrom.left,
              child: _chips(searched, c),
            ),
          ),
        ),
      );
    }

    if (_query.isNotEmpty && shown.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
            child: Text(
              '${shown.length} ${shown.length == 1 ? 'result' : 'results'} for “$_query”',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: c.secondaryText,
              ),
            ),
          ),
        ),
      );
    }

    if (_query.isEmpty && _filter == null && searched.isNotEmpty) {
      if (_app.showStats) {
        slivers.add(
          SliverToBoxAdapter(
            child: LibraryReveal(id: 'stats', child: _statsStrip(searched, c)),
          ),
        );
      }
      if (_device != null) {
        slivers.add(
          SliverToBoxAdapter(
            child: LibraryReveal(
              id: 'device',
              index: 1,
              child: _deviceCard(_device!, c),
            ),
          ),
        );
      }
    }
    if (recent.isNotEmpty) {
      final hero = recent.first;
      final rest = recent.skip(1).toList();
      slivers.add(
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel(
                'Continue Playing',
                c,
                icon: CupertinoIcons.play_circle_fill,
                color: c.accent,
                compact: isLandscape,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LibraryReveal(
                  id: 'hero|${hero.file.path}',
                  child: _HeroGameCard(
                    key: ValueKey('hero_${hero.file.path}_$_artRevision'),
                    game: hero,
                    height: isLandscape ? 150 : 176,
                    playedAgo: _ago(_lastPlayed[hero.name]!),
                    playTime: (_playSeconds[hero.name] ?? 0) <= 0
                        ? null
                        : _fmtPlayTime(_playSeconds[hero.name]!),
                    onTap: () => _launch(hero, direct: true),
                    onLongPress: () => _showGameOptions(hero),
                  ),
                ),
              ),
              if (rest.isNotEmpty) ...[
                _sectionLabel(
                  'Recently Played',
                  c,
                  icon: CupertinoIcons.clock_fill,
                  color: c.secondaryText,
                  compact: isLandscape,
                  count: rest.length,
                ),
                SizedBox(
                  height: shelfHeight,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: rest.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => SizedBox(
                      width: shelfCardWidth,
                      child: _card(
                        rest[i],
                        compact: true,
                        index: i,
                        scope: 'recent',
                        from: RevealFrom.right,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (favorites.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel(
                'Favorites',
                c,
                icon: CupertinoIcons.star_fill,
                color: const Color(0xFFFFC107),
                compact: isLandscape,
                count: favorites.length,
              ),
              SizedBox(
                height: shelfHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: favorites.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => SizedBox(
                    width: shelfCardWidth,
                    child: _card(
                      favorites[i],
                      compact: true,
                      index: i,
                      scope: 'fav',
                      from: RevealFrom.right,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (mostPlayed.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel(
                'Most Played',
                c,
                icon: CupertinoIcons.flame_fill,
                color: const Color(0xFFFF7043),
                compact: isLandscape,
                count: mostPlayed.length,
              ),
              SizedBox(
                height: shelfHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: mostPlayed.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => SizedBox(
                    width: shelfCardWidth,
                    child: _card(
                      mostPlayed[i],
                      compact: true,
                      index: i,
                      scope: 'most',
                      from: RevealFrom.right,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (newAdditions.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel(
                'New Additions',
                c,
                icon: CupertinoIcons.sparkles,
                color: const Color(0xFF4DA3FF),
                compact: isLandscape,
                count: newAdditions.length,
              ),
              SizedBox(
                height: shelfHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: newAdditions.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => SizedBox(
                    width: shelfCardWidth,
                    child: _card(
                      newAdditions[i],
                      compact: true,
                      index: i,
                      scope: 'new',
                      from: RevealFrom.right,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final visibleGroups = [
      for (final g in LibraryGroup.all)
        if ((byGroup[g.id] ?? const <_Game>[]).isNotEmpty) g,
    ];
    if (canCollapse && visibleGroups.length > 1) {
      final allCollapsed = visibleGroups.every(
        (g) => _collapsed.contains(g.id),
      );
      slivers.add(
        SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
              child: PadFocusable(
                radius: 14,
                onTap: () => _setAllCollapsed(visibleGroups, !allCollapsed),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        allCollapsed
                            ? Icons.unfold_more_rounded
                            : Icons.unfold_less_rounded,
                        size: 13,
                        color: c.accent,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        allCollapsed ? 'Expand all' : 'Collapse all',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: c.accent,
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
    for (final g in LibraryGroup.all) {
      final games = byGroup[g.id] ?? const <_Game>[];
      final forceShowNds =
          (g.id == 'nds' && showNdsShelfEvenIfEmpty) ||
          (g.id == 'ps1' && showPs1ShelfEvenIfEmpty);
      if (games.isEmpty && !forceShowNds) continue;

      final collapsed = canCollapse && _collapsed.contains(g.id);
      slivers.add(
        SliverToBoxAdapter(
          child: _groupHeader(
            g,
            games.length,
            collapsed,
            canCollapse,
            c,
            compact: isLandscape,
          ),
        ),
      );
      if (!collapsed && games.isNotEmpty && _listView) {
        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 560,
                mainAxisExtent: 74,
                crossAxisSpacing: 12,
                mainAxisSpacing: 10,
              ),
              itemCount: games.length,
              itemBuilder: (_, i) {
                final gm = games[i];
                final secs = _playSeconds[gm.name] ?? 0;
                return LibraryReveal(
                  id: 'list|${gm.file.path}',
                  index: LibraryReveal.staggerFor(i),
                  child: _GameListTile(
                    key: ValueKey('list_${gm.file.path}_$_artRevision'),
                    game: gm,
                    playedAgo: _lastPlayed[gm.name] == null
                        ? null
                        : _ago(_lastPlayed[gm.name]!),
                    playTime: secs <= 0 ? null : _fmtPlayTime(secs),
                    isFavorite: _favorites.contains(gm.name),
                    onTap: () => _launch(gm),
                    onLongPress: () => _showGameOptions(gm),
                  ),
                );
              },
            ),
          ),
        );
      } else if (!collapsed && games.isNotEmpty && _viewMode == 2) {
        // Compact grid: small cover-only tiles, many per row.
        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: isLandscape ? 104 : 108,
                childAspectRatio: 0.76,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: games.length,
              itemBuilder: (_, i) => _card(
                games[i],
                dense: true,
                scope: 'dense',
                index: LibraryReveal.staggerFor(i),
              ),
            ),
          ),
        );
      } else if (!collapsed && games.isNotEmpty && _viewMode == 3) {
        // Large cards: two big covers per row (more on tablets / landscape).
        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: isLandscape ? 260 : 320,
                childAspectRatio: 0.74,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: games.length,
              itemBuilder: (_, i) => _card(
                games[i],
                large: true,
                scope: 'large',
                index: LibraryReveal.staggerFor(i),
              ),
            ),
          ),
        );
      } else if (!collapsed && games.isNotEmpty) {
        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: isLandscape ? 140 : 155,
                childAspectRatio: 0.72,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: games.length,
              itemBuilder: (_, i) => _card(
                games[i],
                compact: isLandscape,
                index: LibraryReveal.staggerFor(i),
              ),
            ),
          ),
        );
      }
    }
    slivers.add(
      SliverToBoxAdapter(child: _memorialFooter(c, isLandscape: isLandscape)),
    );

    Widget libraryScroll() => RefreshIndicator(
      onRefresh: _loadImportedRoms,
      color: c.accent,
      backgroundColor: c.cardBg,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        controller: _scroll,
        cacheExtent: 480,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: slivers,
      ),
    );

    Widget topButton({required double bottom}) => Positioned(
      right: 16,
      bottom: bottom,
      child: ValueListenableBuilder<bool>(
        valueListenable: _showTop,
        builder: (_, show, child) => IgnorePointer(
          ignoring: !show,
          child: AnimatedScale(
            scale: show ? 1 : 0.6,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            child: AnimatedOpacity(
              opacity: show ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: child,
            ),
          ),
        ),
        child: Semantics(
          button: true,
          label: 'Back to top',
          child: Material(
            color: c.frostedBar,
            shape: CircleBorder(
              side: BorderSide(color: c.hairline, width: 0.7),
            ),
            elevation: 3,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _scrollToTop,
              child: SizedBox(
                width: 42,
                height: 42,
                child: Icon(
                  CupertinoIcons.chevron_up,
                  size: 18,
                  color: c.accent,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final hasAnythingToShow =
        shown.isNotEmpty || showNdsShelfEvenIfEmpty || showPs1ShelfEvenIfEmpty;
    final appBarHeight = isLandscape ? 48.0 : 51.0;

    return CallbackShortcuts(
      bindings: {
        // Gamepad shoulder buttons switch the console filter chips.
        const SingleActivator(LogicalKeyboardKey.gameButtonLeft1): () =>
            _cycleFilter(-1),
        const SingleActivator(LogicalKeyboardKey.gameButtonRight1): () =>
            _cycleFilter(1),
      },
      child: PopScope(
        canPop: _query.isEmpty && _filter == null,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          HapticFeedback.selectionClick();
          _goHome(); // Back first clears search/filter, then leaves the app
        },
        child: ColoredBox(
          color: Colors.black,
          child: FadeTransition(
            opacity: _dim,
            child: c.dotted(
              Scaffold(
                backgroundColor: c.pageBg,
                bottomSheet: _importing
                    ? ImportProgressCard(
                        progress: _import,
                        onCancel: _import.cancel,
                      )
                    : null,
                appBar: PreferredSize(
                  preferredSize: Size.fromHeight(
                    appBarHeight + (_importing ? 3.0 : 0.5),
                  ),
                  child: ClipRect(
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.frostedBar,
                        border: Border(
                          bottom: BorderSide(color: c.hairline, width: 0.5),
                        ),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: appBarHeight,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Row(
                                  children: [
                                    if (c.isDot)
                                      const BlinkingDot()
                                    else
                                      Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: c.accent,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.gamepad_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    const SizedBox(width: 9),
                                    if (isLandscape) ...[
                                      _titleText(c, isLandscape),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxWidth: 440,
                                          ),
                                          child: _searchField(c, height: 34),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                    ] else
                                      // Takes all the room the buttons leave; the title scales
                                      // down instead of overflowing ("Most played" chip + wide
                                      // Dot display font on narrow phones).
                                      Expanded(
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: _titleText(c, isLandscape),
                                          ),
                                        ),
                                      ),
                                    _HeaderButton(
                                      tooltip: c.isDark
                                          ? 'Switch to light mode'
                                          : 'Switch to dark mode',
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        ThemeService.instance.toggleLightDark(
                                          Theme.of(context).brightness,
                                        );
                                      },
                                      child: Icon(
                                        c.isDark
                                            ? CupertinoIcons.sun_max_fill
                                            : CupertinoIcons.moon_fill,
                                        key: ValueKey(c.isDark),
                                        size: 16,
                                        color: c.isDark
                                            ? const Color(0xFFFFD60A)
                                            : c.accent,
                                      ),
                                    ),
                                    _HeaderButton(
                                      tooltip: switch (_viewMode) {
                                        0 => 'Show as list',
                                        1 => 'Show as compact grid',
                                        2 => 'Show as large cards',
                                        _ => 'Show as grid',
                                      },
                                      onTap: _toggleView,
                                      child: Icon(
                                        switch (_viewMode) {
                                          0 => CupertinoIcons.list_bullet,
                                          1 => CupertinoIcons.square_grid_3x2,
                                          2 => CupertinoIcons.square_on_square,
                                          _ => CupertinoIcons.square_grid_2x2,
                                        },
                                        key: ValueKey(_viewMode),
                                        size: 16,
                                        color: c.accent,
                                      ),
                                    ),
                                    Semantics(
                                      button: true,
                                      label: switch (_sortMode) {
                                        0 => 'Sorted by recent. Tap for A to Z',
                                        1 =>
                                          'Sorted A to Z. Tap for most played',
                                        2 => 'Sorted by most played. Tap for newest',
                                        _ => 'Sorted by newest. Tap for recent',
                                      },
                                      child: _PressScale(
                                        scale: 0.94,
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: _toggleSort,
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              4,
                                              6,
                                              0,
                                              6,
                                            ),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 11,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: c.secondaryFill,
                                                borderRadius:
                                                    BorderRadius.circular(18),
                                              ),
                                              child: AnimatedSwitcher(
                                                duration: const Duration(
                                                  milliseconds: 200,
                                                ),
                                                child: Row(
                                                  key: ValueKey(_sortMode),
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      switch (_sortMode) {
                                                        0 =>
                                                          CupertinoIcons.clock,
                                                        1 =>
                                                          CupertinoIcons
                                                              .textformat_abc,
                                                        2 =>
                                                          CupertinoIcons.timer,
                                                        _ =>
                                                          CupertinoIcons
                                                              .plus_circle,
                                                      },
                                                      size: 15,
                                                      color: c.accent,
                                                    ),
                                                    const SizedBox(width: 5),
                                                    Text(
                                                      switch (_sortMode) {
                                                        0 => 'Recent',
                                                        1 => 'A–Z',
                                                        2 => 'Most played',
                                                        _ => 'Newest',
                                                      },
                                                      maxLines: 1,
                                                      softWrap: false,
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: c.primaryText,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_importing)
                              ListenableBuilder(
                                listenable: _import,
                                builder: (_, _) => LinearProgressIndicator(
                                  value: _import.fraction,
                                  minHeight: 2.5,
                                  color: c.accent,
                                  backgroundColor: Colors.transparent,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                body: isLandscape
                    // ── LANDSCAPE LAYOUT: Left Side Rail + Full-Height Content ──
                    ? SafeArea(
                        top: false,
                        bottom: false,
                        child: Row(
                          children: [
                            // Hidden while the keyboard is up: the window is too short for the rail
                            // ("OVERFLOWED BY 13 PIXELS"). FittedBox also shrinks it on any short window.
                            _hideWithKeyboard(
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  10,
                                  4,
                                  10,
                                ),
                                child: Center(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: _FloatingDock(
                                      vertical: true,
                                      homeActive:
                                          _filter == null && _query.isEmpty,
                                      importing: _importing,
                                      onHome: _goHome,
                                      onAdd: _showImportSheet,
                                      onManager: _openManager,
                                      onSettings: _openSettings,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: !hasAnythingToShow
                                        ? _emptyState(c, isLandscape: true)
                                        : libraryScroll(),
                                  ),
                                  topButton(bottom: 16),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    // ── PORTRAIT LAYOUT: Unchanged ──
                    : Stack(
                        children: [
                          Column(
                            children: [
                              _iosSearchBar(c),
                              LibraryReveal(
                                id: 'chips',
                                from: RevealFrom.left,
                                child: _chips(searched, c),
                              ),
                              Expanded(
                                child: !hasAnythingToShow
                                    ? _emptyState(c)
                                    : libraryScroll(),
                              ),
                            ],
                          ),
                          ValueListenableBuilder<bool>(
                            valueListenable: _kbOpen,
                            builder: (_, open, _) =>
                                topButton(bottom: open ? 16 : bottomSafe + 84),
                          ),
                          _hideWithKeyboard(
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: SafeArea(
                                top: false,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: Center(
                                    child: _FloatingDock(
                                      vertical: false,
                                      homeActive:
                                          _filter == null && _query.isEmpty,
                                      importing: _importing,
                                      onHome: _goHome,
                                      onAdd: _showImportSheet,
                                      onManager: _openManager,
                                      onSettings: _openSettings,
                                    ),
                                  ),
                                ),
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

/// Large "pick up where you left off" card: blurred cover backdrop, cover thumbnail, play button.
class _HeroGameCard extends StatefulWidget {
  final _Game game;
  final double height;
  final String playedAgo;
  final String? playTime;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _HeroGameCard({
    super.key,
    required this.game,
    required this.height,
    required this.playedAgo,
    required this.onTap,
    required this.onLongPress,
    this.playTime,
  });

  @override
  State<_HeroGameCard> createState() => _HeroGameCardState();
}

class _HeroGameCardState extends State<_HeroGameCard> {
  File? _cover;

  @override
  void initState() {
    super.initState();
    _cover = BoxArtService.instance.peekCover(
      widget.game.sys,
      widget.game.name,
    );
    if (_cover == null) _load();
  }

  Future<void> _load() async {
    final cached = await BoxArtService.instance.getCachedCover(
      widget.game.sys,
      widget.game.name,
    );
    final f =
        cached ??
        await BoxArtService.instance.getOrFetchCover(
          widget.game.sys,
          widget.game.name,
        );
    if (mounted) setState(() => _cover = f);
  }

  @override
  Widget build(BuildContext context) => _PressScale(child: _buildBody(context));

  Widget _buildBody(BuildContext context) {
    final c = XEmuColors.of(context);
    final color = widget.game.group.color;
    final title = ConsoleSystem.cleanTitle(widget.game.name);
    final radius = BorderRadius.circular(22);
    final artSize = widget.height - 32;

    Widget art = Container(
      width: artSize * 0.78,
      height: artSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0.2)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _cover != null
          ? Image.file(
              _cover!,
              fit: BoxFit.cover,
              // Decode near display size (the art is ~110dp wide), not the full cover file.
              cacheWidth: 360,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) =>
                  Icon(widget.game.group.icon, color: Colors.white, size: 34),
            )
          : Icon(widget.game.group.icon, color: Colors.white, size: 34),
    );

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: c.isDark ? 0.28 : 0.30),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Backdrop: system colour gradient + blurred cover.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(color, Colors.black, 0.25)!,
                      Color.lerp(color, Colors.black, 0.65)!,
                    ],
                  ),
                ),
              ),
              if (_cover != null)
                // Soft backdrop without a GPU blur pass or an offscreen layer: the cover is decoded
                // at ~24px and bilinear-upscaled (which is already a smooth blur), and the 0.45
                // fade is applied by the image paint itself instead of an Opacity layer.
                RepaintBoundary(
                  child: Image.file(
                    _cover!,
                    fit: BoxFit.cover,
                    cacheWidth: 24,
                    filterQuality: FilterQuality.medium,
                    opacity: const AlwaysStoppedAnimation<double>(0.45),
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    art,
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              widget.game.sys.shortName,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            title,
                            maxLines: widget.height < 170 ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 19,
                              height: 1.15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (widget.playTime != null)
                                '${widget.playTime} played',
                              widget.playedAgo,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  CupertinoIcons.play_fill,
                                  size: 14,
                                  color: Color.lerp(color, Colors.black, 0.3),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Resume',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color.lerp(color, Colors.black, 0.3),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact list row: cover thumbnail, title, console + play info, favourite star.
class _GameListTile extends StatefulWidget {
  final _Game game;
  final String? playedAgo;
  final String? playTime;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _GameListTile({
    super.key,
    required this.game,
    required this.onTap,
    required this.onLongPress,
    this.playedAgo,
    this.playTime,
    this.isFavorite = false,
  });

  @override
  State<_GameListTile> createState() => _GameListTileState();
}

class _GameListTileState extends State<_GameListTile> {
  File? _cover;

  @override
  void initState() {
    super.initState();
    _cover = BoxArtService.instance.peekCover(
      widget.game.sys,
      widget.game.name,
    );
    if (_cover == null) _load();
  }

  Future<void> _load() async {
    final cached = await BoxArtService.instance.getCachedCover(
      widget.game.sys,
      widget.game.name,
    );
    final f =
        cached ??
        await BoxArtService.instance.getOrFetchCover(
          widget.game.sys,
          widget.game.name,
        );
    if (mounted) setState(() => _cover = f);
  }

  @override
  Widget build(BuildContext context) => _PressScale(child: _buildBody(context));

  Widget _buildBody(BuildContext context) {
    final c = XEmuColors.of(context);
    final color = widget.game.group.color;
    final radius = BorderRadius.circular(16);
    final info = [
      if (widget.playTime != null) widget.playTime!,
      if (widget.playedAgo != null) widget.playedAgo!,
    ].join(' · ');

    final thumb = Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        color: color.withValues(alpha: c.isDark ? 0.25 : 0.16),
      ),
      clipBehavior: Clip.antiAlias,
      child: _cover != null
          ? Image.file(
              _cover!,
              fit: BoxFit.cover,
              cacheWidth: 150,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) =>
                  Icon(widget.game.group.icon, color: color, size: 24),
            )
          : Icon(widget.game.group.icon, color: color, size: 24),
    );

    return Material(
      color: c.cardBg,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: c.hairline, width: 0.6),
      ),
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              thumb,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ConsoleSystem.cleanTitle(widget.game.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: c.primaryText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            widget.game.sys.shortName,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                        ),
                        if (info.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              info,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: c.secondaryText,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.isFavorite) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.star_rounded,
                  size: 20,
                  color: Color(0xFFFFC107),
                ),
              ],
              const SizedBox(width: 6),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  CupertinoIcons.play_fill,
                  size: 13,
                  color: c.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// iOS-styled box-art cover card that adapts cleanly to Light & Dark mode.
class _BoxArtGameCard extends StatefulWidget {
  final _Game game;
  final String? playedAgo;
  final String? playTime;
  final bool isFavorite;
  final bool isNew;
  final bool compact;

  /// Compact-grid tile: cover only, title on a bottom fade, no text footer.
  final bool dense;

  /// Large-card tile: bigger cover, title and text, sharper art.
  final bool large;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _BoxArtGameCard({
    super.key,
    required this.game,
    required this.playedAgo,
    this.playTime,
    this.isFavorite = false,
    this.isNew = false,
    required this.onTap,
    required this.onLongPress,
    this.compact = false,
    this.dense = false,
    this.large = false,
  });

  @override
  State<_BoxArtGameCard> createState() => _BoxArtGameCardState();
}

class _BoxArtGameCardState extends State<_BoxArtGameCard> {
  File? _coverFile;
  bool _fetching = true;

  @override
  void initState() {
    super.initState();
    // Seen before this session: show it immediately, no async round trip.
    final known = BoxArtService.instance.peekCover(
      widget.game.sys,
      widget.game.name,
    );
    if (known != null) {
      _coverFile = known;
      _fetching = false;
    } else {
      _loadArt();
    }
  }

  Future<void> _loadArt() async {
    final cached = await BoxArtService.instance.getCachedCover(
      widget.game.sys,
      widget.game.name,
    );
    if (cached != null) {
      if (mounted) {
        setState(() {
          _coverFile = cached;
          _fetching = false;
        });
      }
      return;
    }

    final fetched = await BoxArtService.instance.getOrFetchCover(
      widget.game.sys,
      widget.game.name,
    );
    if (mounted) {
      setState(() {
        _coverFile = fetched;
        _fetching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => _PressScale(child: _buildBody(context));

  Widget _buildBody(BuildContext context) {
    final c = XEmuColors.of(context);
    final sysColor = widget.game.group.color;
    final title = ConsoleSystem.cleanTitle(widget.game.name);
    final dense = widget.dense;
    final large = widget.large;
    final radius = BorderRadius.circular(dense ? 12 : (large ? 20 : 16));

    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: radius,
        border: Border.all(color: c.hairline, width: 0.6),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: c.isDark ? 0.35 : 0.08),
            blurRadius: dense ? 6 : (large ? 16 : 12),
            offset: Offset(0, dense ? 2 : 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: () {
            HapticFeedback.mediumImpact();
            widget.onLongPress();
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_coverFile != null)
                      Image.file(
                        _coverFile!,
                        fit: BoxFit.cover,
                        // Decode near tile size instead of full art: less memory in big libraries.
                        cacheWidth: large ? 640 : (dense ? 260 : 400),
                        gaplessPlayback: true,
                        frameBuilder: (_, child, frame, sync) => sync
                            ? child
                            : AnimatedOpacity(
                                opacity: frame == null ? 0 : 1,
                                duration: const Duration(milliseconds: 220),
                                child: child,
                              ),
                        errorBuilder: (_, _, _) =>
                            _fallbackArt(sysColor, title, c),
                      )
                    else
                      _fallbackArt(sysColor, title, c),

                    // Soft top fade so the console badge and star stay readable on bright covers.
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 44,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.28),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Soft bottom fade so the badges stay readable on bright covers.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.35),
                              ],
                              stops: const [0.7, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),

                    Positioned(
                      top: dense ? 5 : 7,
                      right: dense ? 5 : 7,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: dense ? 5 : (large ? 8 : 6.5),
                          vertical: dense ? 1.5 : (large ? 3.5 : 2.5),
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          widget.game.sys.shortName,
                          style: TextStyle(
                            fontSize: dense ? 8.5 : (large ? 11 : 9.5),
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),

                    if (widget.isFavorite)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Icon(
                          Icons.star_rounded,
                          size: dense ? 15 : (large ? 22 : 18),
                          color: const Color(0xFFFFC107),
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 4),
                          ],
                        ),
                      ),

                    if (widget.isNew)
                      Positioned(
                        bottom: dense ? 20 : 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: XEmuColors.of(context).accent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'NEW',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),

                    if (dense)
                      Positioned(
                        left: 6,
                        right: 6,
                        bottom: 4,
                        child: IgnorePointer(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.1,
                              shadows: [
                                Shadow(color: Colors.black87, blurRadius: 4),
                              ],
                            ),
                          ),
                        ),
                      ),

                    if (_fetching)
                      const Positioned(
                        bottom: 6,
                        right: 6,
                        child: CupertinoActivityIndicator(radius: 7),
                      ),
                  ],
                ),
              ),
              if (!dense)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    large ? 14 : 10,
                    large ? 10 : (widget.compact ? 6 : 8),
                    large ? 14 : 10,
                    large ? 12 : (widget.compact ? 6 : 9),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: widget.compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: large ? 15 : (widget.compact ? 11.5 : 12.5),
                          height: 1.18,
                          letterSpacing: -0.2,
                          color: c.primaryText,
                        ),
                      ),
                      if (widget.playedAgo != null || widget.playTime != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            [
                              if (widget.playTime != null) widget.playTime!,
                              if (widget.playedAgo != null) widget.playedAgo!,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: large ? 12.5 : 10.5,
                              color: c.secondaryText,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackArt(Color sysColor, String title, XEmuColors c) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            sysColor.withValues(alpha: c.isDark ? 0.28 : 0.18),
            c.secondaryFill,
          ],
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title.isEmpty
                  ? '?'
                  : String.fromCharCode(title.runes.first).toUpperCase(),
              style: TextStyle(
                fontSize: widget.dense
                    ? 26
                    : (widget.large ? 56 : (widget.compact ? 30 : 42)),
                fontWeight: FontWeight.w800,
                height: 1,
                color: sysColor.withValues(alpha: 0.85),
              ),
            ),
            if (!widget.compact && !widget.dense) ...[
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: c.primaryText.withValues(alpha: 0.78),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Frosted iOS floating pill dock: horizontal bottom pill in portrait, vertical side rail in landscape.
class _FloatingDock extends StatelessWidget {
  final bool vertical;
  final bool homeActive;
  final bool importing;
  final VoidCallback onHome;
  final VoidCallback onAdd;
  final VoidCallback onManager;
  final VoidCallback onSettings;

  const _FloatingDock({
    required this.vertical,
    required this.homeActive,
    required this.importing,
    required this.onHome,
    required this.onAdd,
    required this.onManager,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final items = [
      _DockButton(
        icon: CupertinoIcons.house_fill,
        label: 'Library',
        active: homeActive,
        compact: vertical,
        onTap: onHome,
      ),
      _DockButton(
        icon: CupertinoIcons.folder_fill,
        label: 'jedManager',
        compact: vertical,
        onTap: onManager,
      ),
      _DockButton(
        icon: CupertinoIcons.settings_solid,
        label: 'Settings',
        compact: vertical,
        onTap: onSettings,
      ),
    ];

    // The "+" is no longer a slot inside the pill: it sits next to it (right of the bar in
    // portrait, below the rail in landscape) as its own round button.
    final add = _DockAddButton(
      busy: importing,
      compact: vertical,
      onTap: onAdd,
    );
    final pill = ConstrainedBox(
      constraints: vertical
          ? const BoxConstraints(maxHeight: 310)
          : const BoxConstraints(maxWidth: 232),
      child: Container(
        margin: EdgeInsets.zero,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(34),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: c.isDark ? 0.45 : 0.14),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              padding: vertical
                  ? const EdgeInsets.symmetric(horizontal: 7, vertical: 12)
                  : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: c.frostedBar,
                borderRadius: BorderRadius.circular(34),
                border: Border.all(color: c.hairline, width: 0.7),
              ),
              child: vertical
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0) const SizedBox(height: 10),
                          items[i],
                        ],
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: items,
                    ),
            ),
          ),
        ),
      ),
    );

    return LibraryReveal(
      id: 'dock|${vertical ? 'rail' : 'bar'}',
      index: 3,
      from: vertical ? RevealFrom.left : RevealFrom.bottom,
      child: vertical
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [pill, const SizedBox(height: 12), add],
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [pill, const SizedBox(width: 12), add],
              ),
            ),
    );
  }
}

class _DockButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool compact;
  final VoidCallback onTap;

  const _DockButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final color = active ? c.accent : c.secondaryText;
    return Tooltip(
      message: label,
      child: InkResponse(
        onTap: onTap,
        radius: 30,
        child: SizedBox(
          width: compact ? 54 : 64,
          height: compact ? 46 : 50,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: compact ? 20 : 22, color: color),
              const SizedBox(height: 2),
              // Scales down instead of cutting the label ("jedManager" is wider in the mono font).
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: c
                      .buttonText(
                        size: compact ? 10 : 10.5,
                        color: color,
                        weight: active ? FontWeight.w700 : FontWeight.w500,
                      )
                      .copyWith(letterSpacing: c.isDot ? 0.2 : null),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockAddButton extends StatelessWidget {
  final bool busy;
  final bool compact;
  final VoidCallback onTap;
  const _DockAddButton({
    required this.busy,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final dim = compact ? 48.0 : 58.0;
    return Tooltip(
      message: 'Add games',
      child: Material(
        color: busy ? c.secondaryFill : c.accent,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: c.isDark ? 0.5 : 0.25),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onTap,
          child: SizedBox(
            width: dim,
            height: dim,
            child: busy
                ? const Center(child: CupertinoActivityIndicator())
                : Icon(
                    CupertinoIcons.add,
                    size: compact ? 23 : 26,
                    color: Colors.white,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Gentle shrink while a card/button is held down. Starts after a short delay so scrolling
/// past a card with a finger never makes it flicker; cancelled as soon as the scroll takes over.
class _PressScale extends StatefulWidget {
  final Widget child;
  final double scale;

  /// Draw an accent ring + slight grow while a gamepad/keyboard has focus inside.
  final bool ring;
  const _PressScale({required this.child, this.scale = 0.97, this.ring = true});

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;
  bool _padFocus = false;
  Timer? _delay;

  void _press() {
    _delay?.cancel();
    _delay = Timer(const Duration(milliseconds: 70), () {
      if (mounted) setState(() => _down = true);
    });
  }

  void _release() {
    _delay?.cancel();
    if (_down && mounted) setState(() => _down = false);
  }

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    Widget body = widget.child;
    if (widget.ring) {
      body = Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (f) {
          final show =
              f &&
              FocusManager.instance.highlightMode ==
                  FocusHighlightMode.traditional;
          if (mounted && show != _padFocus) setState(() => _padFocus = show);
        },
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: _padFocus ? Border.all(color: c.accent, width: 2.5) : null,
          ),
          child: widget.child,
        ),
      );
    }
    return Listener(
      onPointerDown: (_) => _press(),
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: AnimatedScale(
        scale: _down ? widget.scale : (_padFocus ? 1.03 : 1),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: body,
      ),
    );
  }
}

/// Round icon button for the top bar: 44 dp touch target around a 34 dp circle, press feedback,
/// tooltip + screen-reader label, and a cross-fade when the icon changes.
class _HeaderButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  const _HeaderButton({
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: _PressScale(
          scale: 0.9,
          ring: false,
          child: PadFocusable(
            circle: true,
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c.secondaryFill,
                    shape: BoxShape.circle,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (w, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(scale: a, child: w),
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
