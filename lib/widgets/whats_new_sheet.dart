// lib/widgets/whats_new_sheet.dart
import 'package:material_ui/material_ui.dart';

import '../screens/about_screen.dart' show kAppVersion;
import '../services/changelog.dart';
import '../services/theme_service.dart';

Future<void> showWhatsNew(BuildContext context, List<ChangelogEntry> entries) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WhatsNewSheet(entries: entries),
  );
}

class _WhatsNewSheet extends StatelessWidget {
  final List<ChangelogEntry> entries;
  const _WhatsNewSheet({required this.entries});

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final maxH = MediaQuery.of(context).size.height * 0.8;
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(c.isDot ? 28 : 22),
          border: c.isDot ? Border.all(color: c.hairline) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What\'s new',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: c.primaryText,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'tonEMU $kAppVersion',
              style: TextStyle(fontSize: 13, color: c.secondaryText),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final e in entries) ...[
                    if (entries.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Text(
                          'v${e.version} · ${e.title}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.primaryText,
                          ),
                        ),
                      ),
                    for (final line in e.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 7, right: 10),
                              child: Icon(
                                Icons.circle,
                                size: 6,
                                color: c.accent,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                line,
                                style: TextStyle(
                                  fontSize: 15,
                                  height: 1.35,
                                  color: c.primaryText,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                autofocus: true, // D-pad / gamepad A works straight away
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
