# Fork

A personal, local-first, open-source alternative to Beli — a map + list of
places to eat, with multi-visit star ratings, photos (with dish tagging),
tags, and price. A local SQLite database on the phone is the real data;
a [`fork-backend`](../Fork-backend) service mirrors a lossy subset
(name/location/region/tier/price) into a Joplin note, so hand-editing the
note or adding a place in the app both stay roughly in sync — the note
never sees scores, reviews, or photos.

Requires a running `fork-backend` instance (its own small service that
holds your Joplin credentials so this app never has to). Point Fork at it
from Settings on first launch.

## Highlights

- Map with a **Nearby to try** button (your own list, by distance) and an
  **Explore** button (nearby restaurants from OpenStreetMap, no API key —
  not "trending," just "nearby you haven't added")
- Multi-visit ratings with half-star precision — a place's score is the
  average of every visit you've rated
- Swipe-to-rate from the list view; region/tag/neighborhood filtering;
  per-region and per-place text sharing
- Fully offline-capable — all reads come from the local database, writes
  queue for sync if the backend's unreachable

## Sync model

The Joplin note is a lossy mirror, not a peer — it only ever carries
`name`/`location`/`region`/`tier`/`price`. A place with no rated visits yet
is *note-authoritative* (its tier tracks whatever heading it's under in
Joplin); once it has a rated visit, the app becomes authoritative and
re-pushes to fix the note if they disagree. Any push that fails while
offline queues locally and retries on the next successful sync.

## Build

```bash
flutter run
# or
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```
