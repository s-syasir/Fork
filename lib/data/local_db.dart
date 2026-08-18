import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/place.dart';

String newLocalId() => '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(0xFFFFFF)}';

const _syncFolderKey = 'fork_sync_folder';

/// The local, on-device SQLite database - the primary store for everything
/// Beli-like (ratings, reviews, photos). Every write also checkpoints and
/// copies the DB (and any new photo files) into a user-chosen folder, for
/// Syncthing to carry to the NAS. See the README for the full model.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _db;
  static const int _version = 6;

  Future<Database> get _database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'fork.db');
    return openDatabase(
      path,
      version: _version,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE places (
            id TEXT PRIMARY KEY,
            note_line_key TEXT,
            name TEXT NOT NULL,
            location TEXT NOT NULL,
            region TEXT NOT NULL,
            address TEXT,
            lat REAL,
            lng REAL,
            score REAL,
            tier TEXT NOT NULL,
            price TEXT,
            review TEXT,
            tags TEXT NOT NULL DEFAULT '[]',
            visit_date TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            note_sync_pending INTEGER NOT NULL DEFAULT 0
          )
        ''');
        // UNIQUE (not just indexed) - SQLite treats NULLs as distinct from
        // each other, so locally-created places (note_line_key still null)
        // are unaffected; this is purely a backstop against the pull-sync
        // race that duplicated imported places (see PlaceRepository.refresh's
        // _refreshing guard for the actual fix - this just makes it
        // impossible to regress even if that guard is ever removed/bypassed).
        await db.execute('CREATE UNIQUE INDEX idx_places_note_line_key ON places(note_line_key)');
        await db.execute('''
          CREATE TABLE photos (
            id TEXT PRIMARY KEY,
            place_id TEXT NOT NULL REFERENCES places(id),
            file_name TEXT NOT NULL,
            dish_name TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_photos_place_id ON photos(place_id)');
        await db.execute('''
          CREATE TABLE visits (
            id TEXT PRIMARY KEY,
            place_id TEXT NOT NULL REFERENCES places(id),
            visit_date TEXT,
            rating REAL,
            description TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX idx_visits_place_id ON visits(place_id)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // De-dupe rows the pre-fix sync race created before adding the
          // unique index (keeps the earliest-created copy of each
          // note_line_key, drops the rest).
          await db.execute('''
            DELETE FROM places WHERE note_line_key IS NOT NULL AND id NOT IN (
              SELECT id FROM places p2
              WHERE p2.note_line_key = places.note_line_key
              ORDER BY p2.created_at ASC LIMIT 1
            )
          ''');
          await db.execute('DROP INDEX IF EXISTS idx_places_note_line_key');
          await db.execute('CREATE UNIQUE INDEX idx_places_note_line_key ON places(note_line_key)');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE places ADD COLUMN address TEXT');
          await db.execute('ALTER TABLE places ADD COLUMN price TEXT');
        }
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE visits (
              id TEXT PRIMARY KEY,
              place_id TEXT NOT NULL REFERENCES places(id),
              visit_date TEXT,
              rating REAL,
              description TEXT,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('CREATE INDEX idx_visits_place_id ON visits(place_id)');
          // Multiple visits/ratings per place replaces the old single
          // score+review+visit_date on the place row itself. Fold any
          // existing value into one visit record so nothing is lost -
          // score/review/visit_date columns stay in the table (unused
          // going forward) rather than risking a DROP COLUMN rebuild.
          final existing = await db.query(
            'places',
            where: 'score IS NOT NULL OR review IS NOT NULL OR visit_date IS NOT NULL',
          );
          for (final row in existing) {
            await db.insert('visits', {
              'id': newLocalId(),
              'place_id': row['id'],
              'visit_date': row['visit_date'],
              'rating': row['score'],
              'description': row['review'],
              'created_at': row['updated_at'],
            });
          }
        }
        if (oldVersion < 5) {
          // Removes "ghost" rows from a transient pull-sync bug (the note
          // was briefly misread by a stale backend parser mid-deploy,
          // producing bare placeholder imports with region/tier both
          // defaulted to "Unsorted"). These sit on the same coordinates as
          // their real counterpart and render on top of them - safe to
          // drop since they never carry a score, visit, or photo.
          await db.execute('''
            DELETE FROM places
            WHERE region = 'Unsorted' AND tier = 'unsorted' AND score IS NULL
              AND note_line_key LIKE 'unsorted-%'
              AND id NOT IN (SELECT place_id FROM visits)
              AND id NOT IN (SELECT place_id FROM photos)
          ''');
        }
        if (oldVersion < 6) {
          await db.execute('ALTER TABLE photos ADD COLUMN dish_name TEXT');
        }
      },
      onOpen: (db) async {
        await db.rawQuery('PRAGMA journal_mode=WAL;');
      },
    );
  }

  Place _fromRow(Map<String, Object?> row) {
    return Place(
      id: row['id'] as String,
      noteLineKey: row['note_line_key'] as String?,
      name: row['name'] as String,
      location: row['location'] as String,
      region: row['region'] as String,
      address: row['address'] as String?,
      lat: (row['lat'] as num?)?.toDouble(),
      lng: (row['lng'] as num?)?.toDouble(),
      score: (row['score'] as num?)?.toDouble(),
      tier: tierFromJson(row['tier'] as String),
      price: priceFromJson(row['price'] as String?),
      tags: (jsonDecode(row['tags'] as String) as List<dynamic>).cast<String>(),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      noteSyncPending: (row['note_sync_pending'] as int) == 1,
    );
  }

  Map<String, Object?> _toRow(Place place) => {
    'id': place.id,
    'note_line_key': place.noteLineKey,
    'name': place.name,
    'location': place.location,
    'region': place.region,
    'address': place.address,
    'lat': place.lat,
    'lng': place.lng,
    'score': place.score,
    'tier': tierToJson(place.tier),
    'price': priceToJson(place.price),
    'tags': jsonEncode(place.tags),
    'created_at': place.createdAt.toIso8601String(),
    'updated_at': place.updatedAt.toIso8601String(),
    'note_sync_pending': place.noteSyncPending ? 1 : 0,
  };

  Visit _visitFromRow(Map<String, Object?> row) {
    return Visit(
      id: row['id'] as String,
      placeId: row['place_id'] as String,
      date: row['visit_date'] != null ? DateTime.parse(row['visit_date'] as String) : null,
      rating: (row['rating'] as num?)?.toDouble(),
      description: row['description'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  Map<String, Object?> _visitToRow(Visit visit) => {
    'id': visit.id,
    'place_id': visit.placeId,
    'visit_date': visit.date?.toIso8601String(),
    'rating': visit.rating,
    'description': visit.description,
    'created_at': visit.createdAt.toIso8601String(),
  };

  Future<List<Place>> getAllPlaces() async {
    final db = await _database;
    final rows = await db.query('places', orderBy: 'name COLLATE NOCASE');
    return rows.map(_fromRow).toList();
  }

  Future<Place?> getPlaceById(String id) async {
    final db = await _database;
    final rows = await db.query('places', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<Place?> findByNoteLineKey(String key) async {
    final db = await _database;
    final rows = await db.query('places', where: 'note_line_key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  Future<List<Place>> getSyncPendingPlaces() async {
    final db = await _database;
    final rows = await db.query('places', where: 'note_sync_pending = 1');
    return rows.map(_fromRow).toList();
  }

  /// Insert or replace, then checkpoint+copy to the sync folder if set.
  Future<void> savePlace(Place place) async {
    final db = await _database;
    await db.insert('places', _toRow(place), conflictAlgorithm: ConflictAlgorithm.replace);
    await _backupToSyncFolder();
  }

  Photo _photoFromRow(Map<String, Object?> row) {
    return Photo(
      id: row['id'] as String,
      placeId: row['place_id'] as String,
      fileName: row['file_name'] as String,
      dishName: row['dish_name'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  Future<void> deletePlace(String placeId) async {
    final db = await _database;
    await db.delete('visits', where: 'place_id = ?', whereArgs: [placeId]);
    await db.delete('photos', where: 'place_id = ?', whereArgs: [placeId]);
    await db.delete('places', where: 'id = ?', whereArgs: [placeId]);
    await _backupToSyncFolder();
  }

  Future<void> addPhoto(String placeId, String fileName, {String? dishName}) async {
    final db = await _database;
    await db.insert('photos', {
      'id': newLocalId(),
      'place_id': placeId,
      'file_name': fileName,
      'dish_name': dishName,
      'created_at': DateTime.now().toIso8601String(),
    });
    await _backupToSyncFolder();
  }

  Future<void> setPhotoDishName(String photoId, String? dishName) async {
    final db = await _database;
    await db.update('photos', {'dish_name': dishName}, where: 'id = ?', whereArgs: [photoId]);
    await _backupToSyncFolder();
  }

  Future<List<Photo>> getPhotos(String placeId) async {
    final db = await _database;
    final rows = await db.query('photos', where: 'place_id = ?', whereArgs: [placeId], orderBy: 'created_at');
    return rows.map(_photoFromRow).toList();
  }

  // --- Distinct region names, for the Add/Edit autocomplete ---

  Future<List<String>> getAllRegions() async {
    final db = await _database;
    final rows = await db.rawQuery('SELECT DISTINCT region FROM places ORDER BY region COLLATE NOCASE');
    return rows.map((r) => r['region'] as String).toList();
  }

  /// (region, location) pairs for every place - for the Add/Edit Location
  /// autocomplete, which narrows to the selected region's locations once
  /// one's picked, or shows every location seen so far if not.
  Future<List<({String region, String location})>> getAllRegionLocationPairs() async {
    final db = await _database;
    final rows = await db.rawQuery(
      "SELECT DISTINCT region, location FROM places WHERE location != '' ORDER BY location COLLATE NOCASE",
    );
    return rows.map((r) => (region: r['region'] as String, location: r['location'] as String)).toList();
  }

  // --- Visits ---

  Future<List<Visit>> getVisits(String placeId) async {
    final db = await _database;
    final rows = await db.query('visits', where: 'place_id = ?', whereArgs: [placeId], orderBy: 'created_at');
    return rows.map(_visitFromRow).toList();
  }

  /// Replaces all of a place's visits with the given set (new ones
  /// inserted, ones no longer present deleted), recomputes the place's
  /// score as the average of rated visits, and re-saves the place - one
  /// call covers "the user edited the visit list in Add/Edit and hit Save."
  Future<Place> replaceVisits(String placeId, List<Visit> visits) async {
    final db = await _database;
    await db.delete('visits', where: 'place_id = ?', whereArgs: [placeId]);
    for (final visit in visits) {
      await db.insert('visits', _visitToRow(visit));
    }

    final place = await getPlaceById(placeId);
    if (place == null) throw StateError('replaceVisits: place $placeId not found');

    final rated = visits.where((v) => v.rating != null).map((v) => v.rating!).toList();
    final avgScore = rated.isEmpty ? null : rated.reduce((a, b) => a + b) / rated.length;
    final updated = place.copyWith(score: () => avgScore, tier: tierFromScore(avgScore));
    await savePlace(updated);
    return updated;
  }

  // --- Sync folder (Syncthing target) ---

  Future<String?> getSyncFolder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_syncFolderKey);
  }

  Future<void> setSyncFolder(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_syncFolderKey, path);
    await _backupToSyncFolder();
  }

  Future<String> photosDirectory() async {
    final folder = await getSyncFolder();
    final dir = Directory(p.join(folder ?? (await _fallbackDir()), 'photos'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  Future<String> _fallbackDir() async {
    // No sync folder configured yet - fall back to app-private storage so
    // photo picking still works; nothing here reaches Syncthing until a
    // folder is set in Settings.
    final dbPath = await getDatabasesPath();
    return p.join(dbPath, 'fork_photos_unsynced');
  }

  /// Replaces the local database with a backup copy (e.g. after a
  /// reinstall). Closes the current connection first - sqflite/SQLite both
  /// hold file handles that a raw overwrite would otherwise corrupt.
  Future<void> restoreFromFile(String sourcePath) async {
    await _db?.close();
    _db = null;

    final dbPath = await getDatabasesPath();
    final dest = File(p.join(dbPath, 'fork.db'));
    // Drop any WAL/SHM sidecars from the pre-restore DB so the restored
    // file opens cleanly instead of replaying stale WAL frames over it.
    for (final suffix in ['-wal', '-shm']) {
      final f = File('${dest.path}$suffix');
      if (f.existsSync()) f.deleteSync();
    }
    await File(sourcePath).copy(dest.path);

    // Re-open so subsequent calls see the restored data immediately.
    _db = await _open();
  }

  Future<bool> hasStoragePermission() async {
    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await Permission.storage.isGranted) return true;
    return false;
  }

  Future<bool> requestStoragePermission() async {
    final manage = await Permission.manageExternalStorage.request();
    if (manage.isGranted) return true;
    final legacy = await Permission.storage.request();
    return legacy.isGranted;
  }

  Future<void> _backupToSyncFolder() async {
    final folder = await getSyncFolder();
    if (folder == null || folder.isEmpty) return;
    if (!await hasStoragePermission()) return;

    final db = await _database;
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE);');

    final dir = Directory(folder);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final dbPath = await getDatabasesPath();
    final src = File(p.join(dbPath, 'fork.db'));
    final dst = File(p.join(folder, 'fork.db'));
    // writeAsBytes, not File.copy - copy preserves source mtime on
    // Android's FUSE filesystem.
    await dst.writeAsBytes(await src.readAsBytes(), flush: true);
  }
}
