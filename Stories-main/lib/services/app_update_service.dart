import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Checks GitHub Releases for a newer Stories APK and installs it on Android.
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  static const repoOwner = 'killamfkr';
  static const repoName = 'Stories';

  Future<PackageInfo> currentPackageInfo() => PackageInfo.fromPlatform();

  Future<AppUpdateOffer?> checkForUpdate() async {
    if (kIsWeb || !Platform.isAndroid) return null;

    final pkg = await currentPackageInfo();
    final current = AppVersion.parse(
      '${pkg.version}+${pkg.buildNumber}',
    );
    if (current == null) return null;

    final release = await _fetchNewestRelease();
    if (release == null) return null;

    final remote = AppVersion.parse(release.tagName);
    if (remote == null) {
      debugPrint('[Stories Update] could not parse tag ${release.tagName}');
      return null;
    }

    debugPrint(
      '[Stories Update] current=${current.label} remote=${remote.label} '
      'tag=${release.tagName}',
    );

    if (!remote.isNewerThan(current)) return null;

    final apkUrl = _apkAssetUrl(release);
    if (apkUrl == null) return null;

    return AppUpdateOffer(
      current: current,
      remote: remote,
      tagName: release.tagName,
      apkUrl: apkUrl,
      releaseNotes: release.body?.trim() ?? '',
    );
  }

  Future<String> downloadApk(
    AppUpdateOffer offer, {
    void Function(double progress)? onProgress,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(offer.apkUrl));
      final response = await client.send(request);
      if (response.statusCode != 200) {
        throw Exception('Download failed (${response.statusCode})');
      }

      final total = response.contentLength ?? 0;
      final dir = await getTemporaryDirectory();
      final safeTag = offer.tagName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final file = File('${dir.path}/stories-update-$safeTag.apk');

      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      }
      await sink.close();
      return file.path;
    } finally {
      client.close();
    }
  }

  Future<OpenResult> installApk(String path) {
    return OpenFilex.open(
      path,
      type: 'application/vnd.android.package-archive',
    );
  }

  /// GitHub returns releases by publish time, not version — scan for the highest.
  Future<_GhRelease?> _fetchNewestRelease() async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$repoOwner/$repoName/releases?per_page=30',
    );
    final res = await http.get(
      uri,
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Stories-Android-Updater',
      },
    ).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      debugPrint('[Stories Update] releases ${res.statusCode}');
      return null;
    }

    final decoded = json.decode(res.body);
    if (decoded is! List) return null;

    _GhRelease? bestRelease;
    AppVersion? bestVersion;

    for (final raw in decoded) {
      if (raw is! Map) continue;
      if (raw['draft'] == true) continue;

      final release = _GhRelease.fromJson(raw.map((k, v) => MapEntry('$k', v)));
      final version = AppVersion.parse(release.tagName);
      if (version == null) continue;
      if (_apkAssetUrl(release) == null) continue;

      if (bestVersion == null || version.isNewerThan(bestVersion)) {
        bestVersion = version;
        bestRelease = release;
      }
    }

    return bestRelease;
  }

  String? _apkAssetUrl(_GhRelease release) {
    for (final asset in release.assets) {
      final name = asset.name.toLowerCase();
      if (name.endsWith('.apk')) return asset.browserDownloadUrl;
    }
    return null;
  }
}

class AppUpdateOffer {
  const AppUpdateOffer({
    required this.current,
    required this.remote,
    required this.tagName,
    required this.apkUrl,
    required this.releaseNotes,
  });

  final AppVersion current;
  final AppVersion remote;
  final String tagName;
  final String apkUrl;
  final String releaseNotes;

  String get versionLabel => remote.label;

  int get remoteBuild => remote.build;
}

class AppVersion {
  const AppVersion({
    required this.major,
    required this.minor,
    required this.patch,
    required this.build,
  });

  final int major;
  final int minor;
  final int patch;
  final int build;

  String get label =>
      build > 0 ? '$major.$minor.$patch ($build)' : '$major.$minor.$patch';

  static AppVersion? parse(String raw) {
    final cleaned = raw.trim().replaceFirst(RegExp(r'^v'), '');
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:[.+_-](\d+))?$',
    ).firstMatch(cleaned);
    if (match == null) return null;
    return AppVersion(
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2)!),
      patch: int.parse(match.group(3)!),
      build: int.tryParse(match.group(4) ?? '') ?? 0,
    );
  }

  bool isNewerThan(AppVersion other) {
    final a = [major, minor, patch, build];
    final b = [other.major, other.minor, other.patch, other.build];
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }
}

class _GhRelease {
  _GhRelease({
    required this.tagName,
    required this.body,
    required this.assets,
  });

  final String tagName;
  final String? body;
  final List<_GhAsset> assets;

  factory _GhRelease.fromJson(Map<String, dynamic> json) {
    final assetsRaw = json['assets'];
    final assets = <_GhAsset>[];
    if (assetsRaw is List) {
      for (final a in assetsRaw) {
        if (a is Map) {
          assets.add(_GhAsset.fromJson(a.map((k, v) => MapEntry('$k', v))));
        }
      }
    }
    return _GhRelease(
      tagName: '${json['tag_name'] ?? ''}',
      body: json['body'] as String?,
      assets: assets,
    );
  }
}

class _GhAsset {
  _GhAsset({required this.name, required this.browserDownloadUrl});

  final String name;
  final String browserDownloadUrl;

  factory _GhAsset.fromJson(Map<String, dynamic> json) {
    return _GhAsset(
      name: '${json['name'] ?? ''}',
      browserDownloadUrl: '${json['browser_download_url'] ?? ''}',
    );
  }
}
