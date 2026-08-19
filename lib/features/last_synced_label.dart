import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/last_synced.dart';

/// "Synced 3m ago" under the AppBar title - re-renders every 30s on its
/// own timer so the label stays fresh even if nothing else on screen
/// triggers a rebuild. Turns amber past an hour stale, since that's
/// usually a sign refresh has been silently failing (offline, expired
/// token, backend down) rather than "just haven't reopened the app".
class LastSyncedLabel extends ConsumerStatefulWidget {
  const LastSyncedLabel({super.key});

  @override
  ConsumerState<LastSyncedLabel> createState() => _LastSyncedLabelState();
}

class _LastSyncedLabelState extends ConsumerState<LastSyncedLabel> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _label(DateTime? t) {
    if (t == null) return 'Not synced yet';
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return 'Synced just now';
    if (diff.inMinutes < 60) return 'Synced ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Synced ${diff.inHours}h ago';
    return 'Synced ${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final lastSynced = ref.watch(lastSyncedProvider);
    final stale = lastSynced == null || DateTime.now().difference(lastSynced).inHours >= 1;
    return Text(
      _label(lastSynced),
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: stale ? Colors.amber.shade200 : Colors.white70),
    );
  }
}
