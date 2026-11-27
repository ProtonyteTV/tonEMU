// lib/screens/setup_screen.dart
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../services/storage_service.dart';
import '../services/theme_service.dart';
import 'bios_screen.dart';

/// First-run setup: Welcome -> Look -> Games & BIOS -> Done. Every step can be skipped and
/// nothing here is required; it only points at things the player would otherwise have to find.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  static const _pageCount = 4;
  final PageController _pc = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _next() {
    if (_page >= _pageCount - 1) {
      Navigator.of(context).pop();
      return;
    }
    _pc.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _back() => _pc.previousPage(
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
  );

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final last = _page == _pageCount - 1;
    return PopScope(
      canPop: false, // finish or skip with the buttons, so the setup is always recorded
      child: Scaffold(
        backgroundColor: c.groupedBg,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: last ? null : () => Navigator.of(context).pop(),
                  child: Text(last ? '' : 'Skip'),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pc,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [
                    _SetupPage(
                      icon: Icons.sports_esports,
                      title: 'Welcome to tonEMU',
                      body:
                          'Play your classic games on one app. This quick setup '
                          'takes under a minute and you can skip any step.',
                    ),
                    const _LookPage(),
                    _SetupPage(
                      icon: Icons.folder_open,
                      title: 'Games & BIOS',
                      body:
                          'Add your own game files from the Import button in the '
                          'library. tonEMU keeps everything in one folder you can '
                          'browse from the Files app or a PC.\n\nSome consoles '
                          '(PS1, Saturn, DS, Dreamcast) need BIOS files that you '
                          'supply yourself.',
                      actions: [
                        _SetupAction(
                          label: 'Open tonEMU folder',
                          icon: Icons.folder,
                          onTap: () async {
                            final ok = await StorageService.instance
                                .openInFilesApp();
                            if (!ok && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('No Files app could open it.'),
                                ),
                              );
                            }
                          },
                        ),
                        _SetupAction(
                          label: 'BIOS guide',
                          icon: Icons.memory,
                          onTap: () => Navigator.of(context).push(
                            CupertinoPageRoute<void>(
                              builder: (_) => const BiosScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    _SetupPage(
                      icon: Icons.check_circle_outline,
                      title: 'You\'re all set',
                      body:
                          'Tap Import in the library to add games. You can change '
                          'everything later in Settings.',
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pageCount; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _page ? c.accent : c.hairline,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Row(
                  children: [
                    if (_page > 0)
                      TextButton(onPressed: _back, child: const Text('Back')),
                    const Spacer(),
                    FilledButton(
                      autofocus: true,
                      onPressed: _next,
                      child: Text(last ? 'Start playing' : 'Next'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _SetupAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

class _SetupPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final List<_SetupAction> actions;
  const _SetupPage({
    required this.icon,
    required this.title,
    required this.body,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: c.accent),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: c.primaryText,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: c.secondaryText,
              ),
            ),
            for (final a in actions) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: a.onTap,
                icon: Icon(a.icon, size: 18),
                label: Text(a.label),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Theme + visual style pickers. Changes apply instantly (ThemeService persists them).
class _LookPage extends StatelessWidget {
  const _LookPage();

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final ts = ThemeService.instance;
    return ListenableBuilder(
      listenable: ts,
      builder: (context, _) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.palette_outlined, size: 72, color: c.accent),
              const SizedBox(height: 20),
              Text(
                'Pick your look',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: c.primaryText,
                ),
              ),
              const SizedBox(height: 20),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ],
                selected: {ts.mode},
                onSelectionChanged: (s) => ts.setMode(s.first),
              ),
              const SizedBox(height: 14),
              SegmentedButton<AppStyle>(
                segments: [
                  for (final s in AppStyle.values)
                    ButtonSegment(value: s, label: Text(s.label)),
                ],
                selected: {ts.style},
                onSelectionChanged: (s) => ts.setStyle(s.first),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
