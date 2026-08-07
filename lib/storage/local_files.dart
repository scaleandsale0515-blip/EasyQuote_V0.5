import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import '../utils/ids.dart';

class LocalFiles {
  static Future<String> saveImage(File source, String prefix) async {
    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${dir.path}/easyquote_images');
    if (!await imagesDir.exists()) await imagesDir.create(recursive: true);
    final ext = source.path.split('.').last;
    final fileName = '${prefix}_${generateId()}.$ext';
    final dest = File('${imagesDir.path}/$fileName');
    await source.copy(dest.path);
    return dest.path;
  }

  static Future<String?> readImageAsBase64(String path) async {
    if (path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      return base64Encode(await file.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  static Future<String?> writeImageFromBase64(
      String base64Str, String prefix, String ext) async {
    try {
      final bytes = base64Decode(base64Str);
      final dir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${dir.path}/easyquote_images');
      if (!await imagesDir.exists()) await imagesDir.create(recursive: true);
      final dest = File('${imagesDir.path}/${prefix}_${generateId()}.$ext');
      await dest.writeAsBytes(bytes);
      return dest.path;
    } catch (_) {
      return null;
    }
  }

  static Future<Directory> exportsDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory('${dir.path}/easyquote_exports');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Writes an auto-backup JSON file to the user-selected folder.
  /// File name format:
  ///   Monthly  → EasyQuote_AB_NOV-2026.json
  ///   Others   → EasyQuote_AB_01-11-2026_15-11-2026.json
  static Future<void> writeAutoBackup(
    Map<String, dynamic> data,
    String freq,
    String folderPath,
    DateTime startDate,
  ) async {
    final now = DateTime.now();
    String fileName;

    if (freq == 'monthly') {
      const months = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
      fileName = 'EasyQuote_AB_${months[now.month - 1]}-${now.year}.json';
    } else {
      String fmt(DateTime d) =>
          '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
      fileName = 'EasyQuote_AB_${fmt(startDate)}_${fmt(now)}.json';
    }

    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);

    // Try writing to the user-selected folder first.
    // Falls back to app documents directory if the path is no longer
    // accessible (e.g. SD card removed).
    try {
      final file = File('$folderPath/$fileName');
      await file.writeAsString(jsonStr);
    } catch (_) {
      final fallbackDir = await getApplicationDocumentsDirectory();
      final file = File('${fallbackDir.path}/$fileName');
      await file.writeAsString(jsonStr);
    }
  }
}
