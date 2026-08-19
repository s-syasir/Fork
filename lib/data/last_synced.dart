import 'package:flutter_riverpod/flutter_riverpod.dart';

/// When the place list was last successfully pulled from fork-backend. A
/// separate provider (not part of the repository's own state) so the
/// AppBar label can watch it without depending on the full place list.
final lastSyncedProvider = StateProvider<DateTime?>((ref) => null);
