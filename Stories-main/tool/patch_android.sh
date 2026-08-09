#!/usr/bin/env bash
# Apply Android manifest + MainActivity after `flutter create .`
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_MANIFEST="$ROOT/android/app/src/main/AndroidManifest.xml"
MAIN_ACTIVITY_PKG="com/playtorrio/audiobook/audiobook_app"
DEST_ACTIVITY="$ROOT/android/app/src/main/kotlin/$MAIN_ACTIVITY_PKG/MainActivity.kt"

if [[ ! -f "$DEST_MANIFEST" ]]; then
  echo "error: run flutter create first (missing $DEST_MANIFEST)" >&2
  exit 1
fi

SRC_MANIFEST="$ROOT/tool/android/AndroidManifest.xml"
if [[ -f "$SRC_MANIFEST" ]]; then
  cp "$SRC_MANIFEST" "$DEST_MANIFEST"
else
  cat > "$DEST_MANIFEST" <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29" />
    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <application
        android:label="Stories"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:appCategory="audio"
        android:usesCleartextTraffic="true"
        android:largeHeap="true">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme" />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>

        <service
            android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true"
            tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>

        <receiver
            android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true"
            tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>

        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />

        <meta-data
            android:name="com.google.android.gms.car.application"
            android:resource="@xml/automotive_app_desc" />
    </application>
</manifest>
EOF
fi

SRC_ACTIVITY="$ROOT/tool/android/MainActivity.kt"
if [[ -f "$SRC_ACTIVITY" ]]; then
  mkdir -p "$(dirname "$DEST_ACTIVITY")"
  cp "$SRC_ACTIVITY" "$DEST_ACTIVITY"
  echo "Patched MainActivity.kt (extends AudioServiceActivity)"
fi

SRC_AUTO_XML="$ROOT/tool/android/res/xml/automotive_app_desc.xml"
DEST_AUTO_XML="$ROOT/android/app/src/main/res/xml/automotive_app_desc.xml"
if [[ -f "$SRC_AUTO_XML" ]]; then
  mkdir -p "$(dirname "$DEST_AUTO_XML")"
  cp "$SRC_AUTO_XML" "$DEST_AUTO_XML"
  echo "Installed Android Auto automotive_app_desc.xml"
fi

SRC_FILE_PATHS="$ROOT/tool/android/res/xml/file_paths.xml"
DEST_FILE_PATHS="$ROOT/android/app/src/main/res/xml/file_paths.xml"
if [[ -f "$SRC_FILE_PATHS" ]]; then
  mkdir -p "$(dirname "$DEST_FILE_PATHS")"
  cp "$SRC_FILE_PATHS" "$DEST_FILE_PATHS"
  echo "Installed FileProvider file_paths.xml"
fi

SRC_DRAWABLE_DIR="$ROOT/tool/android/res/drawable"
DEST_DRAWABLE_DIR="$ROOT/android/app/src/main/res/drawable"
if [[ -d "$SRC_DRAWABLE_DIR" ]]; then
  mkdir -p "$DEST_DRAWABLE_DIR"
  cp -r "$SRC_DRAWABLE_DIR/." "$DEST_DRAWABLE_DIR/"
  echo "Installed notification drawable resources"
fi

SRC_RAW_DIR="$ROOT/tool/android/res/raw"
DEST_RAW_DIR="$ROOT/android/app/src/main/res/raw"
if [[ -d "$SRC_RAW_DIR" ]]; then
  mkdir -p "$DEST_RAW_DIR"
  cp -r "$SRC_RAW_DIR/." "$DEST_RAW_DIR/"
  echo "Installed notification keep.xml"
fi

bash "$ROOT/tool/configure_android_release_signing.sh"
bash "$ROOT/tool/configure_android_sdk_versions.sh"
bash "$ROOT/tool/configure_android_packaging.sh"
bash "$ROOT/tool/configure_android_notification_resources.sh"

echo "Patched AndroidManifest.xml for audiobook app"
