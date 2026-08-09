# Audiozaic Scraper Tutorial

## Overview
Audiozaic separates the book detail page from the actual audio player page. You must click a "Listen" button to access the audio.

## Search and Browse
*   **Search URL**: `https://audiozaic.com/?s={query}`
*   **Item Selector**: `<article class="vce-post">` containing `<h2 class="entry-title"><a href="{url}">{title}</a></h2>`
*   **Cover**: `<div class="meta-image"><img data-src="{url}"></div>`

## Detail Page (Chapters)
1.  Fetch the detail page URL.
2.  Find the listen button: `<button id="listen-button" onclick="window.open('{listen_url}')">`.
3.  The `listen_url` usually looks like `/file-audio?slug32=123`. Construct the full URL: `https://audiozaic.com{listen_url}`.
4.  Fetch the `listen_url`.
5.  On the listen page, find track divs: `<div class="track">`.
6.  Extract the title: `<span class="songtitle">{title}</span>`.
7.  Extract the audio source: `<audio><source src="{stream_url}"></audio>` or match `.mp3` links. (e.g., `free2.audiobookslab.com`).
