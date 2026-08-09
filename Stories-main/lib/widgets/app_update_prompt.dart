import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../services/app_update_service.dart';
import '../utils/app_theme.dart';

Future<void> showAppUpdateDialog(
  BuildContext context,
  AppUpdateOffer offer,
) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      var downloading = false;
      var progress = 0.0;
      String? error;

      return StatefulBuilder(
        builder: (context, setLocal) {
          Future<void> startDownload() async {
            setLocal(() {
              downloading = true;
              error = null;
              progress = 0;
            });
            try {
              final path = await AppUpdateService.instance.downloadApk(
                offer,
                onProgress: (p) {
                  if (context.mounted) {
                    setLocal(() => progress = p);
                  }
                },
              );
              final result = await AppUpdateService.instance.installApk(path);
              if (!context.mounted) return;
              if (result.type != ResultType.done) {
                setLocal(() {
                  downloading = false;
                  error = result.message;
                });
              } else {
                Navigator.pop(context);
              }
            } catch (e) {
              if (!context.mounted) return;
              setLocal(() {
                downloading = false;
                error = '$e';
              });
            }
          }

          return AlertDialog(
            backgroundColor: AppTheme.bgCard,
            title: const Text('Update available'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Version ${offer.versionLabel} is available '
                  '(you have ${offer.current.label}).',
                  style: const TextStyle(height: 1.35),
                ),
                if (offer.releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    offer.releaseNotes,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
                if (downloading) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    color: AppTheme.primaryColor,
                    backgroundColor: Colors.white12,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    progress > 0
                        ? 'Downloading ${(progress * 100).round()}%'
                        : 'Downloading…',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: TextStyle(color: Colors.red.shade300, fontSize: 13),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: downloading ? null : () => Navigator.pop(context),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: downloading ? null : startDownload,
                child: Text(downloading ? 'Downloading…' : 'Download & install'),
              ),
            ],
          );
        },
      );
    },
  );
}
