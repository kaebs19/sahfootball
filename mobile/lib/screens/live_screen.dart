// تبويب "مباشر".
//
// الفرق عن تبويب "المباريات" فرق سؤال لا فرق ترتيب:
//
//   المباريات → "متى ألعب وماذا أتوقّع؟"  جدول، مرتب بالموعد،
//               وكل بطاقة تدعوك لتسجيل توقّع.
//   مباشر     → "ماذا يحدث لتوقّعي الآن؟"  نتيجة جارية بالدقيقة،
//               وكل بطاقة تخبرك بحالك أنت في هذه اللحظة.
//
// لذلك لا يعرض هذا التبويب زر توقّع إطلاقاً: التوقّع أُقفل عند
// الانطلاق، وعرض زر معطّل هنا يوحي بإمكان لا وجود له.
//
// التحديث: نسحب كل 20 ثانية ما دامت الشاشة ظاهرة. الطلب يذهب
// لسيرفرنا لا للمزوّد — المزوّد خلف مجدول وكاش — فتكلفته صفر من
// الحصة اليومية. ونوقف المؤقّت عند مغادرة الشاشة أو خروج التطبيق
// للخلفية: تحديث شاشة لا يراها أحد استنزاف بطارية بلا مقابل.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../models/live_fixture.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/live_match_card.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> with WidgetsBindingObserver {
  static const _refreshEvery = Duration(seconds: 20);

  LiveState? _state;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // التطبيق في الخلفية لا يعرض شيئاً — نوقف السحب ونستأنفه بتحديث
    // فوري عند العودة، كي لا يرى المستخدم نتيجة قديمة للحظة.
    if (state == AppLifecycleState.resumed) {
      _load();
      _startTimer();
    } else {
      _timer?.cancel();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_refreshEvery, (_) => _load(silent: true));
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _error = null);
    try {
      final state = await context.read<ApiClient>().liveState();
      if (mounted) setState(() => _state = state);
    } on ApiException catch (e) {
      // التحديث الصامت لا يمسح ما على الشاشة عند فشل شبكة عابر:
      // إظهار خطأ مكان نتيجة صحيحة كل عشرين ثانية أسوأ من إبقائها.
      if (mounted && !silent) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _state == null) {
      return BrandEmpty(
        icon: Icons.wifi_off,
        message: _error!,
        onRetry: _load,
      );
    }
    final state = _state;
    if (state == null) {
      return const Center(child: CircularProgressIndicator(color: Brand.crown));
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: Brand.crown,
      backgroundColor: Brand.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
        children: [
          if (state.live.isNotEmpty) ...[
            const _SectionHeader(label: 'تُلعب الآن', pulsing: true),
            for (final m in state.live)
              LiveMatchCard(match: m, mode: LiveCardMode.live),
          ] else
            _QuietState(next: state.nextKickoff),

          if (state.finishedToday.isNotEmpty) ...[
            const SizedBox(height: 18),
            const _SectionHeader(label: 'انتهت اليوم'),
            for (final m in state.finishedToday)
              LiveMatchCard(match: m, mode: LiveCardMode.finished),
          ],
        ],
      ),
    );
  }
}

/// عنوان قسم، مع نقطة نابضة للقسم الجاري.
class _SectionHeader extends StatefulWidget {
  final String label;
  final bool pulsing;
  const _SectionHeader({required this.label, this.pulsing = false});

  @override
  State<_SectionHeader> createState() => _SectionHeaderState();
}

class _SectionHeaderState extends State<_SectionHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    // النبض للجاري فقط: حركة دائمة بلا معنى تشوّش، وحركة تعني
    // "هذا يتغير أمامك الآن" تُقرأ فوراً.
    if (widget.pulsing) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
      child: Row(
        children: [
          if (widget.pulsing)
            FadeTransition(
              opacity: Tween(begin: 1.0, end: 0.25).animate(_c),
              child: Container(
                width: 8,
                height: 8,
                margin: const EdgeInsetsDirectional.only(end: 8),
                decoration: const BoxDecoration(
                  color: Brand.wrong,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          Text(
            widget.label,
            style: TextStyle(
              fontFamily: Brand.displayFont,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: widget.pulsing ? Brand.wrong : Brand.crown,
            ),
          ),
        ],
      ),
    );
  }
}

/// ما تعرضه الشاشة حين لا تُلعب أي مباراة — وهو الحال الغالب.
///
/// عرض "لا مباريات" وحده يجعل التبويب ميتاً معظم اليوم. المباراة
/// القادمة بعدّادها تحوّل الانتظار نفسه إلى محتوى.
class _QuietState extends StatelessWidget {
  final LiveFixture? next;
  const _QuietState({this.next});

  @override
  Widget build(BuildContext context) {
    final f = next?.fixture;

    return Column(
      children: [
        const SizedBox(height: 26),
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: Brand.fill,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.stadium_outlined,
              size: 28, color: Brand.textFaint),
        ),
        const SizedBox(height: 14),
        Text(
          'لا مباريات تُلعب الآن',
          style: TextStyle(
            fontFamily: Brand.displayFont,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Brand.text,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'حين تنطلق مباراة ستجدها هنا بنتيجتها لحظة بلحظة.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Brand.textMuted, fontSize: 13, height: 1.6),
        ),
        if (f != null) ...[
          const SizedBox(height: 26),
          const _SectionHeader(label: 'المباراة القادمة'),
          _NextUpCard(match: next!),
        ],
      ],
    );
  }
}

class _NextUpCard extends StatefulWidget {
  final LiveFixture match;
  const _NextUpCard({required this.match});

  @override
  State<_NextUpCard> createState() => _NextUpCardState();
}

class _NextUpCardState extends State<_NextUpCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // العدّاد يتحرك كل ثانية، وهو الشيء الوحيد المتحرك في شاشة
    // ساكنة — يقول للمستخدم إن الشاشة حيّة وإن الانتظار يقصر.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.match.fixture;
    final left = f.kickoffAt.difference(DateTime.now());
    final fmt = intl.DateFormat('EEEE d MMMM · h:mm a', 'ar');

    String countdown() {
      if (left.isNegative) return 'تنطلق الآن';
      final h = left.inHours;
      final m = left.inMinutes % 60;
      final s = left.inSeconds % 60;
      if (h >= 24) return 'بعد ${left.inDays} يوم';
      if (h > 0) return 'بعد $h:${m.toString().padLeft(2, '0')} ساعة';
      return 'بعد $m:${s.toString().padLeft(2, '0')} دقيقة';
    }

    return BrandCard(
      royal: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(
        children: [
          Text(
            countdown(),
            style: const TextStyle(
              fontFamily: Brand.displayFont,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Brand.crown,
              fontFeatures: Brand.tabular,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            fmt.format(f.kickoffAt),
            style: const TextStyle(color: Brand.textFaint, fontSize: 11.5),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _MiniTeam(name: f.homeTeamName, logo: f.homeTeamLogo)),
              const Text('ضد',
                  style: TextStyle(color: Brand.textFaint, fontSize: 12)),
              Expanded(child: _MiniTeam(name: f.awayTeamName, logo: f.awayTeamLogo)),
            ],
          ),
          if (widget.match.myPrediction != null) ...[
            const SizedBox(height: 12),
            BrandChip(
              label:
                  'توقعك ${widget.match.myPrediction!.home} - ${widget.match.myPrediction!.away}',
              icon: Icons.check_circle_outline,
              tone: BrandTone.correct,
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniTeam extends StatelessWidget {
  final String name;
  final String? logo;
  const _MiniTeam({required this.name, this.logo});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (logo != null)
          Image.network(logo!,
              width: 34,
              height: 34,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.shield, size: 34, color: Brand.textFaint))
        else
          const Icon(Icons.shield, size: 34, color: Brand.textFaint),
        const SizedBox(height: 6),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Brand.text, fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
