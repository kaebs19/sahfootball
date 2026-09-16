// سوق اللاعبين — ورقةٌ تُفتح من خانةٍ على الملعب.
//
// ورقةٌ لا شاشة: الاختيار جوابٌ عن سؤال طُرح للتوّ («من يقف هنا؟»)،
// وشاشةٌ كاملة تدفع الملعب خارج البصر فينسى صاحبها لِمَ فتحها.
//
// والتصفية بالمركز تُمرَّر من الخانة لا يختارها المستخدم: من ضغط
// خانة مدافع لا يريد قائمة بمئتي مهاجم، وعرضُها عليه دعوةٌ لخطأ
// يرفضه الخادم بعد ثلاث ضغطات.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../brand.dart';
import '../config.dart';
import '../format.dart';
import '../models/fantasy.dart';

Future<FantasyPlayer?> showFantasyMarket(
  BuildContext context, {
  required List<FantasyPlayer> players,
  required Set<int> taken,
  FantasyPosition? position,
  double? budgetLeft,
}) {
  return showModalBottomSheet<FantasyPlayer>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Brand.surface,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(Brand.radiusCardLarge)),
    ),
    builder: (_) => _MarketSheet(
      players: players,
      taken: taken,
      position: position,
      budgetLeft: budgetLeft,
    ),
  );
}

class _MarketSheet extends StatefulWidget {
  final List<FantasyPlayer> players;
  final Set<int> taken;
  final FantasyPosition? position;
  final double? budgetLeft;

  const _MarketSheet({
    required this.players,
    required this.taken,
    this.position,
    this.budgetLeft,
  });

  @override
  State<_MarketSheet> createState() => _MarketSheetState();
}

class _MarketSheetState extends State<_MarketSheet> {
  String _query = '';
  bool _affordableOnly = false;
  late FantasyPosition? _position = widget.position;

  List<FantasyPlayer> get _filtered {
    final q = _query.trim();
    return widget.players.where((p) {
      if (widget.taken.contains(p.id)) return false;
      if (_position != null && p.position != _position) return false;
      if (q.isNotEmpty && !p.name.contains(q) && !p.teamName.contains(q)) {
        return false;
      }
      if (_affordableOnly &&
          widget.budgetLeft != null &&
          p.price > widget.budgetLeft!) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: Brand.fillStrong,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Text(
                  _position == null ? 'السوق' : _position!.label,
                  style: const TextStyle(
                    color: Brand.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    fontFamily: Brand.displayFont,
                  ),
                ),
                const Spacer(),
                if (widget.budgetLeft != null)
                  Text(
                    'المتبقّي ${Fmt.number(widget.budgetLeft!, decimals: 1)}',
                    style: TextStyle(
                      color: widget.budgetLeft! < 0 ? Brand.wrong : Brand.crown,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      fontFeatures: Brand.tabular,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: false,
              style: const TextStyle(color: Brand.text, fontSize: 14),
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'ابحث باسم اللاعب أو ناديه',
                hintStyle:
                    const TextStyle(color: Brand.textFaint, fontSize: 13.5),
                prefixIcon:
                    const Icon(Icons.search, color: Brand.textFaint, size: 20),
                filled: true,
                fillColor: Brand.fill,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Brand.radiusChip),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                if (widget.position == null) ...[
                  // بلا مركز مطلوب (خانة دكّة): يختار هو.
                  for (final p in FantasyPosition.values)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _MiniChip(
                        label: p.label,
                        selected: _position == p,
                        onTap: () => setState(
                            () => _position = _position == p ? null : p),
                      ),
                    ),
                ],
                const Spacer(),
                if (widget.budgetLeft != null)
                  _MiniChip(
                    label: 'ما أقدر عليه',
                    selected: _affordableOnly,
                    onTap: () =>
                        setState(() => _affordableOnly = !_affordableOnly),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text('لا لاعب يطابق بحثك.',
                        style: TextStyle(color: Brand.textFaint, fontSize: 13)),
                  )
                : ListView.builder(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _MarketRow(
                      player: list[i],
                      // الأغلى من المتبقّي يُعرض رماديّاً ولا يُخفى:
                      // إخفاؤه يجعل اللاعب يظنّ أن نجم الدوري غير
                      // موجود، ورؤيته وهو بعيد المنال هي نصف اللعبة.
                      affordable: widget.budgetLeft == null ||
                          list[i].price <= widget.budgetLeft!,
                      onTap: () => Navigator.of(context).pop(list[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MarketRow extends StatelessWidget {
  final FantasyPlayer player;
  final bool affordable;
  final VoidCallback onTap;

  const _MarketRow({
    required this.player,
    required this.affordable,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dim = affordable ? 1.0 : 0.45;
    return Opacity(
      opacity: dim,
      child: ListTile(
        onTap: affordable ? onTap : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: Brand.fill,
          backgroundImage: player.photoUrl == null
              ? null
              : CachedNetworkImageProvider(
                  AppConfig.absoluteUrl(player.photoUrl!)),
          child: player.photoUrl == null
              ? const Icon(Icons.person, color: Brand.textFaint, size: 20)
              : null,
        ),
        title: Text(player.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Brand.text, fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${player.teamName} · ${player.position.label}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Brand.textFaint, fontSize: 11.5),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // الحركة قبل السعر في القراءة العربية (يمين ← يسار)
                // تقع بعده — فيُقرأ «٧٫٥ ▲» لا «▲ ٧٫٥».
                Text(player.priceLabel,
                    style: const TextStyle(
                      color: Brand.crown,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFamily: Brand.displayFont,
                      fontFeatures: Brand.tabular,
                    )),
                if (player.priceDelta != 0) ...[
                  const SizedBox(width: 5),
                  _DeltaBadge(delta: player.priceDelta),
                ],
              ],
            ),
            Text('${Fmt.number(player.totalPoints)} نقطة',
                style: const TextStyle(color: Brand.textFaint, fontSize: 10.5)),
          ],
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MiniChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? Brand.fillStrong : Brand.fill,
            borderRadius: BorderRadius.circular(Brand.radiusChip),
            border: Border.all(color: selected ? Brand.border : Brand.borderSoft),
          ),
          child: Text(label,
              style: TextStyle(
                color: selected ? Brand.text : Brand.textMuted,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              )),
        ),
      );
}

/// شارة حركة السعر — سهمٌ ورقم.
///
/// السهم وحده لا يكفي: «ارتفع» جوابٌ ناقص عن «كم؟»، والفرق بين
/// ٠٫١ و٠٫٣ هو الفرق بين لاعبٍ يُنتبه له ولاعبٍ يشتريه الجميع.
///
/// وبلا ذهبي: الهوية تحصره في التاج والنقاط والرتب، وحركةُ سعرٍ
/// ليست رتبة. الأخضر والأحمر يقولانها بلا استعارة.
class _DeltaBadge extends StatelessWidget {
  final double delta;
  const _DeltaBadge({required this.delta});

  @override
  Widget build(BuildContext context) {
    final up = delta > 0;
    final color = up ? Brand.correct : Brand.wrong;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              color: color, size: 13),
          Text(Fmt.number(delta.abs(), decimals: 1),
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                fontFeatures: Brand.tabular,
              )),
        ],
      ),
    );
  }
}
