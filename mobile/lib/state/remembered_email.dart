// remembered_email — "حفظ الحساب" في شاشة الدخول.
//
// ما يُحفظ هو البريد فقط، لا كلمة المرور أبداً: حفظ كلمة المرور
// وظيفة نظام التشغيل (iCloud Keychain عبر AutofillGroup في الشاشة)
// لا وظيفتنا — النظام يحرسها بالبصمة ويزامنها بين الأجهزة، وأي
// تخزين منا لها أدنى أماناً من ذلك حتماً.
//
// نستعمل نفس التخزين الآمن الموجود (Keychain) لا تبعية جديدة:
// البريد ليس سراً خطيراً، لكن لا سبب لوضعه في مكان أضعف والأقوى
// حاضر مجاناً.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class RememberedEmail {
  RememberedEmail._();

  static const _key = 'sah_saved_email';
  static const _storage = FlutterSecureStorage();

  static Future<String?> load() => _storage.read(key: _key);

  /// null أو فارغ = انسَ المحفوظ (المستخدم أطفأ "تذكرني").
  static Future<void> save(String? email) async {
    if (email == null || email.isEmpty) {
      await _storage.delete(key: _key);
    } else {
      await _storage.write(key: _key, value: email);
    }
  }
}
