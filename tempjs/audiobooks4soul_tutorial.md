# Audiobooks4Soul Scraper Tutorial

## Overview
Audiobooks4Soul uses a custom player plugin (`custom-story-audio`) that encrypts the audio source URLs directly in the HTML to prevent easy scraping.

## Search and Browse
*   **Search URL**: `https://audiobooks4soul.com/?s={query}`
*   **Item Selector**: `<h2 class="entry-title"><a href="{url}">{title}</a></h2>`

## Detail Page (Chapters)
1.  Fetch the detail page URL.
2.  Look for the playlist items: `<span class="simp-source" data-src="{encrypted_string}">Title</span>`.
3.  **Decrypting**: The site exposes a decryption endpoint. You must send a GET request to:
    `https://audiobooks4soul.com/wp-content/plugins/custom-story-audio/inc/security/decrypt.php?encrypted={encrypted_string}`
4.  The response body of that request is the plain-text `.mp3` URL.
5.  *Note:* The site often inserts a promotional track ("Soulful_Exploration") as the first item in the playlist. You should filter this out by checking the title.
