import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../storage/local_db.dart';
import '../storage/local_files.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  String? _message;

  // Auto-backup state
  String _frequency = 'monthly';
  int _customDays = 30;
  String? _folder;

  @override
  void initState() {
    super.initState();
    _frequency = LocalDB.instance.getAutoBackupFrequency();
    _customDays = LocalDB.instance.getAutoBackupCustomDays();
    _folder = LocalDB.instance.getAutoBackupFolder();
  }

  Future<void> _export() async {
    setState(() { _busy = true; _message = null; });
    try {
      final data = await LocalDB.instance.exportAll();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final dir = await LocalFiles.exportsDirectory();
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final file = File('${dir.path}/easyquote_backup_$stamp.json');
      await file.writeAsString(jsonStr);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        text: 'EasyQuote backup — $stamp',
      ));
      await LocalDB.instance.setLastBackupAtNow();
      setState(() => _message = 'Backup created and ready to share/save.');
    } catch (e) {
      setState(() => _message = 'Export failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() { _busy = true; _message = null; });
    try {
      final result = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['json']);
      if (result == null || result.files.single.path == null) {
        setState(() => _busy = false);
        return;
      }
      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restore this backup?'),
          content: const Text(
            'This will REPLACE all data on this device with the backup file contents. '
            'This can\'t be undone.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore', style: TextStyle(color: AppColors.danger)),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await LocalDB.instance.importAll(data);
        setState(() => _message = 'Backup restored on this device.');
      }
    } catch (e) {
      setState(() => _message = 'Import failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _pickFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Auto-Backup Folder',
    );
    if (result != null) {
      await LocalDB.instance.setAutoBackupFolder(result);
      setState(() => _folder = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lastBackup = LocalDB.instance.getLastBackupAt();
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          // ── Manual Backup ───────────────────────────────────────────────
          const Text('MANUAL BACKUP',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700,
                  color: AppColors.blueprintDk, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          const Text(
            'EasyQuote never syncs to the cloud — all data stays on this device. '
            'Use manual backup to export your data and move it to another device.',
            style: TextStyle(color: AppColors.inkSoft, height: 1.5),
          ),
          const SizedBox(height: 6),
          Text(
            lastBackup == null ? 'Last manual backup: never' : 'Last manual backup: ${formatDate(lastBackup)}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.blueprintDk),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.upload_file_outlined, color: AppColors.blueprint),
              title: const Text('Export backup'),
              subtitle: const Text('Save/share a JSON file of all data on this device.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : _export,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.download_outlined, color: AppColors.rebar),
              title: const Text('Restore from backup'),
              subtitle: const Text('Choose a previously exported JSON file.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _busy ? null : _import,
            ),
          ),

          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 10),

          // ── Auto Backup ─────────────────────────────────────────────────
          const Text('AUTO-BACKUP',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700,
                  color: AppColors.blueprintDk, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          const Text(
            'Auto-backup saves your data automatically to a folder you choose on this device. '
            'Unlike the app\'s private storage, files in that folder survive uninstalling the app.\n\n'
            'Example: set auto-backup to Monthly → on the 1st of each new month, the app '
            'automatically saves EasyQuote_AB_NOV-2026.json to your chosen folder '
            '(e.g. Downloads/EasyQuote). If you lose your phone or reinstall the app, just pick '
            'that file in "Restore from backup" to get everything back.',
            style: TextStyle(color: AppColors.inkSoft, height: 1.55, fontSize: 12.5),
          ),
          const SizedBox(height: 16),

          // Folder picker
          if (_folder != null && _folder!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('Folder: $_folder',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
            ),
          OutlinedButton.icon(
            onPressed: _pickFolder,
            icon: const Icon(Icons.folder_open_outlined),
            label: Text(_folder == null || _folder!.isEmpty
                ? 'Select Folder from Device'
                : 'Change Folder'),
          ),

          const SizedBox(height: 18),

          // Frequency selector
          const Text('Backup Frequency',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _freqChip('15 Days', '15days'),
              _freqChip('30 Days', '30days'),
              _freqChip('Monthly', 'monthly'),
              ChoiceChip(
                label: Text(_frequency == 'custom' ? 'Custom: $_customDays days' : 'Custom'),
                selected: _frequency == 'custom',
                onSelected: (_) async {
                  final val = await _pickCustomDays();
                  if (val != null) {
                    await LocalDB.instance.setAutoBackupFrequency('custom');
                    await LocalDB.instance.setAutoBackupCustomDays(val);
                    setState(() { _frequency = 'custom'; _customDays = val; });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          _freqNote(),

          if (_busy) const Padding(padding: EdgeInsets.only(top: 20), child: LinearProgressIndicator()),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_message!, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  Widget _freqChip(String label, String freq) => ChoiceChip(
        label: Text(label),
        selected: _frequency == freq,
        onSelected: (_) async {
          await LocalDB.instance.setAutoBackupFrequency(freq);
          setState(() => _frequency = freq);
        },
      );

  Widget _freqNote() {
    String note;
    switch (_frequency) {
      case 'monthly': note = 'Auto-backup runs once every month (accounts for different month lengths).'; break;
      case '15days': note = 'Auto-backup runs every 15 days.'; break;
      case '30days': note = 'Auto-backup runs every 30 days.'; break;
      case 'custom': note = 'Auto-backup runs every $_customDays day(s).'; break;
      default: note = '';
    }
    return Text(note, style: const TextStyle(fontSize: 11.5, color: AppColors.inkSoft));
  }

  Future<int?> _pickCustomDays() async {
    final ctl = TextEditingController(text: _customDays.toString());
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom frequency (days)'),
        content: TextField(
          controller: ctl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Days', suffixText: 'days'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctl.text) ?? 30),
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }
}
