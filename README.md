<div align="center">
  <img src="header.png"
       alt="tonEMU Banner"
       width="45%">
</div>

<div align="center">

**A fast, modern, multi-system emulator frontend, built with Flutter.**

**Rewind your play session with jedTimeMachine.**

NES · Super Nintendo · Nintendo 64 · Game Boy · Game Boy Color · Game Boy Advance · Nintendo DS · Nintendo 3DS · PlayStation · PSP · Sega Master System · Game Gear · Genesis / Mega Drive · Saturn · Pokémon Mini · WonderSwan / Color

**Android:** APK release on **November 28, 2026** · **iOS, macOS, Windows, Linux:** planned

**Free and open source · GPL-3.0-or-later**

</div>

---

## About

tonEMU is an all-in-one emulator app that puts your retro and handheld game collection in a single, clean library. It uses proven [Libretro](https://www.libretro.com/) cores under the hood and wraps them in a polished touch-first interface with per-core settings, save states, cheats, box art, save backups and **jedTimeMachine**, a rolling rewind history for every play session. It also works with foldable and flip phones.

> **Status:** the **initial release (v27.0)** is scheduled for **November 28, 2026**. tonEMU is **Android only** for now. iOS, macOS, Windows and Linux ports are planned. See the [Roadmap](#roadmap).

## Flagship feature: jedTimeMachine

Made a mistake and your last save was twenty minutes ago? jedTimeMachine has you covered.

- **Automatic snapshots**: while you play, tonEMU quietly records a snapshot every **15, 30 or 60 seconds** of real play time (time spent in menus, in the background or loading doesn't count). You pick the interval (or turn it off) in **Settings → Display & Controls → Saves**
- **Jump back to any moment**: open the in-game menu, choose **jedTimeMachine**, pick a snapshot and you are back there
- **Smart history**: up to 12 snapshots are kept. Your most recent moments stay dense (one per interval) while older ones thin out, so the history reaches far back without filling your storage
- **A safety net, not a replacement for save slots**: snapshots belong to the current session and are cleared when a game starts and when it ends
- **Safe by design**: for games with very large save states (some PSP and 3DS titles), jedTimeMachine switches itself off so it never makes the game stutter or fill your phone, and tells you why. It also stays off when you boot a system BIOS directly

## Features

### Library
- **Sixteen systems, one app**: Nintendo, Sony, Sega, Bandai and Pokémon Mini, detected automatically from the file extension
- **Game library**: import ROMs, search, favorite, and filter by system group. Four sort modes: recently played, A to Z, most played and recently added
- **Grid or list view**: switch between a cover grid and a compact list with one tap, and tonEMU remembers your choice
- **Shelves**: your last played game gets a large **Continue Playing** card with its cover art, play time and a one-tap Resume button. Below it, optional shelves for recent games, **Favorites**, **Most Played** and **New Additions**. Every shelf can be switched off in Settings
- **Library stats and Surprise Me**: see your game count and total play time at a glance, or let the random-game button pick what to play next
- **Flexible importing**: add individual files, import a whole folder (subfolders included) and let tonEMU pick out the supported games, or **send games from your PC over Wi-Fi** (see below); duplicates are skipped by comparing contents, nothing is ever overwritten, progress is shown, and you get one clear summary at the end
- **Wi-Fi transfer**: open the address shown in the app in your PC's browser and drag in games or whole folders. The page is protected by a random access code (and an address that keeps sending wrong codes is blocked for a while), so other people on the same network can't send files to your phone. The server only runs while the transfer screen is open
- **Disc images stay together**: `.cue` sheets are kept consistent with their track files (even if a track has to be renamed), and `.gdi`, `.ccd` and `.mds` companion files travel with their game
- **Pull to refresh** to re-scan your library
- **Gamepad-friendly menus**: the library, settings and in-game menu can all be navigated with a controller
- **Automatic box art**: fetched from the Libretro thumbnail repositories and cached on-device (can be turned off with **Download cover art**), or set your own custom cover
- **Play time and last played** tracked per game, with an option to clear a game's play history

### jedManager: saves, backups and play time
- **One screen for every game's files**: see each game's battery saves, save states, auto-saves and play time, and spot leftover files that no longer match a game
- **Back up and restore**: copy saves (optionally with save states) into a `backups` folder inside tonEMU, back up or restore a single game, and get an automatic safety copy before every restore
- **Export play time & favorites** to a `jed_stats.json` file in your tonEMU folder (it is never uploaded)
- **Bring in an older tonEMU folder**: pick it with Android's folder picker and tonEMU copies its games, saves, states, BIOS files and screenshots into the new location. Nothing is deleted from the old folder, and existing files are never overwritten silently
- **Open tonEMU in Files** with one tap

### Foldable and flip phones
- **The whole app is fold-aware**, not only games. Half-open a **Z Flip** (tabletop posture) and the app moves to the lower half, under your thumbs and away from the crease; the upper half shows a themed panel
- **Book-style folds** (Z Fold half-open, and dual-screen phones with a hinge gap): the app sits on one page and the other page shows the same panel, so nothing is ever drawn across the crease
- **Dialogs, sheets and menus** stay inside the usable area too
- **Fully unfolded or flat** foldables are treated as a big screen and use the wide tablet layouts
- **Folding while you use the app** doesn't lose your place: the current page, scroll position and open dialogs survive
- **In games**, the picture stays above the hinge in tabletop posture, with layouts for book-style folds as well
- **Your choice**: switch it off in **Settings → Display & Controls → Appearance → Fold & flip layout** if your phone reports its hinge wrongly

### Dual-screen layouts (DS and 3DS)
- **Premade layouts**: stacked, side by side, big top screen, top screen only and bottom screen only. DS adds big bottom screen, flipped stacked and flipped side by side
- **Free form**: place and resize the two screens independently, anywhere on the display
- **Separate layout for every view**: portrait, landscape, portrait with controller and landscape with controller are each saved on their own, so changing one never overwrites another
- **Smart defaults**: stacked in portrait, side by side in landscape
- **Move and resize**: drag the picture anywhere and pinch or use the slider to resize it
- **Touch screen that stays accurate** in every layout, including the single-screen modes
- **Rotation-safe**: the picture is refreshed after rotating so it never stays stuck at the old size

### Controls
- **Customizable touch controls**: edit mode for the on-screen layout, adjustable opacity, haptic feedback, and separate layouts per system and screen mode
- **A pad for every system**: the on-screen controls match each console, including the N64 with its analog stick, Z trigger and C-button stick, the 6-button Genesis pad, the 2-button Master System and Game Gear pads, the Saturn pad, the Pokémon Mini (with its Shake and Power buttons) and the WonderSwan (with its Rotate button for vertical games)
- **PlayStation DualShock**: PS1 games get an analog (DualShock) controller on both ports. Physical gamepads drive both sticks, L2/R2 and L3/R3. The on-screen PS1 pad adds a second stick, and a quick tap on either stick presses L3 / R3. Digital-only games keep playing normally
- **Physical controller support** (Bluetooth and USB): up to **four controllers**, one per player. Touch controls can hide automatically when a gamepad connects; A/B and X/Y swap, stick deadzone, and the controller's Home/Guide button opens the menu
- **Combo hotkeys** (player 1's controller): with Select held, Start opens the menu, R1 quick saves, L1 quick loads, X switches save slot, R3 takes a screenshot, L3 mutes and Y toggles fast-forward. A plain Select press still works as Select
- **Auto-pause**: the game can pause and open the menu if the controller or headphones drop out, or when you leave the app or pull down the notification shade. Press A or B on a gamepad (or tap) to continue

### Playing
- **jedTimeMachine**: rewind to any recent moment of your session from the in-game menu (see [above](#flagship-feature-jedtimemachine))
- **Save states**: **60 slots** with thumbnails and a next-empty-slot shortcut, plus a separate auto-save slot and undo for an accidental load. Optional auto-save on quit, periodic auto-save while you play, and an automatic save when the battery runs low
- **Smart resume**: by default a game with an auto-save jumps straight back in and offers a short-lived Start over button. You can switch to the old Continue / New game prompt, or always start fresh
- **Battery saves** (in-game saves) written automatically and safely, so a crash or a full disk never destroys your previous save. A rolling `.bak` copy of the previous battery save is kept so a bad save can be rolled back
- **Cheats**: add and manage cheats per game, with a built-in cheat browser for every system. The cheat manager and browser follow your chosen theme (Classic or Dot, Light or Dark), and the manager stays compact in landscape so the list keeps its room. Cheat files come from the libretro cheat database the first time a game needs them (internet required) and are cached afterwards. Not every core supports cheats, so tonEMU warns you where a core may ignore them
- **Break reminder** (optional): a gentle note after **30 minutes, 1 hour or 1.5 hours** of play in one session. It only counts time the game is actually running, shows once per interval and never interrupts the game. Off by default, in **Settings → Display & Controls → Saves**
- **Session timer**: the in-game menu shows how long you have been playing this session
- **Fast-forward**, **mute**, **reset** and **screenshots** in the in-game quick menu, with optional export of screenshots to your gallery (off by default)
- **Per-core settings**: one-tap *Performance / Balanced / Quality* presets (tonEMU suggests the one that suits your phone), with options grouped into Video, Performance, Audio, Input and System
- **Safe by design**: options that a core only reads at startup are never changed on a running game, values known to crash on phones are blocked, and if a launch fails, that core's settings are reset on the next start so the game can open again
- **Region**: detected automatically from each game, so PAL and Japanese games run at the correct speed. Region can't be changed on most cores
- **Video filters** (None, Sharp, CRT, LCD, plus smooth pixel-art upscalers where available), low-latency audio option, and adjustable portrait picture size
- **Correct in-game clock**: games with a real-time clock (Pokémon, Animal Crossing and others) follow your phone's time zone
- **Settings**: a player profile card (nickname and birthday), BIOS status for each system, and a one-tap reset for display and control options

### System setup
- **BIOS and system files** imported on the BIOS & System Files screen, with a status for each system (Required, Recommended or Optional) and a warning if a file's size looks wrong. Import loose files, a whole folder, or a zip; tonEMU renames each file to what the core expects and puts it in the right place
- **NDS**: boots games, or straight into the firmware menu, using your own BIOS files
- **PS1**: can boot the BIOS shell (memory card and CD player screen) when you have a BIOS
- **3DS and NDS player profile**: set your nickname and birthday once and it is written to the system
- **PSP**: import the PPSSPP assets zip so system dialogs and fonts show correctly
- **Themes**: Light, Dark or follow the system, in two visual styles: Classic and Dot
- **About, Privacy Policy and licenses**: **Settings → About** opens an About page (version, supported systems, credits), a Privacy Policy, an Open-source licenses list covering every emulator core, library and font the app uses, and the full license texts

## Supported systems

| System | Core | File types |
|---|---|---|
| Nintendo Entertainment System | FCEUmm | `.nes` `.unf` `.unif` |
| Super Nintendo | bsnes | `.sfc` `.smc` `.swc` `.fig` |
| Nintendo 64 | Mupen64Plus-Next | `.n64` `.z64` `.v64` |
| Game Boy | Gambatte | `.gb` |
| Game Boy Color | Gambatte | `.gbc` |
| Game Boy Advance | mGBA | `.gba` |
| Nintendo DS | melonDS | `.nds` |
| Nintendo 3DS | Azahar | `.3ds` `.cci` `.cxi` `.app` `.3dsx` `.cia` |
| PlayStation | SwanStation | `.chd` `.cue` `.pbp` `.bin` |
| PlayStation Portable | PPSSPP | `.iso` `.cso` |
| Sega Master System | Gearsystem | `.sms` |
| Sega Game Gear | Gearsystem | `.gg` |
| Sega Genesis / Mega Drive | BlastEm | `.md` `.gen` `.smd` |
| Sega Saturn (experimental) | Yabause | `.ccd` `.mds` `.chd` `.cue` |
| Pokémon Mini | PokeMini | `.min` |
| WonderSwan / WonderSwan Color | Beetle Cygne | `.ws` `.wsc` `.pc2` `.pcv2` |

> For the best experience, import the system files listed in [BIOS & system files](#bios--system-files) below.

**Format notes:**
- `.cue` and `.chd` files can be PlayStation or Saturn games, so tonEMU asks which console each one belongs to. `.iso` and `.cso` files are PSP games. Sega CD is not supported yet.
- A `.bin` track file is imported together with the `.cue` sheet that uses it; a lone `.bin` is ignored.
- Genesis games saved as `.bin` should be renamed to `.md`.
- `.pc2` / `.pcv2` are Benesse Pocket Challenge V2 games, which run on the WonderSwan core.

## Installation

### Android

1. Starting **November 28, 2026**, download the latest APK from the [Releases](../../releases) page.
2. Allow installs from unknown sources if prompted.
3. Open tonEMU, tap import, and pick your ROM files (or send them from your PC with Wi-Fi transfer).

### Storage

tonEMU keeps everything in its own app folder, `Android/data/com.jedplatforms.jedEmu/files/tonEMU`, with these subfolders: `roms`, `saves`, `states`, `system` (BIOS files) and `screenshots`. A `backups` folder appears when you back up saves with jedManager.

- **No storage permission is needed**, and tonEMU never asks for "All files access".
- **Browse it from the Files app**: tonEMU adds a **tonEMU** location to Android's Files app and file pickers, where you can copy BIOS files in, back up saves, rename and delete. jedManager's **Open tonEMU in Files** button jumps straight there. It is also visible over a USB cable.
- If external app storage is ever unavailable, tonEMU falls back to the app's private storage.
- Uninstalling the app removes this folder, so copy out anything you want to keep first.
- Coming from an older tonEMU build that used `/storage/emulated/0/tonEMU`? Use **jedManager → Bring in an older tonEMU folder** to copy it across.

### Permissions and privacy

tonEMU has no accounts, ads or analytics, and your games, saves and settings stay on your device. It asks for:

| Permission | Why |
|---|---|
| Internet and network state | Download box art and cheat files from GitHub, and run Wi-Fi transfer |
| Keep screen on | While a game is running and while Wi-Fi transfer is sending files |

Optional: if you turn on **Screenshots to Gallery**, a copy of each screenshot is saved to `Pictures/tonEMU`. On Android 9 and older this only happens if you have granted storage permission yourself in Android settings; tonEMU never asks for it.

If Android device backup is on, Android may back up your battery saves (the `saves` folder) to your Google account, and carry saves and save states over when you move to a new phone. Games, BIOS files and the 3DS data folders (Azahar / Citra) are left out of cloud backup, and save states are only included in phone-to-phone transfer. That is handled by Android and Google; jedPlatforms never receives it.

The full text is in **Settings → About → Privacy Policy**.

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
| Pokémon Mini / WonderSwan | Android 8.0, any 2 GB device | Any modern device |
| NDS | Android 8.0, 3 GB RAM, mid-range chipset | 4 GB RAM, recent mid-range or better |
| PS1 | Android 8.0, 3 GB RAM, mid-range chipset | 4 GB RAM, recent mid-range or better |
| N64 | Android 8.0, 4 GB RAM, upper mid-range chipset, OpenGL ES 3 | 6 GB RAM, flagship chipset |
| Sega Saturn | Android 8.0, 4 GB RAM, upper mid-range chipset | 6 GB RAM, flagship chipset |
| PSP | Android 8.0, 4 GB RAM, upper mid-range chipset | 6 GB RAM, flagship chipset |
| 3DS | 64-bit (arm64) device, 6 GB RAM, flagship chipset | 8 GB RAM, latest flagship chipset |

Notes:
- tonEMU renders with OpenGL ES on every system. Vulkan is not used, so a Vulkan-capable GPU is not needed.
- PS1 needs a BIOS file that you provide. NDS and Saturn run without one but are more compatible with a real BIOS, and NDS needs `bios7.bin`, `bios9.bin` and `firmware.bin` to boot the firmware menu (see below).
- PS1 uses a DualShock (analog) controller by default, so analog sticks and L3 / R3 work in games that support them.
- PS1 uses the software renderer by default for compatibility. You can switch to the experimental OpenGL ES renderer in the core settings (it needs a game restart); switch back if you get a black screen.
- The 3DS core is arm64 only and uses OpenGL ES, so it needs a 64-bit device.
- On mid-range devices, use the *Performance* preset in core settings.
- jedTimeMachine adds a small amount of storage use while you play (snapshots are capped and cleared after each session).
- Flip phones: the fold and flip layout applies to the main (inner) display. The small outer cover screen isn't specifically supported yet.

> RAM and storage figures are general guidance, not hard limits. Real performance depends on your chipset, the game and the core settings you choose.

## BIOS & system files

Import these on the **BIOS & System Files** screen (open it from Settings) with **Import files** or **Import folder**; a zip works too. You can also drop them into the `system` folder through the Files app. tonEMU does not include them. See the [Disclaimer](#disclaimer).

| System | What to import | Files | Needed? |
|---|---|---|---|
| PlayStation 1 | BIOS (any one) | `scph5501.bin`, `scph1001.bin` or `scph7001.bin` are best; `scph7003.bin`, `scph5500.bin` and `scph5502.bin` also work | **Required**. No PS1 game starts without one |
| Nintendo DS | BIOS and firmware | `bios7.bin`, `bios9.bin`, `firmware.bin` | Recommended for games; required to boot the firmware menu |
| Sega Saturn | BIOS (any one) | `saturn_bios.bin` or `sega_101.bin` | Recommended. A built-in replacement is used without it |
| PSP | PPSSPP assets, imported as a `.zip` | `PPSSPP.zip` (contains `flash0/font/*.pgf`) | Recommended, for system fonts and dialogs |
| Game Boy Advance | BIOS | `gba_bios.bin` | Optional. A built-in replacement is used; a few games are slightly less accurate |
| Game Boy / Color | Boot ROMs | `gb_bios.bin`, `gbc_bios.bin` | Optional. Only adds the boot logo |
| Master System / Game Gear | BIOS | `bios_U.sms` (or `bios_E.sms`, `bios_J.sms`), `bios.gg` | Optional. Only adds the boot logo |
| Pokémon Mini | BIOS | `bios.min` | Optional. A built-in replacement is used |
| NES (Famicom Disk System) | Disk System BIOS | `disksys.rom` | Only needed for Disk System games |
| Nintendo DS (DSi mode) | DSi BIOS, firmware and NAND | `bios7i.bin`, `bios9i.bin`, `dsi_firmware.bin`, `dsi_nand.bin` | Optional. DSi mode only |

The BIOS & System Files screen shows the status of every system's files. NES, SNES, N64, 3DS, Genesis and WonderSwan games run without any BIOS, and the Game Boy, GBA, Master System, Game Gear and Pokémon Mini files above are optional. You can dump the BIOS files from hardware you own. The PPSSPP assets come from the official PPSSPP project.

## Getting started

1. **Import games**: tap the **+** button and choose individual files, a whole folder, or **Wi-Fi transfer** to send them from your PC's browser. tonEMU detects the system from each file's extension and sorts it into the right group.
2. **Import your BIOS / system files** for PS1, NDS, PSP and Saturn (see [above](#bios--system-files)).
3. **Tap a game** to launch it, or press **Resume** on the home screen to jump back into your last game. Long-press a game for favorites, box art and removal options.
4. **Tune it**: open core settings and pick a Performance, Balanced or Quality preset, or fine-tune individual options.
5. **Play without fear**: jedTimeMachine records your session in the background. If something goes wrong, open the in-game menu and jump back.

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

## Roadmap

- [x] Android APK release (November 28, 2026)
- [ ] iOS
- [ ] macOS
- [ ] Windows
- [ ] Linux
- [ ] Sega CD
- [ ] PS1 controller rumble
- [ ] Flip cover-screen support
- [ ] More systems and cores

The app is written in Flutter, so the main porting work is the native emulator-core bridge for each platform.

## License

**tonEMU is free and open-source software, released under the [GNU General Public License v3.0 or later](https://www.gnu.org/licenses/gpl-3.0.html) (GPL-3.0-or-later).** Its source code is available at [github.com/ProtonyteTV/tonEMU](https://github.com/ProtonyteTV/tonEMU). You are free to use, study, modify and share it under the terms of that license.

tonEMU is built on free and open-source software. Every emulator core and library stays under its own license, and the full texts (GPL-2.0, GPL-3.0, MPL-2.0, Apache-2.0 and the libretro MIT header) ship inside the app under **Settings → About → Open-source licenses → Full license texts**.

### Emulator cores and frontend libraries

| Project | Used for | License |
|---|---|---|
| [LibretroDroid](https://github.com/Swordfish90/LibretroDroid) | Android libretro frontend (game surface, audio, input) | GPL-3.0 |
| [libretro API](https://github.com/libretro/RetroArch) / RetroArch | Core interface and thumbnail database | MIT (`libretro.h`) · GPL-3.0 (RetroArch) |
| [libretro-common](https://github.com/libretro/libretro-common) | Shared C helper code bundled inside LibretroDroid | MIT |
| [Oboe](https://github.com/google/oboe) | Low-latency audio output inside LibretroDroid | Apache-2.0 |
| [FCEUmm](https://github.com/libretro/libretro-fceumm) | NES / Famicom | GPL-2.0 |
| [bsnes](https://github.com/libretro/bsnes) | Super Nintendo | GPL-3.0 |
| [Gambatte](https://github.com/libretro/gambatte-libretro) | Game Boy / Game Boy Color | GPL-2.0 |
| [mGBA](https://github.com/mgba-emu/mgba) | Game Boy Advance | MPL-2.0 |
| [Mupen64Plus-Next](https://github.com/libretro/mupen64plus-libretro-nx) | Nintendo 64 | GPL-2.0-or-later |
| [melonDS](https://github.com/melonDS-emu/melonDS) | Nintendo DS | GPL-3.0 |
| [Azahar](https://github.com/azahar-emu/azahar) | Nintendo 3DS (based on Citra) | GPL-2.0-or-later |
| [SwanStation](https://github.com/libretro/swanstation) | Sony PlayStation (based on DuckStation) | GPL-3.0 |
| [PPSSPP](https://github.com/hrydgard/ppsspp) | Sony PSP (and its fonts / assets) | GPL-2.0-or-later |
| [BlastEm](https://github.com/libretro/blastem) | Sega Genesis / Mega Drive | GPL-3.0-or-later |
| [Gearsystem](https://github.com/drhelius/Gearsystem) | Master System / Game Gear | GPL-3.0 |
| [Yabause](https://github.com/libretro/yabause) | Sega Saturn | GPL-2.0-or-later |
| [PokeMini](https://github.com/libretro/PokeMini) | Pokémon Mini | GPL-3.0-or-later |
| [Beetle Cygne](https://github.com/libretro/beetle-wswan-libretro) | WonderSwan / WonderSwan Color | GPL-2.0-or-later |

### Libraries, fonts and data

| Project | Used for | License |
|---|---|---|
| [Flutter & Dart SDK](https://github.com/flutter/flutter) | App framework | BSD-3-Clause |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | Saving settings | BSD-3-Clause |
| [path_provider](https://pub.dev/packages/path_provider) | Finding app folders | BSD-3-Clause |
| [file_picker](https://pub.dev/packages/file_picker) | Choosing games, BIOS files and folders | MIT |
| [material_ui & cupertino_ui](https://pub.dev/packages/material_ui) | Material and iOS-style interface components | BSD-3-Clause |
| [cupertino_icons](https://pub.dev/packages/cupertino_icons) | iOS-style icons | MIT |
| [wakelock_plus](https://pub.dev/packages/wakelock_plus) | Keeping the screen on during imports | BSD-3-Clause |
| [Doto](https://fonts.google.com/specimen/Doto) | Dot-matrix headings (Dot theme) | SIL Open Font License 1.1 |
| [Space Grotesk](https://fonts.google.com/specimen/Space+Grotesk) | Main interface font | SIL Open Font License 1.1 |
| [Space Mono](https://fonts.google.com/specimen/Space+Mono) | Label font (Dot theme) | SIL Open Font License 1.1 |
| [libretro-thumbnails](https://github.com/libretro-thumbnails) | Optional cover art, downloaded on request and not bundled | Community artwork |

License names above are summaries. Always refer to each project's own repository for the authoritative terms.

## Disclaimer

**tonEMU does not provide, include, or distribute any ROMs, games, BIOS files, or firmware.** You must supply your own.

- Only play games you legally own. tonEMU does not condone or support piracy.
- BIOS and firmware files (for example the Nintendo DS `bios7.bin`, `bios9.bin` and `firmware.bin`) must be dumped by you from hardware you own.
- Please do not ask for ROMs or BIOS files in issues, discussions, or any other tonEMU channel, and do not share them there. Such requests and posts will be removed.
- tonEMU is an emulator frontend for educational and personal use.

All console and game names, logos and trademarks belong to their respective owners. tonEMU is not affiliated with, authorized, or endorsed by Nintendo, Sony, Sega, Bandai, The Pokémon Company, or any other company.

## Credits

tonEMU is made possible by these open-source projects:

- [Libretro](https://www.libretro.com/), [LibretroDroid](https://github.com/Swordfish90/LibretroDroid) and [Oboe](https://github.com/google/oboe)
- [FCEUmm](https://github.com/libretro/libretro-fceumm), [bsnes](https://github.com/libretro/bsnes), [Mupen64Plus-Next](https://github.com/libretro/mupen64plus-libretro-nx), [Gambatte](https://github.com/libretro/gambatte-libretro), [mGBA](https://mgba.io/), [melonDS](https://melonds.kuribo64.net/), [SwanStation](https://github.com/libretro/swanstation), [PPSSPP](https://www.ppsspp.org/) and [Azahar](https://azahar-emu.org/)
- [BlastEm](https://github.com/libretro/blastem), [Gearsystem](https://github.com/drhelius/Gearsystem), [Yabause](https://github.com/libretro/yabause), [PokeMini](https://github.com/libretro/PokeMini) and [Beetle Cygne](https://github.com/libretro/beetle-wswan-libretro)
- [Flutter](https://flutter.dev/)
- [Libretro thumbnails](https://github.com/libretro-thumbnails) for box art
- [Doto](https://fonts.google.com/specimen/Doto), [Space Grotesk](https://fonts.google.com/specimen/Space+Grotesk) and [Space Mono](https://fonts.google.com/specimen/Space+Mono) fonts

Made with dedication by **jedPlatforms**.

## Contact

[jedplatforms.vercel.app](https://jedplatforms.vercel.app) · [GitHub](https://github.com/ProtonyteTV) · [X](https://x.com/ProtonyteTV) · jedplatforms@gmail.com

---

<div align="center">

*In loving memory*

**Burlington "TonTon" Lambot**

*Eternal Player One · Guardian of tonEMU*

October 10, 2026 — November 12, 2026

*Game over was never in his vocabulary. Rest easy, Player One. You will always be the hero of this story.* ❤️

</div>
