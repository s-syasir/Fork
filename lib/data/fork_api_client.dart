import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/place.dart';
import 'app_settings.dart';

/// Thrown for anything that means "couldn't reach fork-backend at all"
/// (DNS failure, connection refused, timeout) — as opposed to a request
/// that reached the backend but got an error response.
class ForkOfflineException implements Exception {
  @override
  String toString() => "Can't reach fork-backend — check you're on Tailscale (or wherever it's reachable from)";
}

class ForkApiException implements Exception {
  final String message;
  ForkApiException(this.message);
  @override
  String toString() => message;
}

const _requestTimeout = Duration(seconds: 10);

class ForkApiClient {
  final ForkSettings settings;
  ForkApiClient(this.settings);

  Uri _uri(String path) => Uri.parse('${settings.backendUrl}$path');

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${settings.token}',
    'Content-Type': 'application/json',
  };

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(_requestTimeout);
    } on SocketException {
      throw ForkOfflineException();
    } on TimeoutException {
      throw ForkOfflineException();
    } on http.ClientException {
      throw ForkOfflineException();
    }
  }

  /// The note-side view: name/location/region/tier only. Used to detect
  /// entries hand-added in Joplin that the local database doesn't have yet.
  Future<List<NoteEntry>> getNoteEntries() async {
    final res = await _send(() => http.get(_uri('/places'), headers: _headers));
    _checkOk(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['places'] as List<dynamic>)
        .map((e) => NoteEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Pushes a place's name/location/region/tier into the note. Returns the
  /// note-side id (fork-backend's derived slug) for linking back via
  /// [Place.noteLineKey].
  Future<String> pushNewEntry(NoteEntry entry) async {
    final res = await _send(
      () => http.post(_uri('/places'), headers: _headers, body: jsonEncode(entry.toJson())),
    );
    _checkOk(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['place'] as Map<String, dynamic>)['id'] as String;
  }

  Future<String> pushUpdatedEntry(String noteLineKey, NoteEntry entry) async {
    final res = await _send(
      () => http.patch(_uri('/places/$noteLineKey'), headers: _headers, body: jsonEncode(entry.toJson())),
    );
    _checkOk(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['place'] as Map<String, dynamic>)['id'] as String;
  }

  Future<({double? lat, double? lng, String? address})> geocode(String name, String location) async {
    final res = await _send(
      () => http.post(_uri('/geocode'), headers: _headers, body: jsonEncode({'name': name, 'location': location})),
    );
    _checkOk(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (
      lat: (data['lat'] as num?)?.toDouble(),
      lng: (data['lng'] as num?)?.toDouble(),
      address: data['address'] as String?,
    );
  }

  /// Removes a place from the note entirely.
  Future<void> deleteEntry(String noteLineKey) async {
    final res = await _send(() => http.delete(_uri('/places/$noteLineKey'), headers: _headers));
    _checkOk(res);
  }

  /// Nearby restaurants from OpenStreetMap (via the backend's Overpass
  /// proxy) - no ratings/trending data, just "what's around here that OSM
  /// knows about." See Fork-backend/src/overpass.ts for why.
  Future<List<({String name, double lat, double lng, String? cuisine, String? address})>> explore(
    double lat,
    double lng,
  ) async {
    final res = await _send(
      () => http.post(_uri('/explore'), headers: _headers, body: jsonEncode({'lat': lat, 'lng': lng})),
    );
    _checkOk(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['places'] as List<dynamic>).map((e) {
      final m = e as Map<String, dynamic>;
      return (
        name: m['name'] as String,
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        cuisine: m['cuisine'] as String?,
        address: m['address'] as String?,
      );
    }).toList();
  }

  /// Resolves a display address from coordinates - used to backfill places
  /// whose address never got saved (e.g. imported before the field existed).
  Future<String?> reverseGeocode(double lat, double lng) async {
    final res = await _send(
      () => http.post(_uri('/reverse-geocode'), headers: _headers, body: jsonEncode({'lat': lat, 'lng': lng})),
    );
    _checkOk(res);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['address'] as String?;
  }

  void _checkOk(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ForkApiException('fork-backend request failed: ${res.statusCode} ${res.body}');
    }
  }
}
