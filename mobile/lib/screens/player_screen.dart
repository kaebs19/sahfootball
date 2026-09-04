// ملف لاعب — من هذا الذي يتصدّرني؟
//
// يُفتح من صفّ في العرش أو عضو في مجلس. يجيب بالترتيب: من هو
// (الاسم والرتبة والنقاط) ← أين هو (المركز) ← كيف يلعب (الدقة
// والسلسلة والعدد) ← أين يلعب (الحصيلة لكل دوري) ← ماذا نال
// (الأوسمة المكتسبة).
//
// نفس ترتيب «ملفي» وبنفس الويدجتات (ProfileHero و PerformanceStrip)
// عمداً — الشاشتان تُقرآن بالعين نفسها — لكن بلا
// سجلّ توقعات ولا إعدادات: توقعات غيري لا تُرى إلا في مجلس وبعد
// انطلاق المباراة، وذلك لسبب مشروح في السيرفر.
//
// عامة للضيف أيضاً: العرش عام، ومن يُعرض فيه يجوز أن يُعرف.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../models/player.dart';
import '../state/session.dart';
import '../widgets/badge_grid.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/league_stats_card.dart';
import '../widgets/profile_hero.dart';

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
                      ProfileHero(
                        name: p.displayName,
                        avatarUrl: p.avatarUrl,
                        isMe: isMe,
                        favoriteTeam: p.favoriteTeam,
                        totalPoints: p.totalPoints,
                        rank: p.rank,
                        totalCompetitors: p.totalCompetitors,
                        accuracy: p.accuracy,
                      ),
                      const SizedBox(height: 10),
                      PerformanceStrip(
                        longestStreak: p.longestStreak,
                        currentStreak: p.currentStreak,
                        predictionsCount: p.predictionsCount,
                        settledPredictions: p.settledPredictions,
                      ),
                      const SizedBox(height: 22),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          'حسب الدوري',
                          style: TextStyle(
                            fontFamily: Brand.displayFont,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Brand.text,
                          ),
                        ),
                      ),
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
                        LeagueCarousel(leagues: p.byLeague, showFollowed: false),
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
