import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../data/app_lock.dart';
import '../../data/app_settings.dart';
import '../../data/config_backup_service.dart';
import '../../data/local_db.dart';
import '../../data/place_repository.dart';

/// Directory picker with graceful fallback: Android's SAF-backed
/// getDirectoryPath() is known-unreliable on Android 11+ (see Qadaa's
/// Docs.MD) - it can silently return null for an otherwise-valid folder.
/// When that happens this just leaves the field as-is so manual typing
/// still works, rather than presenting the picker as the only way in.
Future<void> _browseForFolder(BuildContext context, TextEditingController controller) async {
  final path = await FilePicker.platform.getDirectoryPath();
  if (path != null) {
    controller.text = path;
  } else if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Couldn't open the folder picker - enter the path manually")),
    );
  }
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;
  late final TextEditingController _folderController;
  late final TextEditingController _dataFolderController;

  bool _backingUp = false;
  bool _restoring = false;
  bool _syncing = false;
  bool _restoringDb = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _urlController = TextEditingController(text: settings.backendUrl ?? '');
    _tokenController = TextEditingController(text: settings.token ?? '');
    _folderController = TextEditingController(text: ConfigBackupService.defaultFolder);
    ConfigBackupService.instance.getFolder().then((folder) {
      if (mounted) setState(() => _folderController.text = folder);
    });
    _dataFolderController = TextEditingController();
    LocalDb.instance.getSyncFolder().then((folder) {
      if (mounted) setState(() => _dataFolderController.text = folder ?? '');
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    _folderController.dispose();
    _dataFolderController.dispose();
    super.dispose();
  }

  Future<void> _saveDataFolder() async {
    final folder = _dataFolderController.text.trim();
    if (folder.isEmpty) return;
    if (!await LocalDb.instance.hasStoragePermission()) {
      final granted = await LocalDb.instance.requestStoragePermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Storage permission required')),
          );
        }
        return;
      }
    }
    await LocalDb.instance.setSyncFolder(folder);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Database will sync to $folder')),
      );
    }
  }

  Future<void> _restoreDatabase() async {
    final folder = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select the folder containing your fork.db backup',
    );
    if (folder == null) return;

    final dbFile = File(p.join(folder, 'fork.db'));
    if (!dbFile.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No fork.db found in $folder')),
        );
      }
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore database?'),
        content: const Text(
          'This replaces ALL current places, ratings, reviews, and photo '
          'references on this device with the backup. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _restoringDb = true);
    await LocalDb.instance.restoreFromFile(dbFile.path);
    // Restoring implies "this is my folder going forward" - keeps future
    // backups and photo lookups pointed at the same place the restore came from.
    await LocalDb.instance.setSyncFolder(folder);
    _dataFolderController.text = folder;
    if (mounted) {
      await ref.read(placeRepositoryProvider.notifier).reloadLocal();
      await ref.read(placeRepositoryProvider.notifier).refresh();
    }
    if (mounted) {
      setState(() => _restoringDb = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Database restored')));
    }
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    await ref.read(placeRepositoryProvider.notifier).refresh();
    if (mounted) {
      setState(() => _syncing = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sync complete')));
    }
  }

  Future<void> _backup() async {
    setState(() => _backingUp = true);
    await ConfigBackupService.instance.setFolder(_folderController.text.trim());
    final result = await ConfigBackupService.instance.backupNow(ref.read(settingsProvider));
    if (!mounted) return;
    setState(() => _backingUp = false);

    final message = switch (result) {
      BackupResult.success => 'Backed up to ${_folderController.text.trim()}',
      BackupResult.permissionDenied => 'Storage permission required',
      BackupResult.error => 'Backup failed — save your settings first',
    };
    if (result == BackupResult.permissionDenied) {
      await ConfigBackupService.instance.requestStoragePermission();
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    final result = await ConfigBackupService.instance.restoreNow(ref.read(settingsProvider.notifier));
    if (!mounted) return;
    setState(() => _restoring = false);

    if (result == RestoreResult.success) {
      final settings = ref.read(settingsProvider);
      _urlController.text = settings.backendUrl ?? '';
      _tokenController.text = settings.token ?? '';
      await ref.read(placeRepositoryProvider.notifier).refresh();
    }

    final message = switch (result) {
      RestoreResult.success => 'Configuration restored',
      RestoreResult.cancelled => null,
      RestoreResult.invalidFile => 'Not a valid fork_config.json backup',
      RestoreResult.error => 'Restore failed',
    };
    if (message != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('fork-backend', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Backend URL',
              hintText: 'https://fork.tail.example.org',
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenController,
            decoration: const InputDecoration(labelText: 'Bearer token'),
            obscureText: true,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () async {
              final url = _urlController.text.trim().replaceAll(RegExp(r'/+$'), '');
              final token = _tokenController.text.trim();
              await ref.read(settingsProvider.notifier).save(backendUrl: url, token: token);
              if (context.mounted) await ref.read(placeRepositoryProvider.notifier).refresh();
            },
            child: const Text('Save'),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 8),
          const Text('Security', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Consumer(
            builder: (context, ref, _) {
              final lockEnabled = ref.watch(appLockEnabledProvider);
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Require unlock to open app'),
                subtitle: const Text('Biometric or device PIN, checked on launch and on returning to the app'),
                value: lockEnabled,
                onChanged: (v) => ref.read(appLockEnabledProvider.notifier).setEnabled(v),
              );
            },
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          const Text('Local database', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            "Fork's real data (ratings, reviews, photos) lives in a SQLite "
            'database on this device. Point it at a Syncthing-watched folder '
            'and every save writes there too, so the NAS stays current.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dataFolderController,
            decoration: InputDecoration(
              labelText: 'Data sync folder',
              hintText: '/storage/emulated/0/Documents/Fork',
              suffixIcon: IconButton(
                icon: const Icon(Icons.folder_open),
                tooltip: 'Browse',
                onPressed: () => _browseForFolder(context, _dataFolderController),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: _saveDataFolder, child: const Text('Set folder')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _syncing ? null : _syncNow,
                  child: _syncing
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sync now'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _restoringDb ? null : _restoreDatabase,
            icon: _restoringDb
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.restore),
            label: const Text('Restore database from a backup folder...'),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 8),
          const Text('Backup', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Saves your backend URL + token to a plain file on this device '
            '(e.g. for Syncthing). The token grants access to fork-backend '
            'only, not Joplin directly, and can be rotated any time — but '
            "it's still a real credential, so don't sync this folder "
            'somewhere you wouldn\'t put a password.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _folderController,
            decoration: InputDecoration(
              labelText: 'Backup folder',
              suffixIcon: IconButton(
                icon: const Icon(Icons.folder_open),
                tooltip: 'Browse',
                onPressed: () => _browseForFolder(context, _folderController),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _backingUp ? null : _backup,
                  child: _backingUp
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Back up now'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _restoring ? null : _restore,
                  child: _restoring
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Restore...'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
