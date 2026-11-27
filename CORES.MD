# Emulator cores in tonEMU

tonEMU runs each system on a [libretro](https://www.libretro.com/) core. The prebuilt Android cores in
`android/app/src/main/jniLibs/arm64-v8a/` are **unmodified nightly builds from the official libretro
buildbot**:

<https://buildbot.libretro.com/nightly/android/latest/arm64-v8a/>

tonEMU does not patch or recompile any core. Each core stays under its own license (see the table
below and `assets/licenses/`), and its complete source code is available from the project linked in
the table.

## Cores

| System | Core | File in `jniLibs/arm64-v8a/` | License | Source code |
|---|---|---|---|---|
| NES | FCEUmm | `libfceumm_libretro_android.so` | GPL-2.0 | <https://github.com/libretro/libretro-fceumm> |
| Super Nintendo | bsnes | `libbsnes_libretro_android.so` | GPL-3.0 | <https://github.com/libretro/bsnes> |
| Nintendo 64 | Mupen64Plus-Next (GLES3) | `libmupen64plus_next_gles3_libretro_android.so` | GPL-2.0-or-later | <https://github.com/libretro/mupen64plus-libretro-nx> |
| Game Boy / Color | Gambatte | `libgambatte_libretro_android.so` | GPL-2.0 | <https://github.com/libretro/gambatte-libretro> |
| Game Boy Advance | mGBA | `libmgba_libretro_android.so` | MPL-2.0 | <https://github.com/mgba-emu/mgba> |
| Nintendo DS | melonDS | `libmelonds_libretro_android.so` | GPL-3.0 | <https://github.com/melonDS-emu/melonDS> |
| Nintendo 3DS | Azahar | `libazahar_libretro.so` | GPL-2.0-or-later | <https://github.com/azahar-emu/azahar> |
| PlayStation | SwanStation | `libswanstation_libretro_android.so` | GPL-3.0 | <https://github.com/libretro/swanstation> |
| PSP | PPSSPP | `libppsspp_libretro_android.so` | GPL-2.0-or-later | <https://github.com/hrydgard/ppsspp> |
| Genesis / Mega Drive | BlastEm | `libblastem_libretro_android.so` | GPL-3.0-or-later | <https://github.com/libretro/blastem> |
| Master System / Game Gear | Gearsystem | `libgearsystem_libretro_android.so` | GPL-3.0 | <https://github.com/drhelius/Gearsystem> |
| Sega Saturn | Yabause | `libyabause_libretro_android.so` | GPL-2.0-or-later | <https://github.com/libretro/yabause> |
| Pokémon Mini | PokeMini | `libpokemini_libretro_android.so` | GPL-3.0-or-later | <https://github.com/libretro/PokeMini> |
| WonderSwan / Color | Beetle Cygne | `libmednafen_wswan_libretro_android.so` | GPL-2.0-or-later | <https://github.com/libretro/beetle-wswan-libretro> |

The cores are loaded through [LibretroDroid](https://github.com/Swordfish90/LibretroDroid)
(GPL-3.0), vendored in `android/libretrodroid/`.

## Build provenance

Nightly builds are rebuilt from the latest source every day, so a core downloaded today is not the
same binary as one downloaded next month. To make each shipped binary traceable to its exact
source, every core used in a release is recorded here.

**Release 27.0 (November 28, 2026)**

| Core | Downloaded from buildbot on | Upstream commit | SHA-256 of the `.so` |
|---|---|---|---|
| FCEUmm | _YYYY-MM-DD_ | _commit hash_ | _hash_ |
| bsnes | _YYYY-MM-DD_ | _commit hash_ | _hash_ |
| Mupen64Plus-Next (GLES3) | _YYYY-MM-DD_ | _commit hash_ | _hash_ |
| Gambatte | _YYYY-MM-DD_ | _commit hash_ | _hash_ |
| mGBA | _YYYY-MM-DD_ | _commit hash_ | _hash_ |
| melonDS | _YYYY-MM-DD_ | _commit hash_ | _hash_ |
| Azahar | _YYYY-MM-DD_ | _commit hash_ | _hash_ |
| SwanStation | _YYYY-MM-DD_ | _commit hash_ | _hash_ |
| PPSSPP | _YYYY-MM-DD_ | _commit hash_ | _hash_ |
| BlastEm | _YYYY-MM-DD_ | _commit hash_ | _hash_ |
| Gearsystem | _YYYY-MM-DD_ | _commit hash_ | _hash_ |
| Yabause | _YYYY-MM-DD_ | _commit hash_ | _hash_ |
| PokeMini | _YYYY-MM-DD_ | _commit hash_ | _hash_ |
| Beetle Cygne | _YYYY-MM-DD_ | _commit hash_ | _hash_ |

To fill in the SHA-256 column, run this in `android/app/src/main/jniLibs/arm64-v8a/`:

```sh
sha256sum *.so
```

The upstream commit is the latest commit on the core's default branch on the day you downloaded it.
The buildbot's file listing shows the build date next to each file.

## Getting the exact source

Each core's source is public at the link in the table above. For the exact version in a given
release, check out the commit listed under *Build provenance*. If you cannot find the source for a
core shipped in tonEMU, open an issue or write to jedplatforms@gmail.com and it will be provided.

## Updating a core

1. Download the new `*_libretro_android.so.zip` from the buildbot link above and unzip it.
2. Rename it to match the file name in the table (no doubled `.so.so`) and replace it in
   `android/app/src/main/jniLibs/arm64-v8a/`.
3. Update the date, commit and SHA-256 under *Build provenance*.
4. Test the system on a real device before releasing.