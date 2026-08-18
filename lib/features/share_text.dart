import '../models/place.dart';

String _tierEmoji(Tier tier) {
  switch (tier) {
    case Tier.loved:
      return '💚';
    case Tier.liked:
      return '💛';
    case Tier.meh:
      return '💔';
    case Tier.toTry:
      return '📝';
    case Tier.unsorted:
      return '❔';
  }
}

String _priceEmoji(PriceTier price) {
  switch (price) {
    case PriceTier.cheap:
      return '💵';
    case PriceTier.decent:
      return '💵💵';
    case PriceTier.expensive:
      return '💵💵💵';
  }
}

/// A compact, shareable text card for one place - name, where, rating,
/// and (if there's one) the most recent visit's note.
String buildPlaceShareText(Place place, List<Visit> visits) {
  final lines = <String>[];
  lines.add('${_tierEmoji(place.tier)} ${place.name}');

  final where = [place.location, place.region].where((s) => s.trim().isNotEmpty).join(', ');
  if (where.isNotEmpty) lines.add(where);
  if (place.address != null && place.address!.trim().isNotEmpty) lines.add(place.address!.trim());

  final details = <String>[];
  if (place.score != null) {
    final ratedVisits = visits.where((v) => v.rating != null).length;
    details.add(
      '${place.score!.toStringAsFixed(1)}/10${ratedVisits > 1 ? ' ($ratedVisits visits)' : ''}',
    );
  }
  details.add(tierLabel(place.tier));
  if (place.price != null) details.add('${_priceEmoji(place.price!)} ${priceLabel(place.price!)}');
  if (details.isNotEmpty) lines.add(details.join(' · '));

  final notedVisits = visits.where((v) => v.description != null && v.description!.trim().isNotEmpty).toList();
  if (notedVisits.isNotEmpty) {
    lines.add('"${notedVisits.last.description!.trim()}"');
  }

  return lines.join('\n');
}

/// A plain bulleted list for a set of places, grouped by region - mirrors
/// the note's own `## Region` / `- Name, Location` shape so it reads
/// naturally to anyone who's seen the note.
String buildPlaceListShareText(List<Place> places) {
  final grouped = <String, List<Place>>{};
  for (final p in places) {
    grouped.putIfAbsent(p.region, () => []).add(p);
  }
  final regions = grouped.keys.toList()..sort();

  final lines = <String>[];
  for (final region in regions) {
    lines.add('## $region');
    for (final p in grouped[region]!) {
      final locSuffix = p.location.trim().isEmpty ? '' : ', ${p.location}';
      lines.add('${_tierEmoji(p.tier)} ${p.name}$locSuffix');
    }
    lines.add('');
  }

  return lines.join('\n').trim();
}
