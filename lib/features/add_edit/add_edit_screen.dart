import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import '../../data/local_db.dart';
import '../../data/place_repository.dart';
import '../../models/place.dart';
import '../star_rating.dart';

class AddEditScreen extends ConsumerStatefulWidget {
  final Place? existing;

  // For starting a new place from an Explore result - ignored when
  // [existing] is set.
  final String? prefillName;
  final String? prefillAddress;
  final String? prefillTag;

  const AddEditScreen({
    super.key,
    this.existing,
    this.prefillName,
    this.prefillAddress,
    this.prefillTag,
  });

  @override
  ConsumerState<AddEditScreen> createState() => _AddEditScreenState();
}

/// A single visit row being edited on screen - mutable, holds its own
/// controllers so text fields don't lose focus/cursor on rebuild.
class _VisitDraft {
  String? id;
  DateTime? date;
  double? rating;
  late final TextEditingController description;

  _VisitDraft({this.id, this.date, this.rating, String? description})
    : description = TextEditingController(text: description ?? '');

  factory _VisitDraft.fromVisit(Visit v) =>
      _VisitDraft(id: v.id, date: v.date, rating: v.rating, description: v.description);

  void dispose() => description.dispose();
}

class _AddEditScreenState extends ConsumerState<AddEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _region;
  late final TextEditingController _location;
  late final TextEditingController _address;
  late final TextEditingController _tags;

  // Generated up front (even for a brand-new place) so photos can be
  // attached before the first Save completes.
  late final String _placeId;

  PriceTier? _price;
  List<Photo> _photos = [];
  List<String> _allRegions = [];
  List<({String region, String location})> _allRegionLocations = [];
  List<String> _allTags = [];
  // Text preceding the tag fragment currently being typed (everything up
  // through the last confirmed ", ") - set by _tagOptions each rebuild so
  // displayStringForOption/onSelected can splice the picked tag back in
  // without clobbering tags already typed before it.
  String _tagsPrefix = '';
  final List<_VisitDraft> _visits = [];
  bool _saving = false;
  late bool _loadingVisits;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _placeId = e?.id ?? newLocalId();
    _loadingVisits = e != null;
    _name = TextEditingController(text: e?.name ?? widget.prefillName ?? '');
    _region = TextEditingController(text: e?.region ?? '');
    _location = TextEditingController(text: e?.location ?? '');
    _address = TextEditingController(text: e?.address ?? widget.prefillAddress ?? '');
    _tags = TextEditingController(text: e?.tags.join(', ') ?? widget.prefillTag ?? '');
    _price = e?.price;
    _loadPhotos();
    _loadRegions();
    if (e != null) {
      _loadVisits(e.id);
    }
  }

  Future<void> _loadPhotos() async {
    final photos = await LocalDb.instance.getPhotos(_placeId);
    if (mounted) setState(() => _photos = photos);
  }

  Future<void> _loadRegions() async {
    final regions = await ref.read(placeRepositoryProvider.notifier).getAllRegions();
    if (mounted) setState(() => _allRegions = regions);
    final pairs = await ref.read(placeRepositoryProvider.notifier).getAllRegionLocationPairs();
    if (mounted) setState(() => _allRegionLocations = pairs);
    final tags = await ref.read(placeRepositoryProvider.notifier).getAllTags();
    if (mounted) setState(() => _allTags = tags);
  }

  /// Suggestions for whatever tag fragment is currently being typed (the
  /// text after the last comma), also updates [_tagsPrefix] as a side
  /// effect so the picked suggestion can be spliced back into the rest of
  /// the field.
  List<String> _tagOptions(TextEditingValue value) {
    final text = value.text;
    final lastComma = text.lastIndexOf(',');
    final fragment = (lastComma == -1 ? text : text.substring(lastComma + 1)).trim().toLowerCase();
    _tagsPrefix = lastComma == -1 ? '' : '${text.substring(0, lastComma + 1)} ';
    final alreadyTyped = text.split(',').map((t) => t.trim().toLowerCase()).toSet();
    final candidates = _allTags.where((t) => !alreadyTyped.contains(t.toLowerCase()));
    if (fragment.isEmpty) return candidates.toList();
    return candidates.where((t) => t.toLowerCase().contains(fragment)).toList();
  }

  Future<void> _loadVisits(String placeId) async {
    final visits = await ref.read(placeRepositoryProvider.notifier).getVisits(placeId);
    if (!mounted) return;
    setState(() {
      _visits.addAll(visits.map(_VisitDraft.fromVisit));
      _loadingVisits = false;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _region.dispose();
    _location.dispose();
    _address.dispose();
    _tags.dispose();
    for (final v in _visits) {
      v.dispose();
    }
    super.dispose();
  }

  Future<void> _addPhoto(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (picked == null) return;

    final dir = await LocalDb.instance.photosDirectory();
    final fileName = '${newLocalId()}${p.extension(picked.path)}';
    await File(picked.path).copy(p.join(dir, fileName));
    await LocalDb.instance.addPhoto(_placeId, fileName);
    await _loadPhotos();
  }

  Future<void> _editDishName(Photo photo) async {
    final controller = TextEditingController(text: photo.dishName ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('What dish is this?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Spicy tuna roll'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(''), child: const Text('Clear')),
          TextButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (result == null) return;
    await LocalDb.instance.setPhotoDishName(photo.id, result.isEmpty ? null : result);
    await _loadPhotos();
  }

  Future<void> _pickVisitDate(_VisitDraft visit) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: visit.date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => visit.date = picked);
  }

  void _addVisit() {
    setState(() => _visits.add(_VisitDraft(date: DateTime.now())));
  }

  void _removeVisit(_VisitDraft visit) {
    setState(() {
      _visits.remove(visit);
      visit.dispose();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(placeRepositoryProvider.notifier).savePlace(PlaceDraft(
        existingId: _placeId,
        name: _name.text.trim(),
        region: _region.text.trim().isEmpty ? 'Unsorted' : _region.text.trim(),
        location: _location.text.trim(),
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        price: _price,
        tags: _tags.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
      ));
      await ref.read(placeRepositoryProvider.notifier).saveVisits(
        _placeId,
        _visits
            .map((v) => Visit(
                  id: v.id ?? newLocalId(),
                  placeId: _placeId,
                  date: v.date,
                  rating: v.rating,
                  description: v.description.text.trim().isEmpty ? null : v.description.text.trim(),
                  createdAt: DateTime.now(),
                ))
            .toList(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing != null ? 'Edit place' : 'Add place')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            Autocomplete<String>(
              initialValue: TextEditingValue(text: _region.text),
              optionsBuilder: (value) {
                if (value.text.trim().isEmpty) return _allRegions;
                return _allRegions.where((r) => r.toLowerCase().contains(value.text.trim().toLowerCase()));
              },
              onSelected: (selection) => _region.text = selection,
              fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: (value) => _region.text = value,
                  decoration: const InputDecoration(
                    labelText: 'Region/List name',
                    hintText: 'e.g. Seattle Area, Vancouver Area, NYC',
                    helperText: 'The list this place lives under in the note - usually a city or metro area',
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Autocomplete<String>(
              initialValue: TextEditingValue(text: _location.text),
              optionsBuilder: (value) {
                final regionText = _region.text.trim().toLowerCase();
                final candidates = regionText.isEmpty
                    ? _allRegionLocations.map((p) => p.location)
                    : _allRegionLocations.where((p) => p.region.trim().toLowerCase() == regionText).map((p) => p.location);
                final distinct = candidates.toSet().toList()..sort();
                if (value.text.trim().isEmpty) return distinct;
                return distinct.where((l) => l.toLowerCase().contains(value.text.trim().toLowerCase()));
              },
              onSelected: (selection) => _location.text = selection,
              fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: (value) => _location.text = value,
                  decoration: const InputDecoration(
                    labelText: 'Location',
                    helperText: 'Casual area/neighborhood, just for your own reference',
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(
                labelText: 'Address (optional)',
                helperText: 'Specific street address - used for the map pin, not shown elsewhere',
              ),
            ),
            const SizedBox(height: 16),
            Text('Price', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final tier in PriceTier.values)
                  ChoiceChip(
                    label: Text(priceLabel(tier)),
                    selected: _price == tier,
                    onSelected: (_) => setState(() => _price = _price == tier ? null : tier),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Autocomplete<String>(
              initialValue: TextEditingValue(text: _tags.text),
              optionsBuilder: _tagOptions,
              displayStringForOption: (option) => '$_tagsPrefix$option, ',
              onSelected: (selection) => _tags.text = '$_tagsPrefix$selection, ',
              fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: (value) => _tags.text = value,
                  decoration: const InputDecoration(
                    labelText: 'Tags (comma separated)',
                    helperText: 'Picking a suggestion adds the comma for you',
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text('Visits', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addVisit,
                  icon: const Icon(Icons.add),
                  label: const Text('Add visit'),
                ),
              ],
            ),
            Text(
              "Each visit can have its own date, rating, and notes - the overall rating is the average of every visit you've rated.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (_loadingVisits)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
            else if (_visits.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No visits yet - add one once you\'ve been.'),
              )
            else
              for (final visit in _visits) _VisitCard(visit: visit, onPickDate: _pickVisitDate, onRemove: _removeVisit),
            const SizedBox(height: 20),
            Text('Photos', style: Theme.of(context).textTheme.bodySmall),
            const Text('Tap a photo to name the dish it shows', style: TextStyle(fontSize: 11)),
            const SizedBox(height: 8),
            FutureBuilder<String>(
              future: LocalDb.instance.photosDirectory(),
              builder: (context, snapshot) {
                final dir = snapshot.data;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (dir != null)
                      for (final photo in _photos)
                        GestureDetector(
                          onTap: () => _editDishName(photo),
                          child: SizedBox(
                            width: 80,
                            child: Column(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(p.join(dir, photo.fileName)),
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                if (photo.dishName != null && photo.dishName!.isNotEmpty)
                                  Text(
                                    photo.dishName!,
                                    style: const TextStyle(fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                        ),
                    _AddPhotoButton(onTap: _addPhoto),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisitCard extends StatefulWidget {
  final _VisitDraft visit;
  final Future<void> Function(_VisitDraft) onPickDate;
  final void Function(_VisitDraft) onRemove;

  const _VisitCard({required this.visit, required this.onPickDate, required this.onRemove});

  @override
  State<_VisitCard> createState() => _VisitCardState();
}

class _VisitCardState extends State<_VisitCard> {
  @override
  Widget build(BuildContext context) {
    final visit = widget.visit;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () async {
                      await widget.onPickDate(visit);
                      setState(() {});
                    },
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(visit.date == null ? 'No date set' : DateFormat.yMMMd().format(visit.date!)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => widget.onRemove(visit),
                ),
              ],
            ),
            StarRating(score: visit.rating, onChanged: (v) => setState(() => visit.rating = v)),
            TextFormField(
              controller: visit.description,
              decoration: const InputDecoration(labelText: 'Notes for this visit'),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddPhotoButton extends StatelessWidget {
  final void Function(ImageSource) onTap;
  const _AddPhotoButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showModalBottomSheet(
        context: context,
        builder: (context) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take photo'),
                onTap: () {
                  Navigator.of(context).pop();
                  onTap(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.of(context).pop();
                  onTap(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }
}
