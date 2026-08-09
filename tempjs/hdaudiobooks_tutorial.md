# HDAudiobooks Scraper Tutorial

## Overview
HDAudiobooks requires traversing pagination to find the actual audio files. The first page of a book detail often doesn't contain the audio directly.

## Search and Browse
*   **Search URL**: `https://hdaudiobooks.com/?s={query}`
*   **Item Selector**: `<h2 class="entry-title"><a href="{url}">{title}</a></h2>` (Found inside `<article>` tags).

## Detail Page (Chapters)
1.  Fetch the detail page URL.
2.  If audio tags aren't present, you must look for pagination links indicating parts: `href="https://hdaudiobooks.com/{slug}/2/"`.
3.  Fetch those paginated URLs.
4.  The actual audio files will be embedded on those sub-pages (sometimes requiring further extraction if embedded via players, though often standard MP3 links can be found).
