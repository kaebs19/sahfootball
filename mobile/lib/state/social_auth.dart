// social_auth — طبقة عزل لمزوّدي الهوية (Apple وجوجل).
//
// الشاشات لا تعرف MethodChannel ولا مكتبة google_sign_in — تطلب
// "توكن آبل" أو "توكن جوجل" وتسلّمه لـ Session. نفس فلسفة عزل
// footballProvider في السيرفر: تفاصيل المزوّد تسكن ملفاً واحداً.
//
// لماذا Apple بكود أصلي (Swift) بلا حزمة؟ نفس منطق الإشعارات في
// AppDelegate: ما نحتاجه من AuthenticationServices ثلاثة أسطر فعلية
// (اطلب، اعرض، سلّم التوكن)، والحزمة تضيف تبعية كاملة مقابلها.
// جوجل عكسها تماماً: الرحلة الأصلية هناك OAuth كامل بمتصفح وعودة
// عبر URL scheme — حزمة جوجل الرسمية هي الاختيار الصحيح.
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';

/// نتيجة تفويض Apple. displayName يصل في أول تفويض فقط في عمر
/// الحساب — Apple لا تكرره أبداً، فيُمرَّر للسيرفر فوراً أو يضيع.
class AppleCredential {
  final String identityToken;
  final String? displayName;
  const AppleCredential({required this.identityToken, this.displayName});
}

/// يُرمى حين يفشل المزوّد بخطأ حقيقي (لا بإلغاء المستخدم).
/// الرسالة عربية جاهزة للعرض تحت الأزرار كأخطاء السيرفر تماماً.
class SocialAuthException implements Exception {
  final String message;
  const SocialAuthException(this.message);
  @override
  String toString() => message;
}

class SocialAuth {
  SocialAuth._();

  static const _appleChannel = MethodChannel('sahfootball/apple_signin');

  /// زر Apple يظهر على iOS فقط: على أندرويد لا واجهة نظامية له،
  /// ورحلة الويب البديلة لا تستحق ثمنها — وشرط App Store (وجود
  /// زر Apple بجانب أي دخول اجتماعي) شرط على iOS وحده أصلاً.
  static bool get appleAvailable => Platform.isIOS;

  /// زر جوجل يظهر فقط حين تكون معرّفات العملاء مضبوطة في config —
  /// زر يفتح نافذة ثم يفشل حتماً أسوأ من لا زر.
  static bool get googleAvailable {
    if (AppConfig.googleServerClientId.isEmpty) return false;
    if (Platform.isIOS) return AppConfig.googleIosClientId.isNotEmpty;
    return Platform.isAndroid;
  }

  /// يفتح نافذة Apple النظامية. null = أغلقها المستخدم بنفسه —
  /// ليست خطأ ولا تستحق رسالة.
  static Future<AppleCredential?> apple() async {
    try {
      final res =
          await _appleChannel.invokeMapMethod<String, dynamic>('signIn');
      if (res == null) return null; // إلغاء
      return AppleCredential(
        identityToken: res['identityToken'] as String,
        displayName: res['displayName'] as String?,
      );
    } on PlatformException {
      throw const SocialAuthException('تعذّر إكمال الدخول عبر Apple');
    }
  }

  static bool _googleReady = false;

  /// يفتح رحلة جوجل. null = إلغاء من المستخدم.
  static Future<String?> googleIdToken() async {
    final signIn = GoogleSignIn.instance;
    if (!_googleReady) {
      await signIn.initialize(
        // iOS يحتاج عميله الخاص؛ أندرويد يكتفي بعميل الويب أدناه.
        clientId: Platform.isIOS ? AppConfig.googleIosClientId : null,
        // عميل الويب نفسه الذي يتحقق به السيرفر — به يُصدر التوكن
        // فيتطابق الجمهور (aud) مع ما ينتظره googleAuth هناك.
        serverClientId: AppConfig.googleServerClientId,
      );
      _googleReady = true;
    }

    try {
      final account = await signIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const SocialAuthException('رد جوجل بلا توكن — أعد المحاولة');
      }
      return idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return null; // إلغاء أو مقاطعة — لا رسالة
      }
      throw const SocialAuthException('تعذّر إكمال الدخول عبر جوجل');
    }
  }
}
