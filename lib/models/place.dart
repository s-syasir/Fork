enum Tier { toTry, loved, liked, meh, unsorted }

Tier tierFromJson(String value) {
  switch (value) {
    case 'to_try':
      return Tier.toTry;
    case 'loved':
      return Tier.loved;
    case 'liked':
      return Tier.liked;
    case 'meh':
      return Tier.meh;
    default:
      return Tier.unsorted;
  }
}

String tierToJson(Tier tier) {
  switch (tier) {
    case Tier.toTry:
      return 'to_try';
    case Tier.loved:
      return 'loved';
    case Tier.liked:
      return 'liked';
    case Tier.meh:
      return 'meh';
    case Tier.unsorted:
      return 'unsorted';
  }
}

String tierLabel(Tier tier) {
  switch (tier) {
    case Tier.toTry:
      return 'Should try';
    case Tier.loved:
      return 'Loved';
    case Tier.liked:
      return 'Liked';
    case Tier.meh:
      return 'Meh';
    case Tier.unsorted:
      return 'Unsorted';
  }
}

/// Mirrors fork-backend's src/placeNote.ts tierFromScore exactly - keep the
/// two in sync if the thresholds ever change.
Tier tierFromScore(double? score) {
  if (score == null) return Tier.toTry;
  if (score >= 7) return Tier.loved;
  if (score >= 4) return Tier.liked;
  return Tier.meh;
}

enum PriceTier { cheap, decent, expensive }

PriceTier? priceFromJson(String? value) {
  switch (value) {
    case 'cheap':
      return PriceTier.cheap;
    case 'decent':
      return PriceTier.decent;
    case 'expensive':
      return PriceTier.expensive;
    default:
      return null;
  }
}

String? priceToJson(PriceTier? price) {
  switch (price) {
    case PriceTier.cheap:
      return 'cheap';
    case PriceTier.decent:
      return 'decent';
    case PriceTier.expensive:
      return 'expensive';
    case null:
      return null;
  }
}

String priceLabel(PriceTier price) {
  switch (price) {
    case PriceTier.cheap:
      return 'Cheap';
    case PriceTier.decent:
      return 'Decent';
    case PriceTier.expensive:
      return 'Expensive';
  }
}

/// A place as stored in the local SQLite database - the rich, primary
/// record. Only `name`/`location`/`region`/`tier`/`price` ever leave the
/// device (see [NoteEntry]); everything else (score, review, tags, photos,
/// visit date, exact address) is local-only, by design - see the README's
/// sync model.
class Place {
  final String id;

  /// fork-backend's derived id (region|name|location slug) for the note
  /// bullet this place is matched to. Null until the first successful
  /// push/pull sync links it to one.
  final String? noteLineKey;

  final String name;
  final String location;
  final String region;

  /// Optional, more precise text fed to the geocoder instead of
  /// name+location when set - fixes geocoding misses for places whose
  /// casual/local name (e.g. "Aladdins") doesn't match their official
  /// listed name.
  final String? address;

  final double? lat;
  final double? lng;

  /// 0-10, the average of this place's [Visit] ratings (visits with no
  /// rating set don't count toward it). Null when there are no rated
  /// visits yet - the note (not the app) is authoritative for this place's
  /// tier until then. Recomputed and re-saved by [LocalDb] whenever a visit
  /// is added/edited/removed - never set directly by the UI.
  final double? score;
  final Tier tier;
  final PriceTier? price;

  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// True if a local change hasn't been successfully pushed to fork-backend
  /// yet (e.g. saved while offline). Retried on next successful sync.
  final bool noteSyncPending;

  const Place({
    required this.id,
    required this.noteLineKey,
    required this.name,
    required this.location,
    required this.region,
    required this.address,
    required this.lat,
    required this.lng,
    required this.score,
    required this.tier,
    required this.price,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    required this.noteSyncPending,
  });

  Place copyWith({
    String? noteLineKey,
    String? name,
    String? location,
    String? region,
    String? Function()? address,
    double? lat,
    double? lng,
    double? Function()? score,
    Tier? tier,
    PriceTier? Function()? price,
    List<String>? tags,
    DateTime? updatedAt,
    bool? noteSyncPending,
  }) {
    return Place(
      id: id,
      noteLineKey: noteLineKey ?? this.noteLineKey,
      name: name ?? this.name,
      location: location ?? this.location,
      region: region ?? this.region,
      address: address != null ? address() : this.address,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      score: score != null ? score() : this.score,
      tier: tier ?? this.tier,
      price: price != null ? price() : this.price,
      tags: tags ?? this.tags,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      noteSyncPending: noteSyncPending ?? this.noteSyncPending,
    );
  }
}

/// A single visit to a place: when, how it was rated (if at all), and any
/// notes about that specific time. A place's overall [Place.score] is the
/// average of its visits' ratings (see [LocalDb.recomputeScore]).
class Visit {
  final String id;
  final String placeId;
  final DateTime? date;
  final double? rating;
  final String? description;
  final DateTime createdAt;

  const Visit({
    required this.id,
    required this.placeId,
    required this.date,
    required this.rating,
    required this.description,
    required this.createdAt,
  });

  Visit copyWith({
    DateTime? Function()? date,
    double? Function()? rating,
    String? Function()? description,
  }) {
    return Visit(
      id: id,
      placeId: placeId,
      date: date != null ? date() : this.date,
      rating: rating != null ? rating() : this.rating,
      description: description != null ? description() : this.description,
      createdAt: createdAt,
    );
  }
}

/// A photo attached to a place, optionally tagged with the dish it shows -
/// distinct from the place-level "here's what it looks like" case.
class Photo {
  final String id;
  final String placeId;
  final String fileName;
  final String? dishName;
  final DateTime createdAt;

  const Photo({
    required this.id,
    required this.placeId,
    required this.fileName,
    required this.dishName,
    required this.createdAt,
  });
}

/// The lightweight shape fork-backend actually knows about - what's read
/// from GET /places and sent to POST/PATCH. Deliberately a small subset of
/// [Place]'s fields (see Fork-backend/README.md's "not the source of truth").
///
/// `tags` is read-only from the app's side: it reflects the note's `####`
/// heading structure (see fork-backend's placeNote.ts), imported into
/// [Place.tags] on first pull-sync only - the app never writes tags back
/// into the note.
class NoteEntry {
  final String id;
  final String name;
  final String location;
  final String region;
  final Tier tier;
  final PriceTier? price;
  final List<String> tags;

  const NoteEntry({
    required this.id,
    required this.name,
    required this.location,
    required this.region,
    required this.tier,
    this.price,
    this.tags = const [],
  });

  factory NoteEntry.fromJson(Map<String, dynamic> json) {
    return NoteEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      location: json['location'] as String? ?? '',
      region: json['region'] as String? ?? 'Unsorted',
      tier: tierFromJson(json['tier'] as String? ?? 'unsorted'),
      price: priceFromJson(json['price'] as String?),
      tags: (json['tags'] as List<dynamic>? ?? const []).cast<String>(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'location': location,
    'region': region,
    'tier': tierToJson(tier),
    'price': priceToJson(price),
  };
}
