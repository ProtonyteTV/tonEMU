<div align="center">

# tonEMU `BETA`

**A fast, modern, multi-system emulator frontend, built with Flutter.**

Game Boy · Game Boy Color · Game Boy Advance · Nintendo DS · Nintendo 3DS · PlayStation · PSP

**Android:** available · **iOS, macOS, Windows, Linux:** planned · **Open source:** coming soon

</div>

---

## About

tonEMU is an all-in-one emulator app that puts your retro and handheld game collection in a single, clean library. It uses proven [Libretro](https://www.libretro.com/) cores under the hood and wraps them in a polished touch-first interface with per-core settings, save states, cheats, box art and local multiplayer.

> **Status:** tonEMU is currently in **beta** and **Android only**, and the source code will be **released as open source soon**. iOS, macOS, Windows and Linux ports are planned. See the [Roadmap](#roadmap).

## Features

- **Seven systems, one app**: GB, GBC, GBA, NDS, PS1, PSP and 3DS
- **Game library**: import ROMs and sort by recent, search, favorite, and filter by system group
- **Automatic box art**: fetched from the Libretro thumbnail repositories and cached on-device, or set your own custom cover
- **Save states**: multiple slots with thumbnails, plus optional auto-save on quit and auto-load on start
- **Cheats**: add and manage cheats per game
- **Fast-forward** and **screenshots** built into the in-game menu
- **Dual-screen layouts** for DS and 3DS: top/bottom, side-by-side, hybrid (large top or bottom), or a single screen
- **Customizable touch controls**: edit mode for the on-screen layout, adjustable opacity, haptic feedback, and separate layouts per system and screen mode
- **Physical controller support**: auto-hides touch controls when a gamepad connects; A/B and X/Y swap, stick deadzone, and combo hotkeys (menu, quick save, quick load, fast-forward)
- **Per-core settings**: one-tap *Performance / Balanced / Quality* presets, with options grouped into Video, Performance, Audio, Input and System
- **Video filters** (post-processing shaders), low-latency audio option, and adjustable portrait picture size
- **Local multiplayer**: multi-controller local co-op, plus zero-config LAN host and join with automatic room discovery over Wi-Fi
- **Light, dark and system themes**

## Supported systems

| System | Core | File types |
|---|---|---|
| Game Boy | Gambatte | `.gb` |
| Game Boy Color | Gambatte | `.gbc` |
| Game Boy Advance | mGBA | `.gba` |
| Nintendo DS | melonDS | `.nds` |
| PlayStation | SwanStation | `.chd` `.cue` `.pbp` `.bin` |
| PlayStation Portable | PPSSPP | `.iso` `.cso` |
| Nintendo 3DS | Azahar | `.3ds` `.cci` `.cxi` `.app` `.3dsx` `.cia` |

> For the best experience, import the system files listed in [BIOS & system files](#bios--system-files) below.

## Installation

### Android

1. Download the latest APK from the [Releases](../../releases) page.
2. Allow installs from unknown sources if prompted.
3. Open tonEMU, tap import, and pick your ROM files.

### System requirements (Android)

| | Minimum | Recommended |
|---|---|---|
| **Android version** | 8.0 (API 26) | 12 or newer |
| **Architecture** | arm64-v8a or armeabi-v7a | arm64-v8a (64-bit) |
| **Graphics** | OpenGL ES | Vulkan-capable GPU |
| **RAM** | 3 GB | 6 GB or more |
| **Storage** | Free space for the app, save states and box art, plus your games | 2 GB or more free |

**Per system:**

| System | Minimum | Recommended |
|---|---|---|
| GB / GBC / GBA | Android 8.0, any 2 GB device | Any modern device |
| NDS | Android 8.0, 3 GB RAM, mid-range chipset | 4 GB RAM, recent mid-range or better |
| PS1 | Android 8.0, 3 GB RAM, mid-range chipset | 4 GB RAM, Vulkan-capable GPU |
| PSP | Android 8.0, 4 GB RAM, upper mid-range chipset | 6 GB RAM, flagship chipset, Vulkan |
| 3DS | 64-bit (arm64) device, 6 GB RAM, flagship chipset | 8 GB RAM, latest flagship chipset |

Notes:
- NDS needs your own `bios7.bin`, `bios9.bin` and `firmware.bin`.
- The 3DS core is arm64 only and uses OpenGL ES, so it needs a 64-bit device.
- On mid-range devices, use the *Performance* preset in core settings.

> RAM and storage figures are general guidance, not hard limits. Real performance depends on your chipset, the game and the core settings you choose.

## BIOS & system files

For the best experience, import these files in **Settings → BIOS & System Files** (tap **Import BIOS or PPSSPP.zip**). tonEMU does not include them. See the [Disclaimer](#disclaimer).

| System | What to import | Files |
|---|---|---|
| Nintendo DS | BIOS and firmware | `bios7.bin`, `bios9.bin`, `firmware.bin` |
| PSP | PPSSPP assets, imported as a `.zip` | `PPSSPP.zip` (contains `flash0/font/*.pgf`) |
| PlayStation 1 | BIOS | `scph5501.bin` or `scph1001.bin` (`scph7001.bin`, `scph5500.bin` and `scph5502.bin` are also detected) |

Settings shows a ready indicator for each one once the files are found. You can dump the BIOS files from hardware you own. The PPSSPP assets come from the official PPSSPP project.

## Getting started

1. **Import games**: tonEMU detects the system from each file's extension and sorts it into the right group.
2. **Import your BIOS / system files** for NDS, PS1 and PSP (see [above](#bios--system-files)).
3. **Tap a game** to launch it.
4. **Tune it**: open core settings and pick a Performance, Balanced or Quality preset, or fine-tune individual options.

### Controller hotkeys

With *Combo hotkeys* enabled in settings, a connected gamepad can open the menu, quick save, quick load and toggle fast-forward using Select + Start / R1 / L1 / Y combos.

## Local multiplayer

- **Local co-op**: up to 4 players on ports 1 to 4 using multiple controllers, or a virtual P2 overlay.
- **LAN**: one device hosts a room, others discover it automatically over UDP broadcast and join. Input and state are synced over TCP (default ports `57380` TCP, `57381` UDP). Make sure your devices are on the same network.

## Roadmap

- [x] Android
- [ ] iOS
- [ ] macOS
- [ ] Windows
- [ ] Linux
- [ ] Open source release
- [ ] More systems and cores

The app is written in Flutter and the multiplayer layer is already cross-platform. The main porting work is the native emulator-core bridge for each platform.

## Disclaimer

**tonEMU does not provide, include, or distribute any ROMs, games, BIOS files, or firmware.** You must supply your own.

- Only play games you legally own. tonEMU does not condone or support piracy.
- BIOS and firmware files (for example the Nintendo DS `bios7.bin`, `bios9.bin` and `firmware.bin`) must be dumped by you from hardware you own.
- Please do not ask for ROMs or BIOS files in issues, discussions, or any other tonEMU channel, and do not share them there. Such requests and posts will be removed.
- tonEMU is an emulator frontend for educational and personal use.

All console and game names, logos and trademarks belong to their respective owners. tonEMU is not affiliated with, authorized, or endorsed by Nintendo, Sony, or any other company.

## Credits

tonEMU is made possible by these open-source projects:

- [Libretro](https://www.libretro.com/) and [LibretroDroid](https://github.com/Swordfish90/LibretroDroid)
- [Gambatte](https://github.com/libretro/gambatte-libretro), [mGBA](https://mgba.io/), [melonDS](https://melonds.kuribo64.net/), [SwanStation](https://github.com/libretro/swanstation), [PPSSPP](https://www.ppsspp.org/) and [Azahar](https://azahar-emu.org/)
- [Flutter](https://flutter.dev/)
- [Libretro thumbnails](https://github.com/libretro-thumbnails) for box art

Made with dedication by **jedPlatforms**.

## License

tonEMU will be released under the **GNU General Public License v3.0 (GPL-3.0)** when the source goes public. See the `LICENSE` file in the repository.

This is the usual choice for emulators, because the cores tonEMU uses (such as melonDS, PPSSPP, SwanStation and Azahar) are GPL-licensed. Each core keeps its own license.

---

<div align="center">

*In memoriam*

**Ton** · 2026

</div>
