// شاشة توقعاتي — سجل كل توقعاتي ونقاطها.
//
// نقطة العرض المهمة: التمييز بين ثلاث حالات لكل توقع —
// بانتظار المباراة، ومحتسب بنقاط، ومحتسب بصفر. المستخدم يريد أن
// يعرف بلمحة أين كسب وأين خسر.
//
// هنا يظهر الذهبي لأول مرة في التطبيق: بطاقة النقاط في الأعلى.
// هذا بالضبط ما تحجزه الهوية له — النقاط والرتب.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../models/prediction.dart';
import '../widgets/brand_widgets.dart';

class MyPredictionsScreen extends StatefulWidget {
  const MyPredictionsScreen({super.key});

  @override
  State<MyPredictionsScreen> createState() => _MyPredictionsScreenState();
}

class _MyPredictionsScreenState extends State<MyPredictionsScreen> {
  List<Prediction>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items = await context.read<ApiClient>().myPredictions();
      if (mounted) setState(() => _items = items);
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
    final items = _items;
    if (items == null) {
      return const Center(
          child: CircularProgressIndicator(color: Brand.crown));
    }

    final settled = items.where((p) => p.isSettled).toList();
    final points = settled.fold<int>(0, (sum, p) => sum + (p.points ?? 0));
    // دقة التوقع = كم توقعاً محتسباً أعطى نقاطاً. مقياس الهوية في
    // شاشة الملف، ويُحسب هنا محلياً بلا حاجة لمسار جديد في السيرفر.
    final accuracy = settled.isEmpty
        ? null
        : (settled.where((p) => (p.points ?? 0) > 0).length /
                settled.length *
                100)
            .round();

    return RefreshIndicator(
      onRefresh: _load,
      color: Brand.crown,
      backgroundColor: Brand.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
        children: [
          _CrownCard(
              points: points, count: items.length, accuracy: accuracy),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 70),
              child: Text(
                'ما سجّلت أي توقع بعد — ابدأ من شاشة المباريات',
                textAlign: TextAlign.center,
                style: TextStyle(color: Brand.textMuted, height: 1.6),
              ),
            ),
          if (items.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(2, 20, 2, 10),
              child: BrandSectionLabel('سجلّ التوقعات'),
            ),
            for (final p in items) _PredictionTile(prediction: p),
          ],
        ],
      ),
    );
  }
}

/// بطاقة النقاط — الوحيدة الذهبية في الشاشة.
class _CrownCard extends StatelessWidget {
  final int points;
  final int count;
  final int? accuracy;

  const _CrownCard({
    required this.points,
    required this.count,
    required this.accuracy,
  });

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      royal: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        children: [
          const BrandChip(
              label: 'نقطة تاج', icon: Icons.emoji_events, tone: BrandTone.crown),
          const SizedBox(height: 12),
          BrandNumber('$points', size: 40, color: Brand.crown),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _Stat(value: '$count', label: 'توقّع كلي')),
              Container(width: 1, height: 30, color: Brand.border),
              Expanded(
                child: _Stat(
                  value: accuracy != null ? '$accuracy%' : '—',
                  label: 'دقة التوقّع',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        BrandNumber(value, size: 19),
        const SizedBox(height: 3),
        Text(label,
            style: const TextStyle(color: Brand.textMuted, fontSize: 11.5)),
      ],
    );
  }
}

class _PredictionTile extends StatelessWidget {
  final Prediction prediction;
  const _PredictionTile({required this.prediction});

  @override
  Widget build(BuildContext context) {
    final p = prediction;
    final dateFmt = intl.DateFormat('d MMM • h:mm a', 'ar');
    final hasResult = p.goalsHome != null && p.goalsAway != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BrandCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${p.homeTeamName} — ${p.awayTeamName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Brand.text,
                        fontFamily: Brand.displayFont,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  dateFmt.format(p.kickoffAt),
                  style: const TextStyle(
                    color: Brand.textFaint,
                    fontSize: 11,
                    fontFeatures: Brand.tabular,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _ScoreBox(
                  title: 'توقعك',
                  value: '${p.predHome} - ${p.predAway}',
                  highlight: true,
                ),
                const SizedBox(width: 8),
                _ScoreBox(
                  title: 'النتيجة',
                  // النتيجة قد تكون null لمباراة لم تُلعب بعد
                  value: hasResult ? '${p.goalsHome} - ${p.goalsAway}' : '—',
                  highlight: false,
                ),
                const Spacer(),
                _PointsChip(points: p.isSettled ? (p.points ?? 0) : null),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreBox extends StatelessWidget {
  final String title;
  final String value;

  /// توقّع المستخدم يُبرز بالأخضر (اختيار مؤكَّد)، والنتيجة الفعلية
  /// محايدة — فالتباين بينهما هو ما يريد المستخدم قراءته.
  final bool highlight;

  const _ScoreBox({
    required this.title,
    required this.value,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: highlight ? Brand.correctWash(0.11) : Brand.fill,
        borderRadius: BorderRadius.circular(Brand.radiusSmall),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
                color: highlight ? Brand.correct : Brand.textMuted,
                fontSize: 10),
          ),
          const SizedBox(height: 1),
          BrandNumber(value,
              size: 15, color: highlight ? Brand.correct : Brand.text),
        ],
      ),
    );
  }
}

/// null = لم يُحتسب بعد، 0 = احتُسب بلا نقاط، >0 = نقاط مكتسبة.
class _PointsChip extends StatelessWidget {
  final int? points;
  const _PointsChip({required this.points});

  @override
  Widget build(BuildContext context) {
    if (points == null) {
      return const BrandChip(label: 'بانتظار المباراة', icon: Icons.schedule);
    }
    if (points! > 0) {
      // النقاط المكتسبة ذهبية — هذا هو الاستعمال المحجوز للذهبي.
      return BrandChip(
        label: '+$points نقطة',
        icon: Icons.emoji_events,
        tone: BrandTone.crown,
      );
    }
    return const BrandChip(label: 'بدون نقاط', icon: Icons.close);
  }
}
