import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps Stories alive in the background: battery exemption + unrestricted data.
class AndroidBackgroundPolicyService {
  AndroidBackgroundPolicyService._();
  static final AndroidBackgroundPolicyService instance =
      AndroidBackgroundPolicyService._();

  static const _dataPromptKey = 'stories_data_policy_prompted';

  bool get supported => !kIsWeb && Platform.isAndroid;

  Future<bool> isBatteryUnrestricted() async {
    if (!supported) return true;
    return Permission.ignoreBatteryOptimizations.isGranted;
  }

  Future<bool> requestBatteryUnrestricted() async {
    if (!supported) return true;
    final status = await Permission.ignoreBatteryOptimizations.request();
    return status.isGranted;
  }

  Future<void> openBatterySettings() async {
    if (!supported) return;
    await openAppSettings();
  }

  Future<void> openUnrestrictedDataSettings() async {
    if (!supported) return;
    final packageName = (await PackageInfo.fromPlatform()).packageName;
    final pkgUri = 'package:$packageName';

    for (final action in const [
      'android.settings.IGNORE_BACKGROUND_DATA_RESTRICTIONS_SETTINGS',
      'android.settings.APP_DATA_USAGE',
      'android.settings.APPLICATION_DETAILS_SETTINGS',
    ]) {
      try {
        await AndroidIntent(
          action: action,
          data: pkgUri,
          flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
        ).launch();
        return;
      } catch (e) {
        debugPrint('[Stories Background] intent $action failed: $e');
      }
    }
  }

  /// Ask Android to exempt Stories from battery optimization (Doze).
  Future<void> ensureBatteryOnStartup() async {
    if (!supported) return;
    if (!await isBatteryUnrestricted()) {
      await requestBatteryUnrestricted();
    }
  }

  Future<bool> shouldShowDataReminder() async {
    if (!supported) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_dataPromptKey) != true;
  }

  Future<void> markDataReminderShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dataPromptKey, true);
  }
}
