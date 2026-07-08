import 'dart:io';
import 'dart:ffi' show Abi;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdaterService {
  static const String githubRepo = 'ayman708-UX/WAVE';
  static const String githubApiUrl =
      'https://api.github.com/repos/$githubRepo/releases/latest';

  Future<UpdateInfo?> checkForUpdates() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http.get(Uri.parse(githubApiUrl));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final latestVersion = (data['tag_name'] as String).replaceFirst(
          'v',
          '',
        );
        final releaseNotes =
            data['body'] as String? ?? 'No release notes available';
        final publishedAt = DateTime.parse(data['published_at']);

        if (_isNewerVersion(currentVersion, latestVersion)) {
          final assets = data['assets'] as List;
          final downloadUrl = _findAssetForPlatform(assets);

          return UpdateInfo(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            downloadUrl: downloadUrl ?? data['html_url'],
            releaseNotes: releaseNotes,
            publishedAt: publishedAt,
            isMacOS: Platform.isMacOS,
            isIOS: Platform.isIOS,
          );
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error checking for updates: $e');
      return null;
    }
  }

  /// Detects the current CPU architecture and finds the matching release asset.
  String? _findAssetForPlatform(List assets) {
    final abi = Abi.current();
    debugPrint('Detected ABI: $abi');

    if (Platform.isAndroid) {
      return _findAndroidAsset(assets, abi);
    } else if (Platform.isWindows) {
      return _findWindowsAsset(assets, abi);
    } else if (Platform.isLinux) {
      return _findLinuxAsset(assets, abi);
    }
    // macOS / iOS — we just open the releases page, no direct download
    return null;
  }

  /// Android: match arm64-v8a, armeabi-v7a, x86_64, or fall back to universal
  String? _findAndroidAsset(List assets, Abi abi) {
    final apks = assets
        .where((a) => (a['name'] as String).toLowerCase().endsWith('.apk'))
        .toList();

    if (apks.isEmpty) return null;

    // Determine architecture keywords to search for
    List<String> archKeywords;
    switch (abi) {
      case Abi.androidArm64:
        archKeywords = ['arm64-v8a', 'arm64', 'v8a', 'aarch64'];
        break;
      case Abi.androidArm:
        archKeywords = ['armeabi-v7a', 'armeabi', 'v7a', 'armv7'];
        break;
      case Abi.androidX64:
        archKeywords = ['x86_64', 'x86-64', 'x64'];
        break;
      default:
        archKeywords = [];
    }

    // Try to find an APK matching our architecture
    for (final keyword in archKeywords) {
      final match = apks
          .where((a) => (a['name'] as String).toLowerCase().contains(keyword))
          .firstOrNull;
      if (match != null) {
        debugPrint('Matched APK for $abi: ${match['name']}');
        return match['browser_download_url'];
      }
    }

    // Fall back to a "universal" APK if available
    final universal = apks
        .where((a) => (a['name'] as String).toLowerCase().contains('universal'))
        .firstOrNull;
    if (universal != null) {
      debugPrint('Falling back to universal APK: ${universal['name']}');
      return universal['browser_download_url'];
    }

    // Last resort: if there's only one APK, it's probably universal/fat
    if (apks.length == 1) {
      debugPrint('Only one APK found, using it: ${apks.first['name']}');
      return apks.first['browser_download_url'];
    }

    debugPrint(
      'No matching APK found for $abi among ${apks.map((a) => a['name']).toList()}',
    );
    return null;
  }

  /// Windows: match x64 or arm64 installer
  String? _findWindowsAsset(List assets, Abi abi) {
    final windowsAssets = assets.where((a) {
      final name = (a['name'] as String).toLowerCase();
      return name.contains('windows') &&
          (name.endsWith('.exe') || name.endsWith('.msix'));
    }).toList();

    if (windowsAssets.isEmpty) return null;

    // If only one Windows asset, use it
    if (windowsAssets.length == 1) {
      return windowsAssets.first['browser_download_url'];
    }

    // Multiple Windows assets — pick by architecture
    List<String> archKeywords;
    if (abi == Abi.windowsArm64) {
      archKeywords = ['arm64', 'aarch64'];
    } else {
      archKeywords = ['x64', 'x86_64', 'amd64'];
    }

    for (final keyword in archKeywords) {
      final match = windowsAssets
          .where((a) => (a['name'] as String).toLowerCase().contains(keyword))
          .firstOrNull;
      if (match != null) return match['browser_download_url'];
    }

    // Fallback to first Windows asset
    return windowsAssets.first['browser_download_url'];
  }

  /// Linux: match x64 or arm64 AppImage/deb
  String? _findLinuxAsset(List assets, Abi abi) {
    final linuxAssets = assets.where((a) {
      final name = (a['name'] as String).toLowerCase();
      return name.contains('linux') &&
          (name.endsWith('.appimage') ||
              name.endsWith('.deb') ||
              name.endsWith('.tar.gz'));
    }).toList();

    if (linuxAssets.isEmpty) return null;

    // If only one Linux asset, use it
    if (linuxAssets.length == 1) {
      return linuxAssets.first['browser_download_url'];
    }

    // Multiple Linux assets — pick by architecture
    List<String> archKeywords;
    if (abi == Abi.linuxArm64) {
      archKeywords = ['arm64', 'aarch64'];
    } else {
      archKeywords = ['x86_64', 'x64', 'amd64'];
    }

    for (final keyword in archKeywords) {
      final match = linuxAssets
          .where((a) => (a['name'] as String).toLowerCase().contains(keyword))
          .firstOrNull;
      if (match != null) return match['browser_download_url'];
    }

    // Fallback to first Linux asset
    return linuxAssets.first['browser_download_url'];
  }

  bool _isNewerVersion(String current, String latest) {
    // Strip any suffix like "-test" or "-beta" for comparison
    final currentClean = current.split('-').first;
    final latestClean = latest.split('-').first;

    final currentParts = currentClean
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final latestParts = latestClean
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();

    for (int i = 0; i < 3; i++) {
      final currentPart = i < currentParts.length ? currentParts[i] : 0;
      final latestPart = i < latestParts.length ? latestParts[i] : 0;

      if (latestPart > currentPart) return true;
      if (latestPart < currentPart) return false;
    }
    return false;
  }

  Future<void> openDownloadPage(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final String releaseNotes;
  final DateTime publishedAt;
  final bool isMacOS;
  final bool isIOS;

  UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
    required this.isMacOS,
    this.isIOS = false,
  });
}
