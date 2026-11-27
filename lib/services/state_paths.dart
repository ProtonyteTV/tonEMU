// lib/services/state_paths.dart
import 'dart:io';

/// Save-state file names. A state is only valid for the core that wrote it, so the core is part
/// of the name, exactly like battery saves (EmulatorViewFactory.sramFileFor):
///   <rom>.<coreKey>.auto.state   <rom>.<coreKey>.slotN.state   <rom>.<coreKey>.undo.state
class StatePaths {
  StatePaths._();

  /// Same rule as Java's sramFileFor: "libblastem_libretro_android.so" -> "blastem".
  static String coreKey(String coreFile) => coreFile
      .replaceAll(RegExp(r'^lib|_libretro.*$|\.so$', caseSensitive: false), '')
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');

  /// Cores that replaced an older one. Un-keyed states written before core keys existed came from
  /// the old core and must never be loaded into these.
  static const Set<String> _replacedCores = {'blastem', 'gearsystem', 'bsnes'};

  static String name(String rom, String coreKey, String label) =>
      '$rom.$coreKey.$label.state';

  static String path(Directory dir, String rom, String coreKey, String label) =>
      '${dir.path}/${name(rom, coreKey, label)}';

  /// One-time, never destructive: copies un-keyed states of [rom] (auto-save and numbered slots,
  /// with their thumbnails) to the core-keyed names, unless the core replaced an older one.
  /// The old files stay where they are. Safe to call any number of times.
  static Future<void> migrateLegacy(
    Directory dir,
    String rom,
    String coreKey, {
    required int slots,
  }) async {
    if (coreKey.isEmpty || _replacedCores.contains(coreKey.toLowerCase())) {
      return;
    }
    Future<void> copyIfNeeded(String oldName, String newName) async {
      try {
        final src = File('${dir.path}/$oldName');
        final dst = File('${dir.path}/$newName');
        if (await dst.exists() || !await src.exists()) return;
        if (await src.length() == 0) return;
        final tmp = File('${dst.path}.cp');
        await src.copy(tmp.path);
        await tmp.rename(dst.path);
      } catch (_) {}
    }

    await copyIfNeeded('$rom.auto.state', name(rom, coreKey, 'auto'));
    for (var i = 1; i <= slots; i++) {
      await copyIfNeeded('$rom.slot$i.state', name(rom, coreKey, 'slot$i'));
      await copyIfNeeded('$rom.slot$i.jpg', '$rom.$coreKey.slot$i.jpg');
    }
  }
}
