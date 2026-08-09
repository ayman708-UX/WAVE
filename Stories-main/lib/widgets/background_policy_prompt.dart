import 'package:flutter/material.dart';

import '../services/android_background_policy_service.dart';
import '../utils/app_theme.dart';

/// One-time reminder to allow unrestricted mobile data for torrent streaming.
Future<void> showUnrestrictedDataReminder(BuildContext context) async {
  final service = AndroidBackgroundPolicyService.instance;
  if (!service.supported) return;
  if (!await service.shouldShowDataReminder()) return;

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.bgCard,
      title: const Text('Allow background data'),
      content: const Text(
        'For reliable torrent audiobook streaming, set mobile data to '
        'Unrestricted (or allow background data) on the screen that opens next.',
        style: TextStyle(height: 1.35),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await service.markDataReminderShown();
            await service.openUnrestrictedDataSettings();
          },
          child: const Text('Open settings'),
        ),
      ],
    ),
  );
}
