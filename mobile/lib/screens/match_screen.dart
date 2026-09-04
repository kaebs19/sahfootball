// شاشة المباراة — ما يحدث في الملعب، لحظة بلحظة.
//
// تبويب «مباشر» يجيب «ماذا يعني ما يحدث لتوقّعي؟» ببطاقة واحدة لكل
// مباراة. هذه الشاشة تجيب السؤال التالي، الذي يُسأل بعد الضغط على
// البطاقة: «وماذا يحدث بالضبط؟» — من سجّل ومتى، من أُنذر، من
// استحوذ، من لعب، وكيف انتهت لقاءاتهما السابقة.
//
// الترتيب من الأعلى: النتيجة والدقيقة (ما تريده العين أولاً) ←
// الهدّافون تحت كل فريق (كيف صارت النتيجة هكذا) ← توقّعك (لماذا
// يهمّك) ← ثم الأقسام الأربعة خلف مبدّل، لأن أحداً لا يقرأ
// الإحصاءات والتشكيلة معاً.
//
// التحديث: كل عشرين ثانية ما دامت المباراة جارية والشاشة ظاهرة —
// نفس إيقاع «مباشر». الطلب يذهب لسيرفرنا، والسيرفر يسأل المزوّد
// مرة كل ثلاثين ثانية مهما كثر السائلون. والمنتهية لا تُحدَّث:
// نتيجتها لن تتغيّر.
import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../format.dart';
import '../models/fixture.dart';
import '../models/match_detail.dart';
import '../state/session.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/live_match_card.dart' show LivePredictionLine;

class MatchScreen extends StatefulWidget {
  /// ما تعرفه الشاشة السابقة — يُرسم فوراً قبل وصول التفاصيل، فلا
  /// تُفتح الشاشة بيضاء ثم تقفز.
  final Fixture fixture;

  const MatchScreen({super.key, required this.fixture});

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

enum _Tab { events, stats, lineups, h2h }

class _MatchScreenState extends State<MatchScreen> with WidgetsBindingObserver {
  static const _refreshEvery = Duration(seconds: 20);

  MatchDetail? _detail;
  String? _error;
  Timer? _timer;
  _Tab _tab = _Tab.events;

  Fixture get _fixture => _detail?.match.fixture ?? widget.fixture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // ما لم يبدأ يفتح على التشكيلة والمواجهات: خطّ زمني فارغ لمباراة
    // لم تنطلق يقول «لا شيء هنا» وهو خطأ — التشكيلة هي ما يُقرأ قبلها.
    if (widget.fixture.status == 'scheduled') _tab = _Tab.lineups;
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load(silent: true);
    } else {
      _timer?.cancel();
    }
  }

  /// المؤقّت يعمل للجارية وحدها، ويُعاد تقييمه بعد كل تحميل: مباراة
  /// انتهت أثناء المشاهدة توقف تحديثها وحدها.
  void _schedule() {
    _timer?.cancel();
    final f = _fixture;
    final soon = f.status == 'scheduled' &&
        f.kickoffAt.difference(DateTime.now()) < const Duration(minutes: 20);
    if (f.isLive || soon) {
      _timer = Timer(_refreshEvery, () => _load(silent: true));
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _error = null);
    try {
      final d = await context.read<ApiClient>().matchDetail(widget.fixture.id);
      if (!mounted) return;
      setState(() => _detail = d);
      // شاشة القفل تتابع ما تتابعه هذه الشاشة: يبدأ النشاط الحيّ مع
      // أول تحميل لمباراة جارية، ويُحدَّث بعدها، ويُنهى بالصافرة.
      context.read<Session>().liveActivity.sync(d.match);
    } on ApiException catch (e) {
      // كما في «مباشر»: فشل صامت لا يمسح ما على الشاشة.
      if (mounted && !silent) setState(() => _error = e.message);
    } finally {
      if (mounted) _schedule();
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _fixture;
    final d = _detail;

    return Scaffold(
      appBar: AppBar(title: Text(Fmt.round(f.round))),
      body: _error != null && d == null
          ? BrandEmpty(icon: Icons.wifi_off, message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              color: Brand.crown,
              backgroundColor: Brand.surface,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                children: [
                  _Scoreboard(fixture: f, detail: d),
                  const SizedBox(height: 14),
                  BrandSegmented(
                    labels: const ['الأحداث', 'الإحصاءات', 'التشكيلة', 'المواجهات'],
                    selected: _tab.index,
                    onChanged: (i) => setState(() => _tab = _Tab.values[i]),
                  ),
                  const SizedBox(height: 12),
                  if (d == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                          child: CircularProgressIndicator(color: Brand.crown)),
                    )
                  else
                    switch (_tab) {
                      _Tab.events => _EventsTimeline(detail: d),
                      _Tab.stats => _Statistics(detail: d),
                      _Tab.lineups => _Lineups(detail: d),
                      _Tab.h2h => _HeadToHeadList(detail: d),
                    },
                ],
              ),
            ),
    );
  }
}

// ── لوحة النتيجة ──────────────────────────────────────────────────

class _Scoreboard extends StatelessWidget {
  final Fixture fixture;
  final MatchDetail? detail;
  const _Scoreboard({required this.fixture, this.detail});

  @override
  Widget build(BuildContext context) {
    final f = fixture;
    final elapsed = detail?.match.elapsed;
    final live = f.isLive;
    final hasScore = f.goalsHome != null && f.goalsAway != null;
    final timeFmt = intl.DateFormat('EEEE d MMMM · h:mm a', 'ar');

    final goals = detail?.goals ?? const <MatchEvent>[];
    final homeGoals = goals.where((e) => e.home).toList();
    final awayGoals = goals.where((e) => !e.home).toList();

    // الحدّ الذهبي حين يكون توقّعك مضبوطاً الآن — نفس قاعدة البطاقة
    // في «مباشر»: أعلى لحظة في التجربة تُرى من طرف العين.
    final exact = detail?.match.myPrediction?.state.name == 'exact' &&
        f.status != 'scheduled';

    return BrandCard(
      royal: exact,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _TeamColumn(name: f.homeTeamName, logo: f.homeTeamLogo)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      hasScore ? '${f.goalsHome} - ${f.goalsAway}' : '– : –',
                      style: TextStyle(
                        fontFamily: Brand.displayFont,
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: f.isFinished ? Brand.textMuted : Brand.text,
                        height: 1.05,
                        fontFeatures: Brand.tabular,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _PhasePill(fixture: f, elapsed: elapsed),
                    if (f.penHome != null && f.penAway != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'ركلات ${f.penHome} - ${f.penAway}',
                        style: const TextStyle(
                            color: Brand.textMuted,
                            fontSize: 11,
                            fontFeatures: Brand.tabular),
                      ),
                    ] else if (f.htHome != null && f.htAway != null && !live) ...[
                      const SizedBox(height: 4),
                      Text(
                        'الشوط الأول ${f.htHome} - ${f.htAway}',
                        style: const TextStyle(
                            color: Brand.textFaint,
                            fontSize: 10.5,
                            fontFeatures: Brand.tabular),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(child: _TeamColumn(name: f.awayTeamName, logo: f.awayTeamLogo)),
            ],
          ),

          // الهدّافون تحت كل فريق — الجواب على «كيف صارت النتيجة هكذا؟»
          // قبل فتح الخط الزمني. الاسم في الوسط والدقيقة إلى الجهة
          // الداخلية، فتقرأ العين من الطرفين نحو النتيجة.
          if (goals.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _Scorers(goals: homeGoals, alignEnd: false)),
                const SizedBox(width: 44),
                Expanded(child: _Scorers(goals: awayGoals, alignEnd: true)),
              ],
            ),
          ],

          if (f.status == 'scheduled') ...[
            const SizedBox(height: 12),
            Text(
              Fmt.date(timeFmt, f.kickoffAt),
              style: const TextStyle(color: Brand.textMuted, fontSize: 12),
            ),
          ],

          if (detail != null && f.status != 'scheduled') ...[
            const Divider(color: Brand.borderSoft, height: 26),
            LivePredictionLine(prediction: detail!.match.myPrediction, live: live),
          ] else if (detail?.match.myPrediction != null) ...[
            const SizedBox(height: 12),
            BrandChip(
              label:
                  'توقعك ${detail!.match.myPrediction!.home} - ${detail!.match.myPrediction!.away}',
              icon: Icons.check_circle_outline,
              tone: BrandTone.correct,
            ),
          ],

          if (f.venueName != null || f.referee != null) ...[
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 4,
              children: [
                if (f.venueName != null)
                  _Meta(icon: Icons.stadium_outlined,
                      text: [f.venueName!, if (f.venueCity != null) f.venueCity!].join(' · ')),
                if (f.referee != null)
                  _Meta(icon: Icons.sports, text: f.referee!),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Meta({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Brand.textFaint),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Brand.textFaint, fontSize: 11)),
      ],
    );
  }
}

class _TeamColumn extends StatelessWidget {
  final String name;
  final String? logo;
  const _TeamColumn({required this.name, this.logo});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(color: Brand.fill, shape: BoxShape.circle),
          padding: const EdgeInsets.all(8),
          child: logo != null
              ? CachedNetworkImage(
                  imageUrl: logo!,
                  errorWidget: (_, _, _) =>
                      const Icon(Icons.shield, size: 24, color: Brand.textFaint),
                )
              : const Icon(Icons.shield, size: 24, color: Brand.textFaint),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Brand.text, fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.25),
        ),
      ],
    );
  }
}

/// شريحة الطور: حمراء نابضة للجارية، محايدة لما سواها.
class _PhasePill extends StatefulWidget {
  final Fixture fixture;
  final int? elapsed;
  const _PhasePill({required this.fixture, this.elapsed});

  @override
  State<_PhasePill> createState() => _PhasePillState();
}

class _PhasePillState extends State<_PhasePill> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.fixture.isLive) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PhasePill old) {
    super.didUpdateWidget(old);
    // انتهت أثناء المشاهدة: النبض يتوقف مع الصافرة.
    if (widget.fixture.isLive && !_c.isAnimating) _c.repeat(reverse: true);
    if (!widget.fixture.isLive && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.fixture;
    final live = f.isLive;
    final label = _label();
    if (label.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: live ? Brand.wrong.withValues(alpha: 0.13) : Brand.fill,
        borderRadius: BorderRadius.circular(Brand.radiusChip),
        border: Border.all(
            color: live ? Brand.wrong.withValues(alpha: 0.3) : Colors.transparent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[
            FadeTransition(
              opacity: Tween(begin: 1.0, end: 0.2).animate(_c),
              child: Container(
                width: 6,
                height: 6,
                decoration:
                    const BoxDecoration(color: Brand.wrong, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: Brand.displayFont,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: live ? Brand.wrong : Brand.textMuted,
              fontFeatures: Brand.tabular,
            ),
          ),
        ],
      ),
    );
  }

  String _label() {
    final f = widget.fixture;
    final e = widget.elapsed;
    return switch (f.phase) {
      'HT' => 'استراحة',
      'BT' => 'استراحة الإضافي',
      'P' => 'ركلات الترجيح',
      'INT' || 'SUSP' => 'متوقفة',
      'ET' => e != null ? "إضافي $e'" : 'وقت إضافي',
      'AET' => 'بعد وقت إضافي',
      'PEN' => 'بالترجيح',
      'PST' => 'مؤجلة',
      'CANC' || 'ABD' => 'ملغاة',
      '1H' || '2H' || 'LIVE' => e != null ? "$e'" : 'مباشر',
      _ => f.isFinished
          ? 'انتهت'
          : f.isLive
              ? (e != null ? "$e'" : 'مباشر')
              : '',
    };
  }
}

/// أسماء الهدّافين تحت فريقهم، بدقيقة كل هدف.
class _Scorers extends StatelessWidget {
  final List<MatchEvent> goals;
  final bool alignEnd;
  const _Scorers({required this.goals, required this.alignEnd});

  @override
  Widget build(BuildContext context) {
    if (goals.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        for (final g in goals)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              // "K. Benzema 23'" — والعكسي يُقال: هدف عكسي بعد الاسم.
              '${g.player}${g.kind == MatchEventKind.ownGoal ? ' (عكسي)' : g.kind == MatchEventKind.penaltyGoal ? ' (ج)' : ''} ${g.minuteLabel}',
              textAlign: alignEnd ? TextAlign.end : TextAlign.start,
              textDirection: TextDirection.ltr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Brand.textMuted, fontSize: 11, fontFeatures: Brand.tabular),
            ),
          ),
      ],
    );
  }
}

// ── الأحداث ────────────────────────────────────────────────────────

/// الخط الزمني: المضيف على جهة البداية، والضيف على جهة النهاية،
/// والدقيقة في الوسط — الشكل الذي يعرفه كل من تابع مباراة، والعين
/// تعرف فريق الحدث من جهته قبل أن تقرأ اسماً.
class _EventsTimeline extends StatelessWidget {
  final MatchDetail detail;
  const _EventsTimeline({required this.detail});

  @override
  Widget build(BuildContext context) {
    final events = detail.events;
    final f = detail.match.fixture;
    if (events.isEmpty) {
      return _EmptyTab(
        icon: Icons.timeline,
        text: f.status == 'scheduled'
            ? 'الأحداث تظهر هنا مع صافرة البداية.'
            : 'لا أحداث مسجّلة بعد — لا أهداف ولا بطاقات.',
      );
    }

    // الأحدث أعلى: من فتح الشاشة في الدقيقة 70 يريد الهدف الأخير
    // لا الأول. والمنتهية كذلك، فترتيب واحد أسهل على العين.
    final ordered = events.reversed.toList();

    return BrandCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          for (final (i, e) in ordered.indexed) ...[
            _EventRow(event: e),
            if (i < ordered.length - 1)
              const Divider(color: Brand.borderSoft, height: 1),
          ],
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final MatchEvent event;
  const _EventRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final e = event;
    final body = _EventBody(event: e, alignEnd: !e.home);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: e.home ? body : const SizedBox.shrink()),
          SizedBox(
            width: 52,
            child: Text(
              e.minuteLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: Brand.displayFont,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Brand.text,
                fontFeatures: Brand.tabular,
              ),
            ),
          ),
          Expanded(child: e.home ? const SizedBox.shrink() : body),
        ],
      ),
    );
  }
}

class _EventBody extends StatelessWidget {
  final MatchEvent event;
  final bool alignEnd;
  const _EventBody({required this.event, required this.alignEnd});

  @override
  Widget build(BuildContext context) {
    final e = event;
    final icon = _EventIcon(kind: e.kind);
    final text = Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          e.player,
          textDirection: TextDirection.ltr,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: e.kind.isGoal ? Brand.text : Brand.textMuted,
            fontSize: 13,
            fontWeight: e.kind.isGoal ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          switch (e.kind) {
            // للتبديل نذكر الطرف الثاني بلا ادّعاء من دخل ومن خرج:
            // المزوّد غير متّسق في ترتيبهما، وخطأ الاتجاه يظهر لكل
            // من يعرف الفريق.
            MatchEventKind.substitution =>
              e.assist != null ? 'تبديل مع ${e.assist}' : 'تبديل',
            _ => e.assist != null ? '${e.label} · صناعة ${e.assist}' : e.label,
          },
          textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Brand.textFaint, fontSize: 11),
        ),
      ],
    );

    return Row(
      mainAxisAlignment: alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: alignEnd
          ? [Flexible(child: text), const SizedBox(width: 8), icon]
          : [icon, const SizedBox(width: 8), Flexible(child: text)],
    );
  }
}

/// أيقونة الحدث. ألوان البطاقات ألوان الحكم لا ألوان الهوية: الأصفر
/// هنا بطاقة صفراء حقيقية لا «ذهبي الملكية»، والأحمر بطاقة حمراء
/// لا «توقّع خاطئ» — رمزان يعرفهما كل متفرّج، وتبديلهما إلى لون
/// محايد كان سيجعل الإنذار يشبه التبديل.
class _EventIcon extends StatelessWidget {
  final MatchEventKind kind;
  const _EventIcon({required this.kind});

  static const _cardYellow = Color(0xFFF5D90A);
  static const _cardRed = Color(0xFFE5322D);

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case MatchEventKind.yellow:
      case MatchEventKind.red:
        return Container(
          width: 12,
          height: 16,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: kind == MatchEventKind.yellow ? _cardYellow : _cardRed,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      case MatchEventKind.goal:
      case MatchEventKind.penaltyGoal:
        return const Icon(Icons.sports_soccer, size: 20, color: Brand.text);
      case MatchEventKind.ownGoal:
        return const Icon(Icons.sports_soccer, size: 20, color: Brand.wrong);
      case MatchEventKind.missedPenalty:
        return const Icon(Icons.close, size: 20, color: Brand.wrong);
      case MatchEventKind.substitution:
        return const Icon(Icons.swap_vert, size: 20, color: Brand.textFaint);
    }
  }
}

// ── الإحصاءات ──────────────────────────────────────────────────────

/// صفّ لكل إحصاء: القيمتان على الطرفين والتسمية في الوسط، وتحتها
/// شريطان يخرجان من المنتصف — الأطول هو الأقوى، بلا قراءة رقم.
class _Statistics extends StatelessWidget {
  final MatchDetail detail;
  const _Statistics({required this.detail});

  @override
  Widget build(BuildContext context) {
    final rows = detail.statistics;
    if (rows.isEmpty) {
      return _EmptyTab(
        icon: Icons.bar_chart,
        text: detail.match.fixture.status == 'scheduled'
            ? 'الإحصاءات تبدأ مع المباراة.'
            : 'لا إحصاءات متاحة لهذه المباراة.',
      );
    }
    return BrandCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        children: [for (final s in rows) _StatRow(stat: s)],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final MatchStat stat;
  const _StatRow({required this.stat});

  @override
  Widget build(BuildContext context) {
    final s = stat;
    final homeLeads = s.homeValue > s.awayValue;
    final awayLeads = s.awayValue > s.homeValue;
    TextStyle num(bool leads) => TextStyle(
          fontFamily: Brand.displayFont,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: leads ? Brand.text : Brand.textMuted,
          fontFeatures: Brand.tabular,
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(width: 48, child: Text(s.home, style: num(homeLeads))),
              Expanded(
                child: Text(
                  s.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Brand.textMuted, fontSize: 12),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(s.away, textAlign: TextAlign.end, style: num(awayLeads)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // شريطان من المنتصف: يمين المنتصف للمضيف (جهة البداية في
          // العربية) ويساره للضيف. Row واحد بنسب، لا رسم.
          SizedBox(
            height: 5,
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FractionallySizedBox(
                      widthFactor: s.homeShare.clamp(0.02, 1.0),
                      child: _Bar(strong: homeLeads || !awayLeads),
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FractionallySizedBox(
                      widthFactor: (1 - s.homeShare).clamp(0.02, 1.0),
                      child: _Bar(strong: awayLeads || !homeLeads),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final bool strong;
  const _Bar({required this.strong});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 5,
      decoration: BoxDecoration(
        color: strong ? Brand.text : Brand.fillStrong,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

// ── التشكيلة ───────────────────────────────────────────────────────

/// الملعب: المضيف في النصف السفلي وحارسه في الأسفل، والضيف في
/// العلوي مقلوباً وحارسه في الأعلى — كما يُرسم في كل مكان.
///
/// أحادي اللون عمداً: ملعب أخضر فوق واجهة سوداء-بيضاء كان سيبدو
/// إعلاناً. الخطوط بيضاء خافتة والأسماء تحت الدوائر.
class _Lineups extends StatelessWidget {
  final MatchDetail detail;
  const _Lineups({required this.detail});

  @override
  Widget build(BuildContext context) {
    final home = detail.homeLineup;
    final away = detail.awayLineup;
    final f = detail.match.fixture;
    if (home == null && away == null) {
      return _EmptyTab(
        icon: Icons.groups_outlined,
        text: f.status == 'scheduled'
            ? 'التشكيلة تُنشر قبل الانطلاق بنحو ساعة.'
            : 'لا تشكيلة منشورة لهذه المباراة.',
      );
    }

    return Column(
      children: [
        BrandCard(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            children: [
              _LineupHeader(name: f.awayTeamName, lineup: away),
              const SizedBox(height: 10),
              if ((home?.hasGrid ?? false) || (away?.hasGrid ?? false))
                _Pitch(home: home, away: away)
              else
                _LineupLists(home: home, away: away),
              const SizedBox(height: 10),
              _LineupHeader(name: f.homeTeamName, lineup: home),
            ],
          ),
        ),
        if ((home?.bench.isNotEmpty ?? false) || (away?.bench.isNotEmpty ?? false)) ...[
          const SizedBox(height: 12),
          _Bench(homeName: f.homeTeamName, awayName: f.awayTeamName, home: home, away: away),
        ],
      ],
    );
  }
}

class _LineupHeader extends StatelessWidget {
  final String name;
  final Lineup? lineup;
  const _LineupHeader({required this.name, this.lineup});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Brand.text, fontSize: 13, fontWeight: FontWeight.w700)),
        ),
        if (lineup?.formation != null)
          BrandChip(label: lineup!.formation!),
        if (lineup?.coach != null) ...[
          const SizedBox(width: 8),
          Text(lineup!.coach!,
              style: const TextStyle(color: Brand.textFaint, fontSize: 11)),
        ],
      ],
    );
  }
}

class _Pitch extends StatelessWidget {
  final Lineup? home;
  final Lineup? away;
  const _Pitch({this.home, this.away});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.68,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          return Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: _PitchPainter())),
              // الضيف في النصف العلوي مقلوباً: صفّه الأول (الحارس) عند
              // القمة، وصفوفه تنزل نحو المنتصف.
              if (away?.hasGrid ?? false)
                ..._place(away!, w, h, top: true),
              if (home?.hasGrid ?? false)
                ..._place(home!, w, h, top: false),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _place(Lineup l, double w, double h, {required bool top}) {
    final rows = <int, List<LineupPlayer>>{};
    for (final p in l.starters) {
      rows.putIfAbsent(p.row!, () => []).add(p);
    }
    final rowCount = rows.keys.fold(0, (m, r) => r > m ? r : m);
    final half = h / 2;
    // هامش عند حافة الملعب للحارس، وهامش أكبر عند المنتصف كي لا
    // يلتصق مهاجم الفريقين بخطّ الوسط ويتراكب رأساهما.
    const pad = 22.0;
    const centerPad = 40.0;
    final step = (half - pad - centerPad) / (rowCount <= 1 ? 1 : rowCount - 1);

    final out = <Widget>[];
    for (final entry in rows.entries) {
      final r = entry.key;
      final players = [...entry.value]..sort((a, b) => a.col!.compareTo(b.col!));
      final n = players.length;
      // الحارس (r=1) عند حافة الملعب، والهجوم عند المنتصف.
      final yFromEdge = pad + (r - 1) * step;
      final y = top ? yFromEdge : h - yFromEdge;
      for (final (i, p) in players.indexed) {
        // الأعمدة تُقلب للضيف كي يبقى يمين الفريق يمينه وهو يهاجم
        // نحو الأسفل — كما يراه من يقف خلف مرماه.
        final slot = top ? n - 1 - i : i;
        final x = w * (slot + 0.5) / n;
        out.add(Positioned(
          left: x - 30,
          top: y - 26,
          width: 60,
          child: _PitchPlayer(player: p),
        ));
      }
    }
    return out;
  }
}

class _PitchPlayer extends StatelessWidget {
  final LineupPlayer player;
  const _PitchPlayer({required this.player});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Brand.surface,
            shape: BoxShape.circle,
            border: Border.all(color: Brand.text.withValues(alpha: 0.55), width: 1.2),
          ),
          alignment: Alignment.center,
          child: Text(
            player.number?.toString() ?? '',
            style: const TextStyle(
              fontFamily: Brand.displayFont,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Brand.text,
              fontFeatures: Brand.tabular,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          player.shortName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: TextDirection.ltr,
          style: const TextStyle(color: Brand.textMuted, fontSize: 9.5),
        ),
      ],
    );
  }
}

class _PitchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Brand.text.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final fill = Paint()..color = Brand.fill;
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14));
    canvas.drawRRect(r, fill);
    canvas.drawRRect(r, line);

    final w = size.width;
    final h = size.height;
    // خط المنتصف ودائرته.
    canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), line);
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.14, line);
    // منطقتا الجزاء.
    final boxW = w * 0.6;
    final boxH = h * 0.14;
    canvas.drawRect(Rect.fromLTWH((w - boxW) / 2, 0, boxW, boxH), line);
    canvas.drawRect(Rect.fromLTWH((w - boxW) / 2, h - boxH, boxW, boxH), line);
    final goalW = w * 0.28;
    final goalH = h * 0.05;
    canvas.drawRect(Rect.fromLTWH((w - goalW) / 2, 0, goalW, goalH), line);
    canvas.drawRect(Rect.fromLTWH((w - goalW) / 2, h - goalH, goalW, goalH), line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// حين لا يرسل المزوّد مواضع: قائمتان جنباً إلى جنب.
class _LineupLists extends StatelessWidget {
  final Lineup? home;
  final Lineup? away;
  const _LineupLists({this.home, this.away});

  @override
  Widget build(BuildContext context) {
    Widget list(Lineup? l) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final p in l?.starters ?? const <LineupPlayer>[])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${p.number ?? ''}  ${p.name}',
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Brand.textMuted, fontSize: 12),
                ),
              ),
          ],
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: list(home)),
        const SizedBox(width: 12),
        Expanded(child: list(away)),
      ],
    );
  }
}

class _Bench extends StatelessWidget {
  final String homeName;
  final String awayName;
  final Lineup? home;
  final Lineup? away;
  const _Bench({required this.homeName, required this.awayName, this.home, this.away});

  @override
  Widget build(BuildContext context) {
    Widget side(String name, Lineup? l) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Brand.text, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              for (final p in l?.bench ?? const <LineupPlayer>[])
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${p.number ?? ''}  ${p.name}',
                    textDirection: TextDirection.ltr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Brand.textMuted, fontSize: 11.5),
                  ),
                ),
            ],
          ),
        );
    return BrandCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('الاحتياط',
              style: TextStyle(
                  fontFamily: Brand.displayFont,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Brand.text)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [side(homeName, home), const SizedBox(width: 12), side(awayName, away)],
          ),
        ],
      ),
    );
  }
}

// ── المواجهات ──────────────────────────────────────────────────────

class _HeadToHeadList extends StatelessWidget {
  final MatchDetail detail;
  const _HeadToHeadList({required this.detail});

  @override
  Widget build(BuildContext context) {
    final rows = detail.h2h;
    if (rows.isEmpty) {
      return const _EmptyTab(
          icon: Icons.history, text: 'لا مواجهات سابقة مسجّلة بين الفريقين.');
    }
    final fmt = intl.DateFormat('d MMM yyyy', 'ar');
    return BrandCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        children: [
          for (final (i, m) in rows.indexed) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(m.home,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Brand.text,
                                fontSize: 13,
                                fontWeight: m.goalsHome > m.goalsAway
                                    ? FontWeight.w700
                                    : FontWeight.w400)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: BrandNumber('${m.goalsHome} - ${m.goalsAway}', size: 15),
                      ),
                      Expanded(
                        child: Text(m.away,
                            textAlign: TextAlign.end,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Brand.text,
                                fontSize: 13,
                                fontWeight: m.goalsAway > m.goalsHome
                                    ? FontWeight.w700
                                    : FontWeight.w400)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${Fmt.date(fmt, m.date)}${m.league.isNotEmpty ? ' · ${m.league}' : ''}',
                    style: const TextStyle(color: Brand.textFaint, fontSize: 10.5),
                  ),
                ],
              ),
            ),
            if (i < rows.length - 1) const Divider(color: Brand.borderSoft, height: 1),
          ],
        ],
      ),
    );
  }
}

class _EmptyTab extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyTab({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34),
      child: Column(
        children: [
          Icon(icon, size: 28, color: Brand.textFaint),
          const SizedBox(height: 10),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Brand.textMuted, fontSize: 13, height: 1.6)),
        ],
      ),
    );
  }
}
