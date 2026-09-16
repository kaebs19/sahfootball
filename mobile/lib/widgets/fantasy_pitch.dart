// الملعب — التشكيلة مرسومةً كما تُرى في التلفاز لا كقائمة.
//
// ولماذا ملعبٌ أصلاً وقائمةٌ أسهل؟ لأن الخطة معلومةٌ مكانية:
// «4-4-2» تعني شكلاً، وقائمةٌ من خمسة عشر سطراً تخفي الشكل الذي
// تدور اللعبة كلها حوله. من يرى ثلاثة مدافعين في صفّ واحد يفهم
// خطّته بلا شرح.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../brand.dart';
import '../config.dart';
import '../format.dart';
import '../models/fantasy.dart';
import 'fantasy_sounds.dart';

/// خانة على الملعب: لاعبٌ أو فراغٌ ينتظر.
class PitchSlot {
  final FantasyPosition position;
  final FantasyPlayer? player;

  const PitchSlot({required this.position, this.player});
}

class FantasyPitch extends StatelessWidget {
  /// الأساسيون مرتّبين خطّاً خطّاً من المرمى إلى الهجوم.
  final List<List<PitchSlot>> lines;
  final void Function(PitchSlot slot)? onTapSlot;

  /// سحبُ لاعبٍ وإفلاته على آخر — تبديلُ مكانيهما.
  ///
  /// السحب لا الضغط هو ما يجعل الملعب ملعباً: توزيع لاعبٍ بإصبعك
  /// يشعر أنه فريقك، واختياره من قائمة يشعر أنه نموذج إدخال.
  final void Function(FantasyPlayer dragged, PitchSlot onto)? onSwap;

  /// نقاط اللاعب في الجولة بدل سعره — تُمرَّر في شاشة النقاط وحدها.
  final Map<int, int>? pointsByPlayer;

  const FantasyPitch({
    super.key,
    required this.lines,
    this.onTapSlot,
    this.onSwap,
    this.pointsByPlayer,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      // نسبة الملعب الحقيقي تقريباً (68×105 متراً). الصورة نفسها
      // 1664×2560 وهي أطول، فـ BoxFit.cover يقصّ من الطرفين
      // ويترك المنطقة التي يقف فيها اللاعبون كاملة.
      aspectRatio: 0.66,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Brand.radiusCard),
          border: Border.all(color: Brand.borderSoft),
          image: const DecorationImage(
            image: AssetImage('assets/field/pitch.png'),
            fit: BoxFit.cover,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            // الخطوط تتوزّع على الارتفاع بالتساوي: المرمى فوق
            // والهجوم تحت، كما يقف الفريق حين تصوّره الكاميرا من
            // خلف مرماه.
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final line in lines)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final slot in line)
                      Flexible(
                        child: _PitchCard(
                          slot: slot,
                          points: slot.player == null
                              ? null
                              : pointsByPlayer?[slot.player!.id],
                          onTap: onTapSlot == null
                              ? null
                              : () => onTapSlot!(slot),
                          onSwap: onSwap,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PitchCard extends StatelessWidget {
  final PitchSlot slot;
  final int? points;
  final VoidCallback? onTap;
  final void Function(FantasyPlayer dragged, PitchSlot onto)? onSwap;

  const _PitchCard({required this.slot, this.points, this.onTap, this.onSwap});

  @override
  Widget build(BuildContext context) {
    final player = slot.player;
    final card = _card(context, player);
    if (onSwap == null) return card;

    // الخانة هدفٌ للإفلات دائماً — حتى الفارغة: من سحب بديلاً إلى
    // خانة فارغة يقصد أن يضعه فيها، ورفضُ الإفلات هناك يجعل
    // الحركة تبدو معطّلة لا ممنوعة.
    return DragTarget<FantasyPlayer>(
      onWillAcceptWithDetails: (d) {
        // لاعبٌ على نفسه ليس تبديلاً.
        if (d.data.id == player?.id) return false;
        // المركز شرطٌ لا تشدّد: مهاجمٌ في خانة حارس يكسر الخطة،
        // والقاعدة سترفض التشكيلة كلها عند الحفظ — والرفض هناك
        // متأخّرٌ عن اللحظة التي أخطأ فيها.
        return d.data.position == slot.position;
      },
      onAcceptWithDetails: (d) {
        FantasySounds.play(Sfx.pop);
        onSwap!(d.data, slot);
      },
      builder: (context, candidate, _) {
        final hovering = candidate.isNotEmpty;
        final body = player == null
            ? card
            : LongPressDraggable<FantasyPlayer>(
                // ضغطةٌ مطوّلة لا سحبٌ فوري: القائمة تُمرَّر رأسياً
                // والملعب داخلها، فسحبٌ فوري يخطف كل تمريرة.
                data: player,
                delay: const Duration(milliseconds: 180),
                onDragStarted: () => FantasySounds.play(Sfx.swoosh),
                feedback: Material(
                  color: Colors.transparent,
                  child: Opacity(
                    opacity: 0.9,
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: _PlayerFace(player: player),
                    ),
                  ),
                ),
                childWhenDragging: Opacity(opacity: 0.3, child: card),
                child: card,
              );

        return AnimatedScale(
          duration: const Duration(milliseconds: 140),
          scale: hovering ? 1.12 : 1.0,
          child: body,
        );
      },
    );
  }

  Widget _card(BuildContext context, FantasyPlayer? player) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: player == null
                ? _EmptySlot(position: slot.position)
                : _PlayerFace(player: player),
          ),
          const SizedBox(height: 4),
          // شريطان تحت الصورة: الاسم ثم الرقم. خلفيتهما مصمتة
          // لأن النصّ الفاتح على عشبٍ فاتح لا يُقرأ، ولأن الطبقة
          // نفسها تفصل اللاعب عن الملعب فيبرز.
          _Chip(
            text: player == null ? slot.position.label : _shortName(player.name),
            background: Brand.night.withValues(alpha: 0.86),
            color: player == null ? Brand.textFaint : Brand.text,
          ),
          const SizedBox(height: 2),
          _Chip(
            text: player == null
                ? '—'
                : points != null
                    ? Fmt.number(points!)
                    : player.priceLabel,
            background: points != null
                ? Brand.crown
                : Brand.surface.withValues(alpha: 0.9),
            color: points != null ? Brand.onAccent : Brand.textMuted,
            bold: points != null,
          ),
        ],
      ),
    );
  }

  /// اسمٌ يسع خانةً بعرض ٥٦ نقطة: الكلمة الأخيرة وحدها.
  ///
  /// «محمد عبدالرحمن السهلاوي» لا تُقرأ في هذه المساحة مهما صغر
  /// الخط، و«السهلاوي» هي ما ينطقه المعلّق أصلاً.
  static String _shortName(String full) {
    final parts = full.trim().split(RegExp(r'\s+'));
    return parts.length == 1 ? parts.first : parts.last;
  }
}

class _PlayerFace extends StatelessWidget {
  final FantasyPlayer player;
  const _PlayerFace({required this.player});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Brand.surface,
            border: Border.all(
              // الكابتن بحلقة ذهبية: الذهبي محصورٌ في التاج والنقاط
              // والرتب بحكم الهوية، وشارة الكابتن رتبةٌ داخل الفريق
              // فتستحقّه — ونائبه بحلقة بيضاء لا ذهبية باهتة.
              color: player.isCaptain
                  ? Brand.crown
                  : player.isVice
                      ? Brand.text
                      : Brand.border,
              width: player.isCaptain || player.isVice ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: player.photoUrl == null
              ? const Icon(Icons.person, color: Brand.textFaint, size: 24)
              : CachedNetworkImage(
                  imageUrl: AppConfig.absoluteUrl(player.photoUrl!),
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) =>
                      const Icon(Icons.person, color: Brand.textFaint, size: 24),
                ),
        ),
        if (player.isCaptain || player.isVice)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              width: 17,
              height: 17,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: player.isCaptain ? Brand.crown : Brand.text,
              ),
              child: Text(
                player.isCaptain ? 'ك' : 'ن',
                style: const TextStyle(
                  color: Brand.onAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _EmptySlot extends StatelessWidget {
  final FantasyPosition position;
  const _EmptySlot({required this.position});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Brand.night.withValues(alpha: 0.55),
        border: Border.all(color: Brand.border, style: BorderStyle.solid),
      ),
      child: const Center(
        child: Icon(Icons.add, color: Brand.textMuted, size: 20),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color background;
  final Color color;
  final bool bold;

  const _Chip({
    required this.text,
    required this.background,
    required this.color,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          height: 1.25,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    );
  }
}

/// يوزّع الأساسيين على خطوط الملعب حسب الخطة.
///
/// هنا لا في الشاشة: الترتيب قاعدةٌ لا تنسيق — الحارس أولاً ثم
/// الدفاع ثم الوسط ثم الهجوم — وشاشتان ترسمانه (التشكيلة والنقاط)
/// كانتا ستكتبانه مرتين فتفترقان عند أول تعديل.
List<List<PitchSlot>> pitchLines(String formation, List<FantasyPlayer> starters) {
  final shape = FantasyRules.shapeOf(formation);
  // من الهجوم إلى المرمى: الحارس **أسفل** الشاشة والمهاجمون
  // أعلاها، كما يقف فريقك حين تكون الكاميرا خلفه لا أمامه — وهي
  // الزاوية التي يرى بها المشجّع مرماه في المدرّج.
  //
  // والملعب في الصورة كاملٌ بمرميين، فالحارس يقف في منطقة جزاء
  // حقيقية بلا أن تُقلب الصورة.
  final order = [
    FantasyPosition.attacker,
    FantasyPosition.midfielder,
    FantasyPosition.defender,
    FantasyPosition.goalkeeper,
  ];

  final pool = {
    for (final position in order)
      position: starters.where((p) => p.position == position).toList(),
  };

  return [
    for (final position in order)
      [
        for (var i = 0; i < (shape[position] ?? 0); i++)
          PitchSlot(
            position: position,
            // الخانة تبقى فارغة حين ينقص اللاعبون عن الخطة: هكذا
            // يرى صاحبها أين النقص بدل رسالةٍ تقول «تشكيلة ناقصة».
            player: i < pool[position]!.length ? pool[position]![i] : null,
          ),
      ],
  ];
}
