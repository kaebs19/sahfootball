// شاشة المباريات — قلب التطبيق: هنا يضع المستخدم توقعه.
//
// وضعان: "القادمة" (المباريات التي يمكن توقعها الآن) و"بالتاريخ"
// (تصفح أي يوم، ماضياً أو قادماً، لمشاهدة النتائج). سبب الوضع
// الثاني عملي: خطة API المجانية تسمح بمواسم 2022–2024 فقط، فالموسم
// المخزّن عندنا منتهٍ بالكامل و"القادمة" ستكون فارغة حتى نشترك في
// خطة مدفوعة — وبدون تصفح التاريخ لن يرى المستخدم أي مباراة إطلاقاً.
//
// في الحالتين نجلب شيئين بالتوازي: المباريات + توقعاتي، ثم نبني
// خريطة fixtureId → توقعي كي تعرف كل بطاقة توقع صاحبها بلا طلب
// لكل بطاقة. طلبان اثنان مهما كان عدد المباريات.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../format.dart';
import '../models/fixture.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/fixture_card.dart';
import '../widgets/prediction_sheet.dart';

enum _Mode { upcoming, byDate }

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  _Mode _mode = _Mode.upcoming;
  DateTime _day = DateTime.now();

  List<Fixture>? _fixtures;
  Map<int, ({int home, int away})> _myPicks = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    setState(() {
      _error = null;
      _fixtures = null; // يعيد مؤشر التحميل عند تبديل اليوم أو الوضع
    });
    try {
      // Future.wait = انطلاق الطلبين معاً وانتظارهما — نصف زمن التتابع
      final results = await Future.wait([
        _mode == _Mode.upcoming
            ? api.upcomingFixtures()
            : api.fixturesByDate(_day),
        api.myPredictions(),
      ]);
      final fixtures = results[0] as List<Fixture>;
      final predictions = results[1] as List;
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

  void _shiftDay(int days) {
    setState(() => _day = _day.add(Duration(days: days)));
    _load();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      // نطاق يغطي المواسم المتاحة في الخطة الحالية وسنة قادمة
      firstDate: DateTime(2022, 1, 1),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
    );
    if (picked != null) {
      setState(() => _day = picked);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Row(
            children: [
              BrandModeTab(
                label: 'القادمة',
                selected: _mode == _Mode.upcoming,
                onTap: () => _setMode(_Mode.upcoming),
              ),
              const SizedBox(width: 8),
              BrandModeTab(
                label: 'بالتاريخ',
                selected: _mode == _Mode.byDate,
                onTap: () => _setMode(_Mode.byDate),
              ),
            ],
          ),
        ),
        if (_mode == _Mode.byDate)
          _DayBar(day: _day, onShift: _shiftDay, onPick: _pickDay),
        Expanded(child: _buildList()),
      ],
    );
  }

  void _setMode(_Mode m) {
    if (_mode == m) return;
    setState(() => _mode = m);
    _load();
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
        message: _mode == _Mode.upcoming
            ? 'لا مباريات قادمة حالياً — جرّب تصفح "بالتاريخ"'
            : 'لا مباريات في هذا اليوم',
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

/// شريحة تبديل الوضع.
///
/// كُتبت يدوياً بدل SegmentedButton لأن الأخير يفرض تخطيط Material
/// (علامة صح داخل الشريحة، حدود مصمتة) يخالف شرائح الهوية
/// البيضاوية. الشريحة المختارة ذهبية مصمتة كما في مرشّحات البطولات
/// في ملف الهوية — وهذا استعمال مسموح للذهبي لأنه تمييز حالة لا زر.
/// شريط اليوم: سهمان للتنقل يوماً بيوم (الأكثر استعمالاً) وضغطة على
/// التاريخ نفسه لفتح التقويم للقفزات البعيدة.
class _DayBar extends StatelessWidget {
  final DateTime day;
  final void Function(int days) onShift;
  final VoidCallback onPick;

  const _DayBar(
      {required this.day, required this.onShift, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final fmt = intl.DateFormat('EEEE d MMMM yyyy', 'ar');
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // في واجهة عربية (RTL) يعكس Flutter اتجاه أيقونات
          // chevron_right/left تلقائياً، فالسهم "للأمام" يشير يساراً
          // كما يتوقع القارئ العربي.
          IconButton(
            onPressed: () => onShift(-1),
            icon: const Icon(Icons.chevron_right,
                color: Brand.textMuted, size: 22),
          ),
          TextButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.calendar_today,
                size: 14, color: Brand.textMuted),
            label: Text(
              Fmt.date(fmt, day),
              style: const TextStyle(
                color: Brand.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: Brand.tabular,
              ),
            ),
          ),
          IconButton(
            onPressed: () => onShift(1),
            icon: const Icon(Icons.chevron_left,
                color: Brand.textMuted, size: 22),
          ),
        ],
      ),
    );
  }
}
