// شاشة المباريات — قلب التطبيق: هنا يضع المستخدم توقعه.
//
// الدوري هو المحور: شريط في الأعلى بدوريات المستخدم («الكل» ثم كل
// دوري يتابعه ثم «+ دوري»)، والقائمة تحته مبارياتها القادمة.
// كان في مكانه مبدّل «القادمة | بالتاريخ» من أيام الخطة المجانية
// التي لم تكن تعطي مواسم حيّة؛ اليوم الموسم جارٍ والقادمة لا
// تفرغ، والسؤال الحقيقي صار "أي دوري؟" لا "أي يوم؟".
//
// نجلب شيئين بالتوازي: المباريات + توقعاتي، ثم نبني خريطة
// fixtureId → توقعي كي تعرف كل بطاقة توقع صاحبها بلا طلب لكل
// بطاقة. طلبان اثنان مهما كان عدد المباريات.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../format.dart';
import '../models/champion.dart';
import '../models/fixture.dart';
import '../state/session.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/fixture_card.dart';
import '../widgets/guest_gate.dart';
import '../widgets/league_strip.dart';
import '../widgets/prediction_sheet.dart';
import 'leagues_screen.dart';

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  /// دوريات الشريط: ما يتابعه المستخدم، وإن لم يتابع شيئاً فكل
  /// دوريات اللعبة — شاشة بلا شريط شاشة بلا مباريات.
  List<LeagueFollow>? _leagues;

  /// المختار؛ null = «الكل» (كل دوريات الشريط).
  int? _leagueId;

  List<Fixture>? _fixtures;
  Map<int, ({int home, int away})> _myPicks = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  bool get _isGuest =>
      context.read<Session>().status == SessionStatus.guest;

  /// الدوريات أولاً ثم المباريات: «الكل» تعني دوريات المستخدم لا
  /// كل الدوريات، فلا يمكن طلب المباريات قبل معرفة أيّها له.
  Future<void> _init() async {
    setState(() => _error = null);
    try {
      final all = await context.read<ApiClient>().leagues();
      final followed = all.where((l) => l.followed).toList();
      if (!mounted) return;
      setState(() {
        _leagues = followed.isNotEmpty ? followed : all;
        // من يتابع دورياً واحداً لا يحتاج «الكل» ليصل إليه.
        _leagueId = followed.length == 1 ? followed.first.id : null;
      });
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// معرّفات الدوريات المطلوبة من السيرفر: المختار وحده، أو كل
  /// دوريات الشريط. null = لا تصفية (الشريط يعرض اللعبة كلها أصلاً).
  List<int>? get _askedLeagueIds {
    if (_leagueId != null) return [_leagueId!];
    final strip = _leagues;
    if (strip == null || strip.every((l) => !l.followed)) return null;
    return strip.map((l) => l.id).toList();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    // الضيف بلا توقعات: طلب "توقعاتي" سيرد 401 ويُفشل الشاشة كلها،
    // بينما المباريات نفسها مسار عام يعمل بلا توكن.
    final guest = _isGuest;
    setState(() {
      _error = null;
      _fixtures = null; // يعيد مؤشر التحميل عند تبديل الدوري
    });
    try {
      // Future.wait = انطلاق الطلبين معاً وانتظارهما — نصف زمن التتابع
      final results = await Future.wait([
        api.upcomingFixtures(leagueIds: _askedLeagueIds),
        if (!guest) api.myPredictions(),
      ]);
      final fixtures = results[0] as List<Fixture>;
      final predictions = guest ? const [] : results[1] as List;
      if (!mounted) return;
      setState(() {
        _fixtures = fixtures;
        _myPicks = {
          for (final p in predictions)
            p.fixtureId: (home: p.predHome, away: p.predAway),
        };
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _openPredictionSheet(Fixture fixture) async {
    // ضغطة توقّع من ضيف = لحظة الدعوة الطبيعية: هو يريد الفعل
    // الذي يحتاج الحساب، لا نحن من يقاطعه به.
    if (_isGuest) {
      await showGuestPredictDialog(context);
      return;
    }
    final existing = _myPicks[fixture.id];
    final result = await showPredictionSheet(
      context,
      fixture: fixture,
      initialHome: existing?.home,
      initialAway: existing?.away,
    );
    if (result != null && mounted) {
      // تحديث متفائل محلي: الشيت لا يرجع قيمة إلا بعد نجاح الحفظ في
      // السيرفر، فنحدث الخريطة مباشرة بلا إعادة جلب كل شيء.
      setState(() => _myPicks[fixture.id] = result);
    }
  }

  void _pickLeague(int? id) {
    if (_leagueId == id) return;
    setState(() => _leagueId = id);
    _load();
  }

  /// «+ دوري»: شاشة المتابعة نفسها، ثم إعادة بناء الشريط بما اختار.
  Future<void> _addLeague() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LeaguesScreen()),
    );
    if (changed == true && mounted) {
      setState(() => _leagueId = null);
      await _init();
    }
  }

  @override
  Widget build(BuildContext context) {
    final leagues = _leagues;
    return Column(
      children: [
        if (leagues != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 2),
            child: LeagueStrip(
              leagues: leagues,
              active: _leagueId,
              onPick: _pickLeague,
              // الضيف لا يتابع شيئاً فلا يُعرض عليه ما لا يستطيعه.
              onAdd: _isGuest ? null : _addLeague,
            ),
          ),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildList() {
    if (_error != null) {
      return BrandEmpty(
        icon: Icons.wifi_off,
        message: _error!,
        onRetry: _load,
      );
    }
    final fixtures = _fixtures;
    if (fixtures == null) {
      return const Center(
          child: CircularProgressIndicator(color: Brand.crown));
    }
    if (fixtures.isEmpty) {
      return BrandEmpty(
        icon: Icons.event_busy,
        message: _leagueId == null
            ? 'لا مباريات قادمة في دورياتك حالياً'
            : 'لا مباريات قادمة في هذا الدوري حالياً',
        onRefresh: _load,
      );
    }

    // تجميع بصري حسب اليوم: عنوان تاريخ ثم مبارياته. أسهل مسحاً
    // بالعين من قائمة مسطحة بعشرين موعداً متشابهاً.
    final byDay = <String, List<Fixture>>{};
    final dayFmt = intl.DateFormat('EEEE d MMMM', 'ar');
    for (final f in fixtures) {
      byDay.putIfAbsent(Fmt.date(dayFmt, f.kickoffAt), () => []).add(f);
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: Brand.crown,
      backgroundColor: Brand.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
        children: [
          for (final entry in byDay.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
              child: BrandSectionLabel(entry.key),
            ),
            for (final f in entry.value)
              FixtureCard(
                fixture: f,
                myPick: _myPicks[f.id],
                onTap:
                    f.isOpenForPrediction ? () => _openPredictionSheet(f) : null,
              ),
          ],
        ],
      ),
    );
  }
}
