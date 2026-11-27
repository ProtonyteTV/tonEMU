// lib/services/device_profile.dart
import 'emulator_bridge.dart';

/// How well a phone should run a system, from the minimum / recommended figures tonEMU publishes.
enum DeviceFit { good, limited, unlikely }

/// Speed class of the phone, used to pick a sensible default preset.
enum DeviceTier { low, mid, high }

/// Typed view of what the native side reports about the phone (model, chipset, RAM, 64-bit...).
/// Fields the phone cannot report are simply missing, and every getter has a safe default, so the
/// UI never has to check for null. Mirrors DeviceInfo.java (same keys, same thresholds).
class DeviceProfile {
  const DeviceProfile._(this._m);

  final Map<String, String> _m;

  /// Null when the native side could not provide any information.
  static Future<DeviceProfile?> load() async {
    final m = await EmulatorBridge.getDeviceInfo();
    return m == null ? null : DeviceProfile._(m);
  }

  /// For tests and previews.
  factory DeviceProfile.fromMap(Map<String, String> m) => DeviceProfile._(m);

  String get model => _m['model'] ?? 'Unknown device';
  String get cpu => _m['cpu'] ?? 'Unknown';
  String? get gpu => _m['gpu'];
  String get android => _m['android'] ?? '';
  int get cores => int.tryParse(_m['cores'] ?? '') ?? 0;
  int get maxMhz => int.tryParse(_m['maxMhz'] ?? '') ?? 0;

  /// Total RAM in MB as Android reports it (about 85% of the marketed size); 0 if unknown.
  int get ramMb => int.tryParse(_m['ramMb'] ?? '') ?? 0;

  bool get is64Bit => _m['is64'] == 'true';

  DeviceTier get tier => switch (_m['tier']) {
    'low' => DeviceTier.low,
    'high' => DeviceTier.high,
    _ => DeviceTier.mid,
  };

  /// The core-settings preset that suits this phone.
  String get recommendedPreset => switch (tier) {
    DeviceTier.low => 'performance',
    DeviceTier.mid => 'balanced',
    DeviceTier.high => 'quality',
  };

  /// RAM as a short label such as "5.6 GB", or '' when unknown.
  String get ramLabel =>
      ramMb <= 0 ? '' : '${(ramMb / 1024).toStringAsFixed(1)} GB';

  /// [system] is one of: 8bit16bit (NES, SNES, GB, GBC, GBA, Master System, Game Gear, Genesis),
  /// nds, ps1, n64, saturn, psp, 3ds. Unknown systems and unknown RAM count as good, so the
  /// app never scares anyone without a reason.
  DeviceFit compatibility(String system) {
    final double minGb;
    final double recGb;
    switch (system) {
      case '8bit16bit':
        minGb = 2;
        recGb = 2;
      case 'nds':
      case 'ps1':
        minGb = 3;
        recGb = 4;
      case 'n64':
      case 'saturn':
      case 'psp':
        minGb = 4;
        recGb = 6;
      case '3ds':
        if (!is64Bit) return DeviceFit.unlikely; // the 3DS core is arm64 only
        minGb = 6;
        recGb = 8;
      default:
        return DeviceFit.good;
    }
    if (ramMb <= 0) return DeviceFit.good;
    // Reported RAM is ~85% of the marketed size, so scale the limits the same way.
    if (ramMb >= recGb * 1024 * 0.85) return DeviceFit.good;
    if (ramMb >= minGb * 1024 * 0.85) return DeviceFit.limited;
    return DeviceFit.unlikely;
  }
}
