import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the FULL license texts of the bundled native emulator cores to Flutter's license page
/// (the "Dart & Flutter package licenses" row in About > Open-source licenses opens it), so the
/// GPL / MPL texts really ship inside the app and not only as links.
///
/// Flutter's own license page only lists Dart/Flutter packages. The cores are native code that
/// Flutter knows nothing about, so their texts are registered here from bundled assets.
///
/// Setup (once):
///  1. Put the OFFICIAL texts in assets/licenses/ with exactly these names:
///       GPL-2.0.txt   https://www.gnu.org/licenses/old-licenses/gpl-2.0.txt
///       GPL-3.0.txt   https://www.gnu.org/licenses/gpl-3.0.txt
///       MPL-2.0.txt   https://www.mozilla.org/media/MPL/2.0/index.txt
///       Apache-2.0.txt   https://www.apache.org/licenses/LICENSE-2.0.txt  (for Oboe)
///       MIT-libretro.txt   the MIT header text from libretro-common's libretro.h
///     and a copy of tonEMU's own license as TONEMU.txt (optional but recommended).
///  2. In pubspec.yaml, under flutter: assets:   - assets/licenses/
///  3. Call registerCoreLicenses() once in main(), before runApp().
///
/// A missing file is skipped (never throws), so the app still starts if one is not bundled yet.
void registerCoreLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final e in _entries) {
      String text;
      try {
        text = await rootBundle.loadString('assets/licenses/${e.file}');
      } catch (_) {
        continue;
      }
      yield LicenseEntryWithLineBreaks(e.packages, text);
    }
  });
}

class _Entry {
  const _Entry(this.file, this.packages);
  final String file;
  final List<String> packages;
}

// Package names are the ones shown in About > Open-source licenses. The license names come from
// that list; confirm each against the project's own repository before release (for example,
// Mupen64Plus-Next is listed as GPL-2.0-or-later there, but its repository states GPL-3.0).
const List<_Entry> _entries = [
  _Entry('TONEMU.txt', ['tonEMU']),
  _Entry('GPL-3.0.txt', [
    'LibretroDroid (GPL-3.0)',
    'RetroArch (GPL-3.0)',
    'bsnes (GPL-3.0)',
    'melonDS (GPL-3.0)',
    'SwanStation (GPL-3.0)',
    'BlastEm (GPL-3.0-or-later)',
    'Gearsystem (GPL-3.0)',
    'PokeMini (GPL-3.0-or-later)',
  ]),
  _Entry('GPL-2.0.txt', [
    'FCEUmm (GPL-2.0)',
    'Gambatte (GPL-2.0)',
    'Mupen64Plus-Next (GPL-2.0-or-later)',
    'Azahar (GPL-2.0-or-later)',
    'PPSSPP (GPL-2.0-or-later)',
    'Yabause (GPL-2.0-or-later)',
    'Beetle Cygne (GPL-2.0-or-later)',
  ]),
  _Entry('MPL-2.0.txt', ['mGBA (MPL-2.0)']),
  _Entry('MIT-libretro.txt', ['libretro API (MIT)', 'libretro-common (MIT)']),
  _Entry('Apache-2.0.txt', ['Oboe (Apache-2.0)']),
];
