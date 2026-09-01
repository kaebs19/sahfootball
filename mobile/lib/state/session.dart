// Session — حالة "من المسجل الآن؟" على مستوى التطبيق كله.
//
// ChangeNotifier هنا يلعب دور ObservableObject في SwiftUI:
// الشاشات تراقبه، وكل notifyListeners() تعادل objectWillChange.send —
// فيُعاد بناء ما يعتمد عليه فقط. main.dart يقرر الشاشة الجذرية
// (دخول أم رئيسية) بناءً على status، فتصبح "العودة لشاشة الدخول
// عند انتهاء الجلسة" تحديث حالة لا تنقلاً يدوياً بين الشاشات.
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../models/user.dart';
import 'app_tab.dart';
import 'push.dart';

enum SessionStatus {
  restoring, // لحظة الإقلاع: نفحص التخزين الآمن — تعرض شاشة تحميل
  loggedOut,
  loggedIn,
}

class Session extends ChangeNotifier {
  final ApiClient api;
  final AppTab tab;

  /// جهاز الإشعارات. الجلسة تملكه لأن دورته هي دورتها بالضبط:
  /// يُربط الجهاز بالحساب عند الدخول ويُفكّ عند الخروج. وضعه هنا
  /// يمنع الحالة التي تصل فيها إشعارات حساب سابق لمن دخل بعده.
  late final Push _push = Push(api, tab);

  SessionStatus _status = SessionStatus.restoring;
  User? _user;
  String? _endedReason;

  SessionStatus get status => _status;
  User? get user => _user;

  /// سبب انتهاء الجلسة، حين يكون هناك سبب يستحق العرض (إيقاف
  /// الحساب مثلاً). شاشة الدخول تعرضه ثم تستهلكه بـ [clearReason]
  /// كي لا يبقى معلقاً بعد أن يقرأه المستخدم.
  String? get endedReason => _endedReason;

  void clearReason() {
    if (_endedReason == null) return;
    _endedReason = null;
    notifyListeners();
  }

  Session(this.api, this.tab) {
    // موت الجلسة قد يحدث في أي طلب (تجديد فاشل) — الربط هنا يجعل
    // العودة لشاشة الدخول تلقائية أينما وقع الفشل.
    api.onSessionExpired = _handleExpired;
  }

  /// عند إقلاع التطبيق: هل لدينا جلسة محفوظة وما زالت صالحة؟
  /// نسأل /me — إن انتهى access token جدده الـ interceptor بصمت،
  /// وإن مات refresh token نفسه وصلنا loggedOut من _handleExpired.
  Future<void> restore() async {
    await api.tokens.load();
    if (!api.tokens.hasSession) {
      _setStatus(SessionStatus.loggedOut);
      return;
    }
    try {
      _user = await api.me();
      _setStatus(SessionStatus.loggedIn);
      // بلا await: تسجيل الجهاز لا يجوز أن يؤخر ظهور الشاشة
      // الرئيسية، وفشله لا يعني شيئاً للمستخدم.
      _push.enable();
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        // جلسة ميتة فعلاً
        await api.tokens.clear();
        _setStatus(SessionStatus.loggedOut);
      } else {
        // سيرفر مطفأ أو لا شبكة ≠ جلسة منتهية: لا نرمي توكنات صالحة
        // بسبب انقطاع مؤقت. ندخله ويُعاد المحاولة مع أول طلب بيانات.
        _setStatus(SessionStatus.loggedIn);
      }
    }
  }

  Future<void> login(String email, String password) async {
    _user = await api.login(email: email, password: password);
    _endedReason = null; // دخول ناجح يمسح سبب الخروج السابق
    _setStatus(SessionStatus.loggedIn);
    _push.enable();
  }

  /// الدخول بهوية Apple — نفس مسار login تماماً بعد أن يتسلم
  /// التوكن من الطبقة الأصلية (SocialAuth). الحساب الجديد يُنشأ في
  /// السيرفر ضمن نفس الطلب، فلا فرق هنا بين دخول وتسجيل.
  Future<void> loginWithApple({
    required String identityToken,
    String? displayName,
  }) async {
    _user = await api.loginWithApple(
        identityToken: identityToken, displayName: displayName);
    _endedReason = null;
    _setStatus(SessionStatus.loggedIn);
    _push.enable();
  }

  Future<void> loginWithGoogle(String idToken) async {
    _user = await api.loginWithGoogle(idToken: idToken);
    _endedReason = null;
    _setStatus(SessionStatus.loggedIn);
    _push.enable();
  }

  /// إتمام استعادة كلمة المرور. السيرفر يرد بجلسة كاملة (المستخدم
  /// أثبت ملكية بريده للتو) — فهي دخول ناجح بكل آثاره.
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    _user = await api.resetPassword(
        email: email, code: code, newPassword: newPassword);
    _endedReason = null;
    _setStatus(SessionStatus.loggedIn);
    _push.enable();
  }

  Future<void> register(String email, String password,
      {String? displayName}) async {
    _user =
        await api.register(email: email, password: password, displayName: displayName);
    _setStatus(SessionStatus.loggedIn);
    // أول تسجيل هو أفضل لحظة لطلب الإذن: المستخدم اختار للتو أن
    // يستعمل التطبيق، والسؤال مفهوم في سياقه.
    _push.enable();
  }

  Future<void> logout() async {
    // قبل api.logout لا بعده: بعد إبطال التوكن يُرفض الطلب بـ 401
    // فيبقى الجهاز مربوطاً بهذا الحساب، وتصل إشعاراته لمن يدخل
    // بعده على نفس الهاتف.
    await _push.disable();
    await api.logout();
    _user = null;
    _setStatus(SessionStatus.loggedOut);
  }

  /// تحديث بيانات المستخدم بعد تعديل الملف أو البريد أو الصورة.
  /// الشاشات تقرأ Session لا ردّ الطلب، فبدون هذا يبقى الاسم القديم
  /// معروضاً في الترويسة حتى إعادة التشغيل.
  void setUser(User user) {
    _user = user;
    notifyListeners();
  }

  /// إنهاء الجلسة محلياً بلا نداء /logout — بعد حذف الحساب تحديداً:
  /// الحساب لم يعد موجوداً والتوكنات أُبطلت في السيرفر أصلاً، ونداء
  /// الخروج سيفشل بـ 401 ويظهر خطأً على فعل نجح تماماً.
  Future<void> forgetSession() async {
    await _push.disable();
    await api.tokens.clear();
    _user = null;
    _setStatus(SessionStatus.loggedOut);
  }

  void _handleExpired([String? reason]) {
    _user = null;
    _endedReason = reason;
    _setStatus(SessionStatus.loggedOut);
  }

  void _setStatus(SessionStatus s) {
    _status = s;
    notifyListeners();
  }
}
