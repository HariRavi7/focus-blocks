import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Saves everything as one JSON file on the device.
///
/// Local-only for milestone 1. Sync (Supabase) replaces this behind the
/// same two methods in milestone 2.
class LocalStore {
  File? _file;

  Future<File> _resolve() async {
    if (_file != null) return _file!;
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    _file = File('${dir.path}/focus_blocks.json');
    return _file!;
  }

  Future<AppData> load() async {
    try {
      final f = await _resolve();
      if (!await f.exists()) return const AppData();
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return const AppData();
      return AppData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // A corrupt file should never brick the app; start fresh.
      return const AppData();
    }
  }

  Future<void> save(AppData data) async {
    final f = await _resolve();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(data.toJson()), flush: true);
    await tmp.rename(f.path);
  }
}
