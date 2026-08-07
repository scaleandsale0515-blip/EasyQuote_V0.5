import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/company_profile.dart';
import '../models/client.dart';
import '../models/catalog_item.dart';
import '../models/terms_preset.dart';
import '../models/quote_doc.dart';
import '../utils/ids.dart';
import 'local_files.dart';

class LocalDB {
  LocalDB._();
  static final LocalDB instance = LocalDB._();

  late Box appBox;
  late Box profilesBox;
  late Box clientsBox;
  late Box catalogBox;
  late Box termsBox;
  late Box documentsBox;

  bool _ready = false;
  bool get isReady => _ready;

  Future<void> init() async {
    if (_ready) return;
    await Hive.initFlutter();
    appBox = await Hive.openBox('app');
    profilesBox = await Hive.openBox('profiles');
    clientsBox = await Hive.openBox('clients');
    catalogBox = await Hive.openBox('catalog');
    termsBox = await Hive.openBox('terms');
    documentsBox = await Hive.openBox('documents');
    await _migrateLegacySingleProfile();
    _ready = true;
  }

  Future<void> _migrateLegacySingleProfile() async {
    if (profilesBox.isNotEmpty) return;
    final legacy = appBox.get('companyProfile');
    if (legacy == null) return;
    final profile = CompanyProfile.fromMap(Map<dynamic, dynamic>.from(legacy));
    profile.id = generateId();
    await profilesBox.put(profile.id, profile.toMap());
    await appBox.put('activeProfileId', profile.id);
  }

  // ── Company profiles ──────────────────────────────────────────────────────
  List<CompanyProfile> getProfiles() =>
      profilesBox.values
          .map((m) => CompanyProfile.fromMap(Map<dynamic, dynamic>.from(m)))
          .toList();

  Future<void> saveProfile(CompanyProfile p) async {
    if (p.id.isEmpty) p.id = generateId();
    await profilesBox.put(p.id, p.toMap());
    if (appBox.get('activeProfileId') == null) await setActiveProfileId(p.id);
  }

  Future<void> deleteProfile(String id) async {
    await profilesBox.delete(id);
    if (appBox.get('activeProfileId') == id) {
      final remaining = getProfiles();
      await appBox.put(
          'activeProfileId', remaining.isEmpty ? null : remaining.first.id);
    }
  }

  String? getActiveProfileId() => appBox.get('activeProfileId');
  Future<void> setActiveProfileId(String id) async =>
      appBox.put('activeProfileId', id);

  CompanyProfile getActiveProfile() {
    final profiles = getProfiles();
    if (profiles.isEmpty) return CompanyProfile();
    final activeId = getActiveProfileId();
    return profiles.firstWhere((p) => p.id == activeId,
        orElse: () => profiles.first);
  }

  CompanyProfile getProfileById(String id) {
    final profiles = getProfiles();
    if (profiles.isEmpty) return CompanyProfile();
    return profiles.firstWhere((p) => p.id == id,
        orElse: () => getActiveProfile());
  }

  Future<CompanyProfile> resolveAndPinProfile(QuoteDoc doc) async {
    final profiles = getProfiles();
    if (profiles.isEmpty) return CompanyProfile();
    final exists = profiles.any((p) => p.id == doc.profileId);
    if (exists) return profiles.firstWhere((p) => p.id == doc.profileId);
    final pinned = getActiveProfile();
    doc.profileId = pinned.id;
    await saveDocument(doc);
    return pinned;
  }

  // ── Counters ──────────────────────────────────────────────────────────────
  /// Peek at the next counter value without incrementing it.
  /// Used by the form screen to preview the ref number before saving.
  int peekCounter(String key) {
    final counters = Map<String, dynamic>.from(appBox.get('counters') ?? {});
    return ((counters[key] ?? 0) as int) + 1;
  }

  /// Actually increment the counter — only called when a document is saved.
  int nextCounter(String key) {
    final counters = Map<String, dynamic>.from(appBox.get('counters') ?? {});
    final next = ((counters[key] ?? 0) as int) + 1;
    counters[key] = next;
    appBox.put('counters', counters);
    return next;
  }

  // ── Personal login (Update 1) ─────────────────────────────────────────────
  bool hasPersonalLogin() => appBox.get('personalLoginId') != null;

  String getPersonalLoginId() => appBox.get('personalLoginId') ?? '';

  /// Stores the personal login — plain SHA-256 hash of password.
  Future<void> setPersonalLogin(String id, String passwordHash) async {
    await appBox.put('personalLoginId', id);
    await appBox.put('personalLoginHash', passwordHash);
  }

  String getPersonalLoginHash() => appBox.get('personalLoginHash') ?? '';

  Future<void> clearPersonalLogin() async {
    await appBox.delete('personalLoginId');
    await appBox.delete('personalLoginHash');
  }

  // ── Settings (Update 7) ───────────────────────────────────────────────────
  bool getFollowUpEnabled() => appBox.get('followUpEnabled') ?? true;
  Future<void> setFollowUpEnabled(bool v) async =>
      appBox.put('followUpEnabled', v);

  int getActivePdfTemplate() => appBox.get('activePdfTemplate') ?? 0;
  Future<void> setActivePdfTemplate(int index) async =>
      appBox.put('activePdfTemplate', index);

  // ── Auto-backup settings (Update 8) ──────────────────────────────────────
  String? getAutoBackupFolder() => appBox.get('autoBackupFolder');
  Future<void> setAutoBackupFolder(String path) async =>
      appBox.put('autoBackupFolder', path);

  String getAutoBackupFrequency() =>
      appBox.get('autoBackupFrequency') ?? 'monthly';
  Future<void> setAutoBackupFrequency(String freq) async =>
      appBox.put('autoBackupFrequency', freq);

  int getAutoBackupCustomDays() => appBox.get('autoBackupCustomDays') ?? 30;
  Future<void> setAutoBackupCustomDays(int days) async =>
      appBox.put('autoBackupCustomDays', days);

  DateTime? getLastAutoBackupAt() {
    final raw = appBox.get('lastAutoBackupAt');
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setLastAutoBackupAt(DateTime dt) async =>
      appBox.put('lastAutoBackupAt', dt.toIso8601String());

  bool getShowAutoBackupDoneNotice() =>
      appBox.get('showAutoBackupDoneNotice') ?? false;
  Future<void> setShowAutoBackupDoneNotice(bool v) async =>
      appBox.put('showAutoBackupDoneNotice', v);

  DateTime? getLastBackupAt() {
    final raw = appBox.get('lastBackupAt');
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setLastBackupAtNow() async =>
      appBox.put('lastBackupAt', DateTime.now().toIso8601String());

  // ── Clients ───────────────────────────────────────────────────────────────
  List<Client> getClients() =>
      clientsBox.values
          .map((m) => Client.fromMap(Map<dynamic, dynamic>.from(m)))
          .toList();

  Future<void> saveClient(Client c) async => clientsBox.put(c.id, c.toMap());
  Future<void> deleteClient(String id) async => clientsBox.delete(id);

  // ── Catalog items ─────────────────────────────────────────────────────────
  List<CatalogItem> getCatalogItems() =>
      catalogBox.values
          .map((m) => CatalogItem.fromMap(Map<dynamic, dynamic>.from(m)))
          .toList();

  Future<void> saveCatalogItem(CatalogItem i) async =>
      catalogBox.put(i.id, i.toMap());
  Future<void> deleteCatalogItem(String id) async => catalogBox.delete(id);

  // ── Terms presets ─────────────────────────────────────────────────────────
  List<TermsPreset> getTermsPresets() =>
      termsBox.values
          .map((m) => TermsPreset.fromMap(Map<dynamic, dynamic>.from(m)))
          .toList();

  Future<void> saveTermsPreset(TermsPreset t) async =>
      termsBox.put(t.id, t.toMap());
  Future<void> deleteTermsPreset(String id) async => termsBox.delete(id);

  // ── Documents ─────────────────────────────────────────────────────────────
  List<QuoteDoc> getDocuments() =>
      documentsBox.values
          .map((m) => QuoteDoc.fromMap(Map<dynamic, dynamic>.from(m)))
          .toList();

  Future<void> saveDocument(QuoteDoc d) async =>
      documentsBox.put(d.id, d.toMap());
  Future<void> deleteDocument(String id) async => documentsBox.delete(id);

  // ── Backup / Restore ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>> exportAll() async {
    final profilesRaw = profilesBox
        .toMap()
        .map((k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v)));

    for (final entry in profilesRaw.entries) {
      final p = entry.value;
      for (final field in ['logoPath', 'signaturePath', 'stampPath']) {
        final path = (p[field] ?? '') as String;
        if (path.isNotEmpty) {
          final b64 = await LocalFiles.readImageAsBase64(path);
          if (b64 != null) {
            p['${field}_base64'] = b64;
            p['${field}_ext'] = path.split('.').last;
          }
        }
      }
    }

    return {
      'app': {
        'counters': appBox.get('counters'),
        'activeProfileId': appBox.get('activeProfileId'),
      },
      'profiles': profilesRaw,
      'clients': clientsBox.toMap().map((k, v) => MapEntry(k.toString(), v)),
      'catalog': catalogBox.toMap().map((k, v) => MapEntry(k.toString(), v)),
      'terms': termsBox.toMap().map((k, v) => MapEntry(k.toString(), v)),
      'documents':
          documentsBox.toMap().map((k, v) => MapEntry(k.toString(), v)),
      'exportedAt': DateTime.now().toIso8601String(),
      'app_name': 'EasyQuote',
    };
  }

  Future<void> importAll(Map<String, dynamic> data) async {
    final app = data['app'] as Map?;
    if (app != null) {
      if (app['counters'] != null) await appBox.put('counters', app['counters']);
      if (app['activeProfileId'] != null)
        await appBox.put('activeProfileId', app['activeProfileId']);
    }

    final profilesMap = data['profiles'] as Map?;
    if (profilesMap != null) {
      await profilesBox.clear();
      for (final entry in profilesMap.entries) {
        final raw = Map<String, dynamic>.from(entry.value as Map);
        for (final field in ['logoPath', 'signaturePath', 'stampPath']) {
          final b64 = raw['${field}_base64'] as String?;
          if (b64 != null && b64.isNotEmpty) {
            final ext = (raw['${field}_ext'] as String?) ?? 'png';
            final newPath =
                await LocalFiles.writeImageFromBase64(b64, field, ext);
            raw[field] = newPath ?? '';
          }
          raw.remove('${field}_base64');
          raw.remove('${field}_ext');
        }
        await profilesBox.put(entry.key, raw);
      }
    }

    Future<void> restoreBox(Box box, String key) async {
      final m = data[key] as Map?;
      if (m == null) return;
      await box.clear();
      for (final entry in m.entries) {
        await box.put(entry.key, entry.value);
      }
    }

    await restoreBox(clientsBox, 'clients');
    await restoreBox(catalogBox, 'catalog');
    await restoreBox(termsBox, 'terms');
    await restoreBox(documentsBox, 'documents');
  }
}
