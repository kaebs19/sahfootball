// شيت إدخال التوقع — يطلع من أسفل الشاشة فوق قائمة المباريات.
//
// لماذا bottom sheet وليس شاشة كاملة؟ إدخال التوقع فعل من ثانيتين
// (رقمان وزر)، وإبقاء قائمة المباريات ظاهرة خلفه يحفظ السياق —
// المستخدم يعرف أنه سيرجع لها فوراً.
//
// عقد الدالة: ترجع التوقع المحفوظ فقط بعد نجاح الحفظ في السيرفر،
// أو null لو أغلق المستخدم بلا حفظ. المستدعي لا يحتاج تخمين ماذا حدث.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../format.dart';
import '../models/fixture.dart';
import 'brand_widgets.dart';

Future<({int home, int away})?> showPredictionSheet(
  BuildContext context, {
  required Fixture fixture,
  int? initialHome,
  int? initialAway,
}) {
  return showModalBottomSheet<({int home, int away})>(
    context: context,
    // isScrollControlled + viewInsets: بدونهما تغطي لوحة المفاتيح
    // الشيت لو ظهرت (لا حقول نص هنا لكن العادة الصحيحة تبقى عادة)
    isScrollControlled: true,
    backgroundColor: Brand.surface,
    builder: (_) => _PredictionSheet(
      fixture: fixture,
      initialHome: initialHome ?? 0,
      initialAway: initialAway ?? 0,
    ),
  );
}

class _PredictionSheet extends StatefulWidget {
  final Fixture fixture;
  final int initialHome;
  final int initialAway;

  const _PredictionSheet({
    required this.fixture,
    required this.initialHome,
    required this.initialAway,
  });

  @override
  State<_PredictionSheet> createState() => _PredictionSheetState();
}

class _PredictionSheetState extends State<_PredictionSheet> {
  late int _home = widget.initialHome;
  late int _away = widget.initialAway;
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().submitPrediction(
            fixtureId: widget.fixture.id,
            home: _home,
            away: _away,
          );
      if (mounted) Navigator.pop(context, (home: _home, away: _away));
    } on ApiException catch (e) {
      // أهم حالة هنا: 409 = انطلقت المباراة بين فتح الشيت والحفظ.
      // رسالة السيرفر العربية تشرحها بالضبط، نعرضها كما هي.
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 22,
        right: 22,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 26,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: Brand.fillStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),
          Text('سجّل توقعك',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontSize: 18)),
          const SizedBox(height: 4),
          Text(
            Fmt.round(widget.fixture.round),
            style: const TextStyle(color: Brand.textFaint, fontSize: 12),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: _ScoreStepper(
                  label: widget.fixture.homeTeamName,
                  value: _home,
                  enabled: !_busy,
                  onChanged: (v) => setState(() => _home = v),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text(':',
                    style: TextStyle(color: Brand.textFaint, fontSize: 20)),
              ),
              Expanded(
                child: _ScoreStepper(
                  label: widget.fixture.awayTeamName,
                  value: _away,
                  enabled: !_busy,
                  onChanged: (v) => setState(() => _away = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // جدول النقاط: يذكّر المستخدم بما يكسبه قبل أن يقرر —
          // مأخوذ من شاشة التوقع المفصّل في ملف الهوية.
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              BrandChip(label: 'نتيجة مضبوطة = 5', tone: BrandTone.correct),
              BrandChip(label: 'فارق الأهداف = 3'),
              BrandChip(label: 'الفائز = 2'),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Brand.wrong, fontSize: 13),
            ),
          ],
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Brand.onAccent),
                    )
                  : const Text('أكّد التوقّع'),
            ),
          ),
        ],
      ),
    );
  }
}

/// عداد نتيجة: زرا + و - حول رقم كبير. أسرع وأقل أخطاء من حقل نص
/// رقمي (لا لوحة مفاتيح، لا قيم شاذة) — النتائج واقعياً بين 0 و 9.
class _ScoreStepper extends StatelessWidget {
  final String label;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  const _ScoreStepper({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Brand.text, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StepButton(
              icon: Icons.add,
              onTap: enabled && value < 99 ? () => onChanged(value + 1) : null,
            ),
            SizedBox(
              width: 46,
              child: Center(child: BrandNumber('$value', size: 28)),
            ),
            _StepButton(
              icon: Icons.remove,
              onTap: enabled && value > 0 ? () => onChanged(value - 1) : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return Material(
      color: on ? Brand.correctWash(0.13) : Brand.fill,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon,
              size: 19, color: on ? Brand.correct : Brand.textFaint),
        ),
      ),
    );
  }
}
