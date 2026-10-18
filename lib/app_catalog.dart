import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Persists the installed-app catalog as a local JSON file:
///   { "com.instagram.android": {"name": "Instagram", "type": "Social", ...} }
///
/// Icons stay in memory (fetched fresh each pull) — base64-ing ~150 PNGs
/// would bloat the file for zero benefit since installed_apps reloads fast.
class AppCatalogStore {
  static const _fileName = 'app_catalog.json';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<void> save(Map<String, InstalledApp> catalog) async {
    final json = {
      for (final e in catalog.entries) e.key: e.value.toJson(),
    };
    (await _file()).writeAsStringSync(jsonEncode(json));
  }

  /// Loads the last-saved catalog. Icons are null for loaded entries.
  static Future<Map<String, InstalledApp>> load() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return {};
      final map = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          e.key: InstalledApp(
            packageName: e.key,
            label: (e.value['name'] as String?) ?? e.key,
            type: (e.value['type'] as String?) ?? 'Undefined',
            isSystem: (e.value['system'] as bool?) ?? false,
          ),
      };
    } catch (_) {
      return {};
    }
  }
}
