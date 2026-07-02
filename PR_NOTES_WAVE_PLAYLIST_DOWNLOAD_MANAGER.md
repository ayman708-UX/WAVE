# Pull Request: Playlist / Download Manager, Global On-Device Status, and Downloads Export

## Summary

This PR improves WAVE's offline/download and playlist management workflow.

It adds a proper download/playlist management layer so downloaded songs are easier to organise, bulk add to playlists, remove from playlists, export for backup, and identify across the app.

## Main changes

### 1. Download / Playlist Manager

Added a management workflow in `Library > Downloads` with KPI cards:

- Downloaded
- Not in playlist
- In playlists
- Playlists

The KPI cards act as filters, making it easier to find downloaded tracks that still need to be organised.

### 2. Multi-select for downloads

Downloaded tracks can now be selected in bulk using:

- long press on mobile
- checkboxes
- select visible
- clear selection

Bulk actions include:

- add selected tracks to an existing playlist
- create a new playlist from selected tracks

### 3. Playlist management improvements

Inside playlists, users can now better manage tracks, including:

- adding downloaded tracks into a playlist
- removing tracks from a playlist
- keeping downloaded tracks separate from playlist membership

This makes playlists easier to maintain after songs have already been downloaded.

### 4. Global "On device" status

Downloaded tracks now carry an "On device" status across more of the app, instead of only showing in some places.

This applies across areas such as:

- search results
- home/content cards
- album track lists
- artist popular tracks
- playlist track lists
- now playing
- detail rows

The goal is that if a song is already downloaded, the app shows that status consistently wherever the song appears.

### 5. Smarter download behaviour

Download actions now avoid re-downloading songs that are already on the device.

For albums/playlists/artist popular tracks:

- if all tracks are already downloaded, the app shows that they are already on device
- if only some tracks are missing, only the missing tracks are queued for download

This prevents duplicate downloads and makes offline management clearer.

### 6. Restore cloud-check delete behaviour

The existing user behaviour is preserved:

- cloud download icon = download the song
- cloud check icon = remove/delete the downloaded song from device

This keeps the download toggle simple and predictable.

### 7. Android downloads backup export

On Android, WAVE stores playable offline songs in app-private storage.

Instead of showing the internal private path like:

```text
/data/user/0/com.example.wave/app_flutter/WAVE_Downloads
```

the app now explains that downloads are kept privately for playback and provides an export option.

Export backup copies song files to:

```text
Internal storage/Download/WAVE/wave_downloads
```

The export is a backup/copy. WAVE still plays from its private app folder.

### 8. Song-only backup export

The export backup now copies only song/audio files.

It skips:

- cover artwork
- `_cover` files
- `.jpg`
- `.jpeg`
- `.png`
- `.webp`
- `.gif`
- `wave_downloads_manifest.json`

This keeps the exported backup folder clean and focused on the actual songs.

### 9. Desktop behaviour preserved

On Windows/macOS/Linux, the app continues to show the normal local download folder and lets the user open it.

The Android-specific export messaging is only shown on Android.

## Files changed

```text
lib/core/storage/library_providers.dart
lib/features/library/library_screen.dart
lib/widgets/player/add_to_playlist_sheet.dart
lib/core/downloads/download_manager.dart
android/app/src/main/AndroidManifest.xml
lib/core/downloads/download_status.dart
lib/widgets/on_device_badge.dart
lib/widgets/content_cards.dart
lib/widgets/detail_track_row.dart
lib/features/album/album_screen.dart
lib/features/artist/artist_screen.dart
lib/features/playlist/playlist_screen.dart
lib/features/player/now_playing_screen.dart
```

## Manual testing checklist

Tested locally with the following flows:

- Open `Library > Downloads`
- KPI cards display correctly
- Filter by downloaded tracks
- Filter by tracks not in a playlist
- Multi-select downloaded tracks
- Add selected tracks to an existing playlist
- Create a new playlist from selected tracks
- Open a playlist and remove songs
- Open downloads and verify selected tracks can be managed
- Verify downloaded tracks show `On device` across multiple screens
- Verify already downloaded tracks are not re-downloaded
- Verify cloud-check removes/deletes the downloaded song from device
- Verify Android export backup copies song files only
- Verify desktop still shows the normal download folder

## Notes

This PR focuses on local/offline management and does not add cloud sync.

The Android export is intended as a backup/copy of downloaded audio files, not as the active playback location.
