import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../services/app_updater_service.dart';
import '../core/theme/app_theme.dart';

import 'package:ota_update/ota_update.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({super.key, required this.updateInfo});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog>
    with SingleTickerProviderStateMixin {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  @override
  Widget build(BuildContext context) {
    final theme = AppThemeScope.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(theme.cardRadius),
          border: Border.all(
            color: theme.accent.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.accent.withValues(alpha: 0.2),
              blurRadius: 40,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with animated gradient
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.accent.withValues(alpha: 0.2),
                    theme.accent.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(theme.cardRadius),
                  topRight: Radius.circular(theme.cardRadius),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.system_update_rounded,
                      color: theme.accent,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'UPDATE AVAILABLE',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                            color: theme.accent,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Version ${widget.updateInfo.latestVersion}',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: theme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Version info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.onSurface.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.onSurface.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Current',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.onSurfaceMuted,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.updateInfo.currentVersion,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: theme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                        Icon(Icons.arrow_forward_rounded, color: theme.accent),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Latest',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.onSurfaceMuted,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.updateInfo.latestVersion,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: theme.accent,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Release notes
                  Text(
                    'WHAT\'S NEW',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: theme.onSurfaceMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.background.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.onSurface.withValues(alpha: 0.1),
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        widget.updateInfo.releaseNotes,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.onSurface.withValues(alpha: 0.7),
                          height: 1.6,
                        ),
                      ),
                    ),
                  ),

                  if (widget.updateInfo.isMacOS || widget.updateInfo.isIOS) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange.shade300,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.updateInfo.isIOS
                                  ? 'iOS: You\'ll be redirected to GitHub to download the IPA'
                                  : 'macOS: You\'ll be redirected to GitHub to download',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade200,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (_isDownloading) ...[
                    const SizedBox(height: 20),
                    Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Downloading...',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: theme.accent,
                              ),
                            ),
                            Text(
                              '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: theme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _downloadProgress,
                            backgroundColor: theme.onSurface.withValues(
                              alpha: 0.1,
                            ),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              theme.accent,
                            ),
                            minHeight: 8,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Action buttons
            if (!_isDownloading)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: theme.onSurface.withValues(alpha: 0.2),
                            ),
                          ),
                        ),
                        child: Text(
                          'Later',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: theme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _handleUpdate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.accent,
                          foregroundColor: theme.background,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Update Now',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.download_rounded, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleUpdate() async {
    if (Platform.isAndroid) {
      await _downloadAndInstallAndroid();
    } else if (Platform.isWindows || Platform.isLinux) {
      await _downloadAndInstallDesktop();
    } else {
      // macOS / iOS - open browser
      await AppUpdaterService().openDownloadPage(widget.updateInfo.downloadUrl);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _downloadAndInstallAndroid() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      OtaUpdate()
          .execute(
            widget.updateInfo.downloadUrl,
            destinationFilename: 'WAVE_${widget.updateInfo.latestVersion}.apk',
          )
          .listen(
            (OtaEvent event) {
              if (mounted) {
                setState(() {
                  switch (event.status) {
                    case OtaStatus.DOWNLOADING:
                      final value = event.value;
                      if (value != null) {
                        _downloadProgress =
                            (double.tryParse(value) ?? 0.0) / 100.0;
                      }
                      break;
                    case OtaStatus.INSTALLING:
                      _downloadProgress = 1.0;
                      break;
                    case OtaStatus.ALREADY_RUNNING_ERROR:
                    case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                    case OtaStatus.INTERNAL_ERROR:
                    case OtaStatus.DOWNLOAD_ERROR:
                    case OtaStatus.CHECKSUM_ERROR:
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Update failed: ${event.status}'),
                        ),
                      );
                      Navigator.of(context).pop();
                      break;
                    default:
                      break;
                  }
                });
              }
            },
            onError: (error) {
              if (mounted) {
                setState(() => _isDownloading = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Download failed: $error')),
                );
              }
            },
          );
    } catch (e) {
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
  }

  Future<void> _downloadAndInstallDesktop() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      Directory? downloadsDir;
      try {
        downloadsDir = await getDownloadsDirectory();
      } catch (_) {
        downloadsDir = null;
      }
      final dir = downloadsDir ?? await getTemporaryDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final extension = Platform.isWindows ? '.exe' : '.AppImage';
      final fileName = 'WAVE-${widget.updateInfo.latestVersion}$extension';
      final filePath = path.join(dir.path, fileName);
      final file = File(filePath);

      final request = http.Request(
        'GET',
        Uri.parse(widget.updateInfo.downloadUrl),
      );
      final response = await request.send();

      final contentLength = response.contentLength ?? 0;
      int downloadedBytes = 0;
      int lastUpdateTime = DateTime.now().millisecondsSinceEpoch;

      final sink = file.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;

        final now = DateTime.now().millisecondsSinceEpoch;
        if (contentLength > 0 &&
            mounted &&
            (now - lastUpdateTime > 100 || downloadedBytes == contentLength)) {
          lastUpdateTime = now;
          final progress = downloadedBytes / contentLength;
          setState(() {
            _downloadProgress = progress;
          });
        }
      }

      await sink.close();

      if (mounted) {
        setState(() => _isDownloading = false);

        final theme = AppThemeScope.of(context);
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: theme.surface,
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 32),
                const SizedBox(width: 12),
                Text(
                  'Download Complete',
                  style: TextStyle(color: theme.onSurface),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Update downloaded to:',
                  style: TextStyle(
                    color: theme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.background.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    filePath,
                    style: TextStyle(
                      color: theme.accent,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  Platform.isWindows
                      ? 'Close WAVE and run the installer to update.'
                      : 'Make the file executable and run it:\nchmod +x "$fileName"\n./$fileName',
                  style: TextStyle(
                    color: theme.onSurface.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  if (Platform.isWindows) {
                    await Process.run('explorer', ['/select,', filePath]);
                  } else if (Platform.isLinux) {
                    await Process.run('xdg-open', [dir.path]);
                  }
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: Text(
                  'Open Folder',
                  style: TextStyle(color: theme.onSurface),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(backgroundColor: theme.accent),
                child: Text('OK', style: TextStyle(color: theme.background)),
              ),
            ],
          ),
        );

        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }
}
