// شاشة العرش — أين أنا بين الناس؟
//
// وضعان تحت تبويب واحد: "العام" ترتيب كل المتوقعين، و"مجالسي"
// المنافسات الخاصة. سؤالهما واحد ولذلك لا يستحقان تبويبين في شريط
// من أربعة — والمجلس بلا العرش بجانبه يفقد معناه: النقطة نفسها
// تُحسب في الاثنين.
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
import '../format.dart';
import '../models/champion.dart';
import '../models/group.dart';
import '../models/leaderboard_entry.dart';
import '../state/session.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/league_strip.dart';
import '../widgets/stage_card.dart';
import '../models/rank.dart';

// الرتب تُصدَّر من هنا كما كانت: شاشات أخرى تستوردها بهذا الاسم.
export '../models/rank.dart' show Rank;
import 'discover_councils_screen.dart';
import 'group_screen.dart';
import 'player_screen.dart';
import '../widgets/group_form_sheet.dart';
import '../widgets/group_avatar.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

/// أي ترتيب معروض: العرش العام أم مجالسي.
enum _Board { global, councils }

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<LeaderboardEntry>? _entries;
  List<Group>? _groups;
  List<LeagueFollow>? _leagues;
  _Board _board = _Board.global;
  String? _error;

  /// null = العرش العام. وإلا دوريٌ بعينه.
  int? _leagueId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _isGuest =>
      context.read<Session>().status == SessionStatus.guest;

  Future<void> _load() async {
    // العرش العام وقائمة الدوريات مساران عامّان؛ المجالس وحدها
    // محمية. الضيف يرى العرش بدورياته كلها — وهو وعد التبويب أصلاً.
    final guest = _isGuest;
    setState(() => _error = null);
    try {
      // الاثنان معاً في طلبين متوازيين: التبديل بين الوضعين يجب أن
      // يكون فورياً، وجلب المجالس عند أول ضغطة يجعل الوضع الثاني
      // يبدو أبطأ من الأول بلا سبب يفهمه المستخدم.
      final api = context.read<ApiClient>();
      // الدوريات مرة واحدة: شرائحها لا تتغيّر بتغيّر الشريحة
      // المختارة، وإعادة جلبها مع كل ضغطة رحلةٌ بلا جديد.
      final needLeagues = _leagues == null;
      final results = await Future.wait([
        api.leaderboard(leagueId: _leagueId),
        if (!guest) api.myGroups(),
        if (needLeagues) api.leagues(),
      ]);
      if (!mounted) return;
      setState(() {
        _entries = results[0] as List<LeaderboardEntry>;
        _groups = guest ? const [] : results[1] as List<Group>;
        if (needLeagues) {
          final all = results.last as List<LeagueFollow>;
          // دوريات المستخدم في الشريط؛ ومن لا يتابع شيئاً (الضيف
          // مثلاً) يرى دوريات اللعبة كلها — شريط فارغ لا يقول شيئاً.
          final followed = all.where((l) => l.followed).toList();
          _leagues = followed.isNotEmpty ? followed : all;
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return BrandEmpty(icon: Icons.wifi_off, message: _error!, onRetry: _load);
    }
    if (_entries == null || _groups == null) {
      return const Center(child: CircularProgressIndicator(color: Brand.crown));
    }

    return Column(
      children: [
        // شريط "العام / مجالسي" للمسجّلين وحدهم: مجالس الضيف صفر
        // حتماً، وعرض تبويب فارغ وعدٌ كاذب.
        if (!_isGuest)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: BrandSegmented(
              labels: const ['العرش', 'مجالسي'],
              selected: _board == _Board.global ? 0 : 1,
              onChanged: (i) => setState(
                  () => _board = i == 0 ? _Board.global : _Board.councils),
            ),
          )
        else
          const SizedBox(height: 12),
        // الشرائح في وضع "العام" وحده: ترتيب المجلس محسوب على
        // أعضائه لا على دوري، فشريحةٌ فوقه تَعِد بتصفية لا تقع.
        if (_board == _Board.global && (_leagues?.isNotEmpty ?? false))
          LeagueStrip(
            leagues: _leagues!,
            active: _leagueId,
            allLabel: 'كل الدوريات',
            onPick: (id) {
              if (_leagueId == id) return;
              setState(() {
                _leagueId = id;
                _entries = null;
              });
              _load();
            },
          ),
        Expanded(
          child: _board == _Board.global
              ? _buildGlobal()
              : _CouncilsView(groups: _groups!, onChanged: _load),
        ),
      ],
    );
  }

  Widget _buildGlobal() {
    if (_error != null) {
      return BrandEmpty(icon: Icons.wifi_off, message: _error!, onRetry: _load);
    }
    final entries = _entries;
    if (entries == null) {
      return const Center(child: CircularProgressIndicator(color: Brand.crown));
    }
    if (entries.isEmpty) {
      return BrandEmpty(
        icon: Icons.workspace_premium_outlined,
        message: _leagueId == null
            ? 'لا نقاط بعد — كن أول من يجلس على العرش'
            : 'لم تُحتسب نقاط في هذا الدوري بعد',
        onRefresh: _load,
      );
    }

    final session = context.watch<Session>();
    final myId = session.user?.id;
    final guest = session.status == SessionStatus.guest;
    final league = _leagueId == null
        ? null
        : _leagues?.where((l) => l.id == _leagueId).firstOrNull;
    final myIndex =
        myId == null ? -1 : entries.indexWhere((e) => e.userId == myId);
    final rest = entries.skip(3).toList();

    return RefreshIndicator(
      onRefresh: _load,
      color: Brand.crown,
      backgroundColor: Brand.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
        children: [
          // المسرح: العنوان والمنصّة وصفّ «أنت» في بطاقة واحدة.
          // كانت المنصّة معلّقة فوق فراغ أسود بلا إطار، فبدت الشاشة
          // ناقصة كلما قلّ المتنافسون — والبطاقة تعطيها حدّاً
          // وسياقاً مهما كان عددهم.
          StageCard(
            title: league == null ? 'ملوك كل الدوريات' : 'ملوك ${league.name}',
            hint: league == null
                ? 'المجموع من كل الدوريات التي تلعب فيها'
                : 'بنقاط هذا الدوري وحده — مبارياته ورهان بطله',
            meta: Fmt.counted(entries.length, 'متنافس واحد', 'متنافسان',
                'متنافسين', 'متنافساً'),
            // منصّة التتويج: الأول في الوسط وأعلى، والثاني عن يمينه
            // (أول القراءة) والثالث عن يساره. والمقعد الشاغر يُعرض
            // شاغراً لا يُخفى: مقعد فارغ في العرش أقوى دعوة للعب.
            podium: Podium(entries: entries, myId: myId),
            // صفّ «أنت»: أول سؤال عند كل مستخدم في أي ترتيب هو «وين
            // أنا؟» — يُجاب هنا دائماً، على المنصّة أو تحتها أو خارجها.
            footer: guest
                ? StageFooter(
                    icon: Icons.person_outline,
                    text: 'سجّل الدخول لتظهر في الترتيب',
                    onTap: () => session.leaveGuest(),
                  )
                : myIndex < 0
                    ? const StageFooter(
                        icon: Icons.sports_soccer_outlined,
                        text: 'لم تدخل الترتيب بعد — توقّع مباراة واحدة وستظهر هنا',
                      )
                    : myIndex < 3
                        ? StageFooter(
                            icon: Icons.emoji_events_outlined,
                            text: 'أنت على المنصّة — المركز ${entries[myIndex].rank}',
                            gold: true,
                          )
                        : StageFooter(
                            icon: Icons.person,
                            text:
                                'أنت · المركز ${entries[myIndex].rank} · ${entries[myIndex].totalPoints} نقطة',
                            gold: true,
                          ),
          ),
          if (rest.isNotEmpty) ...[
            const SizedBox(height: 18),
            const BrandSectionLabel('بقية الترتيب'),
            const SizedBox(height: 10),
            for (final e in rest)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LeaderRow(entry: e, isMe: e.userId == myId),
              ),
          ],
        ],
      ),
    );
  }
}

/// صف واحد في أي ترتيب — العرش العام أو ترتيب مجلس.
///
/// مشترك عمداً: الرقم في المجلس والرقم في العرش يخرجان من نفس
/// الحساب، فلو اختلف شكلهما ظنّ المستخدم أنهما شيئان مختلفان.
class LeaderRow extends StatelessWidget {
  final LeaderboardEntry entry;
  final bool isMe;
  const LeaderRow({super.key, required this.entry, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final rank = Rank.of(entry.totalPoints);
    final acc = entry.accuracy;

    return BrandCard(
      royal: isMe,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      // الصف باب إلى ملف صاحبه: «من هذا الذي يتصدّرني؟» سؤال يُسأل
      // من داخل الترتيب لا من مكان آخر.
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
              userId: entry.userId, displayName: entry.displayName),
        ),
      ),
      child: Row(
        children: [
          _RankBadge(rank: entry.rank),
          const SizedBox(width: 10),
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
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      const Text(
                        '· أنت',
                        style: TextStyle(color: Brand.crown, fontSize: 11),
                      ),
                    ],
                    if (entry.favoriteTeamLogo != null) ...[
                      const SizedBox(width: 6),
                      CachedNetworkImage(
                        imageUrl: entry.favoriteTeamLogo!,
                        width: 14,
                        height: 14,
                        errorWidget: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  // الدقّة إلى جانب العدد حين تُعرف: النقاط تكافئ الكثرة،
                  // والنسبة تقول إن كان الرقم إتقاناً أم مثابرة.
                  '${rank.label} · ${entry.settledPredictions} توقّع'
                  '${acc != null ? ' · دقّة $acc%' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Brand.textMuted,
                    fontSize: 10.5,
                    fontFeatures: Brand.tabular,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              BrandNumber('${entry.totalPoints}', size: 16, color: Brand.crown),
              if (entry.movement != null) _Movement(delta: entry.movement!),
            ],
          ),
        ],
      ),
    );
  }
}

/// حركة المركز منذ آخر جولة: ▲2 بالذهبي للصعود، ▼1 بالخافت للهبوط،
/// وشرطة للثبات. لا أخضر ولا أحمر: الهوية تحصرهما في صواب التوقع
/// وخطئه، والسهم في بطاقة فيها نقاط ذهبية لا يشاركها لوناً آخر.
class _Movement extends StatelessWidget {
  final int delta;
  const _Movement({required this.delta});

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String text) = delta > 0
        ? (Icons.arrow_drop_up, Brand.crown, '$delta')
        : delta < 0
            ? (Icons.arrow_drop_down, Brand.textMuted, '${-delta}')
            : (Icons.remove, Brand.textFaint, '');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: delta == 0 ? 12 : 18, color: color),
        if (text.isNotEmpty)
          Text(text,
              style: TextStyle(
                  color: color, fontSize: 10.5, fontFeatures: Brand.tabular)),
      ],
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
      width: 26,
      height: 26,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: rank == 1
          ? const Icon(Icons.emoji_events, size: 14, color: Brand.onAccent)
          : Text(
              '$rank',
              style: TextStyle(
                fontFamily: Brand.displayFont,
                fontSize: 11.5,
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
        width: 26,
        height: 26,
        decoration: const BoxDecoration(
          color: Brand.fill,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          name.isEmpty ? '' : name.characters.first,
          style: const TextStyle(
            color: Brand.textMuted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: 13,
      backgroundColor: Brand.fill,
      backgroundImage: CachedNetworkImageProvider(AppConfig.absoluteUrl(url!)),
    );
  }
}

/// قائمة مجالسي: بطاقة لكل مجلس، وزرّا الإنشاء والانضمام فوقها.
///
/// الزران في الأعلى دائماً لا في حالة الفراغ وحدها: من عنده مجلس
/// واحد هو أكثر من يريد إنشاء الثاني أو الانضمام لمجلس صديق.
class _CouncilsView extends StatelessWidget {
  final List<Group> groups;
  final Future<void> Function() onChanged;

  const _CouncilsView({required this.groups, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onChanged,
      color: Brand.crown,
      backgroundColor: Brand.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _createDialog(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('أنشئ مجلساً'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _joinDialog(context),
                  icon: const Icon(Icons.key_outlined, size: 18),
                  label: const Text('انضم برمز'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // باب ثالث لمن لا يعرف أحداً: الرمز يفترض صديقاً، والمجالس
          // العامة لا تفترض شيئاً.
          BrandCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const DiscoverCouncilsScreen()),
              );
              // قد يكون انضمّ إلى مجلس هناك — القائمة تُعاد.
              await onChanged();
            },
            child: const Row(
              children: [
                Icon(Icons.public, size: 18, color: Brand.textMuted),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'استكشف المجالس العامة',
                    style: TextStyle(
                        color: Brand.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: Brand.textFaint),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(Icons.groups_outlined, size: 42, color: Brand.textFaint),
                  SizedBox(height: 14),
                  Text(
                    'ما عندك مجلس بعد',
                    style: TextStyle(
                      fontFamily: Brand.displayFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Brand.text,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'المجلس منافسة خاصة بينك وبين من تدعوهم — '
                    'نفس النقاط، لكن الترتيب بينكم وحدكم.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Brand.textMuted,
                      fontSize: 13,
                      height: 1.8,
                    ),
                  ),
                ],
              ),
            )
          else
            for (final g in groups)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CouncilCard(group: g, onChanged: onChanged),
              ),
        ],
      ),
    );
  }

  Future<void> _createDialog(BuildContext context) async {
    // نلتقط الخدمات قبل فتح النافذة لا بعدها: البحث عن
    // ScaffoldMessenger يسجّل اعتماداً على الـ context، وتسجيله بعد
    // await على شجرة تُعاد بناؤها هو ما يفجّر التأكيد
    // "_dependents.isEmpty" في فلاتر.
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);

    final form = await GroupFormSheet.show(
      context,
      title: 'مجلس جديد',
      action: 'أنشئ المجلس',
    );
    if (form == null) return;

    try {
      final group = await api.createGroup(
        name: form.name,
        joinPolicy: form.joinPolicy,
        leagueId: form.leagueId,
      );
      await onChanged();
      messenger.showSnackBar(
        SnackBar(
          content: Text(group.isPublic
              ? 'أُنشئ ${group.name} — يظهر الآن في المجالس العامة'
              : 'أُنشئ ${group.name} — شارك رمز الدعوة'),
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _joinDialog(BuildContext context) async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);

    final code = await _promptDialog(
      context,
      title: 'انضمام بمجلس',
      label: 'رمز الدعوة',
      hint: 'ستة أحرف',
      action: 'انضم',
    );
    if (code == null) return;

    try {
      final group = await api.joinGroup(code);
      await onChanged();
      messenger.showSnackBar(
        SnackBar(content: Text('انضممت إلى ${group.name}')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// نافذة إدخال سطر واحد. ترجع النص أو null لو ألغى المستخدم.
  Future<String?> _promptDialog(
    BuildContext context, {
    required String title,
    required String label,
    required String hint,
    required String action,
  }) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _PromptDialog(
        title: title,
        label: label,
        hint: hint,
        action: action,
      ),
    );
    return (value == null || value.isEmpty) ? null : value;
  }
}

/// نافذة الإدخال ويدجت ذات حالة كي تملك المتحكّم وتتخلص منه في
/// dispose الخاص بها.
///
/// الشكل السابق كان ينشئ TextEditingController في دالة ثم يستدعي
/// dispose فور عودة showDialog — بينما مسار النافذة ما زال يتحرك
/// خارج الشاشة وحقل النص حيّ يستعمل المتحكّم. النتيجة انهيار عند
/// الإنشاء، لا عند الكتابة، فيبدو وكأن العطل في نداء السيرفر.
class _PromptDialog extends StatefulWidget {
  final String title;
  final String label;
  final String hint;
  final String action;

  const _PromptDialog({
    required this.title,
    required this.label,
    required this.hint,
    required this.action,
  });

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Brand.surface,
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration:
            InputDecoration(labelText: widget.label, hintText: widget.hint),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء')),
        TextButton(onPressed: _submit, child: Text(widget.action)),
      ],
    );
  }
}

class _CouncilCard extends StatelessWidget {
  final Group group;
  final Future<void> Function() onChanged;

  const _CouncilCard({required this.group, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      onTap: () async {
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) =>
                GroupScreen(groupId: group.id, groupName: group.name),
          ),
        );
        // القائمة تُعاد بعد العودة دائماً: المجلس قد يكون حُذف أو
        // غادره المستخدم أو تغيّر اسمه أو دوريه — والطلب رخيص.
        await onChanged();
      },
      child: Row(
        children: [
          GroupAvatar(group: group, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: Brand.displayFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Brand.text,
                        ),
                      ),
                    ),
                    // التاج لصاحب المجلس، والدرع للمشرف: الذهبي هنا في
                    // محله — تمييز دور لا زينة زر.
                    if (group.role == GroupRole.owner) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.workspace_premium,
                          size: 15, color: Brand.crown),
                    ] else if (group.role == GroupRole.moderator) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.shield_outlined,
                          size: 14, color: Brand.textMuted),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${group.scopeLabel} · ${group.joinPolicy.label} · '
                  '${group.membersCount} عضو'
                  '${group.pendingRequests > 0 && group.role.canManageMembers ? ' · ${group.pendingRequests} طلب' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Brand.textFaint,
                    fontSize: 11.5,
                    fontFeatures: Brand.tabular,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 20, color: Brand.textFaint),
        ],
      ),
    );
  }
}
