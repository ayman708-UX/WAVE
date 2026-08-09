# FullLengthAudiobooks Scraper Tutorial

## Overview
Very similar architecture to GoldenAudiobooks. It uses standard WordPress layouts.

## Search and Browse
*   **Search URL**: `https://fulllengthaudiobooks.com/?s={query}`
*   **Item Selector**: Look for `<article>` tags or `<h2 class="entry-title"><a href="{url}">{title}</a></h2>`.
*   **Cover Image**: Can be extracted from the article's featured image `<img>` tags.

## Detail Page (Chapters)
1.  Fetch the detail page.
2.  Look for `<audio>` tags (specifically with class `wp-audio-shortcode`).
3.  Inside, find `<source src="{stream_url}">`.
4.  Direct MP3 regex `https?:\/\/[^\s"'<>]+\.mp3` also works perfectly.
5.  Usually hosted on domains like `ipaudio.club`.
