#!/usr/bin/env bash
# Patch audio_service for Android Auto browse reliability.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

CACHE_ROOT="${PUB_CACHE:-$HOME/.pub-cache}"
DART_FILE="$(find "$CACHE_ROOT/hosted/pub.dev" -path '*/audio_service-*/lib/audio_service.dart' 2>/dev/null | sort -V | tail -1)"
JAVA_FILE="$(find "$CACHE_ROOT/hosted/pub.dev" -path '*/audio_service-*/android/src/main/java/com/ryanheise/audioservice/AudioServicePlugin.java' 2>/dev/null | sort -V | tail -1)"

if [[ -z "$DART_FILE" || ! -f "$DART_FILE" ]]; then
  echo "error: audio_service dart sources not found in pub cache (run flutter pub get)" >&2
  exit 1
fi
if [[ -z "$JAVA_FILE" || ! -f "$JAVA_FILE" ]]; then
  echo "error: audio_service java sources not found in pub cache" >&2
  exit 1
fi

python3 - "$DART_FILE" "$JAVA_FILE" <<'PY'
import pathlib
import re
import sys

dart_path, java_path = map(pathlib.Path, sys.argv[1:3])
dart = dart_path.read_text()
java = java_path.read_text()

# Fix handler registration race: setHandler before configure().
old = """    final callbacks = _HandlerCallbacks();
    _platform.setHandlerCallbacks(callbacks);
    await _platform.configure(ConfigureRequest(config: config._toMessage()));
    _config = config;
    final handler = builder();
    _handler = handler;
    callbacks.setHandler(handler);"""

new = """    final callbacks = _HandlerCallbacks();
    _platform.setHandlerCallbacks(callbacks);
    _config = config;
    final handler = builder();
    _handler = handler;
    callbacks.setHandler(handler);
    await _platform.configure(ConfigureRequest(config: config._toMessage()));"""

if old not in dart:
    if new in dart:
        print("audio_service.dart init order already patched")
    else:
        raise SystemExit("audio_service.dart: expected init block not found")
else:
    dart_path.write_text(dart.replace(old, new, 1))
    print("Patched audio_service.dart init order")

marker = "STORIES_ANDROID_AUTO_FALLBACK"
context_resolver = """            Context storiesCtx = AudioService.instance != null
                    ? AudioService.instance.getApplicationContext()
                    : null;"""

old_load_bad = """            if (!flutterReady || audioHandlerInterface == null) {
                result.sendResult(storiesBrowseFallback(applicationContext, parentMediaId));
                return;
            }"""

new_load_fixed = context_resolver + """
            if (!flutterReady || audioHandlerInterface == null) {
                result.sendResult(storiesCtx != null
                        ? storiesBrowseFallback(storiesCtx, parentMediaId)
                        : new ArrayList<>());
                return;
            }"""

if old_load_bad in java:
    java = java.replace(old_load_bad, new_load_fixed, 1)
    java_path.write_text(java)
    print("Fixed AudioServicePlugin.java fallback context reference")
elif marker in java:
    print("AudioServicePlugin.java already patched")
else:
    helper = r'''
    // STORIES_ANDROID_AUTO_FALLBACK
    private static List<MediaBrowserCompat.MediaItem> storiesBrowseFallback(Context context, String parentMediaId) {
        List<MediaBrowserCompat.MediaItem> items = new ArrayList<>();
        try {
            SharedPreferences prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
            String raw = prefs.getString("flutter.stories_aa_browse_v1", null);
            if (raw != null && !raw.isEmpty()) {
                JSONObject tree = new JSONObject(raw);
                String bucket;
                if ("root".equals(parentMediaId)) bucket = "root";
                else if ("recent".equals(parentMediaId)) bucket = "recent";
                else if ("stories_continue".equals(parentMediaId)) bucket = "continue";
                else bucket = null;
                if (bucket != null && tree.has(bucket)) {
                    JSONArray arr = tree.getJSONArray(bucket);
                    for (int i = 0; i < arr.length(); i++) {
                        JSONObject obj = arr.getJSONObject(i);
                        String id = obj.optString("id", "");
                        String title = obj.optString("title", "Stories");
                        String album = obj.optString("album", "Stories");
                        boolean playable = obj.optBoolean("playable", false);
                        MediaDescriptionCompat desc = new MediaDescriptionCompat.Builder()
                                .setMediaId(id)
                                .setTitle(title)
                                .setSubtitle(album)
                                .build();
                        int flags = playable
                                ? MediaBrowserCompat.MediaItem.FLAG_PLAYABLE
                                : MediaBrowserCompat.MediaItem.FLAG_BROWSABLE;
                        items.add(new MediaBrowserCompat.MediaItem(desc, flags));
                    }
                    if (!items.isEmpty()) return items;
                }
            }
        } catch (Exception e) {
            System.out.println("storiesBrowseFallback: " + e.getMessage());
        }
        if ("root".equals(parentMediaId) || "recent".equals(parentMediaId)) {
            MediaDescriptionCompat desc = new MediaDescriptionCompat.Builder()
                    .setMediaId("stories_continue")
                    .setTitle("Continue listening")
                    .setSubtitle("Stories")
                    .build();
            items.add(new MediaBrowserCompat.MediaItem(desc, MediaBrowserCompat.MediaItem.FLAG_BROWSABLE));
        }
        return items;
    }
'''
    import_block = "import android.content.SharedPreferences;\nimport org.json.JSONArray;\nimport org.json.JSONObject;\n"
    if "import android.content.SharedPreferences;" not in java:
        java = java.replace("import android.content.Context;\n", "import android.content.Context;\n" + import_block)

    anchor = "        public void invokePendingMethods() {"
    if anchor not in java:
        raise SystemExit("AudioServicePlugin.java: invokePendingMethods anchor missing")
    java = java.replace(anchor, helper + "\n        " + anchor, 1)

    old_load = """        @Override
        public void onLoadChildren(final String parentMediaId, final MediaBrowserServiceCompat.Result<List<MediaBrowserCompat.MediaItem>> result, Bundle options) {
            if (audioHandlerInterface != null) {"""
    new_load = """        @Override
        public void onLoadChildren(final String parentMediaId, final MediaBrowserServiceCompat.Result<List<MediaBrowserCompat.MediaItem>> result, Bundle options) {
""" + context_resolver + """
            if (!flutterReady || audioHandlerInterface == null) {
                result.sendResult(storiesCtx != null
                        ? storiesBrowseFallback(storiesCtx, parentMediaId)
                        : new ArrayList<>());
                return;
            }
            if (audioHandlerInterface != null) {"""
    if old_load not in java:
        raise SystemExit("AudioServicePlugin.java: onLoadChildren block not found")
    java = java.replace(old_load, new_load, 1)
    java_path.write_text(java)
    print("Patched AudioServicePlugin.java Android Auto fallback")
PY

echo "audio_service patch complete"
