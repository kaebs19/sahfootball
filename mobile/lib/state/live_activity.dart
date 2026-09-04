// LiveActivity — النتيجة الجارية على شاشة القفل (iOS).
//
// منسّق بين قناة الكود الأصلي (sahfootball/live_activity) وبين
// ApiClient، على نمط Push تماماً: لا يرسم شيئاً ولا يحفظ حالة
// معروضة. ما يفعله:
//
//   • حين تُفتح شاشة مباراة جارية يبدأ نشاطاً حيّاً بنتيجتها
//     وتوقّع صاحب الهاتف، ويسلّم توكنه للسيرفر ليحدّثه مع كل هدف
//     والتطبيق مغلق.
//   • عند الدخول يطلب توكن «البدء بالدفع» (iOS 17.2+) ويسلّمه:
//     به يستطيع السيرفر أن يُظهر المباراة على شاشة القفل عند
//     صافرة البداية لمن توقّعها ونسيها.
//   • عند الخروج يُنهي كل نشاط ويمسح توكناته من السيرفر.
//
// أندرويد لا نشاط حيّ فيه؛ يكتفي بإشعار الهدف الذي يستبدل سابقه
// (راجع collapseId في السيرفر)، وكل دالة هنا تصمت عليه.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../models/fixture.dart';
import '../models/live_fixture.dart';

class LiveActivity {
  final ApiClient api;

  LiveActivity(this.api) {
    _channel.setMethodCallHandler(_onCall);
  }

  static const _channel = MethodChannel('sahfootball/live_activity');

  bool _enabled = false;

  /// المباريات التي بدأ التطبيق نشاطها في هذا التشغيل — كي لا نبدأ
  /// نشاطاً ثانياً عند كل تحديث للشاشة.
  final _started = <int>{};

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'onActivityToken':
        final args = call.arguments as Map;
        await _register(args['token'] as String?, (args['fixtureId'] as num?)?.toInt());
      case 'onPushToStartToken':
        await _register(call.arguments as String?, null);
    }
    return null;
  }

  Future<bool> get _supported async {
    if (!Platform.isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// بعد الدخول: راقب توكن البدء وسلّم ما فات.
  Future<void> enable() async {
    if (!await _supported) return;
    _enabled = true;
    try {
      await _channel.invokeMethod('observeStartToken');
      await _register(await _channel.invokeMethod<String>('pendingStartToken'), null);
    } on PlatformException catch (e) {
      debugPrint('[live] تعذّر تفعيل النشاط الحيّ: ${e.message}');
    }
  }

  /// قبل الخروج — بينما التوكن ما زال صالحاً للطلب.
  Future<void> disable() async {
    if (!_enabled) return;
    _enabled = false;
    _started.clear();
    try {
      await _channel.invokeMethod('endAll');
      await api.clearLiveActivityTokens();
    } catch (e) {
      debugPrint('[live] تعذّر إنهاء الأنشطة: $e');
    }
  }

  Future<void> _register(String? token, int? fixtureId) async {
    if (token == null || token.isEmpty || !_enabled) return;
    try {
      await api.registerLiveActivityToken(token, fixtureId: fixtureId);
    } catch (e) {
      // كالإشعارات: فشل التسجيل لا يوقف الشاشة، والمحاولة التالية
      // تأتي مع التوكن التالي.
      debugPrint('[live] تعذّر تسجيل توكن النشاط: $e');
    }
  }

  Map<String, dynamic> _args(Fixture f, {int? elapsed, LivePrediction? prediction}) => {
        'fixtureId': f.id,
        'home': f.homeTeamName,
        'away': f.awayTeamName,
        'predHome': prediction?.home,
        'predAway': prediction?.away,
        'goalsHome': f.goalsHome ?? 0,
        'goalsAway': f.goalsAway ?? 0,
        'elapsed': elapsed,
        'phase': f.phase ?? '',
        'status': f.status,
      };

  /// تزامن مع ما تعرضه شاشة المباراة: يبدأ النشاط أول مرة، ويحدّثه
  /// بعدها، وينهيه عند الصافرة. دالة واحدة كي تناديها الشاشة بعد كل
  /// تحميل بلا أن تتذكّر في أي طور هي.
  Future<void> sync(LiveFixture match) async {
    if (!_enabled) return;
    final f = match.fixture;
    final args = _args(f, elapsed: match.elapsed, prediction: match.myPrediction);
    try {
      if (f.isFinished) {
        if (_started.remove(f.id)) await _channel.invokeMethod('end', args);
      } else if (f.isLive) {
        if (_started.contains(f.id)) {
          await _channel.invokeMethod('update', args);
        } else {
          await _channel.invokeMethod('start', args);
          _started.add(f.id);
        }
      }
    } on PlatformException catch (e) {
      // المستخدم أطفأ الأنشطة الحيّة من الإعدادات، أو بلغ حدّ
      // النظام: الشاشة تعمل كما هي، وشاشة القفل وحدها لا تتحدّث.
      debugPrint('[live] تعذّر مزامنة النشاط: ${e.message}');
    }
  }
}
