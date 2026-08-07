import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../storage/local_db.dart';
import 'admin_auth.dart';

/// Personal day-to-day login — separate from the Admin activation lock.
/// Set by the factory owner inside More → Settings → Login ID & Password.
/// Stored as a salted SHA-256 hash of the password (same pattern as Admin).
/// Never included in backup. Wiped on uninstall.
class PersonalAuth {
  PersonalAuth._();

  static const String _salt = 'EQ_PL_v1_xK9!mNp';

  static String _hash(String input) =>
      sha256.convert(utf8.encode(input + _salt)).toString();

  static bool isSet() => LocalDB.instance.hasPersonalLogin();

  static String getSavedId() => LocalDB.instance.getPersonalLoginId();

  static bool verify(String id, String password) {
    final savedId = LocalDB.instance.getPersonalLoginId();
    final savedHash = LocalDB.instance.getPersonalLoginHash();
    return id.trim() == savedId && _hash(password) == savedHash;
  }

  static Future<void> set(String id, String password) async {
    await LocalDB.instance.setPersonalLogin(id.trim(), _hash(password));
  }

  static Future<void> clear() async {
    await LocalDB.instance.clearPersonalLogin();
  }

  /// Verifies the original Admin credentials (used for "Forgot Password").
  static bool verifyAdmin(String enteredId, String enteredPassword) {
    return AdminAuth.verifyAndActivate(enteredId, enteredPassword,
        skipActivation: true);
  }
}
