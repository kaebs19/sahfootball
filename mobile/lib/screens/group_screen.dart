// المجلس — منافسة خاصة أو عامة: ترتيب أعضائه، وقائمتهم بأدوارهم،
// وتوقعاتهم على مباراة، ورمز دعوته.
//
// ثلاثة أسئلة تحت مبدّل واحد لا شاشة طويلة: «من المتصدّر؟» ترتيب
// دائم، و«من هنا ومن يدير؟» قائمة تُدار، و«ماذا توقّع أصحابي؟» لقطة
// لمباراة واحدة. لا تُقرأ معاً، وعرضها معاً تمريرة يتوه فيها الثلاثة.
//
// المبدّل محايد اللون (BrandSegmented) لأنه يجيب «أي عرض؟» —
// والذهبي للشرائح التي تجيب «أي بيانات؟».
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../config.dart';
import '../format.dart';
import '../models/fixture.dart';
import '../models/group.dart';
import '../models/leaderboard_entry.dart';
import '../models/player.dart';
import '../state/session.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/group_avatar.dart';
import '../widgets/group_form_sheet.dart';
import '../widgets/stage_card.dart';
import 'leaderboard_screen.dart' show LeaderRow;
import 'player_screen.dart';

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

/// أي قسم معروض.
enum _Tab { standings, members, predictions }

class _GroupScreenState extends State<GroupScreen> {
  GroupDetail? _detail;
  String? _error;
  _Tab _tab = _Tab.standings;

  /// ترتيب الجولة الأخيرة بدل الموسم. الموسم يجمّد المراكز بعد شهرين؛
  /// الجولة تعطي كل أسبوع منافسة جديدة بنفس الصفوف.
  bool _round = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final detail = await context
          .read<ApiClient>()
          .groupDetail(widget.groupId, round: _round);
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
          // المشاركة في الترويسة لا في القائمة: الدعوة أكثر فعل يُفعل
          // في مجلس جديد، ولا يجوز أن تختبئ خلف ثلاث نقاط.
          if (detail != null && detail.group.isMember && detail.group.inviteUrl != null)
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'شارك رابط الدعوة',
              onPressed: () => _share(detail.group),
            ),
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
                      _HeaderCard(
                        group: detail.group,
                        onJoin: _join,
                        onCancelRequest: _cancelRequest,
                      ),
                      const SizedBox(height: 14),
                      BrandSegmented(
                        // غير العضو لا يرى قسم التوقعات: السيرفر يرفضه
                        // أصلاً، وتبويب يفتح على رسالة رفض وعدٌ كاذب.
                        labels: [
                          'الترتيب',
                          'الأعضاء',
                          if (detail.group.isMember) 'التوقعات',
                        ],
                        selected: _tab.index,
                        onChanged: (i) => setState(() => _tab = _Tab.values[i]),
                      ),
                      const SizedBox(height: 14),
                      ...switch (_tab) {
                        _Tab.standings => _standings(detail, myId),
                        _Tab.members => _members(detail, myId),
                        _Tab.predictions => [
                            _RoundPredictions(
                              groupId: widget.groupId,
                              leagueId: detail.group.leagueId,
                            ),
                          ],
                      },
                    ],
                  ),
                ),
    );
  }

  List<Widget> _standings(GroupDetail detail, String? myId) {
    final g = detail.group;
    final rows = detail.leaderboard;
    final myIndex = myId == null ? -1 : rows.indexWhere((e) => e.userId == myId);
    final rest = rows.skip(3).toList();
    final round = detail.scope == 'round';
    // اسم الجولة من المزود («Regular Season - 5») يُترجم؛ ومجلس كل
    // الدوريات يجمع جولات مختلفة فيقال «آخر جولة» وحسب.
    final roundName = detail.roundLabel == null
        ? 'آخر جولة'
        : Fmt.round(detail.roundLabel, fallback: 'آخر جولة');

    return [
      // المبدّل لا يظهر قبل أول جولة محتسبة: «هذه الجولة» بلا جولة
      // زرٌّ يفتح على أصفار.
      if (detail.hasRound) ...[
        BrandSegmented(
          labels: const ['الموسم', 'هذه الجولة'],
          selected: _round ? 1 : 0,
          onChanged: (i) {
            if ((i == 1) == _round) return;
            setState(() => _round = i == 1);
            _load();
          },
        ),
        const SizedBox(height: 14),
      ],
      // المسرح: منصّة التتويج نفسها التي في العرش — الرقم هنا والرقم
      // هناك من حساب واحد، فيجب أن يبدوا شيئاً واحداً.
      StageCard(
        title: round ? 'ملك $roundName' : 'ملك «${g.name}»',
        hint: round
            ? 'بنقاط ${detail.roundLabel == null ? 'آخر جولة في كل دوري' : roundName} وحدها'
            : g.leagueName == null
                ? 'بمجموع النقاط من كل الدوريات'
                : 'بنقاط ${g.leagueName} وحده — مبارياته ورهان بطله',
        meta: Fmt.counted(rows.length, 'عضو واحد', 'عضوان', 'أعضاء', 'عضواً'),
        podium: Podium(
          entries: rows,
          myId: myId,
          crownLabel: round ? 'ملك $roundName' : 'ملك المجلس',
        ),
        footer: _footer(rows, myIndex),
      ),
      if (!round) ...[
        const SizedBox(height: 12),
        _StandingSummary(detail: detail, myId: myId),
      ],
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
    ];
  }

  /// صفّ «أنت» أسفل المسرح — يُجاب دائماً: على المنصّة أو تحتها أو
  /// خارج المجلس.
  Widget _footer(List<LeaderboardEntry> rows, int myIndex) {
    if (myIndex < 0) {
      return const StageFooter(
        icon: Icons.person_outline,
        text: 'لست عضواً — انضمّ لتظهر في الترتيب',
      );
    }
    final me = rows[myIndex];
    if (myIndex < 3) {
      return StageFooter(
        icon: Icons.emoji_events_outlined,
        text: 'أنت على المنصّة — المركز ${me.rank}',
        gold: true,
      );
    }
    return StageFooter(
      icon: Icons.person,
      text: 'أنت · المركز ${me.rank} · ${me.totalPoints} نقطة',
      gold: true,
    );
  }

  List<Widget> _members(GroupDetail detail, String? myId) {
    final me = detail.viewerRole;
    return [
      if (me.canManageMembers) ...[
        OutlinedButton.icon(
          onPressed: () => _addMember(detail),
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
          label: const Text('أضف عضواً'),
        ),
        const SizedBox(height: 12),
        // الطلبات فوق الأعضاء: ما ينتظر قراراً يسبق ما استقرّ.
        if (detail.requests.isNotEmpty) ...[
          BrandSectionLabel('طلبات الانضمام (${detail.requests.length})'),
          const SizedBox(height: 10),
          for (final r in detail.requests)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RequestRow(
                request: r,
                onApprove: () => _decide(detail.group, r, approve: true),
                onReject: () => _decide(detail.group, r, approve: false),
              ),
            ),
          const SizedBox(height: 10),
          const BrandSectionLabel('الأعضاء'),
          const SizedBox(height: 10),
        ],
      ],
      for (final m in detail.members)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _MemberRow(
            member: m,
            isMe: m.userId == myId,
            actions: _actionsFor(actor: me, target: m),
            onAction: (a) => _runAction(detail.group, m, a),
          ),
        ),
    ];
  }

  /// ما يجوز للناظر أن يفعله بعضو — انعكاس سلّم groupService في
  /// السيرفر، لا مصدر ثانٍ له: الواجهة تخفي ما لا يجوز، والسيرفر
  /// هو من يرفض.
  List<_MemberAction> _actionsFor({
    required GroupRole actor,
    required GroupMember target,
  }) {
    if (target.role == GroupRole.owner) return const [];
    return switch (actor) {
      GroupRole.owner => [
          target.role == GroupRole.moderator
              ? _MemberAction.demote
              : _MemberAction.promote,
          _MemberAction.remove,
        ],
      GroupRole.moderator when target.role == GroupRole.member => const [
          _MemberAction.remove,
        ],
      _ => const [],
    };
  }

  Future<void> _runAction(Group group, GroupMember m, _MemberAction a) async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);

    if (a == _MemberAction.remove) {
      final yes = await _confirm(
        title: 'إزالة ${m.displayName}؟',
        body: 'يخرج من المجلس ويستطيع العودة بالرمز أو من الاستكشاف.',
        action: 'أزل',
      );
      if (yes != true) return;
    }

    try {
      switch (a) {
        case _MemberAction.promote:
          await api.setGroupMemberRole(group.id, m.userId, 'moderator');
        case _MemberAction.demote:
          await api.setGroupMemberRole(group.id, m.userId, 'member');
        case _MemberAction.remove:
          await api.removeGroupMember(group.id, m.userId);
      }
      await _load();
      messenger.showSnackBar(SnackBar(
        content: Text(switch (a) {
          _MemberAction.promote => '${m.displayName} صار مشرفاً',
          _MemberAction.demote => 'أُزيل الإشراف عن ${m.displayName}',
          _MemberAction.remove => 'أُزيل ${m.displayName} من المجلس',
        }),
      ));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// نصّ المشاركة: جملة واحدة ثم الرابط — واتساب يجعل الرابط
  /// معاينةً بصورة المجلس واسمه (og:image من صفحة الدعوة).
  Future<void> _share(Group group) async {
    final url = group.inviteUrl;
    if (url == null) return;
    await SharePlus.instance.share(ShareParams(
      text: 'انضمّ إلى مجلس «${group.name}» في ملك التوقعات ونافسني على العرش:\n$url',
      subject: 'دعوة إلى مجلس ${group.name}',
    ));
  }

  /// صورة المجلس: اختيار من المعرض ثم رفع — نفس حدود الصورة الشخصية
  /// (800px، جودة 85) لأن الشاشة تعرضها في دائرة صغيرة.
  Future<void> _pickImage(Group group) async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked == null) return;
    try {
      await api.uploadGroupImage(group.id, picked.path);
      await _load();
      messenger.showSnackBar(const SnackBar(content: Text('حُفظت صورة المجلس')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _removeImage(Group group) async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.deleteGroupImage(group.id);
      await _load();
      messenger.showSnackBar(const SnackBar(content: Text('أُزيلت صورة المجلس')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _decide(Group group, JoinRequest r, {required bool approve}) async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (approve) {
        await api.approveJoinRequest(group.id, r.userId);
      } else {
        await api.withdrawJoinRequest(group.id, r.userId);
      }
      await _load();
      messenger.showSnackBar(SnackBar(
        content: Text(approve
            ? 'انضمّ ${r.displayName} إلى المجلس'
            : 'رُفض طلب ${r.displayName}'),
      ));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _cancelRequest() async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    final myId = context.read<Session>().user?.id;
    if (myId == null) return;
    try {
      await api.withdrawJoinRequest(widget.groupId, myId);
      await _load();
      messenger.showSnackBar(const SnackBar(content: Text('أُلغي طلبك')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _addMember(GroupDetail detail) async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Brand.surface,
      isScrollControlled: true,
      builder: (_) => _AddMemberSheet(
        groupId: detail.group.id,
        existing: detail.members.map((m) => m.userId).toSet(),
      ),
    );
    if (added == true) await _load();
  }

  Future<void> _join() async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final outcome = await api.joinPublicGroup(widget.groupId);
      await _load();
      messenger.showSnackBar(SnackBar(
        content: Text(outcome.requested
            ? 'أُرسل طلبك — سيصلك إشعار عند الموافقة'
            : 'انضممت إلى المجلس'),
      ));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
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
            if (!group.isMember && group.hasRequest)
              ListTile(
                leading: const Icon(Icons.close, color: Brand.wrong),
                title: const Text('إلغاء طلب الانضمام',
                    style: TextStyle(color: Brand.wrong)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _cancelRequest();
                },
              )
            else if (!group.isMember)
              ListTile(
                leading: const Icon(Icons.login, color: Brand.textMuted),
                title: Text(group.joinPolicy == JoinPolicy.approval
                    ? 'طلب الانضمام'
                    : 'الانضمام إلى المجلس'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _join();
                },
              ),
            if (group.isMember && group.inviteUrl != null)
              ListTile(
                leading: const Icon(Icons.ios_share, color: Brand.textMuted),
                title: const Text('شارك رابط الدعوة'),
                subtitle: const Text('يفتح المجلس في التطبيق مباشرة',
                    style: TextStyle(color: Brand.textFaint, fontSize: 11.5)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _share(group);
                },
              ),
            if (group.isMember)
              ListTile(
                leading: const Icon(Icons.copy, color: Brand.textMuted),
                title: const Text('نسخ رمز الدعوة'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _copyCode(group.inviteCode);
                },
              ),
            if (group.isOwner)
              ListTile(
                leading: const Icon(Icons.image_outlined, color: Brand.textMuted),
                title: Text(group.imageUrl == null ? 'صورة المجلس' : 'تغيير صورة المجلس'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage(group);
                },
              ),
            if (group.isOwner && group.imageUrl != null)
              ListTile(
                leading: const Icon(Icons.hide_image_outlined, color: Brand.textMuted),
                title: const Text('إزالة الصورة'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _removeImage(group);
                },
              ),
            if (group.isOwner)
              ListTile(
                leading: const Icon(Icons.tune, color: Brand.textMuted),
                title: const Text('إعدادات المجلس'),
                subtitle: Text(
                  'الاسم · ${group.joinPolicy.label} · ${group.scopeLabel}',
                  style: const TextStyle(color: Brand.textFaint, fontSize: 11.5),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _editSettings(group);
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
            else if (group.isMember)
              ListTile(
                leading: const Icon(Icons.logout, color: Brand.wrong),
                title: const Text('مغادرة المجلس',
                    style: TextStyle(color: Brand.wrong)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmDestructive(
                    title: 'مغادرة المجلس؟',
                    body: group.isPublic
                        ? 'يمكنك العودة من المجالس العامة متى شئت.'
                        : 'يمكنك العودة برمز الدعوة نفسه متى شئت.',
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

  Future<void> _editSettings(Group group) async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);

    final form = await GroupFormSheet.show(
      context,
      title: 'إعدادات المجلس',
      action: 'احفظ',
      initial: GroupForm(
        name: group.name,
        joinPolicy: group.joinPolicy,
        leagueId: group.leagueId,
      ),
    );
    if (form == null) return;

    try {
      await api.updateGroup(
        group.id,
        name: form.name,
        joinPolicy: form.joinPolicy,
        leagueId: form.leagueId,
      );
      await _load();
      messenger.showSnackBar(const SnackBar(content: Text('حُفظت الإعدادات')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _copyCode(String? code) {
    if (code == null) return;
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('نُسخ رمز الدعوة')));
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
  }) {
    return showDialog<bool>(
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

    final yes = await _confirm(title: title, body: body, action: action);
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

enum _MemberAction { promote, demote, remove }

/// ترويسة المجلس: ما هو (الدوري، عام/خاص، العدد) ورمز دعوته — أو
/// زرّ الانضمام لمن يتصفّح مجلساً عاماً من الخارج.
class _HeaderCard extends StatelessWidget {
  final Group group;
  final Future<void> Function() onJoin;
  final Future<void> Function() onCancelRequest;
  const _HeaderCard({
    required this.group,
    required this.onJoin,
    required this.onCancelRequest,
  });

  @override
  Widget build(BuildContext context) {
    final g = group;
    final code = g.inviteCode;

    return BrandCard(
      royal: g.isMember,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GroupAvatar(group: g, size: 56, ringed: true),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ScopeChip(group: g),
              BrandChip(
                label: g.joinPolicy.label,
                icon: switch (g.joinPolicy) {
                  JoinPolicy.code => Icons.lock_outline,
                  JoinPolicy.approval => Icons.how_to_reg_outlined,
                  JoinPolicy.open => Icons.public,
                },
              ),
              BrandChip(
                label: Fmt.counted(
                    g.membersCount, 'عضو واحد', 'عضوان', 'أعضاء', 'عضواً'),
                icon: Icons.groups_outlined,
              ),
              if (g.role == GroupRole.owner)
                const BrandChip(
                    label: 'مجلسك',
                    icon: Icons.workspace_premium,
                    tone: BrandTone.crown)
              else if (g.role == GroupRole.moderator)
                const BrandChip(label: 'أنت مشرف', icon: Icons.shield_outlined),
            ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!g.isMember && g.hasRequest)
            // الطلب معلّق: نقول ذلك بوضوح ونترك باب الإلغاء — الانتظار
            // بلا معرفة أنك تنتظر هو ما يجعل الناس يطلبون مرتين.
            Row(
              children: [
                const Icon(Icons.schedule, size: 18, color: Brand.crown),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'طلبك بانتظار موافقة المالك — سيصلك إشعار',
                    style: TextStyle(color: Brand.crown, fontSize: 12.5),
                  ),
                ),
                TextButton(
                  onPressed: onCancelRequest,
                  child: const Text('إلغاء'),
                ),
              ],
            )
          else if (!g.isMember)
            FilledButton.icon(
              onPressed: onJoin,
              icon: Icon(
                  g.joinPolicy == JoinPolicy.approval
                      ? Icons.how_to_reg_outlined
                      : Icons.login,
                  size: 18),
              label: Text(g.joinPolicy == JoinPolicy.approval
                  ? 'اطلب الانضمام'
                  : 'انضم إلى المجلس'),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'رمز الدعوة',
                        style: TextStyle(color: Brand.textMuted, fontSize: 11.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        code ?? '——',
                        // الرمز لاتيني دائماً، وفرض اتجاهه يمنع ترتيب
                        // العربية من قلب أحرفه على الشاشة.
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          fontFamily: Brand.displayFont,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 4,
                          color: Brand.crown,
                          fontFeatures: Brand.tabular,
                        ),
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
        ],
      ),
    );
  }
}

/// شريحة الدوري — بشعاره حين يكون مقيّداً، و«كل الدوريات» وإلا.
class _ScopeChip extends StatelessWidget {
  final Group group;
  const _ScopeChip({required this.group});

  @override
  Widget build(BuildContext context) {
    final g = group;
    if (g.leagueLogo == null) {
      return BrandChip(label: g.scopeLabel, icon: Icons.all_inclusive);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: Brand.crownWash(0.13),
        border: Border.all(color: Brand.crownWash(0.3)),
        borderRadius: BorderRadius.circular(Brand.radiusChip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CachedNetworkImage(
            imageUrl: AppConfig.absoluteUrl(g.leagueLogo!),
            width: 14,
            height: 14,
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
          const SizedBox(width: 5),
          Text(
            g.scopeLabel,
            style: const TextStyle(
              fontFamily: Brand.bodyFont,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Brand.crown,
            ),
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
    final league = detail.group.leagueName;

    return BrandCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              _SummaryCell(value: '${rows.length}', label: 'عضو'),
              _SummaryCell(
                value: me == null ? '—' : '${me.rank}',
                label: 'مركزك',
              ),
              _SummaryCell(
                // المتصدّر لا يُقال له "تبعد صفر نقطة" — يُقال له إنه في
                // القمة، وهي معلومة أخرى تماماً. والمتعادل معه في
                // النقاط دون المركز الأول (فضّ التعادل بالأقدمية) يُقال
                // له إنه متعادل، لا إنه المتصدّر.
                value: gap == null
                    ? '—'
                    : me!.rank == 1
                        ? 'المتصدّر'
                        : gap == 0
                            ? 'متعادل'
                            : '$gap',
                label: gap == null
                    ? 'نقطة عن المتصدّر'
                    : me!.rank == 1
                        ? 'أنت'
                        : gap == 0
                            ? 'مع المتصدّر'
                            : 'نقطة عن المتصدّر',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            league == null
                ? 'الترتيب بمجموع النقاط من كل الدوريات'
                : 'الترتيب بنقاط $league وحده — مبارياته ورهان بطله',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Brand.textFaint, fontSize: 10.5),
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

/// صف عضو: صورته واسمه ودوره وتاريخ انضمامه، وقائمة أفعال لمن يملك
/// عليه صلاحية. الضغط على الصف يفتح ملفه.
class _MemberRow extends StatelessWidget {
  final GroupMember member;
  final bool isMe;
  final List<_MemberAction> actions;
  final ValueChanged<_MemberAction> onAction;

  const _MemberRow({
    required this.member,
    required this.isMe,
    required this.actions,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final m = member;
    final joined = m.joinedAt == null
        ? null
        : Fmt.date(intl.DateFormat('d MMM y', 'ar'), m.joinedAt!);

    return BrandCard(
      royal: isMe,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              PlayerScreen(userId: m.userId, displayName: m.displayName),
        ),
      ),
      child: Row(
        children: [
          _SmallAvatar(url: m.avatarUrl, name: m.displayName),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        m.displayName,
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
                      const Text('· أنت',
                          style: TextStyle(color: Brand.crown, fontSize: 11)),
                    ],
                  ],
                ),
                if (joined != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'انضمّ $joined',
                    style: const TextStyle(
                      color: Brand.textFaint,
                      fontSize: 10.5,
                      fontFeatures: Brand.tabular,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _RoleChip(role: m.role),
          if (actions.isNotEmpty)
            PopupMenuButton<_MemberAction>(
              icon: const Icon(Icons.more_vert, size: 18, color: Brand.textMuted),
              color: Brand.surface,
              onSelected: onAction,
              itemBuilder: (_) => [
                for (final a in actions)
                  PopupMenuItem(
                    value: a,
                    child: Text(
                      switch (a) {
                        _MemberAction.promote => 'تعيين مشرفاً',
                        _MemberAction.demote => 'عزل من الإشراف',
                        _MemberAction.remove => 'إزالة من المجلس',
                      },
                      style: TextStyle(
                        color: a == _MemberAction.remove
                            ? Brand.wrong
                            : Brand.text,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            )
          else
            const SizedBox(width: 6),
        ],
      ),
    );
  }
}

/// صف طلب انضمام: من، ومتى، وزرّا القبول والرفض.
class _RequestRow extends StatelessWidget {
  final JoinRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _RequestRow({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final r = request;
    final when = r.requestedAt == null
        ? null
        : Fmt.date(intl.DateFormat('d MMM', 'ar'), r.requestedAt!);
    return BrandCard(
      royal: true,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              PlayerScreen(userId: r.userId, displayName: r.displayName),
        ),
      ),
      child: Row(
        children: [
          _SmallAvatar(url: r.avatarUrl, name: r.displayName),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Brand.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  when == null ? 'يطلب الانضمام' : 'طلب الانضمام $when',
                  style: const TextStyle(
                    color: Brand.textFaint,
                    fontSize: 10.5,
                    fontFeatures: Brand.tabular,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // الرفض أيقونة والقبول زرّ: القبول هو الفعل المتوقّع، والرفض
          // يبقى متاحاً بلا أن ينافسه في الحجم.
          IconButton(
            onPressed: onReject,
            tooltip: 'رفض',
            icon: const Icon(Icons.close, size: 18, color: Brand.textMuted),
          ),
          SizedBox(
            height: 32,
            child: FilledButton(
              onPressed: onApprove,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Text('اقبل'),
            ),
          ),
        ],
      ),
    );
  }
}

/// شارة الدور. المالك ذهبي — تمييز دور لا زينة — والمشرف محايد،
/// والعضو العادي بلا شارة: الأغلبية لا تحتاج وسماً.
class _RoleChip extends StatelessWidget {
  final GroupRole role;
  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) {
    return switch (role) {
      GroupRole.owner => const BrandChip(
          label: 'مالك', icon: Icons.workspace_premium, tone: BrandTone.crown),
      GroupRole.moderator =>
        const BrandChip(label: 'مشرف', icon: Icons.shield_outlined),
      _ => const SizedBox.shrink(),
    };
  }
}

class _SmallAvatar extends StatelessWidget {
  final String? url;
  final String name;
  const _SmallAvatar({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    const size = 30.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Brand.fill,
        image: url != null
            ? DecorationImage(
                image: CachedNetworkImageProvider(AppConfig.absoluteUrl(url!)),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: url == null
          ? Text(
              name.isEmpty ? '' : name.characters.first,
              style: const TextStyle(
                color: Brand.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
    );
  }
}

/// ورقة إضافة عضو: بحث بالاسم أو البريد الكامل، ثم «أضف».
///
/// ويدجت ذات حالة تملك المتحكّم — نفس سبب _PromptDialog في العرش.
class _AddMemberSheet extends StatefulWidget {
  final String groupId;
  final Set<String> existing;
  const _AddMemberSheet({required this.groupId, required this.existing});

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final _query = TextEditingController();
  List<PlayerSummary>? _results;
  String? _error;
  bool _searching = false;
  String? _addingId;
  final _added = <String>{};

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.length < 2) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await context.read<ApiClient>().searchPlayers(q);
      if (mounted) setState(() => _results = results);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _add(PlayerSummary p) async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _addingId = p.id);
    try {
      await api.addGroupMember(widget.groupId, p.id);
      if (mounted) setState(() => _added.add(p.id));
      messenger.showSnackBar(SnackBar(content: Text('أُضيف ${p.displayName}')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _addingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final results = _results;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'أضف عضواً',
                style: TextStyle(
                  fontFamily: Brand.displayFont,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Brand.text,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'بالاسم، أو بالبريد كاملاً.',
                style: TextStyle(color: Brand.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: 'اسم أو بريد',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Brand.crown),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.arrow_forward, size: 20),
                          onPressed: _search,
                        ),
                ),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Text(_error!,
                    style: const TextStyle(color: Brand.wrong, fontSize: 12))
              else if (results != null && results.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('لا أحد بهذا الاسم',
                      style: TextStyle(color: Brand.textMuted)),
                )
              else if (results != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final p = results[i];
                      final inGroup =
                          widget.existing.contains(p.id) || _added.contains(p.id);
                      return Row(
                        children: [
                          _SmallAvatar(url: p.avatarUrl, name: p.displayName),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              p.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Brand.text, fontSize: 13),
                            ),
                          ),
                          if (inGroup)
                            const BrandChip(label: 'عضو', icon: Icons.check)
                          else
                            SizedBox(
                              height: 32,
                              child: FilledButton(
                                onPressed:
                                    _addingId == p.id ? null : () => _add(p),
                                // minimumSize صفر: ثيم التطبيق يمدّ الأزرار
                                // بعرض الشاشة، وداخل Row ذلك عرض لانهائي.
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 32),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14),
                                ),
                                child: const Text('أضف'),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  // true = أُضيف أحد، فتعيد الشاشة الجلب.
                  onPressed: () => Navigator.pop(context, _added.isNotEmpty),
                  child: const Text('تم'),
                ),
              ),
            ],
          ),
        ),
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

  /// دوري المجلس: المنتقي يعرض مبارياته وحدها. null = الكل.
  final int? leagueId;

  const _RoundPredictions({required this.groupId, this.leagueId});

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
    final leagueId = widget.leagueId;
    try {
      final today = DateTime.now();
      final results = await Future.wait([
        api.upcomingFixtures(leagueIds: leagueId == null ? null : [leagueId]),
        for (var d = _pastDays; d >= 0; d--)
          api.fixturesByDate(today.subtract(Duration(days: d))),
      ]);

      // إزالة التكرار بالمعرّف: مباراة اليوم تظهر في "القادمة" وفي
      // يوم اليوم معاً. ومباريات الأيام تُصفّى بالدوري هنا لأن
      // مسار اليوم لا يقبل مرشّح دوري.
      final byId = <int, Fixture>{};
      for (final list in results) {
        for (final f in list) {
          if (leagueId != null && f.leagueId != leagueId) continue;
          byId[f.id] = f;
        }
      }
      // الترتيب: القادمة تصاعدياً ثم ما مضى تنازلياً — أي "الأقرب
      // زمنياً أولاً" في الاتجاهين. هكذا يكون العنصر الأول هو
      // المختار افتراضياً، فيراه المستخدم فور فتح القسم بلا تمرير.
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
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Center(child: CircularProgressIndicator(color: Brand.crown)),
      );
    }
    if (fixtures.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 30),
        child: Text(
          'لا مباريات قريبة في هذا الدوري',
          textAlign: TextAlign.center,
          style: TextStyle(color: Brand.textMuted),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
