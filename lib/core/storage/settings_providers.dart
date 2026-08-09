import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'hive_boxes.dart';

enum AudioQuality { youtube, lossless }

enum AppLanguage { english, french, spanish, german, japanese }

class AppSettings {
  const AppSettings({
    this.audioQuality = AudioQuality.youtube,
    this.crossfadeSeconds = 0,
    this.equalizerBandsDb = const <double>[0, 0, 0, 0, 0],
    this.downloadOnWifiOnly = true,
    this.language = AppLanguage.english,
    this.notifyNewReleases = true,
    this.notifyRecommendations = true,
    this.notifyPlaybackErrors = true,
  });

  final AudioQuality audioQuality;
  final int crossfadeSeconds;
  final List<double> equalizerBandsDb;
  final bool downloadOnWifiOnly;
  final AppLanguage language;
  final bool notifyNewReleases;
  final bool notifyRecommendations;
  final bool notifyPlaybackErrors;

  AppSettings copyWith({
    AudioQuality? audioQuality,
    int? crossfadeSeconds,
    List<double>? equalizerBandsDb,
    bool? downloadOnWifiOnly,
    AppLanguage? language,
    bool? notifyNewReleases,
    bool? notifyRecommendations,
    bool? notifyPlaybackErrors,
  }) {
    return AppSettings(
      audioQuality: audioQuality ?? this.audioQuality,
      crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
      equalizerBandsDb: equalizerBandsDb ?? this.equalizerBandsDb,
      downloadOnWifiOnly: downloadOnWifiOnly ?? this.downloadOnWifiOnly,
      language: language ?? this.language,
      notifyNewReleases: notifyNewReleases ?? this.notifyNewReleases,
      notifyRecommendations:
          notifyRecommendations ?? this.notifyRecommendations,
      notifyPlaybackErrors: notifyPlaybackErrors ?? this.notifyPlaybackErrors,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'audioQuality': audioQuality.name,
    'crossfadeSeconds': crossfadeSeconds,
    'equalizerBandsDb': equalizerBandsDb,
    'downloadOnWifiOnly': downloadOnWifiOnly,
    'language': language.name,
    'notifyNewReleases': notifyNewReleases,
    'notifyRecommendations': notifyRecommendations,
    'notifyPlaybackErrors': notifyPlaybackErrors,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    AudioQuality quality(String? n) {
      if (n == 'lossless') return AudioQuality.lossless;
      return AudioQuality.youtube;
    }
    AppLanguage lang(String? n) => AppLanguage.values.firstWhere(
      (e) => e.name == n,
      orElse: () => AppLanguage.english,
    );
    final bandsRaw = json['equalizerBandsDb'];
    final bands = bandsRaw is List
        ? bandsRaw
              .whereType<num>()
              .map((n) => n.toDouble())
              .toList(growable: false)
        : const <double>[0, 0, 0, 0, 0];
    return AppSettings(
      audioQuality: quality(json['audioQuality'] as String?),
      crossfadeSeconds: (json['crossfadeSeconds'] as num?)?.toInt() ?? 0,
      equalizerBandsDb: bands.length == 5
          ? bands
          : const <double>[0, 0, 0, 0, 0],
      downloadOnWifiOnly: json['downloadOnWifiOnly'] as bool? ?? true,
      language: lang(json['language'] as String?),
      notifyNewReleases: json['notifyNewReleases'] as bool? ?? true,
      notifyRecommendations: json['notifyRecommendations'] as bool? ?? true,
      notifyPlaybackErrors: json['notifyPlaybackErrors'] as bool? ?? true,
    );
  }
}

const String _kSettingsKey = 'app_settings';

class AppSettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final box = Hive.box<dynamic>(HiveBoxes.settings);
    final raw = box.get(_kSettingsKey);
    if (raw is String && raw.isNotEmpty) {
      try {
        final json = jsonDecode(raw);
        if (json is Map<String, dynamic>) return AppSettings.fromJson(json);
      } catch (_) {}
    }
    if (raw is Map) return AppSettings.fromJson(raw.cast<String, dynamic>());
    return const AppSettings();
  }

  Future<void> _persist() async {
    await Hive.box<dynamic>(
      HiveBoxes.settings,
    ).put(_kSettingsKey, jsonEncode(state.toJson()));
  }

  Future<void> setAudioQuality(AudioQuality q) async {
    state = state.copyWith(audioQuality: q);
    await _persist();
  }

  Future<void> setCrossfadeSeconds(int s) async {
    state = state.copyWith(crossfadeSeconds: s.clamp(0, 12));
    await _persist();
  }

  Future<void> setEqualizerBand(int index, double db) async {
    final next = <double>[...state.equalizerBandsDb];
    if (index < 0 || index >= next.length) return;
    next[index] = db.clamp(-12.0, 12.0);
    state = state.copyWith(equalizerBandsDb: next);
    await _persist();
  }

  Future<void> resetEqualizer() async {
    state = state.copyWith(equalizerBandsDb: const <double>[0, 0, 0, 0, 0]);
    await _persist();
  }

  Future<void> setDownloadOnWifiOnly(bool v) async {
    state = state.copyWith(downloadOnWifiOnly: v);
    await _persist();
  }

  Future<void> setLanguage(AppLanguage l) async {
    state = state.copyWith(language: l);
    await _persist();
  }

  Future<void> setNotifyNewReleases(bool v) async {
    state = state.copyWith(notifyNewReleases: v);
    await _persist();
  }

  Future<void> setNotifyRecommendations(bool v) async {
    state = state.copyWith(notifyRecommendations: v);
    await _persist();
  }

  Future<void> setNotifyPlaybackErrors(bool v) async {
    state = state.copyWith(notifyPlaybackErrors: v);
    await _persist();
  }
}

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);
