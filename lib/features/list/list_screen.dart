import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:share_plus/share_plus.dart';
import '../../data/place_repository.dart';
import '../../models/place.dart';
import '../../models/tier_style.dart';
import '../place_detail_sheet.dart';
import '../recommendations.dart';
import '../share_text.dart';

final _regionFilterProvider = StateProvider<String?>((ref) => null);
final _tierFilterProvider = StateProvider<Tier?>((ref) => null);
final _tagFilterProvider = StateProvider<String?>((ref) => null);
final _locationFilterProvider = StateProvider<String?>((ref) => null);
final _unratedOnlyProvider = StateProvider<bool>((ref) => false);
final _unpinnedOnlyProvider = StateProvider<bool>((ref) => false);
final _searchQueryProvider = StateProvider<String>((ref) => '');

class ListScreen extends ConsumerWidget {
  const ListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placesAsync = ref.watch(placeRepositoryProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(placeRepositoryProvider.notifier).refresh(),
      child: placesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('$e'))]),
        data: (places) {
          final regionFilter = ref.watch(_regionFilterProvider);
          final tierFilter = ref.watch(_tierFilterProvider);
          final tagFilter = ref.watch(_tagFilterProvider);
          final locationFilter = ref.watch(_locationFilterProvider);
          final unratedOnly = ref.watch(_unratedOnlyProvider);
          final unpinnedOnly = ref.watch(_unpinnedOnlyProvider);
          final query = ref.watch(_searchQueryProvider).trim().toLowerCase();
          final activeFilterCount = (regionFilter != null ? 1 : 0) +
              (tierFilter != null ? 1 : 0) +
              (tagFilter != null ? 1 : 0) +
              (locationFilter != null ? 1 : 0) +
              (unratedOnly ? 1 : 0) +
              (unpinnedOnly ? 1 : 0);

          final filtered = places.where((p) {
            if (regionFilter != null && p.region != regionFilter) return false;
            if (tierFilter != null && p.tier != tierFilter) return false;
            if (tagFilter != null && !p.tags.contains(tagFilter)) return false;
            if (locationFilter != null && p.location != locationFilter) return false;
            if (unratedOnly && p.score != null) return false;
            if (unpinnedOnly && p.address != null && p.address!.trim().isNotEmpty) return false;
            if (query.isNotEmpty &&
                !p.name.toLowerCase().contains(query) &&
                !p.location.toLowerCase().contains(query) &&
                !p.region.toLowerCase().contains(query) &&
                !p.tags.any((t) => t.toLowerCase().contains(query))) {
              return false;
            }
            return true;
          }).toList();

          final grouped = <String, List<Place>>{};
          for (final p in filtered) {
            grouped.putIfAbsent(p.region, () => []).add(p);
          }
          final sortedRegions = grouped.keys.toList()..sort();

          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search places...',
                          isDense: true,
                        ),
                        onChanged: (v) => ref.read(_searchQueryProvider.notifier).state = v,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Badge(
                      isLabelVisible: activeFilterCount > 0,
                      label: Text('$activeFilterCount'),
                      child: IconButton(
                        icon: const Icon(Icons.filter_list),
                        tooltip: 'Filter',
                        onPressed: () => _showFilterSheet(context, ref, places),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.share),
                      tooltip: 'Share this list',
                      onPressed: filtered.isEmpty
                          ? null
                          : () => Share.share(buildPlaceListShareText(filtered)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Only surface recommendations on the unfiltered, unsearched
              // view - they're a discovery aid, not something to fight for
              // space with an active filter/search the user already chose.
              if (regionFilter == null &&
                  tierFilter == null &&
                  !unratedOnly &&
                  !unpinnedOnly &&
                  query.isEmpty)
                _RecommendedSection(places: places),
              for (final region in sortedRegions)
                _RegionSection(region: region, places: grouped[region]!),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }

  void _showFilterSheet(BuildContext context, WidgetRef ref, List<Place> places) {
    final regions = places.map((p) => p.region).toSet().toList()..sort();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final regionFilter = ref.watch(_regionFilterProvider);
          final tierFilter = ref.watch(_tierFilterProvider);
          final tagFilter = ref.watch(_tagFilterProvider);
          final locationFilter = ref.watch(_locationFilterProvider);
          final unratedOnly = ref.watch(_unratedOnlyProvider);
          final unpinnedOnly = ref.watch(_unpinnedOnlyProvider);

          final regionTags = regionFilter == null
              ? const <String>[]
              : (places.where((p) => p.region == regionFilter).expand((p) => p.tags).toSet().toList()..sort());
          final regionLocations = regionFilter == null
              ? const <String>[]
              : (places
                  .where((p) => p.region == regionFilter && p.location.trim().isNotEmpty)
                  .map((p) => p.location)
                  .toSet()
                  .toList()
                ..sort());

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Filters', style: Theme.of(context).textTheme.titleMedium),
                          TextButton(
                            onPressed: () {
                              ref.read(_regionFilterProvider.notifier).state = null;
                              ref.read(_tierFilterProvider.notifier).state = null;
                              ref.read(_tagFilterProvider.notifier).state = null;
                              ref.read(_locationFilterProvider.notifier).state = null;
                              ref.read(_unratedOnlyProvider.notifier).state = false;
                              ref.read(_unpinnedOnlyProvider.notifier).state = false;
                            },
                            child: const Text('Clear all'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('Region', style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final r in regions)
                            ChoiceChip(
                              label: Text(r),
                              selected: regionFilter == r,
                              onSelected: (_) {
                                final newRegion = regionFilter == r ? null : r;
                                ref.read(_regionFilterProvider.notifier).state = newRegion;
                                // Tags and locations are scoped to a region
                                // - deselecting or switching regions can
                                // leave either pointing at something that
                                // no longer applies, so both clear with it.
                                ref.read(_tagFilterProvider.notifier).state = null;
                                ref.read(_locationFilterProvider.notifier).state = null;
                              },
                            ),
                        ],
                      ),
                      if (regionFilter != null) ...[
                        const SizedBox(height: 16),
                        Text('Tags in $regionFilter', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 8),
                        if (regionTags.isEmpty)
                          Text(
                            'No tags yet - these come from #### headings in the note, or the Tags field in Add/Edit.',
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        else
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final tag in regionTags)
                                ChoiceChip(
                                  label: Text(tag),
                                  selected: tagFilter == tag,
                                  onSelected: (_) =>
                                      ref.read(_tagFilterProvider.notifier).state = tagFilter == tag ? null : tag,
                                ),
                            ],
                          ),
                        if (regionLocations.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Text('Neighborhoods in $regionFilter', style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final loc in regionLocations)
                                ChoiceChip(
                                  label: Text(loc),
                                  selected: locationFilter == loc,
                                  onSelected: (_) => ref.read(_locationFilterProvider.notifier).state =
                                      locationFilter == loc ? null : loc,
                                ),
                            ],
                          ),
                        ],
                      ],
                      const SizedBox(height: 16),
                      Text('Tier', style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final t in Tier.values)
                            ChoiceChip(
                              label: Text(tierLabel(t)),
                              selected: tierFilter == t,
                              selectedColor: tierColor(t).withValues(alpha: 0.25),
                              onSelected: (_) =>
                                  ref.read(_tierFilterProvider.notifier).state = tierFilter == t ? null : t,
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('Unrated only'),
                            selected: unratedOnly,
                            onSelected: (v) => ref.read(_unratedOnlyProvider.notifier).state = v,
                          ),
                          FilterChip(
                            label: const Text('Unpinned only'),
                            selected: unpinnedOnly,
                            onSelected: (v) => ref.read(_unpinnedOnlyProvider.notifier).state = v,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RecommendedSection extends StatelessWidget {
  final List<Place> places;
  const _RecommendedSection({required this.places});

  @override
  Widget build(BuildContext context) {
    final recommended = recommendedToTryPlaces(places);
    if (recommended.isEmpty) return const SizedBox.shrink();

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Recommended for you', style: Theme.of(context).textTheme.titleMedium),
            ),
          ],
        ),
        children: [
          for (final place in recommended)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: tierColor(place.tier),
                child: const Icon(Icons.restaurant, color: Colors.white, size: 16),
              ),
              title: Text(place.name),
              subtitle: Text(
                '${place.region} · ${place.location}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => showPlaceDetail(context, place),
            ),
        ],
      ),
    );
  }
}

class _RegionSection extends ConsumerWidget {
  final String region;
  final List<Place> places;
  const _RegionSection({required this.region, required this.places});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Theme(
      // Kill the default divider ExpansionTile draws around itself so
      // regions read as one continuous list, not boxed-off cards.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(
          children: [
            Expanded(
              child: Text(region, style: Theme.of(context).textTheme.titleMedium),
            ),
            Text('${places.length}', style: Theme.of(context).textTheme.bodySmall),
            IconButton(
              icon: const Icon(Icons.share, size: 20),
              tooltip: 'Share $region',
              onPressed: () => Share.share(buildPlaceListShareText(places)),
            ),
          ],
        ),
        children: [
          for (final place in places)
            Slidable(
              key: ValueKey(place.id),
              endActionPane: ActionPane(
                motion: const DrawerMotion(),
                extentRatio: 0.75,
                children: [
                  SlidableAction(
                    onPressed: (_) => ref.read(placeRepositoryProvider.notifier).quickRate(place.id, Tier.loved),
                    backgroundColor: tierColor(Tier.loved),
                    foregroundColor: Colors.white,
                    icon: Icons.favorite,
                    label: 'Loved',
                  ),
                  SlidableAction(
                    onPressed: (_) => ref.read(placeRepositoryProvider.notifier).quickRate(place.id, Tier.liked),
                    backgroundColor: tierColor(Tier.liked),
                    foregroundColor: Colors.white,
                    icon: Icons.thumb_up,
                    label: 'Liked',
                  ),
                  SlidableAction(
                    onPressed: (_) => ref.read(placeRepositoryProvider.notifier).quickRate(place.id, Tier.meh),
                    backgroundColor: tierColor(Tier.meh),
                    foregroundColor: Colors.white,
                    icon: Icons.thumb_down,
                    label: 'Meh',
                  ),
                ],
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: tierColor(place.tier),
                  child: Text(
                    place.score?.toStringAsFixed(0) ?? '?',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                title: Text(place.name),
                subtitle: Text(
                  place.address != null && place.address!.isNotEmpty
                      ? '${place.location} · ${place.address}'
                      : place.location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => showPlaceDetail(context, place),
              ),
            ),
        ],
      ),
    );
  }
}
