import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_settings.dart';

enum BackupResult { success, permissionDenied, error }

enum RestoreResult { success, cancelled, invalidFile, error }

const _fileName = 'fork_config.json';
const _folderSettingKey = 'fork_backup_folder';

/// Backs up/restores Fork's own settings (backend URL + bearer token) —
/// same "plain file in Download/" convention as Qadaa/Lockout, for
/// Syncthing-style personal backup. Unlike those apps' data exports, the
/// file this writes contains a real credential (the fork-backend bearer
/// token) in plain text — low blast radius since that token only grants
/// access to fork-backend, not Joplin itself, and is trivially rotatable,
/// but worth knowing before syncing Download/ somewhere less trusted.
class ConfigBackupService {
  ConfigBackupService._();
  static final ConfigBackupService instance = ConfigBackupService._();

  static const String defaultFolder = '/storage/emulated/0/Download/Fork';

  Future<String> getFolder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_folderSettingKey) ?? defaultFolder;
  }

  Future<void> setFolder(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_folderSettingKey, path);
  }

  Future<void> resetFolder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_folderSettingKey);
  }

  Future<bool> hasStoragePermission() async {
    if (await Permission.manageExternalStorage.isGranted) return true;
    // Android <= 9: legacy WRITE permission is enough
    if (await Permission.storage.isGranted) return true;
    return false;
  }

  Future<bool> requestStoragePermission() async {
    final manage = await Permission.manageExternalStorage.request();
    if (manage.isGranted) return true;
    final legacy = await Permission.storage.request();
    return legacy.isGranted;
  }

  Future<BackupResult> backupNow(ForkSettings settings) async {
    if (!await hasStoragePermission()) return BackupResult.permissionDenied;
    if (!settings.isConfigured) return BackupResult.error;

    try {
      final folder = await getFolder();
      final dir = Directory(folder);
      if (!dir.existsSync()) dir.createSync(recursive: true);

      final json = jsonEncode({
        'backendUrl': settings.backendUrl,
        'token': settings.token,
      });

      final dst = File(p.join(folder, _fileName));
      // writeAsBytes, not File.copy — copy preserves source mtime on
      // Android's FUSE filesystem, writeAsBytes doesn't.
      await dst.writeAsBytes(utf8.encode(json), flush: true);
      return BackupResult.success;
    } catch (_) {
      return BackupResult.error;
    }
  }

  Future<RestoreResult> restoreNow(SettingsNotifier notifier) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select fork_config.json backup',
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return RestoreResult.cancelled;

    final srcPath = result.files.single.path;
    if (srcPath == null) return RestoreResult.error;

    try {
      final content = await File(srcPath).readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final backendUrl = data['backendUrl'] as String?;
      final token = data['token'] as String?;
      if (backendUrl == null || token == null || backendUrl.isEmpty || token.isEmpty) {
        return RestoreResult.invalidFile;
      }
      await notifier.save(backendUrl: backendUrl, token: token);
      return RestoreResult.success;
    } catch (_) {
      return RestoreResult.error;
    }
  }
}
