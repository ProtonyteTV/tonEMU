# Contributing to tonEMU

Thank you for wanting to help! tonEMU is free and open-source software, and contributions of every size are welcome: bug reports, ideas, documentation, translations and code.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md) and the [Anti-Piracy Policy](ANTI-PIRACY.md).

## Ways to help

- **Report a bug.** Open an issue with your phone model, Android version, the system and game involved (by name only), the core settings you used and the steps to reproduce it. Screenshots and logs help.
- **Suggest a feature.** Open an issue and describe the problem you want solved, not only the solution.
- **Improve the docs.** Fixes to the README, release notes or in-app text are always welcome.
- **Write code.** See below.

## Please never post

ROMs, games, BIOS files, firmware, keys or links to them. Posts like that are removed. See the [Anti-Piracy Policy](ANTI-PIRACY.md).

## Before you write code

1. Check the open issues and pull requests so you do not repeat work.
2. For anything bigger than a small fix, open an issue first so we can agree on the approach.
3. Keep pull requests focused. One change per pull request is easier to review.

## Development setup

tonEMU is a Flutter app with an Android native layer.

- Install the Flutter SDK (the version in `pubspec.yaml`, `sdk: ^3.14.0`) and the Android SDK/NDK.
- Fork and clone the repository, then run `flutter pub get`.
- Dart code is in `lib/`. The Android layer (Java) is in `android/app/src/main/java/`. The libretro bridge is the vendored module in `android/libretrodroid/`.
- Emulator cores are prebuilt libretro nightlies in `android/app/src/main/jniLibs/arm64-v8a/`. See [CORES.md](CORES.md).
- Run on a real arm64 Android device when possible. Emulator cores need OpenGL ES 3.0.
- Run `flutter analyze` and `flutter test` before you open a pull request.

Signing keys, `key.properties` and `local.properties` are private and never belong in the repository.

## Code guidelines

- Follow the existing style and run `dart format` on Dart files.
- Native calls into a core can crash the whole app, so keep them guarded and only call them once the core is ready. Look at how `GameSession` does it.
- Never delete or overwrite a user's saves, states or BIOS files without a safe fallback.
- Do not add analytics, ads, trackers or new permissions. tonEMU is built to run with no accounts and no data collection.
- Test every system your change could affect, and say what you tested in the pull request.

## Pull requests

- Describe what changed and why, and link the issue it fixes.
- Include screenshots for visible changes, including portrait, landscape and, if relevant, foldable layouts.
- Be ready to make changes after review. Reviews are about the code, never about you.

## Licensing of contributions

tonEMU is licensed under the **GNU General Public License v3.0 or later**. By submitting a contribution you confirm that you have the right to submit it and that it is licensed under the same terms (GPL-3.0-or-later). Only add third-party code or assets if their license is compatible with the GPL, and list them in the About screen, the README and `assets/licenses/`.

## Security issues

Do not report security problems in a public issue. Follow the [Security Policy](SECURITY.md).

## Questions

Open a discussion or email **jedplatforms@gmail.com**.