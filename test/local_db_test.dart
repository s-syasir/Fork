import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:fork/data/local_db.dart';
import 'package:fork/models/place.dart';

// No sync folder is ever set in these tests, so LocalDb never touches
// permission_handler's platform channel (which isn't available under plain
// `flutter test`) - _backupToSyncFolder() short-circuits before that point.

Place _place({String? id, double? score, Tier tier = Tier.toTry, String? noteLineKey}) {
  final now = DateTime.now();
  return Place(
    id: id ?? newLocalId(),
    noteLineKey: noteLineKey,
    name: 'Test Place',
    location: 'Test City',
    region: 'Test Region',
    address: null,
    lat: null,
    lng: null,
    score: score,
    tier: tier,
    price: null,
    tags: const [],
    createdAt: now,
    updatedAt: now,
    noteSyncPending: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // LocalDb is a singleton backed by one shared database across all tests
  // in this run - each test below uses a unique place id so assertions
  // never depend on the table being empty.

  test('savePlace then getAllPlaces round-trips all fields', () async {
    final place = _place(score: 8, tier: Tier.loved);
    await LocalDb.instance.savePlace(place);

    final fetched = await LocalDb.instance.getPlaceById(place.id);
    expect(fetched, isNotNull);
    expect(fetched!.name, 'Test Place');
    expect(fetched.score, 8);
    expect(fetched.tier, Tier.loved);
  });

  test('findByNoteLineKey finds a place by its note-side id', () async {
    final place = _place(noteLineKey: 'test-region-test-place-test-city');
    await LocalDb.instance.savePlace(place);

    final found = await LocalDb.instance.findByNoteLineKey('test-region-test-place-test-city');
    expect(found?.id, place.id);

    final notFound = await LocalDb.instance.findByNoteLineKey('nonexistent-key');
    expect(notFound, isNull);
  });

  test('two places sharing a note_line_key collapse to one row (dedup backstop)', () async {
    // Regression test for the pull-sync race that imported the same
    // note-side entry multiple times: two different local ids, same
    // note_line_key, saved back-to-back (as an overlapping refresh() would
    // do without the _refreshing guard) must not both persist.
    const key = 'dup-region-dup-place-dup-city';
    await LocalDb.instance.savePlace(_place(id: 'dup-attempt-1', noteLineKey: key));
    await LocalDb.instance.savePlace(_place(id: 'dup-attempt-2', noteLineKey: key));

    final all = await LocalDb.instance.getAllPlaces();
    expect(all.where((p) => p.noteLineKey == key).length, 1);
  });

  test('getSyncPendingPlaces only returns places flagged pending', () async {
    final pending = _place(id: 'pending-1');
    final synced = _place(id: 'synced-1');
    await LocalDb.instance.savePlace(pending.copyWith(noteSyncPending: true));
    await LocalDb.instance.savePlace(synced.copyWith(noteSyncPending: false));

    final result = await LocalDb.instance.getSyncPendingPlaces();
    expect(result.map((p) => p.id), contains('pending-1'));
    expect(result.map((p) => p.id), isNot(contains('synced-1')));
  });

  test('photos: addPhoto then getPhotos returns them in order', () async {
    final place = _place(id: 'photo-place-1');
    await LocalDb.instance.savePlace(place);
    await LocalDb.instance.addPhoto(place.id, 'a.jpg');
    await LocalDb.instance.addPhoto(place.id, 'b.jpg', dishName: 'Spicy tuna roll');

    final photos = await LocalDb.instance.getPhotos(place.id);
    expect(photos.map((p) => p.fileName), ['a.jpg', 'b.jpg']);
    expect(photos[0].dishName, isNull);
    expect(photos[1].dishName, 'Spicy tuna roll');
  });

  test('setPhotoDishName updates an existing photo', () async {
    final place = _place(id: 'photo-place-2');
    await LocalDb.instance.savePlace(place);
    await LocalDb.instance.addPhoto(place.id, 'c.jpg');
    final photo = (await LocalDb.instance.getPhotos(place.id)).single;

    await LocalDb.instance.setPhotoDishName(photo.id, 'Ramen');
    final updated = (await LocalDb.instance.getPhotos(place.id)).single;
    expect(updated.dishName, 'Ramen');
  });

  test('tierFromScore matches fork-backend thresholds', () {
    expect(tierFromScore(null), Tier.toTry);
    expect(tierFromScore(3.9), Tier.meh);
    expect(tierFromScore(4), Tier.liked);
    expect(tierFromScore(6.9), Tier.liked);
    expect(tierFromScore(7), Tier.loved);
    expect(tierFromScore(10), Tier.loved);
  });
}
