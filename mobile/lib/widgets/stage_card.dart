// منصّة التتويج وبطاقة المسرح — مشتركة بين العرش والمجلس.
//
// كانت خاصة بشاشة العرش. نُقلت هنا حين احتاجها المجلس: المقاعد
// الثلاثة والوهج والصفّ السفلي «وين أنا؟» هي نفسها في الاثنين، ونسختان
// تتباعدان عند أول تعديل فيبدو ترتيب المجلس لعبةً أخرى.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../brand.dart';
import '../config.dart';
import '../models/leaderboard_entry.dart';
import '../models/rank.dart';
import 'brand_widgets.dart';

/// بطاقة المسرح — إطار المنصّة وسياقها.
class StageCard extends StatelessWidget {
  final String title;
  final String hint;
  final String meta;
  final Widget podium;
  final Widget footer;

  const StageCard({
    super.key,
    required this.title,
    required this.hint,
    required this.meta,
    required this.podium,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontFamily: Brand.displayFont,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: Brand.text,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        hint,
                        style: const TextStyle(
                            color: Brand.textMuted, fontSize: 11.5, height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                BrandChip(label: meta),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // وهج ذهبي خلف المقعد الأول — ضوء المسرح على البطل.
          Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                bottom: 26,
                child: Container(
                  width: 200,
                  height: 140,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [Brand.crownWash(0.20), Brand.crownWash(0.0)],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: podium,
              ),
            ],
          ),
          const Divider(color: Brand.border, height: 1),
          footer,
        ],
      ),
    );
  }
}

/// صفّ أسفل المسرح — «أنت» أو دعوة.
class StageFooter extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool gold;
  final VoidCallback? onTap;

  const StageFooter({
    super.key,
    required this.icon,
    required this.text,
    this.gold = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = gold ? Brand.crown : Brand.textMuted;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: gold ? FontWeight.w600 : FontWeight.w400,
                  fontFeatures: Brand.tabular,
                ),
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right, size: 18, color: Brand.textFaint),
          ],
        ),
      ),
    );
  }
}

/// منصّة التتويج — المقاعد الثلاثة الأولى.
class Podium extends StatelessWidget {
  final List<LeaderboardEntry> entries;
  final String? myId;

  /// ما يُكتب تحت رقم المقعد الأول: رتبة اللاعب في العرش، أو لقب
  /// المجلس («ملك «شباب الحي»») في المجالس. null = رتبة العرش.
  final String? crownLabel;

  const Podium({
    super.key,
    required this.entries,
    required this.myId,
    this.crownLabel,
  });

  LeaderboardEntry? _at(int i) => i < entries.length ? entries[i] : null;

  @override
  Widget build(BuildContext context) {
    // ترتيب الأبناء في Row تحت RTL: الأول يمين. فالثاني ← الأول ←
    // الثالث يعطي 2 | 1 | 3 في القراءة، وهو شكل المنصّة المعروف.
    final seats = [
      _PodiumSeat(entry: _at(1), place: 2, myId: myId),
      _PodiumSeat(entry: _at(0), place: 1, myId: myId, crownLabel: crownLabel),
      _PodiumSeat(entry: _at(2), place: 3, myId: myId),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < seats.length; i++) ...[
          // المقعد الأوسط أعرض قليلاً: اسم البطل يستحق سطرين لا
          // قصّاً بثلاث نقاط.
          Expanded(flex: i == 1 ? 5 : 4, child: seats[i]),
          if (i < seats.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _PodiumSeat extends StatelessWidget {
  final LeaderboardEntry? entry;
  final int place;
  final String? myId;
  final String? crownLabel;
  const _PodiumSeat({
    required this.entry,
    required this.place,
    this.myId,
    this.crownLabel,
  });

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final first = place == 1;
    final isMe = e != null && e.userId == myId;
    // الأول أطول قاعدةً وأكبر صورةً: العلوّ هو ما يميّز المنصّة عن
    // ثلاث بطاقات متساوية.
    final baseHeight = first ? 60.0 : 44.0;
    final avatar = first ? 46.0 : 36.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (first)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Icon(Icons.emoji_events, size: 18, color: Brand.crown),
          ),
        _PodiumAvatar(
          url: e?.avatarUrl,
          name: e?.displayName ?? '',
          size: avatar,
          ring: first ? Brand.crown : (isMe ? Brand.crown : Brand.border),
          empty: e == null,
        ),
        const SizedBox(height: 6),
        Text(
          e?.displayName ?? 'مقعد شاغر',
          maxLines: first ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: e == null ? Brand.textFaint : Brand.text,
            fontSize: first ? 11.5 : 11,
            height: 1.25,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        if (e != null)
          BrandNumber('${e.totalPoints}',
              size: first ? 17 : 14, color: Brand.crown)
        else
          const Text('—',
              style: TextStyle(color: Brand.textFaint, fontSize: 14)),
        const SizedBox(height: 8),
        Container(
          height: baseHeight,
          decoration: BoxDecoration(
            color: first ? Brand.crownWash(0.14) : Brand.fill,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: Border.all(
              color: isMe
                  ? Brand.crown
                  : (first ? Brand.crownWash(0.35) : Brand.border),
            ),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$place',
                style: TextStyle(
                  fontFamily: Brand.displayFont,
                  fontSize: first ? 20 : 15,
                  fontWeight: FontWeight.w700,
                  color: first ? Brand.crown : Brand.textMuted,
                  height: 1,
                ),
              ),
              if (e != null && first) ...[
                const SizedBox(height: 3),
                Text(
                  crownLabel ?? Rank.of(e.totalPoints).label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Brand.crown, fontSize: 10),
                ),
              ],
              if (isMe) ...[
                const SizedBox(height: 2),
                const Text('أنت',
                    style: TextStyle(color: Brand.crown, fontSize: 10)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PodiumAvatar extends StatelessWidget {
  final String? url;
  final String name;
  final double size;
  final Color ring;
  final bool empty;
  const _PodiumAvatar({
    required this.url,
    required this.name,
    required this.size,
    required this.ring,
    required this.empty,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Brand.fill,
        border: Border.all(color: ring, width: 2),
        image: url != null
            ? DecorationImage(
                image: CachedNetworkImageProvider(AppConfig.absoluteUrl(url!)),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: url == null
          ? (empty
              ? Icon(Icons.person_outline,
                  size: size * 0.5, color: Brand.textFaint)
              : Text(
                  name.isEmpty ? '' : name.characters.first,
                  style: TextStyle(
                    color: Brand.textMuted,
                    fontSize: size * 0.4,
                    fontWeight: FontWeight.w600,
                  ),
                ))
          : null,
    );
  }
}

