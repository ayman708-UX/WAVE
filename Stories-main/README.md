# Stories

**Stories** is a standalone Flutter audiobook player with a calm, book-first interface. Browse free audiobook catalogs, stream chapters over torrent when needed, pick up where you left off, and optionally sync your library across devices.

![Stories app icon](assets/icon/icon.png)

## What it does

Stories helps you find, listen to, and organize audiobooks without a subscription service. The home screen shows your catalog, **Continue listening**, **Liked** titles, and **Bookmarks**. Open any book to get chapter controls, playback speed, downloads, and a full-screen player with lock-screen notification support on Android.

### Browse & search

- **Audiobook Bay** — catalog and search via client-side scrape (`audiobookbay.lu`)
- Additional sources (Tokybook, Audiozaic, and others) where configured
- Search merges results and deduplicates by title

### Listen

- Stream chapters directly or via **magnet / torrent** (Android & desktop; not available on web)
- Continue listening remembers chapter and position per title
- Playback speed, autoplay next chapter, skip forward/back
- Lock-screen and notification controls on Android (after `tool/patch_android.sh`)
- **Android Auto** — playback controls and continue listening in the car (media app)

### Your library

- **Liked** — favorite titles in one shelf
- **Bookmarks** — save a place in a book (long-press to remove)
- **Continue listening** — recent progress on the browse screen
- **Offline downloads** — save chapters or full books locally
- **Magnet import** — add a torrent by magnet link
- **Generate** — turn an EPUB into a spoken audiobook (where supported)

### Account & sync (optional)

Sign in under **Settings** with email and password to sync bookmarks, favorites, and listening progress across phones and tablets. Cloud sync uses the same Supabase backend as [PlayTorrio](https://github.com/killamfkr/PlayTorrioV2) by default; you can point it at your own project at build time.

Pick a **literary character avatar** (original cartoon designs inspired by classic book heroes) for your profile.

---

## Get started

### Requirements

- [Flutter](https://flutter.dev) 3.41+
- Android SDK (for Android builds)
- Git

This repo ships **source only** — `android/` and `ios/` are generated locally to keep the repository small.

### Run on your machine

```bash
git clone https://github.com/killamfkr/Stories.git
cd Stories

flutter create . --project-name audiobook_app --org com.playtorrio.audiobook
bash tool/patch_android.sh

flutter pub get
dart run flutter_launcher_icons
flutter run
```

`tool/patch_android.sh` configures Android for background audio, notifications, and Android Auto.

### Cloud sync build flags (optional)

Override the default Supabase project when running locally:

```bash
flutter run \
  --dart-define=PLAYTORRIO_SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=PLAYTORRIO_SUPABASE_ANON_KEY=your_anon_jwt
```

---

## Project structure

| Path | Purpose |
|------|---------|
| `lib/screens/` | Library, player, settings, downloads, magnet picker |
| `lib/api/` | Catalog scraping, playback, torrent engine, downloads |
| `lib/services/` | Cloud account sync |
| `lib/widgets/` | UI components (covers, avatars, TV focus) |
| `tool/patch_android.sh` | Android AudioService, notifications, Android Auto |
| `assets/icon/` | App icon |

---

## License

GPL-2.0 — see [LICENSE](LICENSE).

---

## Credits

**Stories** was extracted and developed as a standalone app from the audiobook module in **[PlayTorrioV2](https://github.com/killamfkr/PlayTorrioV2)** (`standalone_audiobook_app/`), created by **[killamfkr](https://github.com/killamfkr)**.

Torrent streaming builds on **[libtorrent_flutter](https://github.com/ayman708-UX/libtorrent_flutter)** by ayman708-UX.

Parts of the design, playback fixes, cloud login, settings screen, and publishing workflow were implemented with assistance from **[Cursor](https://cursor.com) AI** (Cloud Agent).

If you use Stories, a link back to this repo or PlayTorrioV2 is appreciated but not required.
