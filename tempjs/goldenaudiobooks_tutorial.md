# GoldenAudiobooks Scraper Tutorial

## Overview
GoldenAudiobooks uses a WordPress backend with the `ilovewp-post` class for items and standard HTML5 `<audio>` players.

## Search and Browse
*   **Search URL**: `https://goldenaudiobooks.com/?s={query}`
*   **Item Selector**: `<h2 class="title-post"><a href="{url}">{title}</a></h2>`
*   **Cover Image**: `<div class="post-cover"><img data-src="{url}" src="{fallback_url}"></div>`

## Detail Page (Chapters)
1.  Fetch the detail page URL.
2.  Look for `<audio>` tags (specifically with class `wp-audio-shortcode`).
3.  Inside each `<audio>`, there will be a `<source src="{stream_url}">`.
4.  Alternatively, you can regex match `https?:\/\/[^\s"'<>]+\.mp3` directly from the HTML source.
5.  Each MP3 URL corresponds to a chapter.

## Implementation Details
*   The MP3s are typically hosted on external domains like `ipaudio.club`.
*   Direct HTTP GET requests work fine for extracting this data.
