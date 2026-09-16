// تهيئة «فريقي» — ثلاث خطوات قبل أول تشكيلة.
//
// ولماذا شاشةٌ كاملة وليست حواراً أو شريحةً في الأعلى؟ لأن أول
// دخول يحمل ثلاثة قرارات لا واحداً: أيّ دوري، وأيّ نادٍ، وهل
// تفهم اللعبة أصلاً. ومن دخل فوجد ملعباً فارغاً بخمس عشرة خانة
// بلا أن يُسأل عن ناديه ولا يُقال له ما الميزانية — يخرج.
//
// وترتيب الخطوات ليس اعتباطاً: الدوري يحدّد الأندية، والنادي
// يحدّد ثلاثة من تشكيلتك. القرار الذي يقيّد غيره يأتي أولاً.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../config.dart';
import '../format.dart';
import '../models/fantasy.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/fantasy_sounds.dart';

class FantasySetupScreen extends StatefulWidget {
  /// الدوري المفتوح ابتداءً — من شريط المباريات إن كان مختاراً.
  final int? initialLeague;

  const FantasySetupScreen({super.key, this.initialLeague});

  @override
  State<FantasySetupScreen> createState() => _FantasySetupScreenState();
}

class _FantasySetupScreenState extends State<FantasySetupScreen> {
  FantasySetup? _setup;
  int? _league;
  int? _club;

  /// نادٍ مثبَّت سلفاً في هذا الدوري — يُعرض ولا يُبدَّل.
  int? _locked;
  String? _error;
  bool _loading = true;
  bool _saving = false;

  /// شبكة الأندية تطول (١٨ نادياً = خمسة صفوف)، فالخطوة الثالثة
  /// تقع تحت حافة الشاشة. ومن اختار ناديه فلم يرَ بعده شيئاً ظنّ
  /// أن الرحلة انتهت — قِيس على المستخدم الأول فوقع.
  ///
  /// فالشاشة تسوق نفسها إلى ما بعد الاختيار: الخطوة التالية تظهر
  /// لأن الأولى تمّت، لا لأن أحداً خمّن أن تحتها شيئاً.
  final _scroll = ScrollController();
  final _rulesKey = GlobalKey();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _revealRules() {
    // بعد الإطار: الشبكة تُعاد بناؤها بالاختيار، والسوق قبل ذلك
    // يقيس ارتفاعاً قديماً.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _rulesKey.currentContext;
      if (box == null || !_scroll.hasClients) return;
      Scrollable.ensureVisible(
        box,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0.1,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _league = widget.initialLeague;
    _load();
  }

  Future<void> _load({int? league}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final setup = await context
          .read<ApiClient>()
          .fantasySetup(leagueId: league ?? _league);
      if (!mounted) return;
      setState(() {
        _setup = setup;
        _league = setup.leagueId;
        // تبديل الدوري يمسح النادي: نادي الدوري السابق لا وجود له
        // في القائمة الجديدة، وتركُه يعني تشكيلةً ترفضها القاعدة.
        if (league != null) _club = null;
        // وكل دوري وناديه: من ثبّت ناديه في السعودي يجد الإسباني
        // مفتوحاً له.
        _locked = setup.club;
        if (_locked != null) _club = _locked;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => (_error = e.message, _loading = false));
    }
  }

  /// تثبيت النادي في الخادم ثم العودة إلى الملعب.
  ///
  /// الحفظ هنا لا عند اكتمال الخمسة عشر: بينهما رحلةٌ في السوق،
  /// ومن خرج في منتصفها كان يعود فيجد «ابنِ فريقك» كأنه لم يختر
  /// شيئاً — وهذا هو العيب الذي أُصلح.
  ///
  /// ولا نعود قبل أن يُقبل الحفظ: العودة أولاً تعني ملعباً يحمل
  /// شعار نادٍ لم يُثبَّت، وهي كذبةٌ تظهر عند أول تحديث.
  Future<void> _confirm() async {
    final league = _league;
    final club = _club;
    if (league == null || club == null) return;

    // النادي لا يتغيّر بعد تثبيته (قاعدة لعبة يفرضها الخادم)،
    // فيُقال ذلك **قبل** لا بعد: من يكتشف أن اختياره نهائي بعد
    // وقوعه يقرأ القاعدة عقوبةً، ومن يقرأها قبله يقرأها قراراً.
    if (_locked == null) {
      final name = _setup?.clubs
          .where((c) => c.id == club)
          .map((c) => c.name)
          .firstOrNull;
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: Brand.surface,
          title: Text('${name ?? 'هذا النادي'} فريقك؟',
              style: const TextStyle(color: Brand.text, fontSize: 16)),
          content: const Text(
            'شعاره يصير شعار فريقك، وثلاثة من لاعبيه في تشكيلتك '
            'دائماً — ولا يتغيّر هذا الموسم.',
            style: TextStyle(color: Brand.textMuted, fontSize: 13, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('أعيد النظر',
                  style: TextStyle(color: Brand.textMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('هو فريقي',
                  style: TextStyle(color: Brand.crown)),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      await context
          .read<ApiClient>()
          .setFantasyClub(leagueId: league, clubTeamId: club);
      if (!mounted) return;
      FantasySounds.play(Sfx.save);
      Navigator.of(context).pop((league: league, club: club));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      FantasySounds.play(Sfx.error);
      // رسالة الخادم كما هي: هو من يعرف القاعدة المكسورة.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: Brand.wrong,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.night,
      appBar: AppBar(title: const Text('ابدأ فريقك')),
      body: _buildBody(),
      bottomNavigationBar: _club == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _saving ? null : _confirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: Brand.primaryButton,
                    foregroundColor: Brand.onAccent,
                    disabledBackgroundColor: Brand.fillStrong,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Brand.radiusChip),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.2, color: Brand.onAccent),
                        )
                      : const Text('ابنِ تشكيلتي',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Brand.crown));
    }
    final setup = _setup;
    if (_error != null || setup == null) {
      return BrandEmpty(
        icon: Icons.wifi_off,
        message: _error ?? 'تعذّر التحميل',
        onRetry: () => _load(),
      );
    }
    if (setup.followRequired) {
      return const BrandEmpty(
        icon: Icons.emoji_events_outlined,
        message: '«فريقي» يُلعب في الدوريات المحلية — تابِع أحدها لتبدأ،\n'
            'فتشكيلتك تُبنى من لاعبيه.',
      );
    }

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const _Step(number: 1, title: 'اختر الدوري'),
        const SizedBox(height: 8),
        // دوريٌ واحد لا يُسأل عنه: سؤالٌ بجوابٍ واحد يبدو حاجزاً.
        if (setup.leagues.length == 1)
          _OneLine(text: setup.leagues.first.name)
        else
          for (final l in setup.leagues)
            _LeagueTile(
              league: l,
              selected: l.id == _league,
              onTap: () => _load(league: l.id),
            ),

        const SizedBox(height: 22),
        const _Step(number: 2, title: 'اختر ناديك'),
        const SizedBox(height: 4),
        Text(
          _locked != null
              ? 'ناديك في هذا الدوري مثبَّت — ولا يتغيّر هذا الموسم.'
              : 'شعاره يصير شعار فريقك، و${Fmt.number(setup.rules.minFromClub)} '
                  'من لاعبيه في تشكيلتك دائماً. واختياره نهائي.',
          style: const TextStyle(color: Brand.textMuted, fontSize: 12.5, height: 1.5),
        ),
        const SizedBox(height: 10),
        _ClubGrid(
          clubs: setup.clubs,
          selected: _club,
          locked: _locked != null,
          onPick: (id) {
            FantasySounds.play(Sfx.pop);
            setState(() => _club = id);
            _revealRules();
          },
        ),

        SizedBox(key: _rulesKey, height: 22),
        const _Step(number: 3, title: 'قواعد اللعبة'),
        const SizedBox(height: 8),
        _RulesCard(rules: setup.rules),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String title;
  const _Step({required this.number, required this.title});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Brand.crown,
              shape: BoxShape.circle,
            ),
            child: Text(Fmt.number(number),
                style: const TextStyle(
                    color: Brand.onAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 9),
          Text(title,
              style: const TextStyle(
                color: Brand.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                fontFamily: Brand.displayFont,
              )),
        ],
      );
}

class _OneLine extends StatelessWidget {
  final String text;
  const _OneLine({required this.text});

  @override
  Widget build(BuildContext context) => BrandCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Brand.crown, size: 18),
            const SizedBox(width: 9),
            Text(text,
                style: const TextStyle(color: Brand.text, fontSize: 14)),
          ],
        ),
      );
}

class _LeagueTile extends StatelessWidget {
  final FantasySetupLeague league;
  final bool selected;
  final VoidCallback onTap;

  const _LeagueTile({
    required this.league,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: BrandCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CachedNetworkImage(
                imageUrl: AppConfig.absoluteUrl(league.logoUrl),
                errorWidget: (_, _, _) =>
                    const Icon(Icons.shield_outlined, color: Brand.textFaint, size: 20),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(league.name,
                  style: TextStyle(
                    color: Brand.text,
                    fontSize: 14.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  )),
            ),
            // «لك فريق هنا» أهمّ من علامة الاختيار: من يتابع دوريين
            // يريد أن يعرف أين بدأ قبل أن يقرّر أين يبدأ.
            if (league.hasSquad)
              const Text('لك فريق هنا',
                  style: TextStyle(color: Brand.correct, fontSize: 11.5))
            else if (selected)
              const Icon(Icons.radio_button_checked, color: Brand.crown, size: 18)
            else
              const Icon(Icons.radio_button_off, color: Brand.textFaint, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ClubGrid extends StatelessWidget {
  final List<FantasyClub> clubs;
  final int? selected;

  /// نادٍ مثبَّت: الشبكة تُعرض للقراءة، وغيرُ المختار يخفت.
  final bool locked;
  final ValueChanged<int> onPick;

  const _ClubGrid({
    required this.clubs,
    required this.selected,
    required this.onPick,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    // شبكةٌ لا قائمة: الأندية تُعرف بشعاراتها لا بأسمائها، ومن
    // يبحث عن ناديه يمسح الشعارات بعينه في ثانية — بينما قائمةٌ
    // من عشرين سطراً تُقرأ سطراً سطراً.
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 0.82,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: clubs.length,
      itemBuilder: (_, i) {
        final club = clubs[i];
        final isOn = club.id == selected;
        // المقفل يبقى ظاهراً لا يختفي: من ثبّت ناديه يريد أن يراه،
        // وشبكةٌ فيها ناديه وحده تبدو عطلاً.
        if (locked && !isOn) {
          return Opacity(opacity: 0.32, child: _ClubTile(club: club, isOn: false));
        }
        return GestureDetector(
          onTap: locked ? null : () => onPick(club.id),
          behavior: HitTestBehavior.opaque,
          child: _ClubTile(club: club, isOn: isOn),
        );
      },
    );
  }
}

/// مربّع نادٍ في الشبكة — شعارٌ واسم، والاختيار إطارٌ ذهبي.
class _ClubTile extends StatelessWidget {
  final FantasyClub club;
  final bool isOn;

  const _ClubTile({required this.club, required this.isOn});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: isOn ? Brand.fillStrong : Brand.fill,
        borderRadius: BorderRadius.circular(Brand.radiusSmall),
        border: Border.all(
          color: isOn ? Brand.crown : Brand.borderSoft,
          width: isOn ? 1.5 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: club.logoUrl == null
                ? const Icon(Icons.shield_outlined,
                    color: Brand.textFaint, size: 26)
                : CachedNetworkImage(
                    imageUrl: AppConfig.absoluteUrl(club.logoUrl!),
                    errorWidget: (_, _, _) => const Icon(Icons.shield_outlined,
                        color: Brand.textFaint, size: 26),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            club.name,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isOn ? Brand.text : Brand.textMuted,
              fontSize: 10,
              height: 1.25,
              fontWeight: isOn ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _RulesCard extends StatelessWidget {
  final FantasyRules rules;
  const _RulesCard({required this.rules});

  @override
  Widget build(BuildContext context) {
    // الشرح هنا لا في صفحة مساعدة: من يقرأ القواعد وهو يبني أوّل
    // مرة يتذكّرها، ومن يُحال إلى صفحةٍ أخرى لا يفتحها.
    final lines = <(IconData, String, String)>[
      (
        Icons.groups_2_outlined,
        '${Fmt.number(rules.squadSize)} لاعباً',
        '${Fmt.number(rules.starters)} أساسيين و'
            '${Fmt.number(rules.squadSize - rules.starters)} بدلاء'
      ),
      (
        Icons.account_balance_wallet_outlined,
        'ميزانية ${Fmt.number(rules.budget)}',
        'تنمو حين تبيع لاعباً ارتفع سعره'
      ),
      (
        Icons.favorite_outline,
        '${Fmt.number(rules.minFromClub)} من ناديك',
        'على الأقل — وهذا ما يجعله فريقك'
      ),
      (
        Icons.shield_outlined,
        '${Fmt.number(rules.maxFromClub)} من أي نادٍ',
        'كحدّ أقصى، كي لا تصير التشكيلة نادياً واحداً'
      ),
      (
        Icons.workspace_premium_outlined,
        'الكابتن ×٢',
        'نقاطه مضاعفة، ونائبه يحلّ محلّه إن لم يلعب'
      ),
      (
        Icons.swap_horiz,
        'انتقال مجاني كل جولة',
        'يتراكم حتى ٥، وما زاد يكلّف ٤ نقاط'
      ),
      (
        Icons.lock_clock_outlined,
        'الإقفال مع أول مباراة',
        'بعدها تُجمَّد تشكيلتك لتلك الجولة'
      ),
    ];

    return BrandCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        children: [
          for (final (icon, title, body) in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: Brand.crown, size: 17),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                color: Brand.text,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(body,
                            style: const TextStyle(
                                color: Brand.textFaint,
                                fontSize: 11.5,
                                height: 1.45)),
                      ],
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
