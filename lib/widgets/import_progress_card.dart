// lib/widgets/import_progress_card.dart
import 'dart:ui' show FontFeature;

import 'package:material_ui/material_ui.dart';

import '../services/import_service.dart';
import '../services/theme_service.dart';

/// Floating card that shows a local import (Game Files / Folder) while it runs: what it is doing,
/// which file, bytes done / total, speed, time left and a Cancel button. All colors, radii, fonts
/// and shadows come from [XEmuColors], so it follows Classic / Dot and Light / Dark.
class ImportProgressCard extends StatelessWidget {
  final ImportProgress progress;
  final VoidCallback onCancel;

  const ImportProgressCard({
    super.key,
    required this.progress,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ListenableBuilder(
          listenable: progress,
          builder: (context, _) => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(c.cardRadius),
              boxShadow: c.cardShadow,
            ),
            child: Material(
              color: c.cardBg,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(c.cardRadius),
                side: BorderSide(color: c.hairline, width: c.hairlineWidth),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: _body(context, c),
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextStyle _small(XEmuColors c, {Color? color, FontWeight? weight}) =>
      TextStyle(
        fontFamily: c.labelFont,
        fontSize: c.isDot ? 11 : 12,
        color: color ?? c.secondaryText,
        fontWeight: weight,
        letterSpacing: c.isDot ? 0.4 : 0,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  Widget _body(BuildContext context, XEmuColors c) {
    final p = progress;
    final frac = p.fraction;
    final copying = p.phase == ImportPhase.copying;

    final title = switch (p.phase) {
      ImportPhase.preparing => 'Preparing files',
      ImportPhase.scanning => 'Scanning folder',
      ImportPhase.copying => 'Importing games',
      ImportPhase.checking => 'Checking for duplicates',
      ImportPhase.finishing => 'Finishing up',
    };
    final detail = switch (p.phase) {
      ImportPhase.preparing =>
        'Android is getting your files ready. Large games can take a minute.',
      ImportPhase.scanning => '${p.scanned} file(s) checked',
      ImportPhase.checking =>
        'A game with this name is already in your library',
      ImportPhase.finishing => 'Adding games to your library',
      ImportPhase.copying => p.currentName,
    };

    final eta = p.eta;
    final speed = p.bytesPerSecond;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (c.isDot) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: c.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                c.isDot ? title.toUpperCase() : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: c.labelFont,
                  fontSize: c.isDot ? 12.5 : 15,
                  fontWeight: c.isDot ? FontWeight.w400 : FontWeight.w700,
                  letterSpacing: c.isDot ? 1.0 : 0,
                  color: c.primaryText,
                ),
              ),
            ),
            if (frac != null)
              Text(
                '${(frac * 100).floor()}%',
                style: _small(c, color: c.primaryText, weight: FontWeight.w700),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _small(c),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: frac, // null = moving "working" bar
            minHeight: 6,
            color: c.accent,
            backgroundColor: c.secondaryFill,
          ),
        ),
        if (copying) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'File ${(p.doneFiles + 1).clamp(1, p.totalFiles)} of ${p.totalFiles}'
                  '  ·  ${fmtBytes(p.bytesDone)} of ${fmtBytes(p.totalBytes)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _small(c),
                ),
              ),
              if (speed > 0)
                Text(
                  '${fmtBytes(speed.round())}/s'
                  '${eta != null ? '  ·  ${fmtEta(eta)}' : ''}',
                  style: _small(c),
                ),
            ],
          ),
        ],
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: p.cancelled ? null : onCancel,
            style: TextButton.styleFrom(
              foregroundColor: c.accent,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              p.cancelled ? 'Cancelling…' : 'Cancel',
              style: TextStyle(
                fontFamily: c.labelFont,
                fontSize: c.isDot ? 11.5 : 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One file of a Wi-Fi upload: name, "received / total", percent and a bar. Themed like the card.
class TransferBar extends StatelessWidget {
  final String name;
  final int received;
  final int total;

  const TransferBar({
    super.key,
    required this.name,
    required this.received,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final c = XEmuColors.of(context);
    final p = total > 0 ? (received / total).clamp(0.0, 1.0) : null;
    final small = TextStyle(
      fontFamily: c.labelFont,
      fontSize: c.isDot ? 10.5 : 11.5,
      color: c.secondaryText,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: c.primaryText),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: p,
              minHeight: 5,
              backgroundColor: c.secondaryFill,
              color: c.accent,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            total > 0
                ? '${fmtBytes(received)} of ${fmtBytes(total)}  ·  ${(p! * 100).floor()}%'
                : fmtBytes(received),
            style: small,
          ),
        ],
      ),
    );
  }
}
