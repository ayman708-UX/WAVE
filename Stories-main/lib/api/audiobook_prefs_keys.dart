/// [SharedPreferences] keys for audiobook state (used by player + cloud settings sync).
abstract final class AudiobookPrefsKeys {
  static const String history = 'audiobook_history';
  static const String liked = 'audiobook_liked';
  /// Saved titles + optional chapter/position; synced with PlayTorrio cloud login.
  static const String bookmarks = 'audiobook_bookmarks';
  /// Milliseconds since epoch; local bookmark edits win cloud merge until remote is newer.
  static const String bookmarksUpdatedAt = 'audiobook_bookmarks_updated_at';
}
