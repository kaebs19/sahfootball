// شاشة رهان البطل — من يرفع الكأس؟
//
// توقّعُ مباراةٍ قرار دقائق، وتوقّعُ بطلٍ قرار موسم. ولهذا شاشة
// مستقلة لا صفٌّ في قائمة: القرار يُتَّخذ مرة في العام، ويستحق
// أن يُقرأ سعره وقاعدته قبله.
//
// والسعر معروض بأجزائه لا كرقم: "مضى 11% من الموسم فقيمته 886"
// يفهمها اللاعب ويقرّر بها، و"886" وحدها تبدو اعتباطاً. وقاعدة
// التناقص تُقال صراحةً — من يعرف أن السعر ينزل كل جولة يقرّر
// اليوم، ومن لا يعرفها يؤجّل ثم يشعر أنه خُدع.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../config.dart';
import '../models/champion.dart';
import '../widgets/brand_widgets.dart';
import 'leagues_screen.dart';

class ChampionScreen extends StatefulWidget {
  const ChampionScreen({super.key});

  @override
  State<ChampionScreen> createState() => _ChampionScreenState();
}

class _ChampionScreenState extends State<ChampionScreen> {
  List<ChampionCard>? _cards;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final cards = await context.read<ApiClient>().championCards();
      if (mounted) setState(() => _cards = cards);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _pick(ChampionCard card, ChampionTeam team) async {
    try {
      await context
          .read<ApiClient>()
          .pickChampion(leagueId: card.leagueId, teamId: team.id);
      // نُعيد الجلب بدل تعديل الحالة محلياً: السعر يُقفل في الخادم
      // لحظة الاختيار، وتخمينه هنا يعرض رقماً قد يخالف المحفوظ.
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = _cards;
    return Scaffold(
      appBar: AppBar(title: const Text('من يرفع الكأس؟')),
      body: _error != null
          ? _Message(text: _error!, onRetry: _load)
          : cards == null
              ? const Center(child: CircularProgressIndicator())
              : cards.isEmpty
                  ? _NoLeagues(onDone: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
                        children: [
                          for (final c in cards) ...[
                            _CardView(card: c, onPick: (t) => _pick(c, t)),
                            const SizedBox(height: 14),
                          ],
                        ],
                      ),
                    ),
    );
  }
}

class _CardView extends StatelessWidget {
  final ChampionCard card;
  final ValueChanged<ChampionTeam> onPick;

  const _CardView({required this.card, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final mine = card.mine;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.surface,
        border: Border.all(color: Brand.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  card.leagueName,
                  style: const TextStyle(
                      color: Brand.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                ),
              ),
              BrandChip(
                label: '${mine?.award ?? card.award} نقطة',
                tone: BrandTone.crown,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            mine == null
                ? 'مضى ${card.progressPct}% من الموسم، فقيمة الرهان الآن '
                    '${card.award} من ${card.maxAward}.'
                : 'رهانك محفوظ بـ ${mine.award} نقطة. تغييره الآن يُعيد تسعيره '
                    'بـ ${card.award} — السعر ينزل مع الموسم.',
            style: const TextStyle(
                color: Brand.textMuted, fontSize: 12.5, height: 1.6),
          ),
          const SizedBox(height: 14),
          // شبكة الأندية: ضغطة واحدة تختار وترسل. الخطوة التي لا
          // وجود لها لا تُنسى ولا تُخطئ.
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: card.teams.length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 92,
              mainAxisExtent: 84,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (_, i) {
              final t = card.teams[i];
              return _TeamTile(
                team: t,
                picked: mine?.teamId == t.id,
                onTap: () => onPick(t),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TeamTile extends StatelessWidget {
  final ChampionTeam team;
  final bool picked;
  final VoidCallback onTap;

  const _TeamTile(
      {required this.team, required this.picked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: picked ? Brand.crownWash(0.13) : Brand.fill,
          border: Border.all(color: picked ? Brand.crown : Brand.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (team.logoUrl != null)
              CachedNetworkImage(
                imageUrl: AppConfig.absoluteUrl(team.logoUrl!),
                width: 30,
                height: 30,
                errorWidget: (_, _, _) =>
                    const Icon(Icons.shield_outlined, size: 26),
              )
            else
              const Icon(Icons.shield_outlined, size: 26),
            const SizedBox(height: 5),
            Text(
              team.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: picked ? Brand.crown : Brand.textMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// لا دوريات متابَعة: البطاقات تُبنى على المتابعة، وشاشة فارغة
/// بلا طريق إليها أسوأ من رسالة.
class _NoLeagues extends StatelessWidget {
  final Future<void> Function() onDone;
  const _NoLeagues({required this.onDone});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'تابِع دورياً لتراهن على بطله',
                style: TextStyle(
                    color: Brand.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'الجائزة تصل 1000 نقطة، وتنقص مع كل جولة تُلعب.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Brand.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const LeaguesScreen()));
                  await onDone();
                },
                child: const Text('اختر دورياتك'),
              ),
            ],
          ),
        ),
      );
}

class _Message extends StatelessWidget {
  final String text;
  final Future<void> Function() onRetry;
  const _Message({required this.text, required this.onRetry});

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
                  onPressed: () => onRetry(), child: const Text('أعد المحاولة')),
            ],
          ),
        ),
      );
}
