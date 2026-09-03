// Push — دورة حياة توكن الجهاز: اطلب الإذن، استلم التوكن، سلّمه
// للسيرفر، وافصله عند الخروج.
//
// لا تُخزّن حالة معروضة ولا ترسم شيئاً: هي منسّق بين قناة الكود
// الأصلي (sahfootball/push) وبين ApiClient.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import 'app_tab.dart';

class Push {
  final ApiClient api;

  /// التبويب المعروض. الإشعار يحرّكه عند الضغط عليه.
  final AppTab tab;

  Push(this.api, this.tab) {
    _channel.setMethodCallHandler(_onCall);
  }

  static const _channel = MethodChannel('sahfootball/push');

  /// آخر توكن سلّمه النظام. نحفظه لأن الخروج من الحساب يحتاجه
  /// لفكّ الارتباط، وهو لا يصل مرة أخرى في نفس التشغيل.
  String? _token;

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'onToken':
        await _submit(call.arguments as String?);
      case 'onOpen':
        _open(call.arguments);
    }
    return null;
  }

  /// المستخدم ضغط الإشعار — نأخذه حيث يفعل ما يطلبه منه.
  ///
  /// إشعار يقول "ادخل قبل صافرة البداية" ثم يفتح آخر شاشة كان
  /// فيها المستخدم يفقد نصف قيمته: صار عليه أن يتذكر ما قرأه ثم
  /// يبحث عن مكانه بنفسه.
  void _open(dynamic arguments) {
    final data = arguments is Map ? arguments : const {};
    switch (data['type']) {
      // التذكير يطلب فعلاً: شاشة المباريات حيث يسجّل توقعه.
      case 'reminder':
        tab.select(AppTab.matches);
      // النتيجة خبر عن أدائه: "ملفي" حيث نقاطه وسلسلته وأوسمته.
      case 'result':
        tab.select(AppTab.profile);
      // طلب انضمام أو قبول أو إضافة: المجلس نفسه.
      case 'group':
        final id = data['groupId']?.toString();
        if (id != null && id.isNotEmpty) tab.openGroup(id);
    }
  }

  /// ما فات قبل أن نصبح جاهزين: ضغطة على إشعار فتحت التطبيق من
  /// الصفر، فوصل الحدث قبل أن تُبنى شجرة Flutter أصلاً.
  Future<void> _consumePendingOpen() async {
    try {
      _open(await _channel.invokeMethod<Map>('pendingOpen'));
    } on PlatformException catch (_) {
      // لا شيء ينتظر — الحالة الطبيعية.
    }
  }

  /// يُنادى بعد تسجيل الدخول وعند كل إقلاع بجلسة قائمة.
  ///
  /// نطلب الإذن هنا لا عند الإقلاع الأول: المستخدم الذي لم يجرّب
  /// التطبيق بعد لا يعرف لماذا يمنحه، والرفض في iOS شبه نهائي —
  /// النافذة لا تُعرض إلا مرة واحدة في عمر التثبيت.
  Future<void> enable() async {
    // المنصتان موصولتان بنفس القناة وبنفس أسماء الدوال، فلا تفرّع
    // هنا سوى اسم المنصة الذي يُرسل للسيرفر — وهو يحدّد بروتوكول
    // التسليم (APNs أو FCM) لا شكل الطلب.
    if (!Platform.isIOS && !Platform.isAndroid) return;

    try {
      final granted = await _channel.invokeMethod<bool>('requestPermission');
      if (granted != true) return;

      // ما فات قبل أن نصبح جاهزين: التوكن قد يصل من النظام خلال
      // أجزاء من الثانية، أي قبل أن يسجّل Dart مستمعه. الكود
      // الأصلي يحتفظ به وهذا السطر يلتقطه.
      await _submit(await _channel.invokeMethod<String>('pendingToken'));
      await _consumePendingOpen();
    } on PlatformException catch (e) {
      debugPrint('[push] تعذّر تفعيل الإشعارات: ${e.message}');
    }
  }

  static String get _platform => Platform.isIOS ? 'ios' : 'android';

  Future<void> _submit(String? token) async {
    if (token == null || token.isEmpty) return;
    _token = token;
    try {
      await api.registerDeviceToken(token, _platform);
    } catch (e) {
      // فشل التسجيل لا يوقف شيئاً في الواجهة: الإقلاع التالي يعيد
      // المحاولة، والسيرفر يتعامل مع التكرار بلا صف مضاعف.
      debugPrint('[push] تعذّر تسجيل الجهاز: $e');
    }
  }

  /// قبل الخروج من الحساب — بينما التوكن ما زال صالحاً.
  ///
  /// الترتيب مهم: بعد مسح التوكن يصير الطلب بلا مصادقة ويُرفض،
  /// فيبقى الجهاز مربوطاً بالحساب السابق وتصل إشعاراته لمن يدخل
  /// بعده على نفس الهاتف.
  Future<void> disable() async {
    final token = _token;
    if (token == null) return;
    _token = null;
    try {
      await api.unregisterDeviceToken(token);
    } catch (e) {
      debugPrint('[push] تعذّر فكّ ارتباط الجهاز: $e');
    }
  }
}
