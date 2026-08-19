import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'data/app_settings.dart';
import 'data/place_repository.dart';
import 'features/add_edit/add_edit_screen.dart';
import 'features/last_synced_label.dart';
import 'features/list/list_screen.dart';
import 'features/map/map_screen.dart';
import 'features/settings/settings_screen.dart';
import 'models/place.dart';

/// Which bottom-nav tab is showing - a provider (not local State) so
/// other screens (e.g. "View on map" from a place detail sheet) can
/// switch tabs without needing a reference to HomeShell itself.
final selectedTabProvider = StateProvider<int>((ref) => 0);

/// A place the map should center on next time it builds, then clear -
/// set by "View on map" elsewhere, consumed once by MapScreen.
final mapFocusPlaceProvider = StateProvider<Place?>((ref) => null);

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    if (!settings.isConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('Fork')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Point Fork at your fork-backend to get started.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final syncError = ref.watch(syncErrorProvider);
    final hasCachedData = ref.watch(placeRepositoryProvider).hasValue;
    final showStaleBanner = syncError != null && hasCachedData;
    final index = ref.watch(selectedTabProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [Text('Fork'), LastSyncedLabel()],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (showStaleBanner)
            MaterialBanner(
              backgroundColor: Colors.amber.shade100,
              leading: const Icon(Icons.cloud_off),
              content: const Text("Showing cached data — can't reach fork-backend right now."),
              actions: [
                TextButton(
                  onPressed: () => ref.read(placeRepositoryProvider.notifier).refresh(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          Expanded(
            child: IndexedStack(
              index: index,
              children: const [MapScreen(), ListScreen()],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AddEditScreen()),
        ),
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => ref.read(selectedTabProvider.notifier).state = i,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.list), label: 'List'),
        ],
      ),
    );
  }
}
