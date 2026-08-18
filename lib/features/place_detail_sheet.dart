import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../data/local_db.dart';
import '../data/place_repository.dart';
import '../home_shell.dart';
import '../models/place.dart';
import '../models/tier_style.dart';
import 'add_edit/add_edit_screen.dart';
import 'share_text.dart';

Future<void> _navigate(BuildContext context, Place place, {required bool viaGoogleMaps}) async {
  if (place.lat == null || place.lng == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("No coordinates for this place yet - can't navigate")),
    );
    return;
  }

  final intent = viaGoogleMaps
      ? AndroidIntent(
          action: 'action_view',
          package: 'com.google.android.apps.maps',
          data: 'google.navigation:q=${place.lat},${place.lng}',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
        )
      : AndroidIntent(
          action: 'action_view',
          package: 'app.organicmaps',
          data: 'geo:${place.lat},${place.lng}?q=${place.lat},${place.lng}(${Uri.encodeComponent(place.name)})',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
        );

  try {
    await intent.launch();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${viaGoogleMaps ? "Google Maps" : "Organic Maps"} not installed')),
      );
    }
  }
}

/// Opens the place's actual Google Maps business listing (name+address
/// text search) rather than starting a route - lets the user see reviews,
/// hours, or hit "Reserve a table" without committing to navigation.
Future<void> _openGmapsInfo(BuildContext context, Place place) async {
  final query = [place.name, if (place.address != null && place.address!.isNotEmpty) place.address else place.location]
      .where((s) => s != null && s.isNotEmpty)
      .join(', ');

  final intent = AndroidIntent(
    action: 'action_view',
    package: 'com.google.android.apps.maps',
    data: 'geo:0,0?q=${Uri.encodeComponent(query)}',
    flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
  );

  try {
    await intent.launch();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google Maps not installed')),
      );
    }
  }
}

void showPlaceDetail(BuildContext context, Place place) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => _PlaceDetailSheet(place: place),
  );
}

class _PlaceDetailSheet extends ConsumerStatefulWidget {
  final Place place;
  const _PlaceDetailSheet({required this.place});

  @override
  ConsumerState<_PlaceDetailSheet> createState() => _PlaceDetailSheetState();
}

class _PlaceDetailSheetState extends ConsumerState<_PlaceDetailSheet> {
  late Future<List<Visit>> _visitsFuture;
  List<Visit> _visits = [];

  @override
  void initState() {
    super.initState();
    _visitsFuture = LocalDb.instance.getVisits(widget.place.id)
      ..then((v) {
        if (mounted) setState(() => _visits = v);
      });
  }

  void _share() {
    Share.share(buildPlaceShareText(widget.place, _visits));
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${widget.place.name}?'),
        content: const Text('This removes it from the note too, if it was ever synced there. Cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(placeRepositoryProvider.notifier).deletePlace(widget.place);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final place = widget.place;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(place.name, style: Theme.of(context).textTheme.headlineSmall),
                  ),
                  Chip(
                    label: Text(tierLabel(place.tier)),
                    backgroundColor: tierColor(place.tier).withValues(alpha: 0.15),
                    labelStyle: TextStyle(color: tierColor(place.tier), fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(place.location, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(place.region, style: Theme.of(context).textTheme.bodySmall),
                  if (place.price != null) ...[
                    const SizedBox(width: 8),
                    Text('· ${priceLabel(place.price!)}', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
              if (place.address != null && place.address!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(place.address!, style: Theme.of(context).textTheme.bodySmall),
              ],
              if (place.score != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (var i = 1; i <= 10; i++)
                      Icon(
                        place.score! >= i
                            ? Icons.star
                            : place.score! >= i - 0.5
                                ? Icons.star_half
                                : Icons.star_border,
                        size: 18,
                        color: Colors.amber.shade700,
                      ),
                    const SizedBox(width: 6),
                    Text('${place.score!.toStringAsFixed(1)}/10 avg'),
                  ],
                ),
              ],
              if (place.noteSyncPending) ...[
                const SizedBox(height: 8),
                const Row(
                  children: [
                    Icon(Icons.cloud_off, size: 16),
                    SizedBox(width: 4),
                    Text('Not yet synced to the note', style: TextStyle(fontStyle: FontStyle.italic)),
                  ],
                ),
              ],
              if (place.tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 6, children: place.tags.map((t) => Chip(label: Text(t))).toList()),
              ],
              FutureBuilder<List<Visit>>(
                future: _visitsFuture,
                builder: (context, snapshot) {
                  final visits = snapshot.data ?? [];
                  if (visits.isEmpty) return const SizedBox.shrink();
                  final sorted = [...visits]..sort((a, b) {
                    if (a.date == null) return 1;
                    if (b.date == null) return -1;
                    return b.date!.compareTo(a.date!);
                  });
                  return Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Visits', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 6),
                        for (final v in sorted)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 90,
                                  child: Text(
                                    v.date == null ? 'No date' : DateFormat.yMMMd().format(v.date!),
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (v.rating != null)
                                        Text('${v.rating!.toStringAsFixed(1)}/10',
                                            style: const TextStyle(fontWeight: FontWeight.bold)),
                                      if (v.description != null && v.description!.isNotEmpty)
                                        Text(v.description!, style: Theme.of(context).textTheme.bodySmall),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              FutureBuilder<List<Photo>>(
                future: LocalDb.instance.getPhotos(place.id),
                builder: (context, snapshot) {
                  final photos = snapshot.data ?? [];
                  if (photos.isEmpty) return const SizedBox.shrink();
                  return FutureBuilder<String>(
                    future: LocalDb.instance.photosDirectory(),
                    builder: (context, dirSnapshot) {
                      final dir = dirSnapshot.data;
                      if (dir == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SizedBox(
                          height: 112,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: photos.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 8),
                            itemBuilder: (context, i) => SizedBox(
                              width: 90,
                              child: Column(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      File(p.join(dir, photos[i].fileName)),
                                      width: 90,
                                      height: 90,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  if (photos[i].dishName != null && photos[i].dishName!.isNotEmpty)
                                    Text(
                                      photos[i].dishName!,
                                      style: Theme.of(context).textTheme.bodySmall,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => AddEditScreen(existing: place)),
                      );
                    },
                    child: const Text('Edit'),
                  ),
                  OutlinedButton(
                    onPressed: () => _navigate(context, place, viaGoogleMaps: true),
                    child: const Text('Navigate (GMaps)'),
                  ),
                  OutlinedButton(
                    onPressed: () => _navigate(context, place, viaGoogleMaps: false),
                    child: const Text('Navigate (Organic Maps)'),
                  ),
                  OutlinedButton(
                    onPressed: () => _openGmapsInfo(context, place),
                    child: const Text('GMaps Info'),
                  ),
                  OutlinedButton.icon(
                    onPressed: place.lat == null || place.lng == null
                        ? null
                        : () {
                            ref.read(mapFocusPlaceProvider.notifier).state = place;
                            ref.read(selectedTabProvider.notifier).state = 0;
                            Navigator.of(context).pop();
                          },
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: const Text('View on Map'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _share,
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Share'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _delete,
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
