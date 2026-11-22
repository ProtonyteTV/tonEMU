<div align="center">

# tonEMU `BETA`

**A fast, modern, multi-system emulator frontend, built with Flutter.**

NES · Super Nintendo · Nintendo 64 · Game Boy · Game Boy Color · Game Boy Advance · Nintendo DS · Nintendo 3DS · PlayStation · PSP · Sega Master System · Game Gear · Genesis / Mega Drive · 32X · Saturn

**Android:** APK release on **November 28, 2026** · **iOS, macOS, Windows, Linux:** planned · **Open source:** coming soon

</div>

---

## About

tonEMU is an all-in-one emulator app that puts your retro and handheld game collection in a single, clean library. It uses proven [Libretro](https://www.libretro.com/) cores under the hood and wraps them in a polished touch-first interface with per-core settings, save states, cheats, box art and local multiplayer.

> **Status:** the **initial release** is scheduled for **November 28, 2026**. tonEMU is currently in **beta** and **Android only**, and the source code will be **released as open source soon**. iOS, macOS, Windows and Linux ports are planned. See the [Roadmap](#roadmap).

## Features

### Library
- **Fifteen systems, one app**: Nintendo, Sony and Sega consoles and handhelds, detected automatically from the file extension
- **Game library**: import ROMs, sort by recent, search, favorite, and filter by system group
- **Grid or list view**: switch between a cover grid and a compact list with one tap, and tonEMU remembers your choice
- **Resume card**: your last played game gets a large card with its cover art, play time and a one-tap Resume button, with the rest of your recent games on a shelf below
- **Library stats**: see your game count, number of consoles and total play time at a glance
- **Flexible importing**: add individual files, or import a whole folder (subfolders included) and let tonEMU pick out the supported games; duplicates are skipped, progress is shown, and you get one clear summary at the end
- **Pull to refresh** to re-scan your library
- **Automatic box art**: fetched from the Libretro thumbnail repositories and cached on-device, or set your own custom cover
- **Play time and last played** tracked per game, with an option to clear a game's play history

### Dual-screen layouts (DS and 3DS)
- **Premade layouts**: stacked, side by side, big top screen, big bottom screen, top screen only and bottom screen only (DS also has flipped stacked and flipped side by side)
- **Separate layout for every view**: portrait, landscape, portrait with controller and landscape with controller are each saved on their own, so changing one never overwrites another
- **Smart defaults**: stacked in portrait, side by side in landscape (side by side is landscape only)
- **Move and resize**: drag the picture anywhere and pinch or use the slider to resize it, with a live outline so the game never glitches while you adjust
- **Touch screen that stays accurate** in every layout, including the single-screen modes
- **Rotation-safe**: the picture is refreshed after rotating so it never stays stuck at the old size
- **Foldable support**: Z Flip tabletop posture keeps the picture above the hinge, with layouts for book-style folds too

### Controls
- **Customizable touch controls**: edit mode for the on-screen layout, adjustable opacity, haptic feedback, and separate layouts per system and screen mode
- **A pad for every system**: the on-screen controls match each console, including the N64 with its analog stick, Z trigger and C-button stick, the 6-button Genesis pad, the 2-button Master System and Game Gear pads, and the Saturn pad
- **Physical controller support**: touch controls hide automatically when a gamepad connects; A/B and X/Y swap, stick deadzone, and combo hotkeys (menu, quick save, quick load, fast-forward)
- **Local multiplayer**: multi-controller local co-op, plus zero-config LAN host and join with automatic room discovery over Wi-Fi

### Playing
- **Save states**: multiple slots with thumbnails, plus optional auto-save on quit and auto-load on start
- **Battery saves** (in-game saves) written automatically and safely
- **Cheats**: add and manage cheats per game
- **Fast-forward**, **mute**, **reset** and **screenshots** in the in-game quick menu
- **Per-core settings**: one-tap *Performance / Balanced / Quality* presets, with options grouped into Video, Performance, Audio, Input and System
- **Video filters** (None, Sharp, CRT, LCD), low-latency audio option, and adjustable portrait picture size
- **Redesigned settings**: a player profile card, clear status badges for BIOS, storage and each core, theme previews for System, Light and Dark, live previews for picture size and button opacity, and a one-tap reset for display and control options

### System setup
- **BIOS and system files** imported in Settings, with a ready indicator for each one
- **NDS**: boots games or straight into the firmware menu, using your own BIOS files
- **3DS and NDS player profile**: set your nickname and birthday once and it is written to the system
- **PSP**: import the PPSSPP assets zip so system dialogs and fonts show correctly
- **Light, dark and system themes**

## Supported systems

| System | Core | File types |
|---|---|---|
| Nintendo Entertainment System | FCEUmm | `.nes` `.unf` `.unif` |
| Super Nintendo | Snes9x | `.sfc` `.smc` `.swc` `.fig` |
| Nintendo 64 | Mupen64Plus-Next | `.n64` `.z64` `.v64` |
| Game Boy | Gambatte | `.gb` |
| Game Boy Color | Gambatte | `.gbc` |
| Game Boy Advance | mGBA | `.gba` |
| Nintendo DS | melonDS | `.nds` |
| Nintendo 3DS | Azahar | `.3ds` `.cci` `.cxi` `.app` `.3dsx` `.cia` |
| PlayStation | SwanStation | `.chd` `.cue` `.pbp` `.bin` |
| PlayStation Portable | PPSSPP | `.iso` `.cso` |
| Sega Master System | Genesis Plus GX | `.sms` |
| Sega Game Gear | Genesis Plus GX | `.gg` |
| Sega Genesis / Mega Drive | Genesis Plus GX | `.md` `.gen` `.smd` |
| Sega 32X | PicoDrive | `.32x` |
| Sega Saturn (experimental) | Yabause | `.ccd` `.mds` `.chd` `.cue` |

> For the best experience, import the system files listed in [BIOS & system files](#bios--system-files) below.

**Format notes:**
- `.cue` and `.chd` files can be PlayStation or Saturn games, so tonEMU asks which console each one belongs to. `.iso` and `.cso` files are PSP games. Sega CD is not supported yet.
- A `.bin` track file is imported together with the `.cue` sheet that uses it; a lone `.bin` is ignored.
- Genesis games saved as `.bin` should be renamed to `.md`.

## Installation

### Android

1. Starting **November 28, 2026**, download the latest APK from the [Releases](../../releases) page.
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
| NES / SNES / GB / GBC / GBA | Android 8.0, any 2 GB device | Any modern device |
| Master System / Game Gear / Genesis | Android 8.0, any 2 GB device | Any modern device |
| Sega 32X | Android 8.0, 3 GB RAM, entry-level chipset | Any recent mid-range device |
| NDS | Android 8.0, 3 GB RAM, mid-range chipset | 4 GB RAM, recent mid-range or better |
| PS1 | Android 8.0, 3 GB RAM, mid-range chipset | 4 GB RAM, Vulkan-capable GPU |
| N64 | Android 8.0, 4 GB RAM, upper mid-range chipset, OpenGL ES 3 | 6 GB RAM, flagship chipset |
| Sega Saturn | Android 8.0, 4 GB RAM, upper mid-range chipset | 6 GB RAM, flagship chipset |
| PSP | Android 8.0, 4 GB RAM, upper mid-range chipset | 6 GB RAM, flagship chipset, Vulkan |
| 3DS | 64-bit (arm64) device, 6 GB RAM, flagship chipset | 8 GB RAM, latest flagship chipset |

Notes:
- NDS needs your own `bios7.bin`, `bios9.bin` and `firmware.bin`.
- Saturn also needs a BIOS file that you provide (see below).
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
| Sega Saturn | BIOS | `saturn_bios.bin` or `sega_101.bin` |

Settings shows a ready indicator for NDS, PSP and PS1 once the files are found. NES, SNES, Game Boy, GBA, N64, 3DS, Master System, Game Gear, Genesis and 32X games run without any BIOS. You can dump the BIOS files from hardware you own. The PPSSPP assets come from the official PPSSPP project.

## Getting started

1. **Import games**: tap the **+** button and choose individual files or a whole folder. tonEMU detects the system from each file's extension and sorts it into the right group.
2. **Import your BIOS / system files** for NDS, PS1, PSP and Saturn (see [above](#bios--system-files)).
3. **Tap a game** to launch it, or press **Resume** on the home screen to jump back into your last game. Long-press a game for favorites, box art and removal options.
4. **Tune it**: open core settings and pick a Performance, Balanced or Quality preset, or fine-tune individual options.

### Controller hotkeys

With *Combo hotkeys* enabled in settings, a connected gamepad can open the menu, quick save, quick load and toggle fast-forward using Select + Start / R1 / L1 / Y combos.

## Local multiplayer

- **Local co-op**: up to 4 players on ports 1 to 4, with each connected controller driving its own port, or a virtual P2 overlay.
- **LAN**: one device hosts a room, others discover it automatically over UDP broadcast and join. Input and state are synced over TCP (default ports `57380` TCP, `57381` UDP). Make sure your devices are on the same network. A guest's physical controller is forwarded to the host, and the host's save state is only loaded on a guest running the same game and core.

## Roadmap

- [ ] Android APK release (November 28, 2026)
- [ ] iOS
- [ ] macOS
- [ ] Windows
- [ ] Linux
- [ ] Open source release
- [ ] Sega CD
- [ ] More systems and cores

The app is written in Flutter and the multiplayer layer is already cross-platform. The main porting work is the native emulator-core bridge for each platform.

## Disclaimer

**tonEMU does not provide, include, or distribute any ROMs, games, BIOS files, or firmware.** You must supply your own.

- Only play games you legally own. tonEMU does not condone or support piracy.
- BIOS and firmware files (for example the Nintendo DS `bios7.bin`, `bios9.bin` and `firmware.bin`) must be dumped by you from hardware you own.
- Please do not ask for ROMs or BIOS files in issues, discussions, or any other tonEMU channel, and do not share them there. Such requests and posts will be removed.
- tonEMU is an emulator frontend for educational and personal use.

All console and game names, logos and trademarks belong to their respective owners. tonEMU is not affiliated with, authorized, or endorsed by Nintendo, Sony, Sega, or any other company.

## Credits

tonEMU is made possible by these open-source projects:

- [Libretro](https://www.libretro.com/) and [LibretroDroid](https://github.com/Swordfish90/LibretroDroid)
- [FCEUmm](https://github.com/libretro/libretro-fceumm), [Snes9x](https://github.com/libretro/snes9x), [Mupen64Plus-Next](https://github.com/libretro/mupen64plus-libretro-nx), [Gambatte](https://github.com/libretro/gambatte-libretro), [mGBA](https://mgba.io/), [melonDS](https://melonds.kuribo64.net/), [SwanStation](https://github.com/libretro/swanstation), [PPSSPP](https://www.ppsspp.org/) and [Azahar](https://azahar-emu.org/)
- [Genesis Plus GX](https://github.com/libretro/Genesis-Plus-GX), [PicoDrive](https://github.com/libretro/picodrive) and [Yabause](https://github.com/libretro/yabause)
- [Flutter](https://flutter.dev/)
- [Libretro thumbnails](https://github.com/libretro-thumbnails) for box art

Made with dedication by **jedPlatforms**.

## License

tonEMU will be released under the **GNU General Public License v3.0 (GPL-3.0)** when the source goes public. See the `LICENSE` file in the repository.

This is the usual choice for emulators, because many of the cores tonEMU uses (such as melonDS, PPSSPP, SwanStation and Azahar) are GPL-licensed. Each core keeps its own license, and not every core uses the GPL, so check each one before you redistribute a build.

---

<div align="center">

*In memoriam*

**Ton** · 2026

</div>
