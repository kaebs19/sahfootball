// شاشة توقّع الجولة — تسع مباريات وزرّ حفظ واحد.
//
// كان توقّع جولة كاملة يكلّف تسع فتحات لشيت التوقّع وتسعة طلبات:
// تفتح المباراة، تكتب، تحفظ، تُغلق، تفتح التالية. ومن يريد الجولة
// كاملة يستسلم عند الرابعة — فيخسر سبع مباريات، وتخسر اللعبة
// لاعباً ظنّ أنها متعبة.
//
// والشاشة ليست ميزة جديدة بل إعادة ترتيب: نفس العدّادات ونفس
// القواعد ونفس predictionService في الخادم. الجديد أن الحلقة تدور
// مرة واحدة بدل تسع.
//
// وصفٌّ مضغوط لا بطاقة لكل مباراة: الغرض المقارنة والسرعة، وتسع
// بطاقات كاملة تجعل التمرير أطول من تسع شاشات منفصلة فتُلغي
// المكسب كله.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../config.dart';
import '../format.dart';
import '../models/champion.dart';
import '../models/round.dart';
import '../widgets/brand_widgets.dart';

class RoundScreen extends StatefulWidget {
  const RoundScreen({super.key});

  @override
  State<RoundScreen> createState() => _RoundScreenState();
}

class _RoundScreenState extends State<RoundScreen> {
  RoundPage? _page;
  List<LeagueFollow>? _leagues;
  String? _error;
  bool _busy = false;

  int? _leagueId;
  String? _round;

  /// ما كتبه المستخدم الآن — مفتاحه معرّف المباراة.
  final Map<int, ({int? home, int? away, bool x2})> _edits = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final api = context.read<ApiClient>();
      // الدوريات مرة واحدة: قائمة الشرائح لا تتغيّر بتغيّر الجولة.
      _leagues ??= await api.leagues();
      final page = await api.round(leagueId: _leagueId, round: _round);
      if (!mounted) return;
      setState(() {
        _page = page;
        _leagueId = page.leagueId;
        _round = page.round;
        _edits.clear();
        for (final f in page.fixtures) {
          _edits[f.id] = (
            home: f.predHome,
            away: f.predAway,
            x2: f.multiplier > 1,
          );
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _save() async {
    final page = _page;
    if (page == null) return;

    // الفارغان معاً = لا توقّع لهذه المباراة. وهذا هو الحال الغالب
    // في شاشة تعرض تسعاً: من يتوقّع ثلاثاً يترك ستّاً فارغة،
    // وحفظها 0-0 يمنحه ستّة تعادلات لم يقصدها.
    final picks = <({int fixtureId, int home, int away, int multiplier})>[];
    for (final f in page.fixtures) {
      if (!f.open) continue;
      final e = _edits[f.id];
      if (e == null || (e.home == null && e.away == null)) continue;
      picks.add((
        fixtureId: f.id,
        home: e.home ?? 0,
        away: e.away ?? 0,
        multiplier: e.x2 ? page.multiplierFactor : 1,
      ));
    }

    if (picks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ما كتبت أي نتيجة.')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final r = await context.read<ApiClient>().saveRound(picks);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_summary(r))));
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// حصيلة الحفظ بالعربية — الجمع في مكان واحد.
  String _summary(RoundSaveResult r) {
    final parts = <String>[];
    if (r.saved > 0) {
      parts.add('حُفظ ${Fmt.counted(r.saved, 'توقّع واحد', 'توقّعان', 'توقّعات', 'توقّعاً')}.');
    }
    if (r.denied > 0) {
      parts.add('المضاعِف لم يُطبَّق على '
          '${Fmt.counted(r.denied, 'مباراة', 'مباراتين', 'مباريات', 'مباراة')} — نفدت مضاعفاتك.');
    }
    if (r.late > 0) {
      parts.add('${Fmt.counted(r.late, 'مباراة واحدة انطلقت', 'مباراتان انطلقتا', 'مباريات انطلقت', 'مباراة انطلقت')} قبل الحفظ.');
    }
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Scaffold(
      appBar: AppBar(title: const Text('توقّع الجولة')),
      body: _error != null
          ? _Retry(text: _error!, onRetry: _load)
          : page == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _LeagueStrip(
                      leagues: _leagues ?? const [],
                      active: _leagueId,
                      onPick: (id) {
                        setState(() {
                          _leagueId = id;
                          _round = null; // جولة الدوري الجديد تُختار من جديد
                          _page = null;
                        });
                        _load();
                      },
                    ),
                    _RoundHeader(
                      page: page,
                      onJump: (r) {
                        setState(() {
                          _round = r;
                          _page = null;
                        });
                        _load();
                      },
                    ),
                    Expanded(
                      child: page.fixtures.isEmpty
                          ? const Center(
                              child: Text('لا مباريات في هذه الجولة',
                                  style: TextStyle(color: Brand.textMuted)))
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                              itemCount: page.fixtures.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final f = page.fixtures[i];
                                final e = _edits[f.id];
                                return _FixtureRow(
                                  fixture: f,
                                  home: e?.home,
                                  away: e?.away,
                                  x2: e?.x2 ?? false,
                                  factor: page.multiplierFactor,
                                  onChanged: (h, a, x) => setState(
                                      () => _edits[f.id] = (home: h, away: a, x2: x)),
                                );
                              },
                            ),
                    ),
                    if (page.fixtures.any((f) => f.open))
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                          child: Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: _busy ? null : _save,
                                  child: _busy
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Brand.onAccent),
                                        )
                                      : const Text('احفظ توقّعات الجولة'),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'باقٍ لك ${page.multiplierLeft} مضاعِفاً في هذا الدوري. '
                                'الحقل الفارغ لا يُحفظ.',
                                style: const TextStyle(
                                    color: Brand.textFaint, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}

/// شريط الدوريات — شرائح أفقية.
class _LeagueStrip extends StatelessWidget {
  final List<LeagueFollow> leagues;
  final int? active;
  final ValueChanged<int> onPick;

  const _LeagueStrip(
      {required this.leagues, required this.active, required this.onPick});

  @override
  Widget build(BuildContext context) {
    if (leagues.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: leagues.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (_, i) {
          final l = leagues[i];
          final on = l.id == active;
          return InkWell(
            onTap: () => onPick(l.id),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: on ? Brand.crown : Brand.fill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: on ? Brand.crown : Brand.border),
              ),
              child: Row(
                children: [
                  if (l.logoUrl != null)
                    CachedNetworkImage(
                      imageUrl: AppConfig.absoluteUrl(l.logoUrl!),
                      width: 18,
                      height: 18,
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    ),
                  const SizedBox(width: 6),
                  Text(
                    l.name,
                    style: TextStyle(
                      color: on ? Brand.onAccent : Brand.textMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// ترويسة الجولة: شعار الدوري واسمه، ورقم الجولة، والتنقّل بينها.
class _RoundHeader extends StatelessWidget {
  final RoundPage page;
  final ValueChanged<String> onJump;

  const _RoundHeader({required this.page, required this.onJump});

  int get _index => page.rounds.indexWhere((r) => r.round == page.round);

  @override
  Widget build(BuildContext context) {
    final i = _index;
    final prev = i > 0 ? page.rounds[i - 1] : null;
    final next = i >= 0 && i < page.rounds.length - 1 ? page.rounds[i + 1] : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: Row(
        children: [
          // الشعار قبل الاسم: الدوري يُعرف بشعاره أسرع مما يُقرأ
          // اسمه، وشريط الشرائح فوقه يُمرَّر فيضيع السياق بلا هوية
          // ثابتة تحته.
          if (page.leagueLogo.isNotEmpty)
            CachedNetworkImage(
              imageUrl: AppConfig.absoluteUrl(page.leagueLogo),
              width: 30,
              height: 30,
              errorWidget: (_, _, _) =>
                  const Icon(Icons.emoji_events_outlined, size: 24),
            ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  page.leagueName,
                  style: const TextStyle(
                      color: Brand.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  Fmt.round(page.round),
                  style:
                      const TextStyle(color: Brand.textFaint, fontSize: 11.5),
                ),
              ],
            ),
          ),
          if (prev != null)
            IconButton(
              icon: const Icon(Icons.chevron_right, size: 22),
              color: Brand.crown,
              onPressed: () => onJump(prev.round),
              tooltip: 'الجولة السابقة',
            ),
          if (next != null)
            IconButton(
              icon: const Icon(Icons.chevron_left, size: 22),
              color: Brand.crown,
              onPressed: () => onJump(next.round),
              tooltip: 'الجولة التالية',
            ),
        ],
      ),
    );
  }
}

/// صفّ مباراة: فريق — عدّادان — فريق، ومربّع المضاعِف في آخره.
class _FixtureRow extends StatelessWidget {
  final RoundFixture fixture;
  final int? home;
  final int? away;
  final bool x2;
  final int factor;
  final void Function(int? home, int? away, bool x2) onChanged;

  const _FixtureRow({
    required this.fixture,
    required this.home,
    required this.away,
    required this.x2,
    required this.factor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final open = fixture.open;
    final touched = home != null || away != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: touched ? Brand.crownWash(0.05) : Brand.surface,
        border: Border.all(color: Brand.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: _Side(name: fixture.homeName, logo: fixture.homeLogo)),
          if (open) ...[
            _Counter(
              value: home,
              onChanged: (v) => onChanged(v, away, x2),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 3),
              child: Text('-',
                  style: TextStyle(color: Brand.textFaint, fontSize: 13)),
            ),
            _Counter(
              value: away,
              onChanged: (v) => onChanged(home, v, x2),
            ),
          ] else
            SizedBox(
              width: 74,
              child: Center(
                child: Text(
                  fixture.predHome != null
                      ? '${fixture.predHome} - ${fixture.predAway}'
                      : '—',
                  style: const TextStyle(
                      color: Brand.textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          Expanded(
              child: _Side(
                  name: fixture.awayName,
                  logo: fixture.awayLogo,
                  reverse: true)),
          const SizedBox(width: 4),
          if (open)
            InkWell(
              onTap: () => onChanged(home, away, !x2),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 32,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: x2 ? Brand.crownWash(0.13) : Colors.transparent,
                  border:
                      Border.all(color: x2 ? Brand.crown : Brand.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '×$factor',
                  style: TextStyle(
                    color: x2 ? Brand.crown : Brand.textFaint,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 32),
        ],
      ),
    );
  }
}

class _Side extends StatelessWidget {
  final String name;
  final String logo;
  final bool reverse;

  const _Side({required this.name, required this.logo, this.reverse = false});

  @override
  Widget build(BuildContext context) {
    final badge = CachedNetworkImage(
      imageUrl: AppConfig.absoluteUrl(logo),
      width: 22,
      height: 22,
      errorWidget: (_, _, _) => const Icon(Icons.shield_outlined, size: 18),
    );
    final label = Flexible(
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: reverse ? TextAlign.start : TextAlign.end,
        style: const TextStyle(
            color: Brand.text, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );

    return Row(
      mainAxisAlignment:
          reverse ? MainAxisAlignment.start : MainAxisAlignment.end,
      children: reverse
          ? [badge, const SizedBox(width: 6), label]
          : [label, const SizedBox(width: 6), badge],
    );
  }
}

/// عدّاد صغير: ضغطة ترفع، وضغطة مطوّلة تُنقص.
///
/// زرّان لكل رقم يعنيان ستّة وثلاثين زرّاً في شاشة واحدة — والصفّ
/// يضيق بها حتى تُقصّ الأسماء. والضغطة المطوّلة للإنقاص مقبولة هنا
/// لأن الإنقاص نادر: من يخطئ يضغط حتى يلتفّ من 9 إلى 0.
class _Counter extends StatelessWidget {
  final int? value;
  final ValueChanged<int> onChanged;

  const _Counter({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final v = value;
    return InkWell(
      onTap: () => onChanged(v == null ? 0 : (v >= 9 ? 0 : v + 1)),
      onLongPress: () => onChanged(v == null || v == 0 ? 9 : v - 1),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: v == null ? Brand.fill : Brand.crownWash(0.10),
          border: Border.all(color: v == null ? Brand.border : Brand.crown),
          borderRadius: BorderRadius.circular(9),
        ),
        child: BrandNumber(v == null ? '–' : '$v', size: 17),
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  final String text;
  final Future<void> Function() onRetry;
  const _Retry({required this.text, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Brand.textMuted)),
              const SizedBox(height: 14),
              OutlinedButton(
                  onPressed: () => onRetry(),
                  child: const Text('أعد المحاولة')),
            ],
          ),
        ),
      );
}
