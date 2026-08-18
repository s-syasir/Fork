import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/place.dart';
import 'app_settings.dart';
import 'fork_api_client.dart';
import 'local_db.dart';

/// Fields the UI collects to create/update a place. `id`/`noteLineKey` are
/// filled in by the repository, not the caller.
class PlaceDraft {
  final String? existingId;
  final String name;
  final String location;
  final String region;
  final String? address;
  final PriceTier? price;
  final List<String> tags;

  const PlaceDraft({
    this.existingId,
    required this.name,
    required this.location,
    required this.region,
    this.address,
    this.price,
    this.tags = const [],
  });
}

/// True whenever local data exists that hasn't successfully synced to the
/// note yet - either the last pull failed, or there are pushes still
/// queued from being offline. Local data itself is never blocked on this.
final syncErrorProvider = StateProvider<String?>((ref) => null);

class PlaceRepository extends StateNotifier<AsyncValue<List<Place>>> {
  final ForkSettings settings;
  final Ref ref;

  PlaceRepository(this.settings, this.ref) : super(const AsyncValue.loading()) {
    _loadLocalThenSync();
  }

  ForkApiClient get _client => ForkApiClient(settings);
  bool get _canReachBackend => settings.isConfigured;

  // Riverpod rebuilds this provider (and re-runs the constructor's initial
  // sync) whenever settingsProvider emits - which can happen more than once
  // per app open (e.g. secure storage finishing its async read after the
  // first build). Without this guard, an overlapping refresh() could race
  // itself: two calls both see "not found locally" for the same note entry
  // before either finishes inserting it, importing it twice. The
  // UNIQUE(note_line_key) index in local_db.dart is the hard backstop;
  // this avoids hitting it in the first place.
  bool _refreshing = false;

  Future<void> _loadLocalThenSync() async {
    state = AsyncValue.data(await LocalDb.instance.getAllPlaces());
    if (_canReachBackend) await refresh();
  }

  Future<void> _reload() async {
    state = AsyncValue.data(await LocalDb.instance.getAllPlaces());
  }

  /// Re-reads local data into state without touching the network - for
  /// callers (like a DB restore) that changed local data directly and need
  /// the UI to reflect it even if a follow-up refresh() can't reach the
  /// backend.
  Future<void> reloadLocal() => _reload();

  /// Pull-sync: pick up note-side changes (new hand-added entries, or
  /// headings moved by hand for never-rated places), and retry pushing
  /// anything that failed to sync earlier (offline queue).
  Future<void> refresh() async {
    if (!_canReachBackend || _refreshing) return;
    _refreshing = true;
    try {
      final noteEntries = await _client.getNoteEntries();

      // note_line_key is derived from region|name|location, so any edit to
      // region/name/location (e.g. a region rename like the Vancouver Area
      // split) changes a place's slug - the old local row's noteLineKey
      // then matches nothing in the note anymore ("orphaned"). Without this,
      // that place would import a second time under its new slug instead of
      // being recognized as the same place, leaving a stale duplicate
      // behind. Matched by name+location, which a region-only rename
      // doesn't touch - claimed orphans are removed from the pool so two
      // note entries can't both claim the same stale local row.
      final noteEntryIds = noteEntries.map((e) => e.id).toSet();
      final unclaimedOrphans = (await LocalDb.instance.getAllPlaces())
          .where((p) => p.noteLineKey != null && !noteEntryIds.contains(p.noteLineKey))
          .toList();

      for (final entry in noteEntries) {
        final local = await LocalDb.instance.findByNoteLineKey(entry.id);
        if (local == null) {
          Place? orphan;
          for (final o in unclaimedOrphans) {
            if (o.name.trim().toLowerCase() == entry.name.trim().toLowerCase() &&
                o.location.trim().toLowerCase() == entry.location.trim().toLowerCase()) {
              orphan = o;
              break;
            }
          }

          if (orphan != null) {
            unclaimedOrphans.remove(orphan);
            final relinked = orphan.copyWith(
              region: entry.region,
              noteLineKey: entry.id,
              tier: orphan.score == null ? entry.tier : orphan.tier,
              updatedAt: DateTime.now(),
            );
            await LocalDb.instance.savePlace(relinked);
            if (orphan.score != null && orphan.tier != entry.tier) {
              // App-authoritative: fix the note's tier back rather than
              // letting the rename silently drop it.
              await _pushEntry(relinked);
            }
            continue;
          }

          // Hand-added in Joplin - import as a bare, unrated placeholder.
          // Price is the one field the note carries that isn't score-gated,
          // so it comes along on import same as tier does.
          final coords = await geocode(entry.name, entry.location);
          await LocalDb.instance.savePlace(Place(
            id: newLocalId(),
            noteLineKey: entry.id,
            name: entry.name,
            location: entry.location,
            region: entry.region,
            address: coords.address,
            lat: coords.lat,
            lng: coords.lng,
            score: null,
            tier: entry.tier,
            price: entry.price,
            tags: entry.tags,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            noteSyncPending: false,
          ));
        } else if (local.score == null && local.tier != entry.tier) {
          // Note-authoritative: no local rating yet, so the note's heading wins.
          await LocalDb.instance.savePlace(local.copyWith(tier: entry.tier, updatedAt: DateTime.now()));
        } else if (local.score != null && local.tier != entry.tier) {
          // App-authoritative: a rated place's tier always wins - re-push
          // to fix the note back rather than letting it silently drift.
          await _pushEntry(local);
        }
      }

      // Retry anything that failed to push earlier (offline queue).
      for (final pending in await LocalDb.instance.getSyncPendingPlaces()) {
        await _pushEntry(pending);
      }

      // Backfill addresses that never got saved (e.g. places imported
      // before the address field existed) - one place at a time, since the
      // backend's own Nominatim queue is already rate-limited to 1/sec.
      for (final place in await LocalDb.instance.getAllPlaces()) {
        final hasAddress = place.address != null && place.address!.trim().isNotEmpty;
        if (hasAddress || place.lat == null || place.lng == null) continue;
        try {
          final address = await _client.reverseGeocode(place.lat!, place.lng!);
          if (address != null && address.trim().isNotEmpty) {
            await LocalDb.instance.savePlace(place.copyWith(address: () => address));
          }
        } catch (_) {
          // Non-fatal - just means this place's address stays empty until
          // the next successful refresh.
        }
      }

      final stillPending = await LocalDb.instance.getSyncPendingPlaces();
      ref.read(syncErrorProvider.notifier).state =
          stillPending.isEmpty ? null : '${stillPending.length} place(s) not yet synced to the note';
      await _reload();
    } catch (e) {
      // Pull failures are non-fatal - local data (already loaded) stays
      // shown; just nothing new comes in until the next successful sync.
      ref.read(syncErrorProvider.notifier).state = e.toString();
    } finally {
      _refreshing = false;
    }
  }

  /// Pushes a place's name/location/region/tier/price to fork-backend,
  /// updating its noteLineKey on first success. Marks it pending on failure
  /// instead of throwing - the local save already succeeded and shouldn't
  /// be undone just because the network isn't there right now.
  Future<void> _pushEntry(Place place) async {
    final entry = NoteEntry(
      id: place.noteLineKey ?? '',
      name: place.name,
      location: place.location,
      region: place.region,
      tier: place.tier,
      price: place.price,
    );
    try {
      final newKey = place.noteLineKey == null
          ? await _client.pushNewEntry(entry)
          : await _client.pushUpdatedEntry(place.noteLineKey!, entry);
      await LocalDb.instance.savePlace(place.copyWith(noteLineKey: newKey, noteSyncPending: false));
    } catch (_) {
      await LocalDb.instance.savePlace(place.copyWith(noteSyncPending: true));
    }
  }

  /// Nearby restaurants from OpenStreetMap - candidates for adding, not
  /// places already on the list. Empty (not thrown) on any failure, same
  /// as [geocode] - Explore is a nice-to-have, never worth surfacing an
  /// error over.
  Future<List<({String name, double lat, double lng, String? cuisine, String? address})>> explore(
    double lat,
    double lng,
  ) async {
    if (!_canReachBackend) return [];
    try {
      return await _client.explore(lat, lng);
    } catch (_) {
      return [];
    }
  }

  /// Geocodes `address` if given (more precise - fixes misses from casual
  /// names like "Aladdins" vs an official listing name), falling back to
  /// name+location. Never throws - failures just come back empty.
  Future<({double? lat, double? lng, String? address})> geocode(
    String name,
    String location, [
    String? address,
  ]) async {
    if (!_canReachBackend) return (lat: null, lng: null, address: null);
    try {
      final query = (address != null && address.trim().isNotEmpty) ? address : location;
      return await _client.geocode(name, query);
    } catch (_) {
      return (lat: null, lng: null, address: null);
    }
  }

  /// Saves a place's core fields (name/location/region/address/price/tags).
  /// Score/tier are handled separately by [saveVisits] - a brand-new place
  /// starts as `to_try` (no visits yet means no rating).
  Future<Place> savePlace(PlaceDraft draft) async {
    final existing = draft.existingId == null ? null : await LocalDb.instance.getPlaceById(draft.existingId!);
    final now = DateTime.now();

    ({double? lat, double? lng, String? address})? coords;
    if (existing == null ||
        existing.name != draft.name ||
        existing.location != draft.location ||
        existing.address != draft.address) {
      coords = await geocode(draft.name, draft.location, draft.address);
    }

    // Auto-fill the address from what Nominatim actually resolved, but
    // only when the user hasn't typed one themselves - theirs always wins.
    final resolvedAddress =
        (draft.address != null && draft.address!.trim().isNotEmpty) ? draft.address : coords?.address;

    final place = Place(
      id: draft.existingId ?? newLocalId(),
      noteLineKey: existing?.noteLineKey,
      name: draft.name,
      location: draft.location,
      region: draft.region,
      address: resolvedAddress,
      lat: coords?.lat ?? existing?.lat,
      lng: coords?.lng ?? existing?.lng,
      score: existing?.score,
      tier: existing?.tier ?? Tier.toTry,
      price: draft.price,
      tags: draft.tags,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      noteSyncPending: existing?.noteSyncPending ?? false,
    );

    await LocalDb.instance.savePlace(place);
    await _reload();

    if (_canReachBackend) {
      await _pushEntry(place);
    } else {
      await LocalDb.instance.savePlace(place.copyWith(noteSyncPending: true));
      ref.read(syncErrorProvider.notifier).state = "Not synced to the note yet - can't reach fork-backend";
    }
    await _reload();
    return (await LocalDb.instance.getPlaceById(place.id))!;
  }

  /// Replaces a place's full visit list, recomputes its score/tier as the
  /// average of rated visits, and pushes the tier to the note if it changed.
  Future<void> saveVisits(String placeId, List<Visit> visits) async {
    final updated = await LocalDb.instance.replaceVisits(placeId, visits);
    await _reload();

    if (_canReachBackend) {
      await _pushEntry(updated);
    } else {
      await LocalDb.instance.savePlace(updated.copyWith(noteSyncPending: true));
      ref.read(syncErrorProvider.notifier).state = "Not synced to the note yet - can't reach fork-backend";
    }
    await _reload();
  }

  /// Removes a place both from the note (if it's ever been synced there)
  /// and locally. If the note-side delete fails (offline/unreachable), the
  /// local delete still goes through - the note entry will just linger
  /// until it's removed by hand or this is retried.
  Future<void> deletePlace(Place place) async {
    if (place.noteLineKey != null && _canReachBackend) {
      try {
        await _client.deleteEntry(place.noteLineKey!);
      } catch (_) {
        // Non-fatal - see doc comment above.
      }
    }
    await LocalDb.instance.deletePlace(place.id);
    await _reload();
  }

  /// Adds a single dated, unnamed visit at a representative score for the
  /// given tier - the fast path for "swipe to rate" in the list view,
  /// where a full visit-with-notes flow would be overkill. Anything more
  /// specific than this can still be added via Edit afterward.
  Future<void> quickRate(String placeId, Tier tier) async {
    const representativeScore = {Tier.loved: 8.5, Tier.liked: 5.5, Tier.meh: 2.5};
    final rating = representativeScore[tier];
    if (rating == null) return;

    final existingVisits = await LocalDb.instance.getVisits(placeId);
    final visits = [
      ...existingVisits,
      Visit(id: newLocalId(), placeId: placeId, date: DateTime.now(), rating: rating, description: null, createdAt: DateTime.now()),
    ];
    await saveVisits(placeId, visits);
  }

  Future<void> addPhoto(String placeId, String fileName, {String? dishName}) async {
    await LocalDb.instance.addPhoto(placeId, fileName, dishName: dishName);
  }

  Future<void> setPhotoDishName(String photoId, String? dishName) =>
      LocalDb.instance.setPhotoDishName(photoId, dishName);

  Future<List<Photo>> getPhotos(String placeId) => LocalDb.instance.getPhotos(placeId);

  Future<List<Visit>> getVisits(String placeId) => LocalDb.instance.getVisits(placeId);

  Future<List<String>> getAllRegions() => LocalDb.instance.getAllRegions();

  Future<List<({String region, String location})>> getAllRegionLocationPairs() =>
      LocalDb.instance.getAllRegionLocationPairs();
}

final placeRepositoryProvider = StateNotifierProvider<PlaceRepository, AsyncValue<List<Place>>>((ref) {
  final settings = ref.watch(settingsProvider);
  return PlaceRepository(settings, ref);
});
