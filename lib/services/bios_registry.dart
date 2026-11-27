// lib/services/bios_registry.dart
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'storage_service.dart';

/// How much a missing file matters.
enum BiosNeed { required, recommended, optional }

extension BiosNeedX on BiosNeed {
  String get label => switch (this) {
    BiosNeed.required => 'Required',
    BiosNeed.recommended => 'Recommended',
    BiosNeed.optional => 'Optional',
  };
}

/// One file a core looks for. [name] is the exact (case-sensitive) name the core opens, so
/// imports are always saved under it, whatever the user's copy is called.
class BiosFile {
  final String name;
  final String dir; // sub-folder inside system/ ('' = system root)
  final List<String>
  aliases; // other names people commonly have for the same dump
  final List<int> sizes; // accepted byte sizes; empty = don't check
  const BiosFile(
    this.name, {
    this.dir = '',
    this.aliases = const [],
    this.sizes = const [],
  });

  String get relPath => dir.isEmpty ? name : '$dir/$name';
}

/// One "slot" is one thing a system needs. If several files can fill it (e.g. any PS1 BIOS
/// revision), the slot is satisfied by whichever one is found.
class BiosSlot {
  final String label;
  final String? hint;
  final BiosNeed need;
  final List<BiosFile> files;
  const BiosSlot(
    this.label,
    this.files, {
    this.need = BiosNeed.optional,
    this.hint,
  });
}

class BiosGroup {
  final String id;
  final String title; // "Nintendo DS"
  final String systems; // "NDS · melonDS"
  final IconData icon;
  final Color color;
  final String without; // what happens if nothing is installed
  final List<BiosSlot> slots;
  const BiosGroup({
    required this.id,
    required this.title,
    required this.systems,
    required this.icon,
    required this.color,
    required this.without,
    required this.slots,
  });
}

enum SlotState { missing, found, badSize }

class SlotStatus {
  final BiosSlot slot;
  final SlotState state;
  final BiosFile? file; // the file that was found
  final int? size;
  const SlotStatus(this.slot, this.state, [this.file, this.size]);
  bool get ok => state != SlotState.missing;
}

enum GroupLevel { ready, incomplete, recommended, needsFiles, optional }

class GroupStatus {
  final BiosGroup group;
  final List<SlotStatus> slots;
  const GroupStatus(this.group, this.slots);

  int get found => slots.where((s) => s.ok).length;

  Iterable<SlotStatus> _of(BiosNeed n) => slots.where((s) => s.slot.need == n);

  bool get requiredMissing => _of(BiosNeed.required).any((s) => !s.ok);

  GroupLevel get level {
    if (requiredMissing) return GroupLevel.needsFiles;
    final rec = _of(BiosNeed.recommended).toList();
    if (rec.isNotEmpty) {
      if (rec.every((s) => s.ok)) return GroupLevel.ready;
      return rec.any((s) => s.ok)
          ? GroupLevel.incomplete
          : GroupLevel.recommended;
    }
    // Only optional slots (or only satisfied required ones).
    if (_of(BiosNeed.required).isNotEmpty) return GroupLevel.ready;
    return found > 0 ? GroupLevel.ready : GroupLevel.optional;
  }
}

class ImportReport {
  final List<String> imported = []; // "bios7.bin → Nintendo DS"
  final List<String> badSize = []; // saved, but size looks wrong
  final List<String> unknown = []; // saved to the system root, not recognised
  int ppssppFonts = -1; // -1 = no PPSSPP zip in this import
  final List<String> errors = [];

  int get total =>
      imported.length + unknown.length + (ppssppFonts >= 0 ? 1 : 0);
  bool get isEmpty => total == 0 && errors.isEmpty;
}

class BiosRegistry {
  static const _channel = MethodChannel('com.jedplatforms.jedEmu/core');

  // ───────────────────────── Catalog ─────────────────────────

  static const _blue = Color(0xFF007AFF);
  static const _red = Color(0xFFFF3B30);
  static const _indigo = Color(0xFF5856D6);
  static const _teal = Color(0xFF32ADE6);
  static const _orange = Color(0xFFFF9500);
  static const _green = Color(0xFF34C759);
  static const _purple = Color(0xFFAF52DE);

  static const groups = <BiosGroup>[
    BiosGroup(
      id: 'nds',
      title: 'Nintendo DS',
      systems: 'NDS · melonDS',
      icon: Icons.gamepad_rounded,
      color: _blue,
      without: 'Games run without these. You need all three to boot the DS menu from the BIOS button.',
      slots: [
        BiosSlot('ARM7 BIOS', [
          BiosFile(
            'bios7.bin',
            sizes: [16384],
            aliases: ['biosnds7.rom', 'nds_bios7.bin'],
          ),
        ], need: BiosNeed.recommended),
        BiosSlot('ARM9 BIOS', [
          BiosFile(
            'bios9.bin',
            sizes: [4096],
            aliases: ['biosnds9.rom', 'nds_bios9.bin'],
          ),
        ], need: BiosNeed.recommended),
        BiosSlot(
          'Firmware',
          [
            BiosFile(
              'firmware.bin',
              sizes: [131072, 262144, 524288],
              aliases: ['nds_firmware.bin', 'firmware.nds'],
            ),
          ],
          need: BiosNeed.recommended,
          hint: 'Also stores your nickname and birthday',
        ),
        BiosSlot('DSi ARM7 BIOS', [
          BiosFile('bios7i.bin', sizes: [65536]),
        ], hint: 'DSi mode only'),
        BiosSlot('DSi ARM9 BIOS', [
          BiosFile('bios9i.bin', sizes: [65536]),
        ], hint: 'DSi mode only'),
        BiosSlot('DSi firmware', [
          BiosFile('dsi_firmware.bin'),
        ], hint: 'DSi mode only'),
        BiosSlot('DSi NAND', [BiosFile('dsi_nand.bin')], hint: 'DSi mode only'),
      ],
    ),
    BiosGroup(
      id: 'ps1',
      title: 'PlayStation',
      systems: 'PS1 · SwanStation',
      icon: Icons.videogame_asset_rounded,
      color: _indigo,
      without: 'No PlayStation game will start without a BIOS. Any one revision is enough.',
      slots: [
        BiosSlot(
          'PS1 BIOS (any one)',
          [
            BiosFile('scph5501.bin', sizes: [524288], aliases: ['ps-22a.bin']),
            BiosFile('scph1001.bin', sizes: [524288], aliases: ['ps-20a.bin']),
            BiosFile('scph7001.bin', sizes: [524288]),
            BiosFile('scph7003.bin', sizes: [524288]),
            BiosFile('scph5500.bin', sizes: [524288]),
            BiosFile('scph5502.bin', sizes: [524288]),
          ],
          need: BiosNeed.required,
          hint: 'USA: scph5501 / scph1001 / scph7001 are best',
        ),
      ],
    ),
    BiosGroup(
      id: 'psp',
      title: 'PSP',
      systems: 'PSP · PPSSPP',
      icon: Icons.gamepad_rounded,
      color: _teal,
      without:
          'Games run, but system dialogs (save, error messages) show no text.',
      slots: [
        BiosSlot(
          'System fonts (flash0)',
          [BiosFile('ltn0.pgf', dir: 'PPSSPP/flash0/font')],
          need: BiosNeed.recommended,
          hint: 'Import PPSSPP.zip. It installs by itself the first time a PSP game starts.',
        ),
      ],
    ),
    BiosGroup(
      id: 'gba',
      title: 'Game Boy Advance',
      systems: 'GBA · mGBA',
      icon: Icons.gamepad_rounded,
      color: _purple,
      without: 'A built-in replacement is used. A few games are slightly less accurate.',
      slots: [
        BiosSlot('GBA BIOS', [
          BiosFile('gba_bios.bin', sizes: [16384], aliases: ['gba.bios']),
        ]),
      ],
    ),
    BiosGroup(
      id: 'gb',
      title: 'Game Boy / Color',
      systems: 'GB · GBC · Gambatte',
      icon: Icons.gamepad_rounded,
      color: _green,
      without: 'Boot logos are skipped. Games are unaffected.',
      slots: [
        BiosSlot('Game Boy boot ROM', [
          BiosFile('gb_bios.bin', sizes: [256], aliases: ['dmg_boot.bin']),
        ]),
        BiosSlot('Game Boy Color boot ROM', [
          BiosFile(
            'gbc_bios.bin',
            sizes: [2048, 2304],
            aliases: ['cgb_boot.bin'],
          ),
        ]),
      ],
    ),
    BiosGroup(
      id: 'sega8',
      title: 'Master System / Game Gear',
      systems: 'SMS · GG · Gearsystem',
      icon: Icons.videogame_asset_rounded,
      color: _red,
      without: 'Games run. The boot logo is skipped.',
      slots: [
        BiosSlot('Master System BIOS (any one)', [
          BiosFile('bios_U.sms', aliases: ['bios_u.sms']),
          BiosFile('bios_E.sms', aliases: ['bios_e.sms']),
          BiosFile('bios_J.sms', aliases: ['bios_j.sms']),
        ]),
        BiosSlot('Game Gear BIOS', [BiosFile('bios.gg')]),
      ],
    ),
    BiosGroup(
      id: 'saturn',
      title: 'Sega Saturn',
      systems: 'Saturn · Yabause',
      icon: Icons.videogame_asset_rounded,
      color: _blue,
      without:
          'A built-in replacement is used. A real BIOS is more compatible.',
      slots: [
        BiosSlot('Saturn BIOS (any one)', [
          BiosFile('saturn_bios.bin', sizes: [524288]),
          BiosFile('sega_101.bin', sizes: [524288], aliases: ['mpr-17933.bin']),
        ], need: BiosNeed.recommended),
      ],
    ),
    BiosGroup(
      id: 'pokemini',
      title: 'Pokémon Mini',
      systems: 'Mini · PokeMini',
      icon: Icons.videogame_asset_rounded,
      color: _teal,
      without: 'A built-in replacement BIOS is used. Games are unaffected.',
      slots: [
        BiosSlot('Pokémon Mini BIOS', [BiosFile('bios.min')]),
      ],
    ),
    BiosGroup(
      id: 'fds',
      title: 'Famicom Disk System',
      systems: 'NES · FCEUmm',
      icon: Icons.videogame_asset_rounded,
      color: _red,
      without:
          'Only needed for .fds disk games. Normal NES games are unaffected.',
      slots: [
        BiosSlot('Disk System BIOS', [
          BiosFile('disksys.rom', sizes: [8192]),
        ]),
      ],
    ),
  ];

  /// Systems that never need files, shown as one reassuring line.
  static const noFilesNeeded =
      'NES, SNES, N64, Genesis, WonderSwan and 3DS need no BIOS files.';

  // ───────────────────────── Lookup ─────────────────────────

  static final Map<String, (BiosGroup, BiosFile)> _byName = _buildLookup();

  static Map<String, (BiosGroup, BiosFile)> _buildLookup() {
    final m = <String, (BiosGroup, BiosFile)>{};
    for (final g in groups) {
      for (final s in g.slots) {
        for (final f in s.files) {
          m[f.name.toLowerCase()] = (g, f);
          for (final a in f.aliases) {
            m[a.toLowerCase()] = (g, f);
          }
        }
      }
    }
    return m;
  }

  /// lower-case file name -> relative destination, handed to the native zip importer.
  static Map<String, String> get zipLookup => {
    for (final e in _byName.entries) e.key: e.value.$2.relPath,
  };

  static Future<Directory> systemDir() async {
    if (!StorageService.instance.isInitialized) {
      await StorageService.instance.init();
    }
    final d = StorageService.instance.systemDir;
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static String _base(String path) {
    final n = path.replaceAll('\\', '/').split('/').last;
    return n;
  }

  // ───────────────────────── Status ─────────────────────────

  static Future<List<GroupStatus>> scan() async {
    final sys = await systemDir();
    final out = <GroupStatus>[];
    for (final g in groups) {
      final slots = <SlotStatus>[];
      for (final s in g.slots) {
        slots.add(await _slotStatus(sys, g, s));
      }
      out.add(GroupStatus(g, slots));
    }
    return out;
  }

  static Future<SlotStatus> _slotStatus(
    Directory sys,
    BiosGroup g,
    BiosSlot s,
  ) async {
    for (final f in s.files) {
      final file = File('${sys.path}/${f.relPath}');
      if (await _usable(file)) {
        final len = await file.length();
        final sizeOk = f.sizes.isEmpty || f.sizes.contains(len);
        return SlotStatus(
          s,
          sizeOk ? SlotState.found : SlotState.badSize,
          f,
          len,
        );
      }
      // PPSSPP also looks in system/PPSSPP/assets/flash0
      if (g.id == 'psp') {
        final alt = File('${sys.path}/PPSSPP/assets/flash0/font/ltn0.pgf');
        if (await _usable(alt)) {
          return SlotStatus(s, SlotState.found, f, await alt.length());
        }
      }
    }
    return SlotStatus(s, SlotState.missing);
  }

  /// True when [a] and [b] are the same file. Copying a file onto itself empties it, which
  /// happened when the user imported straight from the tonEMU/system folder.
  static bool _sameFile(String a, String b) {
    try {
      return File(a).absolute.resolveSymbolicLinksSync() ==
          File(b).absolute.resolveSymbolicLinksSync();
    } catch (_) {
      return File(a).absolute.path == File(b).absolute.path;
    }
  }

  static Future<bool> _usable(File f) async =>
      await f.exists() && await f.length() > 0;

  /// Names still missing for the DS firmware boot (used by the library's BIOS button).
  static Future<List<String>> missingNdsBoot() async {
    final sys = await systemDir();
    final missing = <String>[];
    for (final n in const ['bios7.bin', 'bios9.bin', 'firmware.bin']) {
      if (!await _usable(File('${sys.path}/$n'))) missing.add(n);
    }
    return missing;
  }

  // ───────────────────────── Import ─────────────────────────

  /// Imports any mix of files: BIOS dumps, PPSSPP.zip, or zips that contain BIOS files.
  /// Every recognised file is renamed to the exact name the core expects and put in the right
  /// folder, so the user never has to know where anything goes.
  static Future<ImportReport> importPaths(List<String> paths) async {
    final report = ImportReport();
    final sys = await systemDir();

    for (final path in paths) {
      final name = _base(path);
      final lower = name.toLowerCase();
      try {
        if (lower.endsWith('.zip')) {
          await _importZip(path, name, sys, report);
          continue;
        }
        final hit = _byName[lower];
        if (hit != null) {
          final f = hit.$2;
          final dest = File('${sys.path}/${f.relPath}');
          await dest.parent.create(recursive: true);
          if (!(await dest.exists() && _sameFile(path, dest.path))) {
            await File(path).copy(dest.path);
          }
          final len = await dest.length();
          if (f.sizes.isNotEmpty && !f.sizes.contains(len)) {
            report.badSize.add('${f.name} (${_fmtSize(len)})');
          }
          final renamed = name == f.name ? '' : ' (saved as ${f.name})';
          report.imported.add('${f.name} → ${hit.$1.title}$renamed');
        } else {
          final unknownDest = '${sys.path}/$name';
          if (!(await File(unknownDest).exists() &&
              _sameFile(path, unknownDest))) {
            await File(path).copy(unknownDest);
          }
          report.unknown.add(name);
        }
      } catch (e) {
        report.errors.add('$name: $e');
      }
    }
    return report;
  }

  static Future<void> _importZip(
    String path,
    String name,
    Directory sys,
    ImportReport report,
  ) async {
    final lower = name.toLowerCase();
    if (lower.contains('ppsspp') || lower.contains('flash0')) {
      final count = await _channel.invokeMethod<int>('extractPpssppZip', {
        'path': path,
      });
      report.ppssppFonts =
          (report.ppssppFonts < 0 ? 0 : report.ppssppFonts) + (count ?? 0);
      return;
    }
    final raw = await _channel.invokeMethod<List<dynamic>>('importBiosZip', {
      'path': path,
      'lookup': zipLookup,
    });
    final found = (raw ?? const []).map((e) => '$e').toList();
    if (found.isEmpty) {
      report.errors.add('$name: no known BIOS files inside this zip');
      return;
    }
    for (final rel in found) {
      final fileName = _base(rel);
      final hit = _byName[fileName.toLowerCase()];
      report.imported.add('$fileName → ${hit?.$1.title ?? 'system'}');
      if (hit != null && hit.$2.sizes.isNotEmpty) {
        final len = await File('${sys.path}/$rel').length();
        if (!hit.$2.sizes.contains(len)) {
          report.badSize.add('${hit.$2.name} (${_fmtSize(len)})');
        }
      }
    }
  }

  /// Recursively imports every recognised file below [dirPath] (a user's "BIOS" folder).
  static Future<ImportReport> importFolder(String dirPath) async {
    final paths = <String>[];
    try {
      await for (final e in Directory(
        dirPath,
      ).list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final n = _base(e.path).toLowerCase();
        if (_byName.containsKey(n) || _isPpssppZip(n)) {
          paths.add(e.path);
        }
      }
    } catch (e) {
      return ImportReport()..errors.add('Could not read that folder: $e');
    }
    final r = await importPaths(paths);
    if (paths.isEmpty) {
      r.errors.add('No known BIOS files were found in that folder.');
    }
    return r;
  }

  static bool _isPpssppZip(String lower) =>
      lower.endsWith('.zip') &&
      (lower.contains('ppsspp') || lower.contains('flash0'));

  static Future<void> remove(BiosFile f) async {
    final sys = await systemDir();
    final file = File('${sys.path}/${f.relPath}');
    if (await file.exists()) await file.delete();
  }

  static String _fmtSize(int bytes) {
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
    return '$bytes B';
  }

  static String formatSize(int bytes) => _fmtSize(bytes);
}
