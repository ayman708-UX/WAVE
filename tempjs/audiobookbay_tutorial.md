# AudiobookBay Scraper Tutorial

## Overview
AudiobookBay distributes audiobooks via BitTorrent/Magnet links. It requires scraping HTML to extract Info Hashes and Trackers, then reconstructing the magnet URI. Streaming is achieved via a BitTorrent engine (e.g., `libtorrent_flutter`).

## Search and Browse
*   **Search URL**: `https://audiobookbay.lu/?s={query}`
*   **Item Selector**: Look for `<div class="post">`.
*   **Title/URL**: `<div class="postTitle"><h2><a href="{url}">{title}</a></h2></div>`
*   **Cover**: `<div class="postContent"><img src="{url}"></div>`

## Detail Page (Magnet & Chapters)
1.  Fetch the detail page.
2.  **Info Hash**: Extract the 40-character hex string using regex: `Info Hash:<\/td>\s*<td[^>]*>\s*([a-fA-F0-9]{40})\s*<\/td>`
3.  **Trackers**: Extract the announce URL and trackers using regex:
    *   `Announce URL:<\/td>\s*<td[^>]*>\s*([^<]+?)\s*<\/td>`
    *   `Tracker:<\/td>\s*<td[^>]*>\s*([^<]+?)\s*<\/td>`
4.  **Construct Magnet URI**: `magnet:?xt=urn:btih:{info_hash}&dn={encoded_title}&tr={encoded_tracker_1}&tr={encoded_tracker_2}...`
5.  **Chapters (Files)**: The HTML table lists the files in the torrent. Look for rows matching audio extensions (`.mp3`, `.m4b`, etc.) alongside sizes (`MB`, `GB`). E.g., `^(.+?\.(?:m4b|mp3|aac|flac|ogg|opus|wav|wma|m4a))\s+[\d.]+\s*(?:MB|GB)`.
6.  The order of these files in the HTML corresponds to the file index in the torrent.

## Streaming
*   Pass the constructed Magnet URI to `libtorrent_flutter` (version 1.8.5).
*   Use the index of the file you want to play to prioritize it or fetch its HTTP stream URL from the local server provided by libtorrent.
*   **WARNING**: Users MUST be warned that playback uses P2P BitTorrent streaming.
