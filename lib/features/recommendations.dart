import 'dart:math';
import '../models/place.dart';

/// Ranks to-try places by how well they match the tags and price tier of
/// places you've already rated positively - purely on-device, no
/// telemetry, no external data. Needs at least 3 loved/liked places to
/// have anything worth generalizing from; otherwise returns nothing rather
/// than guessing from too little signal.
List<Place> recommendedToTryPlaces(List<Place> places, {int limit = 5}) {
  final positive = places.where((p) => p.tier == Tier.loved || p.tier == Tier.liked).toList();
  if (positive.length < 3) return [];

  final tagCounts = <String, int>{};
  for (final p in positive) {
    for (final tag in p.tags) {
      tagCounts[tag] = (tagCounts[tag] ?? 0) + 1;
    }
  }

  final priceCounts = <PriceTier, int>{};
  for (final p in positive) {
    if (p.price != null) priceCounts[p.price!] = (priceCounts[p.price!] ?? 0) + 1;
  }
  PriceTier? favoritePrice;
  var bestPriceCount = 0;
  for (final entry in priceCounts.entries) {
    if (entry.value > bestPriceCount) {
      bestPriceCount = entry.value;
      favoritePrice = entry.key;
    }
  }

  final scored = <(Place, int)>[];
  for (final p in places.where((p) => p.tier == Tier.toTry)) {
    var score = 0;
    for (final tag in p.tags) {
      score += tagCounts[tag] ?? 0;
    }
    if (favoritePrice != null && p.price == favoritePrice) score += 2;
    if (score > 0) scored.add((p, score));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return scored.take(limit).map((e) => e.$1).toList();
}

const _earthRadiusKm = 6371.0;

double _toRadians(double degrees) => degrees * pi / 180;

double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  final dLat = _toRadians(lat2 - lat1);
  final dLng = _toRadians(lng2 - lng1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRadians(lat1)) * cos(_toRadians(lat2)) * sin(dLng / 2) * sin(dLng / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return _earthRadiusKm * c;
}

/// To-try places nearest to a given point, closest first - a reframing of
/// Beli's "trending nearby" that works without any other users' data.
List<(Place, double)> nearbyToTryPlaces(
  List<Place> places,
  double lat,
  double lng, {
  int limit = 10,
}) {
  final withDistance = <(Place, double)>[];
  for (final p in places.where((p) => p.tier == Tier.toTry && p.lat != null && p.lng != null)) {
    withDistance.add((p, distanceKm(lat, lng, p.lat!, p.lng!)));
  }
  withDistance.sort((a, b) => a.$2.compareTo(b.$2));
  return withDistance.take(limit).toList();
}
