// lib/screens/about_screen.dart
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../services/emulator_bridge.dart';
import '../services/theme_service.dart';
import '../widgets/settings_kit.dart';

const String kAppName = 'tonEMU';
const String kAppVersion = '27.0';
const String kContactEmail = 'jedplatforms@gmail.com';

/// Public source-code page of tonEMU (the GPL cores require the source to be offered). The
/// "Source code" row in About is hidden whenever this is empty.
const String kSourceUrl = 'https://github.com/ProtonyteTV/tonEMU';

/// Optional donation page (Buy Me a Coffee). Opens in the browser; nothing is sent from the app.
const String kSupportUrl = 'https://buymeacoffee.com/jedplatforms';
const String kPrivacyUpdated = 'November 27, 2026';

const String kTontonName = 'Burlington "TonTon" Lambot';
const String kTontonTitle = 'Eternal Player One · Guardian of tonEMU';
const String kTontonDates = 'October 10, 2026 — November 12, 2026 · 10:38 PM';

/// Memorial card for TonTon. Used on the About page and at the end of the Developers sheet.
class TontonTribute extends StatelessWidget {
  const TontonTribute({super.key});

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    const gold = Color(0xFFFFB63D);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            gold.withValues(alpha: c.isDark ? 0.18 : 0.22),
            c.cardBg,
          ],
        ),
        border: Border.all(color: gold.withValues(alpha: 0.55), width: 1),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: gold.withValues(alpha: 0.18),
              border: Border.all(color: gold, width: 1.5),
            ),
            child: const Icon(Icons.pets_rounded, color: gold, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            'IN LOVING MEMORY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.4,
              color: gold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            kTontonName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: c.primaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            kTontonTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: c.secondaryText,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            kTontonDates,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 0.3,
              color: c.tertiaryText,
            ),
          ),
          const SizedBox(height: 14),
          Divider(
            height: 1,
            thickness: 0.5,
            color: gold.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 14),
          Text(
            'A small cat with a giant heart. He kept watch through every late '
            'night of building, and every game that runs here carries his spirit. '
            'Though his time was brief, his courage and love were boundless.\n\n'
            'Game over was never in his vocabulary. Rest easy, Player One. '
            'You will always be the hero of this story. ❤️',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              fontStyle: FontStyle.italic,
              color: c.primaryText,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared page frame: same background / app bar / width limit as the other settings screens.
class _InfoPage extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _InfoPage({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return c.dotted(
      Scaffold(
        backgroundColor: c.pageBg,
        appBar: AppBar(
          backgroundColor: c.pageBg,
          centerTitle: true,
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _open(BuildContext context, String label, String url) async {
  if (await EmulatorBridge.openUrl(url)) return;
  final text = url.startsWith('mailto:')
      ? url.substring(7).split('?').first
      : url;
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text('Couldn\'t open $label, copied: $text')),
    );
}

Widget _card(XEmuColors c, Widget child) => Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: c.cardBg,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: c.hairline, width: 0.5),
  ),
  child: child,
);

Widget _heading(XEmuColors c, String text) => Padding(
  padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
  child: Text(
    text.toUpperCase(),
    style: TextStyle(
      color: c.secondaryText,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    ),
  ),
);

Widget _body(XEmuColors c, String text) => Text(
  text,
  style: TextStyle(fontSize: 14, height: 1.45, color: c.primaryText),
);

// ═════════════════════════════ About ═════════════════════════════

class AboutScreen extends StatelessWidget {
  /// Opens the Developers & Credits sheet (owned by the settings screen).
  final VoidCallback onDevelopers;
  const AboutScreen({super.key, required this.onDevelopers});

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return _InfoPage(
      title: 'About',
      children: [
        const SizedBox(height: 16),
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: c.accent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.gamepad_rounded,
              color: Colors.white,
              size: 46,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            kAppName,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: c.primaryText,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Center(
          child: Text(
            'Multi-System Emulator · Version $kAppVersion',
            style: TextStyle(fontSize: 13, color: c.secondaryText),
          ),
        ),
        const SizedBox(height: 22),
        _card(
          c,
          _body(
            c,
            'tonEMU plays the games you own on one phone, with one library, one '
            'set of controls and one save system. Every system runs on a '
            'libretro emulator core, so you can tune each one separately or '
            'leave it on its defaults.\n\n'
            'tonEMU does not include any games or console BIOS files. You '
            'provide your own legally obtained backups.',
          ),
        ),
        _heading(c, 'Supported systems'),
        _card(
          c,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in const [
                'NES',
                'SNES',
                'Game Boy / Color',
                'Game Boy Advance',
                'Nintendo 64',
                'Nintendo DS',
                'Nintendo 3DS',
                'PlayStation',
                'PSP',
                'Master System',
                'Game Gear',
                'Genesis / Mega Drive',
                'Sega Saturn',
                'Pokémon Mini',
                'WonderSwan / Color',
              ])
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: c.secondaryFill,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    s,
                    style: TextStyle(fontSize: 12.5, color: c.primaryText),
                  ),
                ),
            ],
          ),
        ),
        SettingsGroup(
          title: 'Information',
          children: [
            const SettingsRow(
              icon: CupertinoIcons.info_circle_fill,
              color: Color(0xFF007AFF),
              title: 'Version',
              value: 'v$kAppVersion',
            ),
            SettingsRow(
              icon: CupertinoIcons.person_2_fill,
              color: kSettingsWarn,
              title: 'Developers & Credits',
              subtitle: 'The team behind tonEMU and its emulator cores',
              onTap: onDevelopers,
            ),
            SettingsRow(
              icon: CupertinoIcons.hand_raised_fill,
              color: const Color(0xFF34C759),
              title: 'Privacy Policy',
              subtitle: 'What tonEMU stores and what it sends',
              onTap: () => Navigator.push(
                context,
                CupertinoPageRoute(builder: (_) => const PrivacyPolicyScreen()),
              ),
            ),
            SettingsRow(
              icon: CupertinoIcons.doc_text_fill,
              color: const Color(0xFF8E8E93),
              title: 'Open-source licenses',
              subtitle: 'Emulator cores, libraries and fonts used by the app',
              onTap: () => Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (_) => const OpenSourceLicensesScreen(),
                ),
              ),
            ),
            SettingsRow(
              icon: CupertinoIcons.heart_fill,
              color: const Color(0xFFFF2D55),
              title: 'Support tonEMU',
              subtitle: 'Buy me a coffee. tonEMU stays free either way',
              onTap: () => _open(context, 'Support page', kSupportUrl),
            ),
            if (kSourceUrl.isNotEmpty)
              SettingsRow(
                icon: CupertinoIcons.chevron_left_slash_chevron_right,
                color: const Color(0xFF8E8E93),
                title: 'Source code',
                subtitle: 'tonEMU is open source, view it on GitHub',
                onTap: () => _open(context, 'Source code', kSourceUrl),
              ),
            SettingsRow(
              icon: CupertinoIcons.mail_solid,
              color: kSettingsWarn,
              title: 'Contact',
              subtitle: kContactEmail,
              onTap: () => _open(
                context,
                'Email',
                'mailto:$kContactEmail?subject=$kAppName',
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        const TontonTribute(),
        const SizedBox(height: 18),
        Center(
          child: Text(
            'Made with dedication by jedPlatforms',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.5, color: c.secondaryText),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Game consoles and brands named here belong to their owners. tonEMU is '
            'not affiliated with or endorsed by any console maker.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, height: 1.4, color: c.tertiaryText),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════ Privacy Policy ═══════════════════════════

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _sections = <({String title, String text})>[
    (
      title: 'Summary',
      text:
          'tonEMU has no accounts, no ads and no analytics or tracking, and '
          'jedPlatforms collects no data from you. Your games, saves and settings '
          'stay on your device. The app goes online only for three things, all '
          'described below: cover art, the cheat database, and Wi-Fi Transfer '
          '(which stays on your local network).',
    ),
    (
      title: 'What stays on your device',
      text:
          'Your game files, BIOS files, battery saves, save states, screenshots, '
          'cheats, save backups and play-time file are kept in the tonEMU folder '
          'inside the app\'s own storage on your device '
          '(Android/data/com.jedplatforms.jedEmu/files/tonEMU). Your settings '
          '(controller layout, per-core options, theme, favorites, play time and '
          'the player profile used by DS / 3DS games: nickname and birthday) and '
          'downloaded cover art are kept in the app\'s private storage. '
          'jedPlatforms does not receive or have access to any of it.\n\n'
          'You can browse, copy or delete the tonEMU folder from your Files app '
          '(look for \"tonEMU\") or over a USB cable. That location is provided by '
          'tonEMU itself; another app can read these files only if you pick them '
          'for it in Android\'s file picker. Uninstalling the app removes '
          'all of it, so copy out anything you want to keep first.',
    ),
    (
      title: 'Saves, backups and snapshots',
      text:
          'jedManager shows the saves, states and play time of each game. It can '
          'copy your saves into a \"backups\" folder inside tonEMU, or delete them, '
          'only when you ask. \"Export play time & favorites\" writes a '
          'jed_stats.json file into the tonEMU folder; it is never uploaded.\n\n'
          'jedTimeMachine keeps a short rolling history of snapshots (a save '
          'state and a small thumbnail) while you play, so you can jump back. They '
          'are stored in the tonEMU folder and deleted when a game starts and when '
          'it ends.\n\n'
          'If you bring in the folder of an older tonEMU version, you choose it '
          'with Android\'s folder picker. tonEMU can then read only that folder, '
          'and copies its games, saves, states, BIOS files and screenshots into '
          'the new location. Nothing is deleted from the old folder.',
    ),
    (
      title: 'Information we collect',
      text:
          'None. tonEMU does not collect, sell or share personal information, and '
          'it does not contain advertising or third-party analytics or '
          'crash-reporting services.\n\n'
          'Device details: to suggest a settings preset and to show whether your '
          'phone can run each console, the app reads your phone\'s model, chipset, '
          'graphics chip, memory and Android version. This is shown on your device '
          'only and is never sent anywhere.\n\n'
          'Time zone: the app reads your phone\'s time zone so the clocks inside '
          'games show your local time. It stays on your device.',
    ),
    (
      title: 'Network access',
      text:
          'Cover art: when games appear in your library, tonEMU looks for matching '
          'box art in the public libretro-thumbnails repository on GitHub. It may '
          'first download the list of file names for your console (this request '
          'contains no game title), then request one or more images whose names '
          'are built from the game\'s title (taken from its file name) and its '
          'console. Some consoles are checked in more than one repository, for '
          'example WonderSwan and WonderSwan Color. Each image is saved on your '
          'device; saved covers are kept within a size limit, so one removed to '
          'make room can be downloaded again. Covers you pick yourself are copied '
          'into the app\'s storage, are never removed by that limit and are never '
          'uploaded. You can turn cover downloads off with \"Download '
          'cover art\" in Display & Controls (Library): nothing is then sent, and '
          'covers already saved or picked by you keep showing.\n\n'
          'Cheat database: when you open the cheat browser for a game, tonEMU '
          'downloads the list of cheat files for that console and then the '
          'matching cheat file (named after the game) from the public '
          'libretro-database repository on GitHub, and keeps a copy on your '
          'device.\n\n'
          'These requests go directly to GitHub, which can see your IP address '
          'and a generic app identifier, and may log them under its own privacy '
          'policy. jedPlatforms does not operate these servers and receives none '
          'of this data. With no connection (for example in airplane mode) tonEMU '
          'works as normal; only new cover art and cheat downloads are missing.\n\n'
          'Wi-Fi Transfer: nothing starts until you tap \"Start Wi-Fi Transfer\". '
          'The app then runs a temporary web server on your local network so a '
          'computer\'s browser can send games to your phone. The address shown in '
          'the app contains a random access code that every request must include, '
          'and an address that keeps sending wrong codes is blocked for a short '
          'time. The connection is plain HTTP and is not encrypted, so use it only '
          'on a network you trust (your home Wi-Fi or your own hotspot). It stops '
          'when you tap \"Stop Transfer\" or leave the screen. Received files are '
          'first placed in a temporary folder inside tonEMU, and only supported '
          'game files are moved into your library.',
    ),
    (
      title: 'Android backup',
      text:
          'If device backup is turned on in your Android settings, Android may '
          'back up your battery-save files (the \"saves\" folder) to your Google '
          'account, and include saves and save states when you move to a new '
          'phone. Games, BIOS files, save states and the 3DS data folders are '
          'left out of cloud backup. This is handled by Android and Google under '
          'your own Google account settings; jedPlatforms never receives it.',
    ),
    (
      title: 'Permissions',
      text:
          'Storage: tonEMU needs no storage permission and never asks for access '
          'to all of your files. It uses its own app folder. To add files, use '
          'the \"tonEMU\" location in your Files app, any file or folder picker '
          '(you choose what to share), or Wi-Fi Transfer.\n\n'
          'Internet and network state: for cover art, cheats and Wi-Fi Transfer, '
          'and to check that a connection is available.\n\n'
          'Keep screen on: while a game is running and while Wi-Fi Transfer is '
          'sending files.\n\n'
          'Gallery: off by default. If you turn on \"Screenshots to Gallery\", a '
          'copy of each screenshot you take is also saved to Pictures/tonEMU. '
          'On Android 9 and older this copy is made only if you have granted the '
          'storage permission yourself in Android settings; tonEMU never asks '
          'for it. '
          'Screenshots are always kept in the tonEMU folder.\n\n'
          'Controllers: physical gamepad input is read only to control the app '
          'and the running game.',
    ),
    (
      title: 'Your choices',
      text:
          'There is nothing to sign up for and no account to delete. You can '
          'remove any file from your Files app or from jedManager, clear the '
          'app\'s storage in Android settings, or uninstall the app to erase '
          'everything tonEMU stored. You can turn off cover-art downloads and '
          'the gallery copy at any time, and stop Wi-Fi Transfer by leaving its '
          'screen.',
    ),
    (
      title: 'Third-party services',
      text:
          'The emulator cores run entirely on your device and send no data '
          'anywhere. The app contains no third-party analytics, advertising or '
          'crash-reporting libraries. If you installed tonEMU from Google Play '
          'and allowed Android to share usage and diagnostic data, Google may '
          'collect crash and performance reports for apps and show them to the '
          'developer; that is controlled by your Android settings and Google\'s '
          'privacy policy. Links in the app (website, GitHub, X, email, the optional support page) open in '
          'your browser or mail app and are then covered by those services\' own '
          'policies.',
    ),
    (
      title: 'Your games and BIOS files',
      text:
          'tonEMU ships without games or BIOS files. You are responsible for only '
          'using backups of media you legally own, and for following the laws '
          'where you live.',
    ),
    (
      title: 'Children',
      text:
          'tonEMU does not knowingly collect information from anyone, including '
          'children under 13. The birthday setting is stored only on your device '
          'and is used solely to fill in the in-game profile of DS / 3DS titles.',
    ),
    (
      title: 'Changes to this policy',
      text:
          'If the app\'s behaviour changes, this policy will be updated and the '
          '\"Last updated\" date below will change with the new version.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return _InfoPage(
      title: 'Privacy Policy',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            'Last updated: $kPrivacyUpdated',
            style: TextStyle(fontSize: 12, color: c.secondaryText),
          ),
        ),
        for (final s in _sections) ...[
          _heading(c, s.title),
          _card(c, _body(c, s.text)),
        ],
        SettingsGroup(
          title: 'Contact',
          children: [
            SettingsRow(
              icon: CupertinoIcons.mail_solid,
              color: kSettingsWarn,
              title: 'Questions about privacy',
              subtitle: kContactEmail,
              onTap: () => _open(
                context,
                'Email',
                'mailto:$kContactEmail?subject=$kAppName%20Privacy',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════ Open-source licenses ═══════════════════════

typedef _Lic = ({
  String name,
  String by,
  String license,
  String use,
  String url,
});

class OpenSourceLicensesScreen extends StatelessWidget {
  const OpenSourceLicensesScreen({super.key});

  static const List<_Lic> _cores = [
    (
      name: 'LibretroDroid',
      by: 'Filippo Scognamiglio',
      license: 'GPL-3.0',
      use: 'Android libretro frontend (game surface, audio, input)',
      url: 'https://github.com/Swordfish90/LibretroDroid',
    ),
    (
      name: 'libretro API / RetroArch',
      by: 'Libretro Team',
      license: 'MIT (libretro.h) · GPL-3.0 (RetroArch)',
      use: 'Core interface and thumbnail database',
      url: 'https://github.com/libretro/RetroArch',
    ),
    (
      name: 'libretro-common',
      by: 'Libretro Team',
      license: 'MIT',
      use: 'Shared C helper code bundled inside LibretroDroid',
      url: 'https://github.com/libretro/libretro-common',
    ),
    (
      name: 'Oboe',
      by: 'Google',
      license: 'Apache-2.0',
      use: 'Low-latency audio output inside LibretroDroid',
      url: 'https://github.com/google/oboe',
    ),
    (
      name: 'FCEUmm',
      by: 'FCEU Team, CaH4e3 & contributors',
      license: 'GPL-2.0',
      use: 'NES / Famicom',
      url: 'https://github.com/libretro/libretro-fceumm',
    ),
    (
      name: 'bsnes',
      by: 'Near, byuu & contributors',
      license: 'GPL-3.0',
      use: 'Super Nintendo',
      url: 'https://github.com/libretro/bsnes',
    ),
    (
      name: 'Gambatte',
      by: 'Sinamas & contributors',
      license: 'GPL-2.0',
      use: 'Game Boy / Game Boy Color',
      url: 'https://github.com/libretro/gambatte-libretro',
    ),
    (
      name: 'mGBA',
      by: 'Vicki Pfau & contributors',
      license: 'MPL-2.0',
      use: 'Game Boy Advance',
      url: 'https://github.com/mgba-emu/mgba',
    ),
    (
      name: 'Mupen64Plus-Next',
      by: 'Mupen64Plus Team & libretro contributors',
      license: 'GPL-2.0-or-later',
      use: 'Nintendo 64',
      url: 'https://github.com/libretro/mupen64plus-libretro-nx',
    ),
    (
      name: 'melonDS',
      by: 'Arisotura & contributors',
      license: 'GPL-3.0',
      use: 'Nintendo DS',
      url: 'https://github.com/melonDS-emu/melonDS',
    ),
    (
      name: 'Azahar',
      by: 'Azahar Team, PabloMK7, OpenSauce04',
      license: 'GPL-2.0-or-later',
      use: 'Nintendo 3DS (based on Citra)',
      url: 'https://github.com/azahar-emu/azahar',
    ),
    (
      name: 'SwanStation',
      by: 'Stenzek & contributors',
      license: 'GPL-3.0',
      use: 'Sony PlayStation (based on DuckStation)',
      url: 'https://github.com/libretro/swanstation',
    ),
    (
      name: 'PPSSPP',
      by: 'Henrik Rydgård & contributors',
      license: 'GPL-2.0-or-later',
      use: 'Sony PSP (also its bundled fonts / assets)',
      url: 'https://github.com/hrydgard/ppsspp',
    ),
    (
      name: 'BlastEm',
      by: 'Mike Pavone & contributors',
      license: 'GPL-3.0-or-later',
      use: 'Sega Genesis / Mega Drive',
      url: 'https://github.com/libretro/blastem',
    ),
    (
      name: 'Gearsystem',
      by: 'Ignacio Sanchez & contributors',
      license: 'GPL-3.0',
      use: 'Master System / Game Gear',
      url: 'https://github.com/drhelius/Gearsystem',
    ),
    (
      name: 'Yabause',
      by: 'Yabause Team & contributors',
      license: 'GPL-2.0-or-later',
      use: 'Sega Saturn',
      url: 'https://github.com/libretro/yabause',
    ),
    (
      name: 'PokeMini',
      by: 'JustBurn & contributors',
      license: 'GPL-3.0-or-later',
      use: 'Pokémon Mini',
      url: 'https://github.com/libretro/PokeMini',
    ),
    (
      name: 'Beetle Cygne',
      by: 'Dox, Mednafen Team & contributors',
      license: 'GPL-2.0-or-later',
      use: 'WonderSwan / WonderSwan Color',
      url: 'https://github.com/libretro/beetle-wswan-libretro',
    ),
  ];

  static const List<_Lic> _libs = [
    (
      name: 'Flutter & Dart SDK',
      by: 'The Flutter Authors / Google',
      license: 'BSD-3-Clause',
      use: 'App framework',
      url: 'https://github.com/flutter/flutter',
    ),
    (
      name: 'shared_preferences',
      by: 'The Flutter Authors',
      license: 'BSD-3-Clause',
      use: 'Saving settings',
      url: 'https://pub.dev/packages/shared_preferences',
    ),
    (
      name: 'path_provider',
      by: 'The Flutter Authors',
      license: 'BSD-3-Clause',
      use: 'Finding app folders',
      url: 'https://pub.dev/packages/path_provider',
    ),
    (
      name: 'file_picker',
      by: 'Miguel Ruivo & contributors',
      license: 'MIT',
      use: 'Choosing games, BIOS files and folders',
      url: 'https://pub.dev/packages/file_picker',
    ),
    (
      name: 'material_ui & cupertino_ui',
      by: 'The Flutter Authors',
      license: 'BSD-3-Clause',
      use: 'Material and iOS-style interface components',
      url: 'https://pub.dev/packages/material_ui',
    ),
    (
      name: 'cupertino_icons',
      by: 'The Flutter Authors',
      license: 'MIT',
      use: 'iOS-style icons',
      url: 'https://pub.dev/packages/cupertino_icons',
    ),
    (
      name: 'wakelock_plus',
      by: 'Flutter Community',
      license: 'BSD-3-Clause',
      use: 'Keeping the screen on during imports',
      url: 'https://pub.dev/packages/wakelock_plus',
    ),
    (
      name: 'Doto',
      by: 'Oliver Lalan',
      license: 'SIL Open Font License 1.1',
      use: 'Dot-matrix headings (Dot theme)',
      url: 'https://fonts.google.com/specimen/Doto',
    ),
    (
      name: 'Space Grotesk',
      by: 'Florian Karsten',
      license: 'SIL Open Font License 1.1',
      use: 'Main interface font',
      url: 'https://fonts.google.com/specimen/Space+Grotesk',
    ),
    (
      name: 'Space Mono',
      by: 'Colophon Foundry',
      license: 'SIL Open Font License 1.1',
      use: 'Label font (Dot theme)',
      url: 'https://fonts.google.com/specimen/Space+Mono',
    ),
    (
      name: 'libretro-thumbnails',
      by: 'Libretro community',
      license: 'Community artwork (downloaded on request)',
      use: 'Optional cover art, not bundled with the app',
      url: 'https://github.com/libretro-thumbnails',
    ),
  ];

  Widget _tile(BuildContext context, XEmuColors c, _Lic l) {
    return InkWell(
      onTap: () => _open(context, l.name, l.url),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.name,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: c.primaryText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l.use,
                    style: TextStyle(fontSize: 12.5, color: c.secondaryText),
                  ),
                  Text(
                    l.by,
                    style: TextStyle(fontSize: 12, color: c.tertiaryText),
                  ),
                  const SizedBox(height: 5),
                  StatusPill(text: l.license, color: c.accent),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.arrow_up_right,
              size: 15,
              color: c.tertiaryText,
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context, XEmuColors c, List<_Lic> items) {
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.hairline, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                Divider(height: 0.5, thickness: 0.5, color: c.hairline),
              _tile(context, c, items[i]),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return _InfoPage(
      title: 'Open-source licenses',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            'tonEMU is free software, released under the GNU General Public License '
            'v3.0 or later (GPL-3.0-or-later). It is built on free and open-source '
            'software. Each emulator core '
            'stays under its own license, and its full source code is available at '
            'the link shown. Tap an entry to open its project page.',
            style: TextStyle(fontSize: 13, height: 1.4, color: c.secondaryText),
          ),
        ),
        _heading(c, 'Emulator cores'),
        _list(context, c, _cores),
        _heading(c, 'Libraries, fonts & data'),
        _list(context, c, _libs),
        SettingsGroup(
          title: 'License texts',
          children: [
            SettingsRow(
              icon: CupertinoIcons.doc_plaintext,
              color: const Color(0xFF8E8E93),
              title: 'Full license texts',
              subtitle: 'GPL, MPL and MIT texts of the emulator cores, plus every bundled package',
              onTap: () => showLicensePage(
                context: context,
                applicationName: kAppName,
                applicationVersion: kAppVersion,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'License names are summaries. Always refer to each project\'s own '
          'repository for the authoritative terms.',
          style: TextStyle(fontSize: 11.5, height: 1.4, color: c.tertiaryText),
        ),
      ],
    );
  }
}
