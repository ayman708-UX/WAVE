import 'dart:io' show Platform;

bool get platformIsWeb => false;
bool get platformIsAndroid => Platform.isAndroid;
bool get platformIsIOS => Platform.isIOS;
bool get platformIsWindows => Platform.isWindows;
bool get platformIsLinux => Platform.isLinux;
bool get platformIsMacOS => Platform.isMacOS;
bool get platformIsDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;
