// المجلس — منافسة خاصة: ترتيب أعضائه، وتوقعاتهم على مباراة، ورمز
// دعوته.
//
// الشاشة قسمان لأن للمجلس سؤالين لا ثالث لهما: "من المتصدّر؟"
// و"ماذا توقّع أصحابي؟". الأول ترتيب دائم والثاني لقطة لمباراة
// واحدة، فلا يُقرآن معاً.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../format.dart';
import '../models/fixture.dart';
import '../models/group.dart';
import '../state/session.dart';
import '../widgets/brand_widgets.dart';
import 'leaderboard_screen.dart' show LeaderRow;

class GroupScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  GroupDetail? _detail;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final detail = await context.read<ApiClient>().groupDetail(widget.groupId);
      if (mounted) setState(() => _detail = detail);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final myId = context.watch<Session>().user?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(detail?.group.name ?? widget.groupName),
        actions: [
          if (detail != null)
            IconButton(
              icon: const Icon(Icons.more_horiz),
              tooltip: 'خيارات المجلس',
              onPressed: () => _showOptions(detail.group),
            ),
        ],
      ),
      body: _error != null
          ? BrandEmpty(icon: Icons.wifi_off, message: _error!, onRetry: _load)
          : detail == null
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
                      _InviteCard(group: detail.group),
                      const SizedBox(height: 12),
                      _StandingSummary(detail: detail, myId: myId),
                      const SizedBox(height: 18),
                      const BrandSectionLabel('ترتيب الأعضاء'),
                      const SizedBox(height: 10),
                      for (final e in detail.leaderboard)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: LeaderRow(entry: e, isMe: e.userId == myId),
                        ),
                      const SizedBox(height: 20),
                      _RoundPredictions(groupId: widget.groupId),
                    ],
                  ),
                ),
    );
  }

  void _showOptions(Group group) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Brand.surface,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.copy, color: Brand.textMuted),
              title: const Text('نسخ رمز الدعوة'),
              onTap: () {
                Navigator.pop(sheetContext);
                _copyCode(group.inviteCode);
              },
            ),
            // المالك لا يغادر مجلسه: مجلس بلا صاحب لا أحد يديره أو
            // يحذفه. خياره الحذف الكامل — وهذه قاعدة السيرفر نفسها،
            // نعكسها في الواجهة بدل أن نترك المستخدم يصطدم برسالة خطأ.
            if (group.isOwner)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Brand.wrong),
                title: const Text('حذف المجلس',
                    style: TextStyle(color: Brand.wrong)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmDestructive(
                    title: 'حذف المجلس؟',
                    body: 'يختفي المجلس وترتيبه لكل الأعضاء. لا يمكن التراجع.',
                    action: 'احذف',
                    run: (api) => api.deleteGroup(group.id),
                  );
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.logout, color: Brand.wrong),
                title: const Text('مغادرة المجلس',
                    style: TextStyle(color: Brand.wrong)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmDestructive(
                    title: 'مغادرة المجلس؟',
                    body: 'يمكنك العودة برمز الدعوة نفسه متى شئت.',
                    action: 'غادر',
                    run: (api) => api.leaveGroup(group.id),
                  );
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _copyCode(String? code) {
    if (code == null) return;
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('نُسخ رمز الدعوة')));
  }

  Future<void> _confirmDestructive({
    required String title,
    required String body,
    required String action,
    required Future<void> Function(ApiClient api) run,
  }) async {
    final api = context.read<ApiClient>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Brand.surface,
        title: Text(title),
        content: Text(body,
            style: const TextStyle(color: Brand.textMuted, height: 1.8)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('تراجع')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Brand.wrong),
            child: Text(action),
          ),
        ],
      ),
    );
    if (yes != true) return;

    try {
      await run(api);
      // true تخبر شاشة القائمة أن تعيد الجلب: المجلس لم يعد موجوداً
      // فيها أو لم يعد المستخدم عضواً فيه.
      navigator.pop(true);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// رمز الدعوة — الطريق الوحيد لدخول المجلس، فهو أول ما يُرى.
class _InviteCard extends StatelessWidget {
  final Group group;
  const _InviteCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final code = group.inviteCode;

    return BrandCard(
      royal: true,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'رمز الدعوة',
                  style: const TextStyle(color: Brand.textMuted, fontSize: 11.5),
                ),
                const SizedBox(height: 6),
                Text(
                  code ?? '——',
                  // الرمز لاتيني دائماً، وفرض اتجاهه يمنع ترتيب
                  // العربية من قلب أحرفه على الشاشة.
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontFamily: Brand.displayFont,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                    color: Brand.crown,
                    fontFeatures: Brand.tabular,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${group.membersCount} عضو',
                  style: const TextStyle(
                      color: Brand.textFaint,
                      fontSize: 11.5,
                      fontFeatures: Brand.tabular),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, color: Brand.textMuted),
            tooltip: 'نسخ',
            onPressed: code == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('نُسخ رمز الدعوة')));
                  },
          ),
        ],
      ),
    );
  }
}

/// إحصاءات المجلس في سطر: أين أنا، وكم يفصلني عن المتصدّر.
///
/// الفارق عن المتصدّر هو الرقم الذي يُسأل عنه فعلاً في أي منافسة
/// صغيرة — الترتيب وحده يقول "الثاني" ولا يقول إن الثاني على بعد
/// نقطتين أو مئة.
class _StandingSummary extends StatelessWidget {
  final GroupDetail detail;
  final String? myId;

  const _StandingSummary({required this.detail, required this.myId});

  @override
  Widget build(BuildContext context) {
    final rows = detail.leaderboard;
    if (rows.isEmpty) return const SizedBox.shrink();

    final me = rows.where((e) => e.userId == myId).firstOrNull;
    final leader = rows.first;
    final gap = me == null ? null : leader.totalPoints - me.totalPoints;

    return BrandCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _SummaryCell(value: '${rows.length}', label: 'عضو'),
          _SummaryCell(
            value: me == null ? '—' : '${me.rank}',
            label: 'مركزك',
          ),
          _SummaryCell(
            // المتصدّر لا يُقال له "تبعد صفر نقطة" — يُقال له إنه في
            // القمة، وهي معلومة أخرى تماماً.
            value: gap == null ? '—' : (gap == 0 ? 'المتصدّر' : '$gap'),
            label: gap == 0 ? 'أنت' : 'نقطة عن المتصدّر',
          ),
        ],
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  final String value;
  final String label;
  const _SummaryCell({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontFamily: Brand.displayFont,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Brand.text,
              fontFeatures: Brand.tabular,
            ),
          ),
          const SizedBox(height: 3),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Brand.textFaint, fontSize: 10.5)),
        ],
      ),
    );
  }
}

/// توقعات الأعضاء على مباراة واحدة — الميزة التي تجعل المجلس مجلساً.
///
/// المباراة الافتراضية أقرب مباراة قادمة: هي التي يدور حولها الكلام
/// اليوم، ومطالبة المستخدم باختيار مباراة قبل أن يرى شيئاً تجعل
/// القسم يبدو فارغاً دائماً.
class _RoundPredictions extends StatefulWidget {
  final String groupId;
  const _RoundPredictions({required this.groupId});

  @override
  State<_RoundPredictions> createState() => _RoundPredictionsState();
}

class _RoundPredictionsState extends State<_RoundPredictions> {
  List<Fixture>? _fixtures;
  Fixture? _selected;
  GroupFixturePredictions? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFixtures();
  }

  /// كم يوماً للوراء يعرض المنتقي.
  ///
  /// الجولة تمتد ثلاثة أيام تقريباً، والقادمة وحدها لا تكفي: متعة
  /// "ماذا توقّع أصحابي؟" تحدث بعد المباراة لا قبلها — قبلها تكون
  /// التوقعات مخفية أصلاً بقاعدة السيرفر.
  static const _pastDays = 3;

  Future<void> _loadFixtures() async {
    final api = context.read<ApiClient>();
    try {
      final today = DateTime.now();
      final results = await Future.wait([
        api.upcomingFixtures(),
        for (var d = _pastDays; d >= 0; d--)
          api.fixturesByDate(today.subtract(Duration(days: d))),
      ]);

      // إزالة التكرار بالمعرّف: مباراة اليوم تظهر في "القادمة" وفي
      // يوم اليوم معاً.
      final byId = <int, Fixture>{};
      for (final list in results) {
        for (final f in list) {
          byId[f.id] = f;
        }
      }
      // الترتيب: القادمة تصاعدياً ثم ما مضى تنازلياً — أي "الأقرب
      // زمنياً أولاً" في الاتجاهين. هكذا يكون العنصر الأول هو
      // المختار افتراضياً، فيراه المستخدم فور فتح القسم بلا تمرير.
      // الترتيب الزمني البحت كان يضع أقدم مباراة أول الشريط بينما
      // البيانات تحته لمباراة خارج الشاشة.
      final now = DateTime.now();
      final upcoming = byId.values
          .where((f) => f.kickoffAt.isAfter(now))
          .toList()
        ..sort((a, b) => a.kickoffAt.compareTo(b.kickoffAt));
      final past = byId.values
          .where((f) => !f.kickoffAt.isAfter(now))
          .toList()
        ..sort((a, b) => b.kickoffAt.compareTo(a.kickoffAt));
      final fixtures = [...upcoming, ...past];

      if (!mounted) return;
      setState(() {
        _fixtures = fixtures;
        _selected = fixtures.isEmpty ? null : fixtures.first;
      });
      if (_selected != null) await _loadPredictions();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _loadPredictions() async {
    final fixture = _selected;
    if (fixture == null) return;
    setState(() => _data = null);
    try {
      final data = await context
          .read<ApiClient>()
          .groupFixturePredictions(widget.groupId, fixture.id);
      if (mounted) setState(() => _data = data);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fixtures = _fixtures;
    if (fixtures == null) {
      return const SizedBox.shrink();
    }
    if (fixtures.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BrandSectionLabel('توقعات الأعضاء'),
        const SizedBox(height: 10),
        _FixturePicker(
          fixtures: fixtures,
          selected: _selected,
          onPick: (f) {
            setState(() => _selected = f);
            _loadPredictions();
          },
        ),
        const SizedBox(height: 12),
        if (_error != null)
          Text(_error!,
              style: const TextStyle(color: Brand.wrong, fontSize: 12.5))
        else if (_data == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
                child: CircularProgressIndicator(color: Brand.crown)),
          )
        else
          _PredictionsList(data: _data!),
      ],
    );
  }
}

/// منتقي المباراة — شريط أفقي، أول عنصر فيه هو المختار افتراضياً.
class _FixturePicker extends StatelessWidget {
  final List<Fixture> fixtures;
  final Fixture? selected;
  final ValueChanged<Fixture> onPick;

  const _FixturePicker({
    required this.fixtures,
    required this.selected,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final timeFmt = intl.DateFormat('d MMM', 'ar');

    return SizedBox(
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: fixtures.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = fixtures[i];
          final isSelected = f.id == selected?.id;
          return Material(
            color: isSelected ? Brand.crownWash(0.16) : Brand.fill,
            borderRadius: BorderRadius.circular(Brand.radiusSmall),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onPick(f),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Brand.radiusSmall),
                  border: Border.all(
                    color:
                        isSelected ? Brand.crownWash(0.45) : Colors.transparent,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${f.homeTeamName} — ${f.awayTeamName}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Brand.crown : Brand.textMuted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      Fmt.date(timeFmt, f.kickoffAt),
                      style: const TextStyle(
                          color: Brand.textFaint,
                          fontSize: 10.5,
                          fontFeatures: Brand.tabular),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PredictionsList extends StatelessWidget {
  final GroupFixturePredictions data;
  const _PredictionsList({required this.data});

  @override
  Widget build(BuildContext context) {
    final predicted = data.predictions.where((p) => p.predicted).length;

    return BrandCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        children: [
          if (!data.revealed) ...[
            // سببان مختلفان للإخفاء، ولكل واحد رسالته: الأول انتظار
            // لا حيلة فيه، والثاني فيه فعل يفعله المستخدم الآن.
            Row(
              children: [
                Icon(
                  data.locked ? Icons.visibility_off_outlined : Icons.lock_outline,
                  size: 16,
                  color: data.locked ? Brand.crown : Brand.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    data.locked
                        ? 'توقّعك أنت شرط لرؤية توقعات الأعضاء — '
                            'سجّل توقعك في المباراة القادمة'
                        : 'توقّع $predicted من ${data.predictions.length} — '
                            'تنكشف التوقعات عند انطلاق المباراة',
                    style: TextStyle(
                        color: data.locked ? Brand.crown : Brand.textMuted,
                        fontSize: 12.5,
                        height: 1.6),
                  ),
                ),
              ],
            ),
            const Divider(color: Brand.borderSoft, height: 20),
          ],
          for (final p in data.predictions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      p.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Brand.text, fontSize: 13),
                    ),
                  ),
                  if (!p.predicted)
                    const Text('لم يتوقّع',
                        style:
                            TextStyle(color: Brand.textFaint, fontSize: 11.5))
                  else if (!data.revealed)
                    const Icon(Icons.check_circle_outline,
                        size: 16, color: Brand.correct)
                  else ...[
                    Text(
                      '${p.predHome} - ${p.predAway}',
                      style: const TextStyle(
                          color: Brand.text,
                          fontSize: 13,
                          fontFeatures: Brand.tabular),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text(
                        (p.points ?? 0) > 0 ? '+${p.points}' : '—',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontFamily: Brand.displayFont,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontFeatures: Brand.tabular,
                          color: (p.points ?? 0) > 0
                              ? Brand.crown
                              : Brand.textFaint,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
