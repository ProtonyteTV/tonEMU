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
- **Flexible importing**: add individual files, import a whole folder (subfolders included) and let tonEMU pick out the supported games, or **send games from your PC over Wi-Fi** (see below); duplicates are skipped by comparing contents, nothing is ever overwritten, progress is shown, and you get one clear summary at the end
- **Wi-Fi transfer**: open the address shown in the app in your PC's browser and drag in games or whole folders. The page is protected by a random access code, so other people on the same network can't send files to your phone, and the server only runs while the import screen is open
- **Disc images stay together**: `.cue` sheets are kept consistent with their track files (even if a track has to be renamed), and `.gdi`, `.ccd` and `.mds` companion files travel with their game
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
- **Physical controller support** (Bluetooth and USB): touch controls hide automatically when a gamepad connects; A/B and X/Y swap, stick deadzone, and the controller's Home/Guide button opens the menu
- **Combo hotkeys**: with Select held, Start opens the menu, R1 quick saves, L1 quick loads, X switches save slot, R3 takes a screenshot, L3 mutes and Y toggles fast-forward. A plain Select press still works as Select
- **Auto-pause**: the game can pause and open the menu if the controller or headphones drop out
- **Local multiplayer**: multi-controller local co-op, plus zero-config LAN host and join with automatic room discovery over Wi-Fi

### Playing
- **Save states**: four slots with thumbnails, plus a separate auto-save slot and undo for an accidental load. Optional auto-save on quit, periodic auto-save while you play, and an option to always continue automatically
- **Battery saves** (in-game saves) written automatically and safely, so a crash or a full disk never destroys your previous save
- **Cheats**: add and manage cheats per game
- **Fast-forward**, **mute**, **reset** and **screenshots** in the in-game quick menu, with optional export of screenshots to your gallery
- **Per-core settings**: one-tap *Performance / Balanced / Quality* presets, with options grouped into Video, Performance, Audio, Input and System
- **Safe by design**: options that a core only reads at startup are never changed on a running game, values known to crash on phones are blocked, and if a launch fails, that core's settings are reset on the next start so the game can open again
- **Region**: forced to USA on most cores for consistent behavior; the Sega cores keep their own auto-detect
- **Video filters** (None, Sharp, CRT, LCD), low-latency audio option, and adjustable portrait picture size
- **Correct in-game clock**: games with a real-time clock (Pokémon, Animal Crossing and others) follow your phone's time zone
- **Redesigned settings**: a player profile card, clear status badges for BIOS, storage and each core, theme previews for System, Light and Dark, live previews for picture size and button opacity, and a one-tap reset for display and control options

### System setup
- **BIOS and system files** imported in Settings, with a status for each system (Required, Recommended or Optional). Import loose files, a whole folder, or a zip; tonEMU renames each file to what the core expects and puts it in the right place
- **NDS**: boots games, or straight into the firmware menu, using your own BIOS files
- **PS1**: can boot the BIOS shell (memory card and CD player screen) when you have a BIOS
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
3. Open tonEMU, tap import, and pick your ROM files (or send them from your PC with Wi-Fi transfer).

### Storage

tonEMU keeps everything in one folder, `/storage/emulated/0/tonEMU`, with these subfolders: `roms`, `saves`, `states`, `system` (BIOS files) and `screenshots`.

- On first use, tonEMU offers to turn on **All files access**. This is what lets it use that shared folder, so you can copy BIOS files and back up saves from a PC or file manager.
- If you decline, tonEMU still works and keeps its files in private app storage instead.
- If you grant the permission later, tonEMU moves your existing games, saves and BIOS files into the shared folder automatically.

### System requirements (Android)

| | Minimum | Recommended |
|---|---|---|
| **Android version** | 8.0 (API 26) | 12 or newer |
| **Architecture** | arm64-v8a (64-bit) | arm64-v8a (64-bit) |
| **Graphics** | OpenGL ES 3.0 | A recent GPU (Adreno 600 series, Mali-G7x or newer) |
| **RAM** | 3 GB | 6 GB or more |
| **Storage** | Free space for the app, save states and box art, plus your games | 2 GB or more free |

**Per system:**

| System | Minimum | Recommended |
|---|---|---|
| NES / SNES / GB / GBC / GBA | Android 8.0, any 2 GB device | Any modern device |
| Master System / Game Gear / Genesis | Android 8.0, any 2 GB device | Any modern device |
| Sega 32X | Android 8.0, 3 GB RAM, entry-level chipset | Any recent mid-range device |
| NDS | Android 8.0, 3 GB RAM, mid-range chipset | 4 GB RAM, recent mid-range or better |
| PS1 | Android 8.0, 3 GB RAM, mid-range chipset | 4 GB RAM, recent mid-range or better |
| N64 | Android 8.0, 4 GB RAM, upper mid-range chipset, OpenGL ES 3 | 6 GB RAM, flagship chipset |
| Sega Saturn | Android 8.0, 4 GB RAM, upper mid-range chipset | 6 GB RAM, flagship chipset |
| PSP | Android 8.0, 4 GB RAM, upper mid-range chipset | 6 GB RAM, flagship chipset |
| 3DS | 64-bit (arm64) device, 6 GB RAM, flagship chipset | 8 GB RAM, latest flagship chipset |

Notes:
- tonEMU renders with OpenGL ES on every system. Vulkan is not used, so a Vulkan-capable GPU is not needed.
- PS1 needs a BIOS file that you provide. NDS and Saturn run without one but are more compatible with a real BIOS, and NDS needs `bios7.bin`, `bios9.bin` and `firmware.bin` to boot the firmware menu (see below).
- PS1 uses the software renderer by default for compatibility. You can switch to OpenGL ES in the core settings; if that renderer shows a black screen on your device, tonEMU tells you and you can switch back.
- The 3DS core is arm64 only and uses OpenGL ES, so it needs a 64-bit device.
- On mid-range devices, use the *Performance* preset in core settings.

> RAM and storage figures are general guidance, not hard limits. Real performance depends on your chipset, the game and the core settings you choose.

## BIOS & system files

Import these in **Settings → BIOS & System Files** (tap **Import BIOS or PPSSPP.zip**). tonEMU does not include them. See the [Disclaimer](#disclaimer).

| System | What to import | Files | Needed? |
|---|---|---|---|
| PlayStation 1 | BIOS (any one) | `scph5501.bin`, `scph1001.bin` or `scph7001.bin` are best; `scph7003.bin`, `scph5500.bin` and `scph5502.bin` also work | **Required**. No PS1 game starts without one |
| Nintendo DS | BIOS and firmware | `bios7.bin`, `bios9.bin`, `firmware.bin` | Recommended for games; required to boot the firmware menu |
| Sega Saturn | BIOS (any one) | `saturn_bios.bin` or `sega_101.bin` | Recommended. A built-in replacement is used without it |
| PSP | PPSSPP assets, imported as a `.zip` | `PPSSPP.zip` (contains `flash0/font/*.pgf`) | Recommended, for system fonts and dialogs |

Settings shows the status of every system's files once you import them. NES, SNES, N64, 3DS, Master System, Game Gear, Genesis and 32X games run without any BIOS, and Game Boy and GBA games run without one too (the optional boot ROMs only add the startup logo). You can dump the BIOS files from hardware you own. The PPSSPP assets come from the official PPSSPP project.

## Getting started

1. **Import games**: tap the **+** button and choose individual files, a whole folder, or **Wi-Fi transfer** to send them from your PC's browser. tonEMU detects the system from each file's extension and sorts it into the right group.
2. **Import your BIOS / system files** for PS1, NDS, PSP and Saturn (see [above](#bios--system-files)).
3. **Tap a game** to launch it, or press **Resume** on the home screen to jump back into your last game. Long-press a game for favorites, box art and removal options.
4. **Tune it**: open core settings and pick a Performance, Balanced or Quality preset, or fine-tune individual options.

### Controller hotkeys

With *Combo hotkeys* enabled in settings, hold **Select** on a connected gamepad and press:

| Button | Action |
|---|---|
| Start | Open the menu |
| R1 / L1 | Quick save / quick load |
| X | Next save slot |
| R3 | Screenshot |
| L3 | Mute |
| Y | Fast-forward |

The controller's Home / Guide button always opens the menu.

## Local multiplayer

- **Local co-op**: up to 4 players on ports 1 to 4, with each connected controller driving its own port, or a virtual P2 overlay.
- **LAN**: one device hosts a room and shows a **6-digit room code**; other devices discover it automatically over UDP broadcast and join by entering the code. Input and state are synced over TCP (ports `57380` TCP and `57381` UDP). Make sure your devices are on the same network and run the same tonEMU version. A guest's physical controller is forwarded to the host, and the host's save state is only loaded on a guest running the same game and core.

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
