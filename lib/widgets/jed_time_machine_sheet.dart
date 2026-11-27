// lib/widgets/jed_time_machine_sheet.dart
import 'package:material_ui/material_ui.dart';

import '../services/theme_service.dart';
import '../services/jed_time_machine.dart';

/// Bottom sheet that lists the recorded moments (newest first). Pops with the chosen
/// [JedTimeMachineEntry], or null if dismissed.
Future<JedTimeMachineEntry?> showJedTimeMachineSheet(
  BuildContext context, {
  required JedTimeMachine? machine,
  required int nowSec,
  required int intervalSec,
  Offset? anchorPoint, // lower half on a tabletop Flip
}) {
  final c = XEmuColors.of(context);
  return showModalBottomSheet<JedTimeMachineEntry>(
    context: context,
    anchorPoint: anchorPoint,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: c.cardBg,
    constraints: const BoxConstraints(maxWidth: 640),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _JedTimeMachineSheet(
      machine: machine,
      nowSec: nowSec,
      intervalSec: intervalSec,
    ),
  );
}

String _ago(int sec) {
  if (sec < 5) return 'Just now';
  if (sec < 90) return '$sec s ago';
  final m = (sec / 60).round();
  if (m < 60) return '$m min ago';
  final h = sec ~/ 3600;
  final rest = (sec % 3600) ~/ 60;
  return rest == 0 ? '$h h ago' : '$h h $rest min ago';
}

class _JedTimeMachineSheet extends StatelessWidget {
  const _JedTimeMachineSheet({
    required this.machine,
    required this.nowSec,
    required this.intervalSec,
  });

  final JedTimeMachine? machine;
  final int nowSec;
  final int intervalSec;

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final list = (machine?.entries ?? const <JedTimeMachineEntry>[]).reversed
        .toList();
    final landscape =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;

    String? empty;
    if (intervalSec <= 0) {
      empty = 'jedTimeMachine is off. Turn it on in Settings > Display & Controls > Saves.';
    } else if (machine?.disabledReason != null) {
      empty = machine!.disabledReason;
    } else if (list.isEmpty) {
      empty =
          'Nothing recorded yet. A snapshot is taken every $intervalSec seconds while you play.';
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.fast_rewind_rounded, color: c.accent, size: 22),
                const SizedBox(width: 8),
                Text(
                  'jedTimeMachine',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: c.primaryText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Tap a moment to jump back to it. Where you are now is kept, so you can undo.',
              style: TextStyle(fontSize: 13, color: c.secondaryText),
            ),
            const SizedBox(height: 14),
            if (empty != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: Text(
                    empty,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: c.secondaryText),
                  ),
                ),
              )
            else
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  itemCount: list.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: landscape ? 4 : 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.45,
                  ),
                  itemBuilder: (ctx, i) {
                    final e = list[i];
                    return _Tile(
                      entry: e,
                      label: _ago(nowSec - e.playSec),
                      onTap: () => Navigator.pop(ctx, e),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.entry, required this.label, required this.onTap});

  final JedTimeMachineEntry entry;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return Semantics(
      button: true,
      label: 'Jump back: $label',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: c.secondaryFill,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  entry.thumb,
                  fit: BoxFit.cover,
                  cacheWidth: 320,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => Center(
                    child: Icon(
                      Icons.history_rounded,
                      color: c.secondaryText,
                      size: 28,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 14, 10, 7),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xB3000000)],
                      ),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
