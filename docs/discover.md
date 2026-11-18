---
type: reference
purpose: Describe public-domain book discovery and downloads.
sections: [Sources and discovery, Local catalog and search, Download and import, Network and notifications, Failure behavior]
---

# Discover books

## Sources and discovery

`BookSource` exposes search, detail and download. `bookSourcesProvider` currently provides `GutenbergSource`: an empty query loads popular books from Gutenberg OPDS, while a query searches the local catalog. Detail is fetched from OPDS. The discovery interface is designed and built; see [design](design.md).

## Local catalog and search

`CatalogSyncService` downloads the Gutenberg catalog dump and `CatalogRepository` stores searchable English text-book metadata. A catalog synced less than seven days ago is fresh; manual force bypasses that check. `If-Modified-Since` is sent only when the local catalog is nonempty; a 304 updates only the sync timestamp. Search works offline once the catalog is available. See [data model](data-model.md) for storage.

## Download and import

`downloadQueueProvider` runs one download at a time and queues the rest across screen changes. Downloaded EPUB bytes go through the existing EPUB importer, including duplicate detection; source and external IDs identify catalog books already on the shelf. Shelf metadata comes from the EPUB.

## Network and notifications

Requests go directly to Gutenberg through the shared HTTP client, which supplies `lumaUserAgent` with contact information and retries HTTP 429 and 503 up to three attempts. The app reports completed, duplicate and failed downloads through notifications or toasts.

Download notifications are shown only while the app is paused or hidden; notification permission is requested on the first download, and tapping a notification while the app is running opens the book.

## Failure behavior

A failed catalog replacement transaction leaves the old catalog intact. Sync metadata is saved separately after replacement, so refresh can report failure even after the new catalog commits. Cancelling a queued download removes it; cancelling an active download stops it at the next checkpoint. Download failures remain available for dismissal or retry.
