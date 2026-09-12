// LeagueFilter — «أيّ دوري يعنيني الآن؟» كحالة مشتركة.
//
// كانت لكل شاشة نسختها: المباريات تحمل شريطها وحالتها، والجولة
// تحمل شريطاً آخر يعرض دوريات اللعبة كلها، و«مباشر» بلا شريط أصلاً
// فيعرض كل ملاعب أوروبا. فيختار اللاعب دورياً في تبويب ثم ينتقل
// لتبويب فيجده لم يسمع بالاختيار — والشاشات الثلاث تقول إنها عن
// «دورياتي».
//
// فصارت الحالة واحدة فوق التبويبات الثلاثة، على نفس نمط [AppTab]:
// الاختيار حالة تطبيق لا حالة شاشة.
//
// وتستمع إلى Session لنفس سبب Premium: الدخول والخروج وتبديل
// الحساب تغيّر المتابعات، ونداءٌ يدوي من كل شاشة يُنسى في واحدة —
// فيرى اللاعب دوريات من كان قبله على الهاتف.
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../models/champion.dart';
import 'session.dart';

class LeagueFilter extends ChangeNotifier {
  final ApiClient api;
  final Session session;

  LeagueFilter(this.api, this.session) {
    session.addListener(_onSession);
    _onSession();
  }

  /// دوريات اللعبة كما ردّها السيرفر، وفيها علامة المتابعة.
  List<LeagueFollow> _all = const [];

  /// المختار الآن؛ null = «الكل» أي كل ما يتابعه.
  int? _selected;

  bool _loaded = false;
  String? _error;

  List<LeagueFollow> get all => _all;
  List<LeagueFollow> get followed =>
      _all.where((l) => l.followed).toList(growable: false);

  /// شرائح الشريط: متابعاته، وإن لم يتابع شيئاً فدوريات اللعبة —
  /// شريطٌ فارغ يبدو عطلاً، والدعوة للمتابعة محلّها شريحة «+ دوري».
  List<LeagueFollow> get strip => followed.isNotEmpty ? followed : _all;

  int? get selected => _selected;
  bool get isLoaded => _loaded;
  String? get error => _error;

  /// لا يتابع شيئاً — يُقرأ لعرض دعوة المتابعة بدل قائمة فارغة.
  bool get followsNothing => _loaded && followed.isEmpty;

  /// ما يُرسل للسيرفر: المختار وحده، أو كل متابعاته.
  ///
  /// null = بلا تصفية، وهي حالة من لا يتابع شيئاً: السيرفر نفسه
  /// يوسّع النطاق حينها (راجع leagueScope في routes/fixtures)،
  /// والقائمة هنا وسيلةُ تضييق لا مصدرَ حقيقة.
  List<int>? get askedIds {
    if (_selected != null) return [_selected!];
    final mine = followed;
    return mine.isEmpty ? null : mine.map((l) => l.id).toList();
  }

  /// اسم الدوري المختار — للعناوين والرسائل الفارغة.
  String? get selectedName {
    final id = _selected;
    if (id == null) return null;
    for (final l in _all) {
      if (l.id == id) return l.name;
    }
    return null;
  }

  SessionStatus? _lastStatus;

  void _onSession() {
    final status = session.status;
    if (status == _lastStatus) return;
    _lastStatus = status;
    if (status == SessionStatus.loggedIn || status == SessionStatus.guest) {
      load(force: true);
    } else {
      // الخروج يمسح المتابعات فوراً لا بعد رحلة شبكة.
      _all = const [];
      _selected = null;
      _loaded = false;
      notifyListeners();
    }
  }

  /// القائمة من السيرفر. تُنادى عند تغيّر الجلسة وبعد شاشة الدوريات.
  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    try {
      final leagues = await api.leagues();
      _all = leagues;
      _error = null;
      _loaded = true;

      final mine = followed;
      // من يتابع دورياً واحداً لا يحتاج «الكل» ليصل إليه.
      if (mine.length == 1) {
        _selected = mine.first.id;
      } else if (_selected != null && !mine.any((l) => l.id == _selected)) {
        // دوريٌ أُلغيت متابعته (من هنا أو من الموقع) لا يبقى مختاراً.
        _selected = null;
      }
      notifyListeners();
    } on ApiException catch (e) {
      _error = e.message;
      // القائمة القديمة تبقى: شبكةٌ انقطعت لا تعني أنه ترك دورياته.
      notifyListeners();
    }
  }

  void select(int? id) {
    if (_selected == id) return;
    _selected = id;
    notifyListeners();
  }

  @override
  void dispose() {
    session.removeListener(_onSession);
    super.dispose();
  }
}
