import 'package:flutter/material.dart';

import 'storage/local_db.dart';
import 'storage/local_files.dart';
import 'auth/admin_auth.dart';
import 'auth/lock_screen.dart';
import 'auth/personal_auth.dart';
import 'auth/personal_login_screen.dart';
import 'screens/home_shell.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EasyQuoteApp());
}

class EasyQuoteApp extends StatefulWidget {
  const EasyQuoteApp({super.key});

  @override
  State<EasyQuoteApp> createState() => _EasyQuoteAppState();
}

class _EasyQuoteAppState extends State<EasyQuoteApp> {
  bool _dbReady = false;
  bool _adminUnlocked = false;
  bool _personalUnlocked = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await LocalDB.instance.init();
    final adminOk = AdminAuth.isActivated();
    // Personal login only blocks if it has been set AND the admin is already
    // activated (i.e. normal run, not first-ever launch).
    final personalNeeded = adminOk && PersonalAuth.isSet();
    setState(() {
      _dbReady = true;
      _adminUnlocked = adminOk;
      // If no personal login is set, treat it as already unlocked.
      _personalUnlocked = !personalNeeded;
    });

    // Run auto-backup check silently on every cold start.
    if (adminOk) _checkAutoBackup();
  }

  Future<void> _checkAutoBackup() async {
    final folder = LocalDB.instance.getAutoBackupFolder();
    if (folder == null || folder.isEmpty) return;

    final freq = LocalDB.instance.getAutoBackupFrequency();
    final lastBackup = LocalDB.instance.getLastAutoBackupAt();
    final now = DateTime.now();

    bool due = false;
    if (lastBackup == null) {
      due = true;
    } else {
      if (freq == 'monthly') {
        due = now.month != lastBackup.month || now.year != lastBackup.year;
      } else if (freq == '15days') {
        due = now.difference(lastBackup).inDays >= 15;
      } else if (freq == '30days') {
        due = now.difference(lastBackup).inDays >= 30;
      } else if (freq == 'custom') {
        final days = LocalDB.instance.getAutoBackupCustomDays();
        due = now.difference(lastBackup).inDays >= days;
      }
    }

    if (!due) return;

    try {
      final data = await LocalDB.instance.exportAll();
      await LocalFiles.writeAutoBackup(data, freq, folder, lastBackup ?? now);
      await LocalDB.instance.setLastAutoBackupAt(now);
      await LocalDB.instance.setShowAutoBackupDoneNotice(true);
    } catch (_) {
      // Silent fail — auto-backup should never crash the app.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasyQuote',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: !_dbReady
          ? const _SplashLoading()
          : !_adminUnlocked
              ? LockScreen(onUnlocked: () => setState(() {
                    _adminUnlocked = true;
                    _personalUnlocked = !PersonalAuth.isSet();
                  }))
              : !_personalUnlocked
                  ? PersonalLoginScreen(
                      onUnlocked: () => setState(() => _personalUnlocked = true))
                  : const HomeShell(),
    );
  }
}

class _SplashLoading extends StatelessWidget {
  const _SplashLoading();
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: AppColors.slab,
        body: Center(child: CircularProgressIndicator(color: AppColors.electricBlue)),
      );
}
