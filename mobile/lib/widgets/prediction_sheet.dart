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
import '../models/rules.dart';
import '../screens/premium_screen.dart';
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

  /// آخر خطأ كان سببه غياب الاشتراك — فنعرض باب الاشتراك تحته.
  bool _paywall = false;

  // القواعد وحالة الأداة تصلان بعد الفتح: الشيت يُفتح فوراً بجدول
  // احتياطي ثم يُصحّح نفسه. انتظارُ الشبكة قبل عرضه يجعل ضغطة
  // "توقّع" تبدو معطّلة لثوانٍ على شبكة بطيئة.
  GameRules _rules = GameRules.fallback;
  MultiplierState? _mult;

  /// المضاعِف المختار: 1 أو 2 (المجاني) أو 5 (المشترى).
  ///
  /// رقمٌ واحد لا مربّعان منطقيان: التوقّع يحمل مضاعِفاً واحداً بحكم
  /// عمود القاعدة، ومتغيّران منفصلان كانا سيسمحان بحالة "الاثنان
  /// مشغّلان" التي لا وجود لها.
  int _multiplier = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final rules = await api.rules();
    final mult = await api.multiplierState(widget.fixture.id);
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _mult = mult;
      _multiplier = mult == null
          ? 1
          : mult.boost.on
              ? mult.boost.factor
              : mult.on
                  ? mult.factor
                  : 1;
    });
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final warning = await context.read<ApiClient>().submitPrediction(
            fixtureId: widget.fixture.id,
            home: _home,
            away: _away,
            // نرسله صراحةً لأن الشيت يعرض حالته: إلغاء التأشير
            // هنا قرارٌ لا سهو، وإرسال null كان سيتجاهله.
            multiplier: _mult == null ? null : _multiplier,
          );
      if (!mounted) return;
      if (warning != null) {
        // التوقّع حُفظ والأداة وحدها لم تُطبَّق. رسالة تُقرأ ثم
        // يُغلق الشيت — لا نُبقيه مفتوحاً على عمل تمّ.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(warning)),
        );
      }
      Navigator.pop(context, (home: _home, away: _away));
    } on ApiException catch (e) {
      // أهم حالة هنا: 409 = انطلقت المباراة بين فتح الشيت والحفظ.
      // رسالة السيرفر العربية تشرحها بالضبط، نعرضها كما هي.
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
        // تعديلٌ يحتاج التاج: الرسالة وحدها طريق مسدود، فنعرض معها
        // باباً — الرمز من السيرفر لا مطابقة نصّ (راجع ApiException.code).
        _paywall = e.code == 'EDIT_REQUIRES_CROWN';
      });
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
          // جدول النقاط من الخادم لا من نصّ مكتوب هنا: كان يقول
          // "نتيجة مضبوطة = 5" بينما يمنح النظام مئة.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              BrandChip(
                  label: 'نتيجة مضبوطة = ${_rules.exact}',
                  tone: BrandTone.correct),
              BrandChip(label: 'فارق الأهداف = ${_rules.diff}'),
              BrandChip(label: 'الفائز = ${_rules.outcome}'),
            ],
          ),
          if (_mult != null) ...[
            const SizedBox(height: 16),
            _MultiplierTile(
              title: 'ضاعِف نقاط هذه المباراة ×${_mult!.factor}',
              note: _multiplier != _mult!.factor && _mult!.left == 0
                  ? 'استعملت مضاعفاتك ${_mult!.free} في هذا الدوري'
                  : 'باقٍ لك ${_mult!.left} من ${_mult!.free} في هذا الدوري',
              on: _multiplier == _mult!.factor,
              enabled: !_busy &&
                  (_multiplier == _mult!.factor || _mult!.left > 0),
              onChanged: (v) =>
                  setState(() => _multiplier = v ? _mult!.factor : 1),
            ),
            // المضاعِف المشترى: يظهر لمن يملك رصيداً أو لمن شغّله
            // هنا. من لا رصيد له يرى الدعوة في صفحة التاج لا فوق
            // توقّعه — شيت التوقّع مكان لعب لا مكان بيع.
            if (_mult!.boost.left > 0 || _mult!.boost.on) ...[
              const SizedBox(height: 10),
              _MultiplierTile(
                title: 'مضاعِف ×${_mult!.boost.factor}',
                note: 'رصيدك ${_mult!.boost.left} · يُنفق في أي دوري',
                on: _multiplier == _mult!.boost.factor,
                enabled: !_busy,
                onChanged: (v) =>
                    setState(() => _multiplier = v ? _mult!.boost.factor : 1),
              ),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Brand.wrong, fontSize: 13),
            ),
            if (_paywall) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const PremiumScreen()));
                },
                icon: const Icon(Icons.workspace_premium,
                    size: 18, color: Brand.crown),
                label: const Text('التاج الذهبي'),
              ),
            ],
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

/// مربّع المضاعِف داخل الشيت.
///
/// يبقى ظاهراً معطّلاً حين تنفد الحصة، ومعه سببه: من لا يرى الأداة
/// لا يعرف أنها موجودة ولا متى تعود. (نفس قاعدة الموقع.)
class _MultiplierTile extends StatelessWidget {
  final String title;
  final String note;
  final bool on;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _MultiplierTile({
    required this.title,
    required this.note,
    required this.on,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final spent = !on && !enabled;
    return Opacity(
      opacity: spent ? 0.55 : 1,
      child: InkWell(
        onTap: enabled ? () => onChanged(!on) : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: on ? Brand.crownWash(0.13) : Brand.fill,
            border: Border.all(color: on ? Brand.crown : Brand.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                on ? Icons.check_box : Icons.check_box_outline_blank,
                color: on ? Brand.crown : Brand.textFaint,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          color: Brand.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      note,
                      style: const TextStyle(
                          color: Brand.textFaint, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
