# Add download manager, playlist bulk actions, and on-device status

## Summary

This PR is separated from playback/resolver changes and focuses only on library, download, and playlist management.

It adds a cleaner local music management workflow for downloaded songs, including KPI cards, bulk playlist actions, global on-device status, and song-only Android export backup.

## What changed

### Download manager KPI cards

Adds KPI cards in `Library > Downloads`:

- Downloaded
- Not in playlist
- In playlists
- Playlists

These cards also work as filters so users can quickly find downloaded songs that still need to be organised.

### Multi-select downloaded songs

Downloaded songs can now be selected in bulk using long press or checkboxes.

Bulk actions include:

- Add selected songs to an existing playlist
- Create a new playlist from selected songs
- Select visible songs
- Clear selection

### Playlist management

Improves playlist management so users can:

- Add downloaded songs into playlists
- Remove songs from playlists
- Manage songs from inside the playlist screen
- Keep downloaded songs separate from playlist membership

### Global On device status

Downloaded songs now show `On device` consistently across more of the app, including:

- Search/content cards
- Album track lists
- Artist popular tracks
- Playlist track lists
- Now Playing
- Track detail rows

### Smarter download actions

Download actions avoid re-downloading songs already on the device.

For albums, playlists, and artist popular tracks:

- If everything is already downloaded, the app shows it is already on device
- If only some songs are missing, only the missing songs are queued

### Restore cloud-check delete behaviour

The existing cloud button behaviour is preserved:

- Cloud download icon = download song
- Cloud check icon = remove/delete song from device

### Android song-only export backup

On Android, downloaded songs are kept in app-private storage for playback.

This PR adds a user-friendly export option that copies song files to:

```text
Internal storage/Download/WAVE/wave_downloads
```

The export is a backup/copy only. WAVE still plays from the private app folder.

The export copies audio/song files only and skips:

- Cover artwork
- `_cover` files
- `.jpg`
- `.jpeg`
- `.png`
- `.webp`
- `.gif`
- `wave_downloads_manifest.json`

### Desktop behaviour preserved

Windows/macOS/Linux still show the normal local download folder and allow the user to open it.

The Android export message only appears on Android.

## Scope control

This PR intentionally excludes playback resolver changes, YouTube extraction changes, audio proxy changes, lyrics changes, theme changes, pubspec changes, and unrelated UI changes.

## Testing

Tested locally:

- Opened `Library > Downloads`
- Verified KPI cards display correctly
- Filtered downloaded songs
- Filtered songs not in playlists
- Selected multiple downloaded songs
- Added selected songs to an existing playlist
- Created a new playlist from selected songs
- Removed songs from playlists
- Verified `On device` appears across multiple screens
- Verified already-downloaded songs are not downloaded again
- Verified cloud-check removes the song from device
- Verified Android export backup copies songs only
- Verified desktop still shows the normal download folder
