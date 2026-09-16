// تشكيلة مدرّبٍ آخر — «من هذا الذي يتصدّرني، وبمن؟»
//
// يُفتح من صفٍّ في عرش «فريقي» أو من ملف لاعب. وهو نصف متعة
// اللعبة: النقاط تقول من فاز، والتشكيلة تقول **لماذا** — وهي
// المعلومة التي يتعلّم منها من يخسر.
//
// **والمعروض مجمَّدٌ لا حيّ** (راجع FANTASY.md): تشكيلة آخر جولة
// أُقفلت. ورؤية التشكيلة الحيّة قبل صافرة البداية تعني أن من
// يتصدّر يُنسَخ، فتموت المفاضلة التي هي اللعبة كلها. ومن لم تُقفل
// له جولةٌ بعد لا تشكيلة له هنا — ويُقال ذلك صراحةً بدل ملعبٍ
// فارغ لا يشرح صمته.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../config.dart';
import '../format.dart';
import '../models/fantasy.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/fantasy_pitch.dart';

class FantasyManagerScreen extends StatefulWidget {
  final String userId;

  /// الاسم إن عُرف من الشاشة السابقة — ترويسةٌ فوراً بدل فراغٍ
  /// ينتظر الرد.
  final String? displayName;
  final int? leagueId;

  const FantasyManagerScreen({
    super.key,
    required this.userId,
    this.displayName,
    this.leagueId,
  });

  @override
  State<FantasyManagerScreen> createState() => _FantasyManagerScreenState();
}

class _FantasyManagerScreenState extends State<FantasyManagerScreen> {
  FantasyManagerView? _view;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final view = await context
          .read<ApiClient>()
          .fantasyManager(userId: widget.userId, leagueId: widget.leagueId);
      if (mounted) setState(() => (_view = view, _loading = false));
    } on ApiException catch (e) {
      if (mounted) setState(() => (_error = e.message, _loading = false));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.night,
      appBar: AppBar(title: Text(widget.displayName ?? 'فريقه')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Brand.crown));
    }
    final view = _view;
    if (_error != null || view == null) {
      return BrandEmpty(
        icon: Icons.wifi_off,
        message: _error ?? 'تعذّر التحميل',
        onRetry: _load,
      );
    }

    final starters =
        view.players.where((r) => !r.onBench).map((r) => r.player).toList();
    final points = {
      for (final r in view.players) r.player.id: r.points,
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      children: [
        _ManagerHead(view: view, fallbackName: widget.displayName),
        const SizedBox(height: 12),
        if (view.isEmpty)
          BrandEmpty(
            icon: Icons.lock_clock_outlined,
            message: view.rank == null
                ? 'لم يبنِ فريقه في هذا الدوري بعد.'
                : 'تظهر تشكيلته بعد إقفال أول جولة — حتى لا '
                    'تُنسَخ التشكيلات قبل صافرة البداية.',
          )
        else ...[
          Row(
            children: [
              const Icon(Icons.lock_outline, color: Brand.textFaint, size: 14),
              const SizedBox(width: 6),
              Text(
                '${Fmt.round(view.round)} · ${Fmt.number(view.roundPoints)} نقطة',
                style: const TextStyle(color: Brand.textMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // بلا onTapSlot ولا onSwap: ملعبٌ يُقرأ لا يُعدَّل — وخانةٌ
          // تستجيب للمس في تشكيلة غيرك وعدٌ كاذب.
          FantasyPitch(
            lines: pitchLines(view.formation, starters),
            pointsByPlayer: points,
          ),
          const SizedBox(height: 16),
          const BrandSectionLabel('الدكّة'),
          const SizedBox(height: 8),
          for (final row in view.players.where((r) => r.onBench))
            _BenchLine(row: row),
        ],
      ],
    );
  }
}

class _ManagerHead extends StatelessWidget {
  final FantasyManagerView view;
  final String? fallbackName;

  const _ManagerHead({required this.view, this.fallbackName});

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            height: 38,
            child: view.clubLogo == null
                ? const Icon(Icons.shield_outlined, color: Brand.crown, size: 30)
                : CachedNetworkImage(
                    imageUrl: AppConfig.absoluteUrl(view.clubLogo!),
                    errorWidget: (_, _, _) => const Icon(Icons.shield_outlined,
                        color: Brand.crown, size: 30),
                  ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  view.name ?? fallbackName ?? 'مدرّب',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Brand.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFamily: Brand.displayFont,
                  ),
                ),
                if (view.clubName != null)
                  Text(view.clubName!,
                      style: const TextStyle(
                          color: Brand.textFaint, fontSize: 11.5)),
              ],
            ),
          ),
          if (view.rank != null) ...[
            _Stat(label: 'الترتيب', value: '#${Fmt.number(view.rank!)}'),
            const SizedBox(width: 14),
          ],
          _Stat(label: 'الموسم', value: Fmt.number(view.totalPoints)),
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
              style: const TextStyle(color: Brand.textFaint, fontSize: 10.5)),
        ],
      );
}

class _BenchLine extends StatelessWidget {
  final FantasyRoundRow row;
  const _BenchLine({required this.row});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: BrandCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Text(row.player.position.short,
                style: const TextStyle(color: Brand.textFaint, fontSize: 10.5)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                row.player.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Brand.text, fontSize: 13),
              ),
            ),
            // البديل الذي دخل يُحتسب — والراية تقول ذلك، وإلا بدت
            // نقاطه خطأً في الحساب.
            if (row.autoSubbed)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Text('دخل بديلاً',
                    style: TextStyle(color: Brand.correct, fontSize: 10.5)),
              ),
            Text(Fmt.number(row.points),
                style: const TextStyle(
                    color: Brand.crown,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
