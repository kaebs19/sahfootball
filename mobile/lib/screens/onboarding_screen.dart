// رحلة "أول مرة" — تُعرض مرة واحدة بعد إنشاء الحساب مباشرة.
//
// ثلاث خطوات بترتيب متعمّد يطابق بناء اللعبة نفسها:
//   1. تابع دورياتك — عليها تُبنى بطاقات الرهان والتذكيرات، فهي
//      الأساس الذي بلا اختياره تبدو الخطوتان التاليتان فارغتين.
//   2. راهن على البطل — القرار الأغلى في اللعبة وأسعاره في أولها،
//      واللحظة الوحيدة المضمونة التي يكون فيها السعر بأعلاه هي الآن.
//   3. افهم النقاط — من يعرف أن المضبوطة بـ 100 وأن معه خمسة
//      مضاعِفات يلعب من اليوم الأول بدل أن يكتشف ذلك في الجولة
//      الخامسة.
//
// الجذر (_Root في main) يعرضها بدل الرئيسية ما دامت
// Session.needsOnboarding مرفوعة — فلا هي مسار يُدفع ويُنسى فوق
// الشجرة، ولا يمكن الالتفاف عليها بزر رجوع. و"تخطي" حاضرة في كل
// خطوة: الرحلة دعوة لا حاجز، ومن يتخطاها يجد كل شيء في الإعدادات.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../config.dart';
import '../models/champion.dart';
import '../models/rules.dart';
import '../state/session.dart';
import 'champion_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _step = 0;

  // خطوة الدوريات
  List<LeagueFollow>? _leagues;
  String? _leaguesError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadLeagues();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadLeagues() async {
    setState(() => _leaguesError = null);
    try {
      final leagues = await context.read<ApiClient>().leagues();
      if (mounted) setState(() => _leagues = leagues);
    } on ApiException catch (e) {
      if (mounted) setState(() => _leaguesError = e.message);
    }
  }

  /// حفظ المتابعات ثم الانتقال. فشل الحفظ يُبقي المستخدم في مكانه
  /// برسالة — التقدم فوق حفظٍ فاشل يعني بطاقات بطل فارغة بلا تفسير.
  Future<void> _saveLeaguesAndNext() async {
    final leagues = _leagues;
    if (leagues == null) return _next(); // تعذّر الجلب — لا تحبسه هنا
    setState(() => _saving = true);
    try {
      await context.read<ApiClient>().setFollowedLeagues(
            leagues.where((l) => l.followed).map((l) => l.id).toList(),
          );
      if (mounted) _next();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _next() {
    if (_step >= 2) return _finish();
    _pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _finish() => context.read<Session>().completeOnboarding();

  bool get _anyFollowed => _leagues?.any((l) => l.followed) ?? false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // الترويسة: نقاط التقدم يميناً (بداية السطر في RTL)
            // و"تخطي" يساراً — تخطي الرحلة كلها لا الخطوة.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 0),
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: i == _step ? 22 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == _step ? Brand.text : Brand.fillStrong,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  const Spacer(),
                  TextButton(
                    onPressed: _finish,
                    child: const Text('تخطي',
                        style: TextStyle(fontSize: 13.5)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                // التنقل بالأزرار فقط: الخطوة الأولى تحفظ عند الخروج
                // منها، والسحب الحر يقفز فوق الحفظ.
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _step = i),
                children: [
                  _LeaguesStep(
                    leagues: _leagues,
                    error: _leaguesError,
                    onRetry: _loadLeagues,
                    onToggle: (i, v) => setState(
                        () => _leagues![i] = _leagues![i].copyWith(followed: v)),
                  ),
                  _ChampionStep(followedAny: _anyFollowed),
                  const _RulesStep(),
                ],
              ),
            ),
            // زر الخطوة — نصه يقول ما سيحدث لا "التالي" المجرد.
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                child: FilledButton(
                  onPressed: _saving
                      ? null
                      : switch (_step) {
                          0 => _saveLeaguesAndNext,
                          1 => _next,
                          _ => _finish,
                        },
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Brand.onAccent),
                        )
                      : Text(switch (_step) {
                          0 => _anyFollowed
                              ? 'احفظ دورياتي وواصل'
                              : 'واصل بلا متابعة',
                          1 => 'واصل',
                          _ => 'ابدأ اللعب',
                        }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────── الخطوة 1: الدوريات ───────────────────────

class _LeaguesStep extends StatelessWidget {
  final List<LeagueFollow>? leagues;
  final String? error;
  final VoidCallback onRetry;
  final void Function(int index, bool value) onToggle;

  const _LeaguesStep({
    required this.leagues,
    required this.error,
    required this.onRetry,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'تابع دورياتك',
      subtitle: 'اختر دورياً أو أكثر — عليها تُبنى رهانات الأبطال '
          'وتذكيرات المباريات، وتغييرها لاحقاً من الإعدادات.',
      child: error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Brand.textMuted)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                      onPressed: onRetry, child: const Text('إعادة المحاولة')),
                ],
              ),
            )
          : leagues == null
              ? const Center(
                  child: CircularProgressIndicator(color: Brand.crown))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  itemCount: leagues!.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final l = leagues![i];
                    final on = l.followed;
                    return InkWell(
                      onTap: () => onToggle(i, !on),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 12),
                        decoration: BoxDecoration(
                          color: on ? Brand.crownWash(0.10) : Brand.fill,
                          border: Border.all(
                              color: on ? Brand.crown : Brand.border),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              on
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              color: on ? Brand.crown : Brand.textFaint,
                              size: 21,
                            ),
                            const SizedBox(width: 11),
                            if (l.logoUrl != null)
                              CachedNetworkImage(
                                imageUrl: AppConfig.absoluteUrl(l.logoUrl!),
                                width: 26,
                                height: 26,
                                errorWidget: (_, _, _) => const Icon(
                                    Icons.emoji_events_outlined,
                                    size: 22),
                              ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                l.name,
                                style: TextStyle(
                                  color: on ? Brand.text : Brand.textMuted,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
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

// ─────────────────────── الخطوة 2: البطل ───────────────────────

class _ChampionStep extends StatelessWidget {
  final bool followedAny;

  const _ChampionStep({required this.followedAny});

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'من يرفع الكأس؟',
      subtitle: 'رهان واحد لكل دوري تتابعه على بطل الموسم — وجائزته '
          'تتناقص كل جولة، فأعلى سعر له هو الآن.',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.emoji_events_outlined,
                  size: 56, color: Brand.crown),
              const SizedBox(height: 18),
              FutureBuilder<GameRules>(
                future: context.read<ApiClient>().rules(),
                builder: (_, snap) {
                  final max =
                      (snap.data ?? GameRules.fallback).championMax;
                  return Text(
                    'أصِب البطل من بداية الموسم واكسب حتى $max نقطة '
                    'دفعة واحدة.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Brand.textMuted, fontSize: 14.5, height: 1.7),
                  );
                },
              ),
              const SizedBox(height: 22),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  side: const BorderSide(color: Brand.crown),
                  foregroundColor: Brand.crown,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  textStyle: const TextStyle(
                    fontFamily: Brand.displayFont,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                // شاشة الرهان الكاملة نفسها — بأسعارها وقواعدها،
                // لا نسخة مصغرة تتقادم عند أول تعديل عليها.
                onPressed: followedAny
                    ? () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ChampionScreen()))
                    : null,
                child: Text(followedAny
                    ? 'اختر بطلك الآن'
                    : 'تابع دورياً أولاً لتراهن على بطله'),
              ),
              const SizedBox(height: 8),
              const Text(
                'وتقدر تراهن لاحقاً من الإعدادات ← من يرفع الكأس؟',
                textAlign: TextAlign.center,
                style: TextStyle(color: Brand.textFaint, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────── الخطوة 3: كيف تلعب ───────────────────────

class _RulesStep extends StatelessWidget {
  const _RulesStep();

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'كيف تجمع النقاط؟',
      subtitle: 'توقّع نتيجة كل مباراة قبل انطلاقها — '
          'التوقعات تُقفل عند صافرة البداية.',
      child: FutureBuilder<GameRules>(
        future: context.read<ApiClient>().rules(),
        builder: (_, snap) {
          final r = snap.data ?? GameRules.fallback;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            children: [
              _RuleCard(
                icon: Icons.gps_fixed,
                iconColor: Brand.correct,
                title: 'أصبت النتيجة بالضبط',
                points: '${r.exact} نقطة',
              ),
              const SizedBox(height: 8),
              _RuleCard(
                icon: Icons.swap_vert,
                iconColor: Brand.text,
                title: 'أصبت فارق الأهداف',
                points: '${r.diff} نقطة',
              ),
              const SizedBox(height: 8),
              _RuleCard(
                icon: Icons.check,
                iconColor: Brand.text,
                title: 'أصبت الفائز فقط',
                points: '${r.outcome} نقطة',
              ),
              const SizedBox(height: 8),
              _RuleCard(
                icon: Icons.bolt,
                iconColor: Brand.crown,
                title: 'المضاعِف ×${r.multiplierFactor}',
                points: '${r.multipliersFree} لكل دوري في الموسم',
                subtitle: 'فعّله على مباراة واثق منها وتتضاعف نقاطها.',
              ),
              const SizedBox(height: 8),
              _RuleCard(
                icon: Icons.emoji_events_outlined,
                iconColor: Brand.crown,
                title: 'رهان البطل',
                points: 'حتى ${r.championMax} نقطة',
                subtitle: 'كلما بكّرت كان أعلى — ويمكن تغييره بسعر يومه.',
              ),
              const SizedBox(height: 8),
              const _RuleCard(
                icon: Icons.calendar_month_outlined,
                iconColor: Brand.text,
                title: 'توقّع الجولة كاملة',
                points: 'شاشة واحدة',
                subtitle:
                    'كل مباريات الجولة بضغطة حفظ واحدة — من الإعدادات '
                    '← توقّع الجولة.',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String points;
  final String? subtitle;

  const _RuleCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.points,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Brand.fill,
        border: Border.all(color: Brand.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Brand.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!,
                      style: const TextStyle(
                          color: Brand.textFaint,
                          fontSize: 12,
                          height: 1.5)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            points,
            style: const TextStyle(
              color: Brand.crown,
              fontFamily: Brand.displayFont,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              fontFeatures: Brand.tabular,
            ),
          ),
        ],
      ),
    );
  }
}

/// هيكل موحّد للخطوات الثلاث: عنوان كبير + شرح + محتوى.
class _StepScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _StepScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontSize: 24)),
              const SizedBox(height: 7),
              Text(subtitle,
                  style: const TextStyle(
                      color: Brand.textMuted, fontSize: 13.5, height: 1.65)),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
