# Security Policy

## Supported versions

Security fixes are provided for the latest release of tonEMU.

| Version | Supported |
|---|---|
| 27.x (latest) | Yes |
| Older versions | No |

## Reporting a vulnerability

**Please do not report security problems in public issues, discussions or pull requests.**

Report them privately, using either of these:

1. **GitHub private reporting:** open the repository's **Security** tab and choose **Report a vulnerability**.
2. **Email:** **jedplatforms@gmail.com** with the subject "tonEMU security".

Please include:

- A description of the problem and what an attacker could do with it.
- The tonEMU version, Android version and phone model.
- Steps to reproduce it, or a proof of concept.
- Any suggested fix, if you have one.

Never attach ROMs, BIOS files or other copyrighted material to a report.

## What to expect

- We will acknowledge your report within **7 days**.
- We will confirm whether we can reproduce it and keep you updated.
- We aim to release a fix for confirmed issues as soon as we reasonably can, and will credit you in the release notes if you wish.
- Please give us reasonable time to fix the problem before you share details publicly.

## Areas of particular interest

- **Wi-Fi transfer:** the temporary local web server, its access code and file handling.
- **File and archive handling:** ZIP import for BIOS and PPSSPP files, folder import, and path handling (for example path traversal).
- **The tonEMU files provider** that exposes the app folder to the Files app.
- **Save, state and backup handling:** anything that could destroy or leak user data.
- **The native layer:** crashes or memory-safety problems in the libretro bridge.

## Out of scope

- Bugs inside an emulator core itself (FCEUmm, mGBA, PPSSPP and so on). Please report those to the core's own project (see [CORES.md](CORES.md)). If you are not sure, report it to us and we will pass it on.
- Problems that need a rooted or already-compromised phone.
- Wi-Fi transfer being plain HTTP. This is documented, and the feature is meant only for networks you trust.
- Reports with no demonstrated security impact, and automated scanner output without analysis.

## Privacy

tonEMU has no accounts, ads or analytics. See **Settings → About → Privacy Policy** in the app.