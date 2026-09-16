// بطاقة «فريقي» — تشكيلتك صورةً تُشارَك.
//
// ولماذا بطاقة في حوار لا لقطةٌ للشاشة كما هي؟ لسببين:
//
// الأول تقني وحاسم: الملعب داخل قائمة تُمرَّر، وما خرج من الشاشة
// لا يُرسم — والتقاطُ حدودٍ فيها جزءٌ غير مرسوم يعطي صورة نصفها
// فارغ. البطاقة تُبنى كاملةً ظاهرةً فتُلتقط كاملة.
//
// والثاني أن ما يُشارَك يجب أن يُرى قبل أن يُرسل: من يضغط
// «مشاركة» فتفتح ورقة النظام بصورة لم يرها يرسل شيئاً لا يعرفه.
//
// وما فيها ليس الملعب وحده: الشعار والنقاط وقيمة الفريق — لأن
// الصورة تُنشر لتقول «هذا فريقي وهذه نتيجته»، لا لتعرض أسماء.
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../brand.dart';
import '../config.dart';
import '../format.dart';
import '../models/fantasy.dart';
import 'fantasy_pitch.dart';

/// يفتح معاينة البطاقة، ومنها تُشارَك.
Future<void> showFantasyShareCard(
  BuildContext context, {
  required String formation,
  required List<FantasyPlayer> squad,
  required String? clubName,
  required String? clubLogo,
  required int totalPoints,
  required double teamValue,
}) {
  return showDialog(
    context: context,
    barrierColor: Brand.night.withValues(alpha: 0.86),
    builder: (_) => _ShareDialog(
      formation: formation,
      squad: squad,
      clubName: clubName,
      clubLogo: clubLogo,
      totalPoints: totalPoints,
      teamValue: teamValue,
    ),
  );
}

class _ShareDialog extends StatefulWidget {
  final String formation;
  final List<FantasyPlayer> squad;
  final String? clubName;
  final String? clubLogo;
  final int totalPoints;
  final double teamValue;

  const _ShareDialog({
    required this.formation,
    required this.squad,
    required this.clubName,
    required this.clubLogo,
    required this.totalPoints,
    required this.teamValue,
  });

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  final _card = GlobalKey();
  bool _busy = false;

  /// التقاط البطاقة ثم فتح ورقة المشاركة.
  ///
  /// `pixelRatio: 3` لا 1: الصورة تُفتح على شاشات أخرى وتُكبَّر في
  /// واتساب، ولقطةٌ بحجم الشاشة المنطقي تصل مهترئة الحروف.
  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final boundary =
          _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw Exception('تعذّر التقاط الصورة');

      final file = XFile.fromData(
        bytes.buffer.asUint8List(),
        mimeType: 'image/png',
        name: 'my-team.png',
      );
      await SharePlus.instance.share(ShareParams(
        files: [file],
        fileNameOverrides: const ['my-team.png'],
        text: 'هذه تشكيلتي في «فريقي» — ملك التوقعات.',
      ));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذّرت مشاركة الصورة.'),
        backgroundColor: Brand.wrong,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final starters = widget.squad.where((p) => !p.onBench).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // البطاقة تُبنى بعرضٍ ثابت ثم تُصغَّر لتدخل الشاشة: بلا
          // ذلك تختلف الصورة الخارجة باختلاف الهاتف، فيرسل صاحب
          // الشاشة الصغيرة بطاقةً أضيق من بطاقة جاره.
          Flexible(
            child: FittedBox(
              child: RepaintBoundary(
                key: _card,
                child: _Card(
                  formation: widget.formation,
                  starters: starters,
                  clubName: widget.clubName,
                  clubLogo: widget.clubLogo,
                  totalPoints: widget.totalPoints,
                  teamValue: widget.teamValue,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('إغلاق',
                    style: TextStyle(color: Brand.textMuted)),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _busy ? null : _share,
                style: FilledButton.styleFrom(
                  backgroundColor: Brand.primaryButton,
                  foregroundColor: Brand.onAccent,
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Brand.onAccent),
                      )
                    : const Icon(Icons.ios_share, size: 18),
                label: const Text('مشاركة'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// البطاقة نفسها — بعرض ثابت ٣٤٠ كي تخرج الصورة واحدةً للجميع.
class _Card extends StatelessWidget {
  final String formation;
  final List<FantasyPlayer> starters;
  final String? clubName;
  final String? clubLogo;
  final int totalPoints;
  final double teamValue;

  const _Card({
    required this.formation,
    required this.starters,
    required this.clubName,
    required this.clubLogo,
    required this.totalPoints,
    required this.teamValue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Brand.night,
        borderRadius: BorderRadius.circular(Brand.radiusCard),
        border: Border.all(color: Brand.borderSoft),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 30,
                height: 30,
                child: clubLogo == null
                    ? const Icon(Icons.shield_outlined,
                        color: Brand.crown, size: 24)
                    : CachedNetworkImage(
                        imageUrl: AppConfig.absoluteUrl(clubLogo!),
                        errorWidget: (_, _, _) => const Icon(
                            Icons.shield_outlined,
                            color: Brand.crown,
                            size: 24),
                      ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clubName ?? 'فريقي',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Brand.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFamily: Brand.displayFont,
                      ),
                    ),
                    Text(
                      formation,
                      style: const TextStyle(
                          color: Brand.textFaint, fontSize: 11),
                    ),
                  ],
                ),
              ),
              _Stat(label: 'النقاط', value: Fmt.number(totalPoints)),
              const SizedBox(width: 12),
              _Stat(label: 'القيمة', value: Fmt.number(teamValue, decimals: 1)),
            ],
          ),
          const SizedBox(height: 10),
          FantasyPitch(lines: pitchLines(formation, starters)),
          const SizedBox(height: 9),
          const Text(
            'ملك التوقعات · فريقي',
            style: TextStyle(color: Brand.textFaint, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: Brand.crown,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          Text(label,
              style: const TextStyle(color: Brand.textFaint, fontSize: 10)),
        ],
      );
}
