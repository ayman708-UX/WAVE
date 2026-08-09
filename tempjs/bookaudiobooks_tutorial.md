# BookAudiobooks Scraper Tutorial

## Overview
Another WordPress site using standard audio shortcodes.

## Search and Browse
*   **Search URL**: `https://bookaudiobooks.com/?s={query}`
*   **Item Selector**: `<h2 class="entry-title"><a href="{url}">{title}</a></h2>`

## Detail Page (Chapters)
1.  Fetch detail page.
2.  Extract MP3s via `<source src="{stream_url}">` tags inside `<audio class="wp-audio-shortcode">`.
3.  Audio typically hosted on `ipaudio6.com` or similar.
