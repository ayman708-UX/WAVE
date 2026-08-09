# HotAudiobooks Scraper Tutorial

## Overview
Standard WordPress site, very similar to GoldenAudiobooks and FullLengthAudiobooks.

## Search and Browse
*   **Search URL**: `https://hotaudiobooks.com/?s={query}`
*   **Item Selector**: `<article>` tags contain the `<h2><a href="{url}">{title}</a></h2>` headers for each book.

## Detail Page (Chapters)
1.  Fetch the detail page.
2.  Search the HTML for `<audio>` and `<source src="{stream_url}">`.
3.  MP3 links are directly embedded and easily extractable via regex (`https?:\/\/[^\s"'<>]+\.mp3`).
4.  Audio typically hosted on `ipaudio.club` or similar CDNs.
