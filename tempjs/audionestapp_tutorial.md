# AudionestApp Scraper Tutorial

## Overview
Audionest is a mobile app back-end using Meilisearch for searching and Firebase Cloud Firestore for database storage. It requires a hardcoded Meilisearch key and an anonymous Firebase auth flow.

## API Keys (Hardcoded)
*   **MeiliBase**: `https://search.audionestapp.com`
*   **MeiliKey**: `MWJiNWM0MjA2N2ZkM2RiMDNhNWFmNGNk`
*   **Firebase API Key**: `AIzaSyAG-z_yl0_55NEYTEKGoVJyixtHG-FhnfA`
*   **Firestore DB**: `projects/learningfirebase-ae02f/databases/(default)/documents`

## Search and Browse (Meilisearch)
1.  POST to `https://search.audionestapp.com/indexes/trackfiles/search`
2.  Headers: `Authorization: Bearer MWJiNWM0MjA2N2ZkM2RiMDNhNWFmNGNk`
3.  Body: `{"q": "query", "limit": 30}`
4.  The response contains `hits`. Extract `id` (this is the `book_id`), `title`, and `thumbnailUrl`.

## Detail Page (Firestore)
1.  **Auth**: POST to `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={Firebase_API_Key}` with body `{"returnSecureToken": true}`. Save the `idToken`.
2.  **Query**: POST to `https://firestore.googleapis.com/v1/{Firestore_DB}:runQuery`
3.  Headers: `Authorization: Bearer {idToken}`
4.  Body:
    ```json
    {
      "structuredQuery": {
        "from": [{"collectionId": "TrackFiles"}],
        "where": {
          "fieldFilter": {
            "field": {"fieldPath": "book_id"},
            "op": "EQUAL",
            "value": {"integerValue": "{book_id}"}
          }
        },
        "limit": 1
      }
    }
    ```
5.  The response contains the document. Navigate to `document.fields.urlLink.arrayValue.values` to get the list of string URLs. These are the chapter `.mp3` links.
