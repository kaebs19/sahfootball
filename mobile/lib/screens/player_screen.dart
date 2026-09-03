// ملف لاعب — من هذا الذي يتصدّرني؟
//
// يُفتح من صفّ في العرش أو عضو في مجلس. يجيب بالترتيب: من هو
// (الاسم والرتبة والنقاط) ← أين هو (المركز) ← كيف يلعب (الدقة
// والسلسلة والعدد) ← أين يلعب (الحصيلة لكل دوري) ← ماذا نال
// (الأوسمة المكتسبة).
//
// نفس ترتيب «ملفي» عمداً — الشاشتان تُقرآن بالعين نفسها — لكن بلا
// سجلّ توقعات ولا إعدادات: توقعات غيري لا تُرى إلا في مجلس وبعد
// انطلاق المباراة، وذلك لسبب مشروح في السيرفر.
//
// عامة للضيف أيضاً: العرش عام، ومن يُعرض فيه يجوز أن يُعرف.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../config.dart';
import '../models/player.dart';
import '../state/session.dart';
import '../widgets/badge_grid.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/league_stats_card.dart';
import 'leaderboard_screen.dart' show Rank;

class PlayerScreen extends StatefulWidget {
  final String userId;

  /// الاسم إن عُرف من الشاشة السابقة — يُعرض في الترويسة فوراً
  /// بدل ترويسة فارغة حتى يصل الرد.
  final String? displayName;

  const PlayerScreen({super.key, required this.userId, this.displayName});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  PlayerProfile? _player;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final player = await context.read<ApiClient>().player(widget.userId);
      if (mounted) setState(() => _player = player);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _player;
    final isMe = context.watch<Session>().user?.id == widget.userId;

    return Scaffold(
      appBar: AppBar(title: Text(p?.displayName ?? widget.displayName ?? 'لاعب')),
      body: _error != null
          ? BrandEmpty(icon: Icons.wifi_off, message: _error!, onRetry: _load)
          : p == null
              ? const Center(
                  child: CircularProgressIndicator(color: Brand.crown))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: Brand.crown,
                  backgroundColor: Brand.surface,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                    children: [
                      _Identity(player: p, isMe: isMe),
                      const SizedBox(height: 12),
                      _Stats(player: p),
                      const SizedBox(height: 18),
                      const BrandSectionLabel('حسب الدوري'),
                      const SizedBox(height: 10),
                      if (p.byLeague.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Text(
                            'لم يلعب في أي دوري بعد',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Brand.textMuted),
                          ),
                        )
                      else
                        for (final l in p.byLeague)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child:
                                LeagueStatsCard(league: l, showFollowed: false),
                          ),
                      // الشريط كاملاً حين نال وساماً واحداً على الأقل:
                      // «1 من 9» يقول كم أنجز من الطريق، أما قصّ القائمة
                      // على المكتسب فيجعل العدّاد يقول «1 من 1» بلا معنى.
                      // ومن لم ينل شيئاً لا يُعرض له شريط مطفأ بالكامل.
                      if (p.badges.any((b) => b.earned)) ...[
                        const SizedBox(height: 14),
                        BadgeStrip(badges: p.badges),
                      ],
                    ],
                  ),
                ),
    );
  }
}

/// الهوية: الصورة والاسم والرتبة، والنقاط، والمركز في العرش.
class _Identity extends StatelessWidget {
  final PlayerProfile player;
  final bool isMe;
  const _Identity({required this.player, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final p = player;
    return BrandCard(
      royal: true,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        children: [
          Row(
            children: [
              _Avatar(url: p.avatarUrl, name: p.displayName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            p.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: Brand.displayFont,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Brand.text,
                            ),
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 6),
                          const Text('· أنت',
                              style: TextStyle(
                                  color: Brand.crown, fontSize: 12)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        BrandChip(
                          label: Rank.of(p.totalPoints).label,
                          icon: Icons.workspace_premium,
                          tone: BrandTone.crown,
                        ),
                        if (p.favoriteTeam?.logoUrl != null) ...[
                          const SizedBox(width: 8),
                          CachedNetworkImage(
                            imageUrl:
                                AppConfig.absoluteUrl(p.favoriteTeam!.logoUrl!),
                            width: 18,
                            height: 18,
                            errorWidget: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  BrandNumber('${p.totalPoints}', size: 24, color: Brand.crown),
                  const Text('نقطة',
                      style: TextStyle(color: Brand.textFaint, fontSize: 10.5)),
                ],
              ),
            ],
          ),
          const Divider(color: Brand.borderSoft, height: 22),
          Row(
            children: [
              const Icon(Icons.emoji_events_outlined,
                  size: 16, color: Brand.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  p.rank == null
                      ? 'لم يدخل الترتيب بعد'
                      : 'المركز ${p.rank} من ${p.totalCompetitors} في العرش',
                  style: const TextStyle(
                    color: Brand.textMuted,
                    fontSize: 12.5,
                    fontFeatures: Brand.tabular,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ثلاثة أرقام تصف طريقة لعبه — نفس ثلاثية «ملفي».
class _Stats extends StatelessWidget {
  final PlayerProfile player;
  const _Stats({required this.player});

  @override
  Widget build(BuildContext context) {
    final p = player;
    return Row(
      children: [
        _StatBox(
          value: p.accuracy != null ? '${p.accuracy}%' : '—',
          label: 'دقة التوقّع',
          hint: p.accuracy == null ? 'لا شيء محتسب' : null,
        ),
        const SizedBox(width: 10),
        _StatBox(
          value: '×${p.longestStreak}',
          label: 'أطول سلسلة',
          hint: p.currentStreak > 0 ? 'الحالية ×${p.currentStreak}' : null,
          tone: p.currentStreak > 0 ? Brand.correct : null,
        ),
        const SizedBox(width: 10),
        _StatBox(
          value: '${p.predictionsCount}',
          label: 'توقّع كلي',
          hint: '${p.settledPredictions} محتسب',
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  final String value;
  final String label;
  final String? hint;
  final Color? tone;

  const _StatBox({
    required this.value,
    required this.label,
    this.hint,
    this.tone,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: BrandCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
        child: Column(
          children: [
            BrandNumber(value, size: 19, color: tone ?? Brand.text),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Brand.textMuted, fontSize: 11),
            ),
            if (hint != null) ...[
              const SizedBox(height: 2),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: tone ?? Brand.textFaint,
                  fontSize: 10,
                  fontFeatures: Brand.tabular,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final String name;
  const _Avatar({this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    const size = 52.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Brand.fill,
        border: Border.all(color: Brand.crownWash(0.4), width: 2),
        image: url != null
            ? DecorationImage(
                image: CachedNetworkImageProvider(AppConfig.absoluteUrl(url!)),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: url == null
          ? Text(
              name.isEmpty ? '' : name.characters.first,
              style: const TextStyle(
                fontFamily: Brand.displayFont,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Brand.textMuted,
              ),
            )
          : null,
    );
  }
}
