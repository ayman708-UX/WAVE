# AudioAZ Scraper Tutorial

## Overview
AudioAZ uses a more complex backend. It streams audio natively through `archive.org` using an internal proxy API endpoint to hide the source.

## Search and Browse
*   **Search URL**: `https://audioaz.com/en/search?q={query}` (Note: MUST include `/en/`).
*   **Item Selector**: The search results often don't contain standard book links directly. Look for paths like `/en/audiobook/{slug}` or `/en/archive/archive-{slug}`.
*   **Cover**: Images contain alt text matching the book, often hosted on `f.audioaz.com`.

## Detail Page (Chapters)
1.  Fetch the detail page (`/en/audiobook/{slug}`).
2.  Look for `<audio><source src="{stream_url}"></audio>`.
3.  The `stream_url` is often an `archive.org` file or a proxied token link like `https://audioaz.com/api/stream?token=...`.
4.  AudioAZ typically streams full audiobooks as a single massive `.opus` or `.m4a` file. It does not consistently provide chapterized tracks in the HTML payload. You get a single "Full Audiobook" stream.
