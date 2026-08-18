import '../../models/place.dart';

/// Pulled out of [ListScreen]'s build method so the multi-select filter
/// logic (each category is OR'd internally, AND'd against the others) is
/// unit-testable without spinning up widgets/providers.
List<Place> filterPlaces(
  List<Place> places, {
  Set<String> regions = const {},
  Set<Tier> tiers = const {},
  Set<String> tags = const {},
  Set<String> locations = const {},
  bool unratedOnly = false,
  bool unpinnedOnly = false,
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  return places.where((p) {
    if (regions.isNotEmpty && !regions.contains(p.region)) return false;
    if (tiers.isNotEmpty && !tiers.contains(p.tier)) return false;
    if (tags.isNotEmpty && !p.tags.any(tags.contains)) return false;
    if (locations.isNotEmpty && !locations.contains(p.location)) return false;
    if (unratedOnly && p.score != null) return false;
    if (unpinnedOnly && p.address != null && p.address!.trim().isNotEmpty) return false;
    if (q.isNotEmpty &&
        !p.name.toLowerCase().contains(q) &&
        !p.location.toLowerCase().contains(q) &&
        !p.region.toLowerCase().contains(q) &&
        !p.tags.any((t) => t.toLowerCase().contains(q))) {
      return false;
    }
    return true;
  }).toList();
}
