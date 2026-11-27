// lib/widgets/update_rows.dart
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import 'package:flutter/foundation.dart' show kDebugMode;

import '../services/onboarding_service.dart';
import '../services/update_service.dart';
import 'settings_kit.dart';
import 'update_sheet.dart';

/// "Check for updates" row for the About screen.
class CheckUpdateRow extends StatefulWidget {
  const CheckUpdateRow({super.key});

  @override
  State<CheckUpdateRow> createState() => _CheckUpdateRowState();
}

class _CheckUpdateRowState extends State<CheckUpdateRow> {
  bool _busy = false;
  String? _status;

  Future<void> _run() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    final r = await UpdateService.instance.check();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = switch (r.status) {
        UpdateCheck.newer => 'Version ${r.info!.version} is available',
        UpdateCheck.upToDate => 'You have the latest version',
        UpdateCheck.failed => r.error ?? 'Could not check',
      };
    });
    if (r.status == UpdateCheck.newer) await showUpdateSheet(context, r.info!);
  }

  @override
  Widget build(BuildContext context) => SettingsRow(
    icon: CupertinoIcons.arrow_down_circle_fill,
    color: kSettingsOk,
    title: 'Check for updates',
    subtitle: _busy
        ? 'Checking…'
        : (_status ?? 'Looks for a new release on GitHub'),
    onTap: _run,
  );
}

/// "Check automatically" switch (once every 12 hours, only while the app is open).
class AutoUpdateSwitchRow extends StatefulWidget {
  const AutoUpdateSwitchRow({super.key});

  @override
  State<AutoUpdateSwitchRow> createState() => _AutoUpdateSwitchRowState();
}

class _AutoUpdateSwitchRowState extends State<AutoUpdateSwitchRow> {
  bool _on = true;

  @override
  void initState() {
    super.initState();
    UpdateService.instance.autoCheckEnabled().then((v) {
      if (mounted) setState(() => _on = v);
    });
  }

  @override
  Widget build(BuildContext context) => SettingsSwitchRow(
    icon: CupertinoIcons.arrow_2_circlepath,
    color: kSettingsOk,
    title: 'Check automatically',
    subtitle: 'Asks GitHub for a new version when the app opens. Nothing else is sent.',
    value: _on,
    onChanged: (v) {
      setState(() => _on = v);
      UpdateService.instance.setAutoCheck(v);
    },
  );
}

/// The whole "Updates" block for General Settings: check now, release notes, automatic check
/// and (debug builds only) the tools that force each popup.
class UpdatesGroup extends StatelessWidget {
  const UpdatesGroup({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsGroup(
      title: 'Updates',
      children: [
        const CheckUpdateRow(),
        SettingsRow(
          icon: CupertinoIcons.sparkles,
          color: kSettingsOk,
          title: 'What\'s new',
          subtitle: 'Release notes for this version',
          onTap: () => OnboardingService.instance.showCurrent(context),
        ),
        const AutoUpdateSwitchRow(),
        if (kDebugMode) ...[
          SettingsRow(
            icon: CupertinoIcons.ant_fill,
            color: kSettingsWarn,
            title: 'Debug: replay setup',
            onTap: () => OnboardingService.instance.replaySetup(context),
          ),
          SettingsRow(
            icon: CupertinoIcons.ant_fill,
            color: kSettingsWarn,
            title: 'Debug: show fake update sheet',
            subtitle: 'No APK attached, so the button opens the release page',
            onTap: () => showUpdateSheet(
              context,
              const UpdateInfo(
                version: '99.0',
                tag: 'v99.0',
                notes: '## Fake release\n- First change\n- Second change',
                pageUrl: kReleasesPage,
              ),
            ),
          ),
          SettingsRow(
            icon: CupertinoIcons.ant_fill,
            color: kSettingsWarn,
            title: 'Debug: update state',
            subtitle:
                'Version, install permission, last check, skipped version',
            onTap: () async {
              final s = await UpdateService.instance.debugState();
              if (!context.mounted) return;
              showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Update state'),
                  content: Text(
                    s.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        await UpdateService.instance.debugReset();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      child: const Text('Reset'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
          SettingsRow(
            icon: CupertinoIcons.ant_fill,
            color: kSettingsWarn,
            title: 'Debug: reset onboarding',
            subtitle: 'What\'s new shows again on the next launch',
            onTap: () async {
              await OnboardingService.instance.reset();
              final st = await OnboardingService.instance.debugState();
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('Reset. State: $st')));
              }
            },
          ),
        ],
      ],
    );
  }
}
