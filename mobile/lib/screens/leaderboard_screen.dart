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
import 'group_screen.dart';

/// سلّم الرتب الموسمية كما في ملف الهوية.
enum Rank {
  fan('مشجّع', 0),
  player('لاعب', 500),
  knight('فارس', 1500),
  prince('أمير', 3000),
  king('الملك', 5000);

  final String label;
  final int from;
  const Rank(this.label, this.from);

  static Rank of(int points) {
    // من الأعلى للأدنى: أول عتبة يبلغها المستخدم هي رتبته.
    for (final r in Rank.values.reversed) {
      if (points >= r.from) return r;
    }
    return Rank.fan;
  }
}

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
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(
              children: [
                BrandModeTab(
                  label: 'العام',
                  selected: _board == _Board.global,
                  onTap: () => setState(() => _board = _Board.global),
                ),
                const SizedBox(width: 8),
                BrandModeTab(
                  label: 'مجالسي',
                  selected: _board == _Board.councils,
                  onTap: () => setState(() => _board = _Board.councils),
                ),
              ],
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
            allLabel: 'العام',
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

    final myId = context.watch<Session>().user?.id;
    final league = _leagueId == null
        ? null
        : _leagues?.where((l) => l.id == _leagueId).firstOrNull;

    return RefreshIndicator(
      onRefresh: _load,
      color: Brand.crown,
      backgroundColor: Brand.surface,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        children: [
          Text(
            league == null ? 'من يجلس على العرش؟' : 'ملوك ${league.name}',
            style: const TextStyle(
              fontFamily: Brand.displayFont,
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: Brand.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            league == null
                ? 'المجموع من كل الدوريات · ${Fmt.counted(entries.length, 'متنافس واحد', 'متنافسان', 'متنافسين', 'متنافساً')}'
                : 'بنقاط هذا الدوري وحده — مبارياته ورهان بطله',
            style: const TextStyle(color: Brand.textMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          // منصّة التتويج: الأول في الوسط وأعلى، والثاني عن يمينه
          // (أول القراءة) والثالث عن يساره. الثلاثة الكبار يستحقون
          // مشهداً لا ثلاثة صفوف — والمقعد الشاغر يُعرض شاغراً لا
          // يُخفى: مقعد فارغ في العرش أقوى دعوة للعب من أي نص.
          _Podium(entries: entries, myId: myId),
          const SizedBox(height: 14),
          for (final e in entries.skip(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: LeaderRow(entry: e, isMe: e.userId == myId),
            ),
        ],
      ),
    );
  }
}

/// منصّة التتويج — المقاعد الثلاثة الأولى.
class _Podium extends StatelessWidget {
  final List<LeaderboardEntry> entries;
  final String? myId;
  const _Podium({required this.entries, required this.myId});

  LeaderboardEntry? _at(int i) => i < entries.length ? entries[i] : null;

  @override
  Widget build(BuildContext context) {
    // ترتيب الأبناء في Row تحت RTL: الأول يمين. فالثاني ← الأول ←
    // الثالث يعطي 2 | 1 | 3 في القراءة، وهو شكل المنصّة المعروف.
    final seats = [
      _PodiumSeat(entry: _at(1), place: 2, myId: myId),
      _PodiumSeat(entry: _at(0), place: 1, myId: myId),
      _PodiumSeat(entry: _at(2), place: 3, myId: myId),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < seats.length; i++) ...[
          Expanded(child: seats[i]),
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
  const _PodiumSeat({required this.entry, required this.place, this.myId});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final first = place == 1;
    final isMe = e != null && e.userId == myId;
    // الأول أطول قاعدةً وأكبر صورةً: العلوّ هو ما يميّز المنصّة عن
    // ثلاث بطاقات متساوية.
    final baseHeight = first ? 74.0 : 52.0;
    final avatar = first ? 56.0 : 44.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (first)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Icon(Icons.emoji_events, size: 22, color: Brand.crown),
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
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: e == null ? Brand.textFaint : Brand.text,
            fontSize: first ? 13 : 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        if (e != null)
          BrandNumber('${e.totalPoints}',
              size: first ? 20 : 16, color: Brand.crown)
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
                  fontSize: first ? 24 : 18,
                  fontWeight: FontWeight.w700,
                  color: first ? Brand.crown : Brand.textMuted,
                  height: 1,
                ),
              ),
              if (e != null && first) ...[
                const SizedBox(height: 3),
                Text(
                  Rank.of(e.totalPoints).label,
                  style: const TextStyle(color: Brand.crown, fontSize: 10.5),
                ),
              ],
              if (isMe) ...[
                const SizedBox(height: 2),
                const Text('أنت',
                    style: TextStyle(color: Brand.crown, fontSize: 10.5)),
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

    return BrandCard(
      royal: isMe,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      child: Row(
        children: [
          _RankBadge(rank: entry.rank),
          const SizedBox(width: 11),
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
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      const Text(
                        '· أنت',
                        style: TextStyle(color: Brand.crown, fontSize: 11.5),
                      ),
                    ],
                    if (entry.favoriteTeamLogo != null) ...[
                      const SizedBox(width: 6),
                      CachedNetworkImage(
                        imageUrl: entry.favoriteTeamLogo!,
                        width: 16,
                        height: 16,
                        errorWidget: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${rank.label} · ${entry.settledPredictions} توقّع محتسب',
                  style: const TextStyle(
                    color: Brand.textMuted,
                    fontSize: 11,
                    fontFeatures: Brand.tabular,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          BrandNumber('${entry.totalPoints}', size: 19, color: Brand.crown),
        ],
      ),
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
      width: 30,
      height: 30,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: rank == 1
          ? const Icon(Icons.emoji_events, size: 16, color: Brand.onAccent)
          : Text(
              '$rank',
              style: TextStyle(
                fontFamily: Brand.displayFont,
                fontSize: 13,
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
        width: 30,
        height: 30,
        decoration: const BoxDecoration(
          color: Brand.fill,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          name.characters.first,
          style: const TextStyle(
            color: Brand.textMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: 15,
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

    final name = await _promptDialog(
      context,
      title: 'مجلس جديد',
      label: 'اسم المجلس',
      hint: 'مثلاً: شباب الحي',
      action: 'أنشئ',
    );
    if (name == null) return;

    try {
      final group = await api.createGroup(name);
      await onChanged();
      messenger.showSnackBar(
        SnackBar(content: Text('أُنشئ ${group.name} — شارك رمز الدعوة')),
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
        final changed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) =>
                GroupScreen(groupId: group.id, groupName: group.name),
          ),
        );
        // المجلس قد يكون حُذف أو غادره المستخدم — القائمة تُعاد بعده.
        if (changed == true) await onChanged();
      },
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Brand.fill,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              group.isOwner ? Icons.workspace_premium : Icons.groups_outlined,
              size: 20,
              // التاج لصاحب المجلس: الذهبي هنا في محله — تمييز دور
              // لا زينة زر.
              color: group.isOwner ? Brand.crown : Brand.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: Brand.displayFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Brand.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  group.isOwner
                      ? '${group.membersCount} عضو · مجلسك'
                      : '${group.membersCount} عضو',
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
