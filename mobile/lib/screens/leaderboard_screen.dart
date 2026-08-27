// شاشة العرش — ترتيب كل المتوقعين بنقاط التاج.
//
// نبرز صف المستخدم الحالي بحد ذهبي: في قائمة من خمسين اسماً،
// السؤال الأول عند كل مستخدم هو "وين أنا؟".
//
// الرتب (مشجّع → لاعب → فارس → أمير → الملك) مشتقة من النقاط حسب
// سلّم الهوية، ومحسوبة في العميل عمداً: السلّم قرار عرض لا حقيقة
// في قاعدة البيانات، فلو تغيّرت عتباته غداً نغيّر ملفاً واحداً بلا
// ترحيل بيانات ولا مسار جديد في السيرفر.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../config.dart';
import '../models/leaderboard_entry.dart';
import '../state/session.dart';
import '../widgets/brand_widgets.dart';

/// سلّم الرتب الموسمية كما في ملف الهوية.
enum Rank {
  fan('مشجّع', 0),
  player('لاعب', 500),
  knight('فارس', 1500),
  prince('أمير', 3000),
  king('الملك', 5000);

  final String label;
  final int from;
  const Rank(this.label, this.from);

  static Rank of(int points) {
    // من الأعلى للأدنى: أول عتبة يبلغها المستخدم هي رتبته.
    for (final r in Rank.values.reversed) {
      if (points >= r.from) return r;
    }
    return Rank.fan;
  }
}

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<LeaderboardEntry>? _entries;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final entries = await context.read<ApiClient>().leaderboard();
      if (mounted) setState(() => _entries = entries);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return BrandEmpty(
          icon: Icons.wifi_off, message: _error!, onRetry: _load);
    }
    final entries = _entries;
    if (entries == null) {
      return const Center(
          child: CircularProgressIndicator(color: Brand.crown));
    }
    if (entries.isEmpty) {
      return BrandEmpty(
        icon: Icons.workspace_premium_outlined,
        message: 'لا نقاط بعد — كن أول من يجلس على العرش',
        onRefresh: _load,
      );
    }

    final myId = context.watch<Session>().user?.id;

    return RefreshIndicator(
      onRefresh: _load,
      color: Brand.crown,
      backgroundColor: Brand.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        children: [
          const Text(
            'من يجلس على العرش؟',
            style: TextStyle(
                fontFamily: Brand.displayFont,
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: Brand.text),
          ),
          const SizedBox(height: 4),
          Text(
            'الترتيب العام · ${entries.length} متنافس',
            style: const TextStyle(color: Brand.textMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _LeaderRow(entry: e, isMe: e.userId == myId),
            ),
        ],
      ),
    );
  }
}

class _LeaderRow extends StatelessWidget {
  final LeaderboardEntry entry;
  final bool isMe;
  const _LeaderRow({required this.entry, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final rank = Rank.of(entry.totalPoints);

    return BrandCard(
      royal: isMe,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          _RankBadge(rank: entry.rank),
          const SizedBox(width: 11),
          _Avatar(url: entry.avatarUrl, name: entry.displayName),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Brand.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      const Text('· أنت',
                          style:
                              TextStyle(color: Brand.crown, fontSize: 11.5)),
                    ],
                    if (entry.favoriteTeamLogo != null) ...[
                      const SizedBox(width: 6),
                      CachedNetworkImage(
                        imageUrl: entry.favoriteTeamLogo!,
                        width: 16,
                        height: 16,
                        errorWidget: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${rank.label} · ${entry.settledPredictions} توقّع محتسب',
                  style: const TextStyle(
                    color: Brand.textMuted,
                    fontSize: 11,
                    fontFeatures: Brand.tabular,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          BrandNumber('${entry.totalPoints}', size: 19, color: Brand.crown),
        ],
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  final int rank;
  const _RankBadge({required this.rank});

  @override
  Widget build(BuildContext context) {
    // المركز الأول ذهبي مصمت، والثاني والثالث ذهبي خافت، ومن بعدهم
    // محايد. تدرّج واحد بلون واحد بدل ثلاثة ألوان ميداليات — الهوية
    // لا تسمح بلون ثالث، ونقص التنوّع هنا يكسب وضوحاً.
    final (Color bg, Color fg) = switch (rank) {
      1 => (Brand.crown, Brand.onAccent),
      2 || 3 => (Brand.crownWash(0.18), Brand.crown),
      _ => (Brand.fill, Brand.textMuted),
    };

    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: rank == 1
          ? const Icon(Icons.emoji_events, size: 16, color: Brand.onAccent)
          : Text(
              '$rank',
              style: TextStyle(
                fontFamily: Brand.displayFont,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: fg,
                fontFeatures: Brand.tabular,
              ),
            ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final String name;
  const _Avatar({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    if (url == null) {
      // الحرف الأول بديلاً — أهدأ من أيقونة شخص عامة مكررة في كل صف
      return Container(
        width: 30,
        height: 30,
        decoration: const BoxDecoration(color: Brand.fill, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(
          name.characters.first,
          style: const TextStyle(
              color: Brand.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600),
        ),
      );
    }
    return CircleAvatar(
      radius: 15,
      backgroundColor: Brand.fill,
      backgroundImage: CachedNetworkImageProvider(AppConfig.absoluteUrl(url!)),
    );
  }
}
