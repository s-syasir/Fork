import 'package:flutter_test/flutter_test.dart';
import 'package:fork/features/list/place_filter.dart';
import 'package:fork/models/place.dart';

Place _place({
  required String name,
  required String region,
  required String location,
  Tier tier = Tier.toTry,
  double? score,
  String? address,
  List<String> tags = const [],
}) {
  final now = DateTime(2026, 1, 1);
  return Place(
    id: name,
    noteLineKey: null,
    name: name,
    location: location,
    region: region,
    address: address,
    lat: null,
    lng: null,
    score: score,
    tier: tier,
    price: null,
    tags: tags,
    createdAt: now,
    updatedAt: now,
    noteSyncPending: false,
  );
}

void main() {
  final places = [
    _place(name: 'Aladdins', region: 'Seattle Area', location: 'Seattle', tier: Tier.loved, score: 8.5, tags: ['GOAT']),
    _place(name: 'The Nest', region: 'Seattle Area', location: 'SLU', tier: Tier.liked, score: 6, tags: ['Bars']),
    _place(name: 'Musashis', region: 'Seattle Area', location: 'Redmond', tier: Tier.toTry, address: '7405 168th Ave NE'),
    _place(name: 'Los Tacos No. 1', region: 'NYC', location: 'Chelsea', tier: Tier.loved, score: 9),
    _place(name: 'Xian\'s Famous Food', region: 'NYC', location: 'Chinatown', tier: Tier.meh, score: 3),
  ];

  test('no filters returns everything', () {
    expect(filterPlaces(places), hasLength(places.length));
  });

  test('single region filters to that region only', () {
    final result = filterPlaces(places, regions: {'NYC'});
    expect(result.map((p) => p.name), unorderedEquals(['Los Tacos No. 1', 'Xian\'s Famous Food']));
  });

  test('multi-select region is OR\'d across regions', () {
    final result = filterPlaces(places, regions: {'NYC', 'Seattle Area'});
    expect(result, hasLength(places.length));
  });

  test('multi-select tier is OR\'d across tiers', () {
    final result = filterPlaces(places, tiers: {Tier.loved, Tier.meh});
    expect(result.map((p) => p.name), unorderedEquals(['Aladdins', 'Los Tacos No. 1', 'Xian\'s Famous Food']));
  });

  test('region and tier filters AND together', () {
    final result = filterPlaces(places, regions: {'Seattle Area'}, tiers: {Tier.loved});
    expect(result.map((p) => p.name), ['Aladdins']);
  });

  test('multi-select tags matches any selected tag', () {
    final result = filterPlaces(places, tags: {'GOAT', 'Bars'});
    expect(result.map((p) => p.name), unorderedEquals(['Aladdins', 'The Nest']));
  });

  test('multi-select neighborhoods matches any selected location', () {
    final result = filterPlaces(places, locations: {'Redmond', 'Chinatown'});
    expect(result.map((p) => p.name), unorderedEquals(['Musashis', 'Xian\'s Famous Food']));
  });

  test('unrated only excludes places with a score', () {
    final result = filterPlaces(places, unratedOnly: true);
    expect(result.map((p) => p.name), ['Musashis']);
  });

  test('unpinned only excludes places with an address on file', () {
    final result = filterPlaces(places, unpinnedOnly: true);
    expect(result.any((p) => p.name == 'Musashis'), isFalse);
    expect(result, hasLength(places.length - 1));
  });

  test('search query matches name, location, region, or tags', () {
    expect(filterPlaces(places, query: 'goat').map((p) => p.name), ['Aladdins']);
    expect(filterPlaces(places, query: 'chinatown').map((p) => p.name), ['Xian\'s Famous Food']);
    expect(filterPlaces(places, query: 'nyc'), hasLength(2));
  });
}
