import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../data/place_repository.dart';
import '../../home_shell.dart';
import '../../models/place.dart';
import '../../models/tier_style.dart';
import '../add_edit/add_edit_screen.dart';
import '../place_detail_sheet.dart';
import '../recommendations.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _mapController = MapController();
  bool _locating = false;
  bool _findingNearby = false;
  bool _exploring = false;

  Future<Position?> _getCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      _showMessage('Location services are off');
      return null;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      _showMessage('Location permission denied');
      return null;
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
    );
  }

  Future<void> _goToMyLocation() async {
    setState(() => _locating = true);
    try {
      final position = await _getCurrentPosition();
      if (position == null) return;
      _mapController.move(LatLng(position.latitude, position.longitude), 14);
    } catch (e) {
      _showMessage("Couldn't get your location: $e");
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _showNearbyToTry(List<Place> places) async {
    setState(() => _findingNearby = true);
    try {
      final position = await _getCurrentPosition();
      if (position == null) return;
      final nearby = nearbyToTryPlaces(places, position.latitude, position.longitude);
      if (!mounted) return;
      if (nearby.isEmpty) {
        _showMessage("No pinned to-try places yet - add an address to some and they'll show up here");
        return;
      }
      showModalBottomSheet(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nearby to try', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              for (final (place, km) in nearby)
                ListTile(
                  leading: const Icon(Icons.explore_outlined),
                  title: Text(place.name),
                  subtitle: Text('${place.region} · ${(km * 0.621371).toStringAsFixed(1)} mi away'),
                  onTap: () {
                    Navigator.of(context).pop();
                    showPlaceDetail(context, place);
                  },
                ),
            ],
          ),
        ),
      );
    } catch (e) {
      _showMessage("Couldn't find nearby places: $e");
    } finally {
      if (mounted) setState(() => _findingNearby = false);
    }
  }

  Future<void> _showExplore(List<Place> places) async {
    setState(() => _exploring = true);
    try {
      // Wherever the map's currently centered - not GPS location - so
      // panning around and hitting Explore looks at that area, not just
      // "near me right now."
      final center = _mapController.camera.center;

      final results = await ref.read(placeRepositoryProvider.notifier).explore(center.latitude, center.longitude);
      if (!mounted) return;

      final knownNames = places.map((p) => p.name.trim().toLowerCase()).toSet();
      final newResults = results.where((r) => !knownNames.contains(r.name.trim().toLowerCase())).toList()
        ..sort(
          (a, b) => distanceKm(center.latitude, center.longitude, a.lat, a.lng)
              .compareTo(distanceKm(center.latitude, center.longitude, b.lat, b.lng)),
        );

      if (newResults.isEmpty) {
        _showMessage("Nothing nearby on OpenStreetMap that isn't already on your list");
        return;
      }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Explore', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      "From OpenStreetMap - no ratings or trending data, just what's near the map's center that you haven't added.",
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              for (final r in newResults)
                ListTile(
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(r.name),
                  subtitle: Text(
                    [
                      if (r.cuisine != null && r.cuisine!.isNotEmpty) r.cuisine!,
                      '${(distanceKm(center.latitude, center.longitude, r.lat, r.lng) * 0.621371).toStringAsFixed(1)} mi away',
                    ].join(' · '),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Add to list',
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AddEditScreen(
                            prefillName: r.name,
                            prefillAddress: r.address,
                            prefillTag: r.cuisine,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    } catch (e) {
      _showMessage("Couldn't explore nearby places: $e");
    } finally {
      if (mounted) setState(() => _exploring = false);
    }
  }

  void _showMessage(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showSearch(List<Place> places) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        var query = '';
        return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              final matches = places.where((p) {
                if (query.isEmpty) return true;
                final q = query.toLowerCase();
                return p.name.toLowerCase().contains(q) ||
                    p.location.toLowerCase().contains(q) ||
                    p.region.toLowerCase().contains(q);
              }).toList();

              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search your places...',
                          isDense: true,
                        ),
                        onChanged: (v) => setSheetState(() => query = v),
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final place in matches)
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: tierColor(place.tier),
                                child: Text(
                                  place.score?.toStringAsFixed(0) ?? '?',
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ),
                              title: Text(place.name),
                              subtitle: Text('${place.region} · ${place.location}'),
                              onTap: () {
                                Navigator.of(context).pop();
                                if (place.lat != null && place.lng != null) {
                                  _mapController.move(LatLng(place.lat!, place.lng!), 15);
                                }
                                showPlaceDetail(context, place);
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final placesAsync = ref.watch(placeRepositoryProvider);

    ref.listen(mapFocusPlaceProvider, (previous, place) {
      if (place != null && place.lat != null && place.lng != null) {
        _mapController.move(LatLng(place.lat!, place.lng!), 15);
        // One-shot - consumed, so returning to this tab later doesn't
        // keep re-centering on a stale focus request.
        Future.microtask(() => ref.read(mapFocusPlaceProvider.notifier).state = null);
      }
    });

    return placesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('$e'))),
      data: (places) {
        final located = places.where((p) => p.lat != null && p.lng != null).toList();
        final center = located.isNotEmpty
            ? LatLng(located.first.lat!, located.first.lng!)
            : const LatLng(47.6062, -122.3321); // Seattle, as a reasonable default

        return Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: center, initialZoom: located.isEmpty ? 4 : 10),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.yasir.fork',
                ),
                MarkerLayer(
                  markers: [
                    for (final p in located)
                      Marker(
                        point: LatLng(p.lat!, p.lng!),
                        width: 36,
                        height: 36,
                        child: GestureDetector(
                          onTap: () => showPlaceDetail(context, p),
                          child: _PinIcon(place: p),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            // Left side, not right - home_shell.dart's global "Add place"
            // FAB docks bottom-right (Scaffold's default endFloat location)
            // and renders on top of anything in this Stack at that corner.
            Positioned(
              left: 12,
              bottom: 124,
              child: FloatingActionButton.small(
                heroTag: 'explore',
                tooltip: 'Explore nearby (OpenStreetMap)',
                onPressed: _exploring ? null : () => _showExplore(places),
                child: _exploring
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.storefront_outlined),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 68,
              child: FloatingActionButton.small(
                heroTag: 'nearby-to-try',
                tooltip: 'Nearby to try',
                onPressed: _findingNearby ? null : () => _showNearbyToTry(places),
                child: _findingNearby
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.explore_outlined),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: FloatingActionButton.small(
                heroTag: 'locate-me',
                tooltip: 'My location',
                onPressed: _locating ? null : _goToMyLocation,
                child: _locating
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.my_location),
              ),
            ),
            // Right side, stacked above home_shell.dart's global "Add
            // place" FAB (which docks bottom-right, ~72dp tall including
            // its margin) - this is search over your own list, distinct
            // from the storefront "Explore" button on the left.
            Positioned(
              right: 12,
              bottom: 84,
              child: FloatingActionButton.small(
                heroTag: 'search',
                tooltip: 'Search your places',
                onPressed: () => _showSearch(places),
                child: const Icon(Icons.search),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PinIcon extends StatelessWidget {
  final Place place;
  const _PinIcon({required this.place});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: tierMapOpacity(place.tier),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.location_on, color: tierColor(place.tier), size: 36),
          // Loved places get a star badge - green alone doesn't stand out
          // enough against the rest of the map at a glance.
          if (place.tier == Tier.loved)
            Positioned(
              top: 1,
              left: 10,
              child: Icon(Icons.star, color: Colors.yellowAccent.shade400, size: 11),
            ),
        ],
      ),
    );
  }
}
