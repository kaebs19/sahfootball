// المجلس — منافسة خاصة بين أصدقاء، بنفس قواعد العرش لكن بين أعضائه.
//
// التسمية من الهوية لا من التقنية: العرش عام والمجلس يجتمع حوله،
// والسيرفر يسميها groups لأن الاسم هناك بنية بيانات لا كلمة يقرؤها
// مستخدم. حدّ الترجمة هنا في نماذج العميل، وهو المكان الصحيح.
import 'leaderboard_entry.dart';

/// دور المستخدم في مجلس. [none] = يتصفّح مجلساً عاماً ولم ينضم.
///
/// السلّم مرجعه groupService في السيرفر — الواجهة تعكسه لتخفي ما لا
/// يجوز، والسيرفر هو من يرفض فعلاً.
enum GroupRole {
  owner('مالك'),
  moderator('مشرف'),
  member('عضو'),
  none('');

  final String label;
  const GroupRole(this.label);

  static GroupRole parse(Object? raw) => switch (raw) {
        'owner' => GroupRole.owner,
        'moderator' => GroupRole.moderator,
        'member' => GroupRole.member,
        _ => GroupRole.none,
      };

  bool get canManageMembers => this == owner || this == moderator;
  bool get isMember => this != none;
}

/// سياسة الانضمام — كيف يُدخَل المجلس (الهجرة 025).
enum JoinPolicy {
  /// بالرمز وحده؛ لا يظهر في الاستكشاف.
  code('بالرمز', 'لا يدخله إلا من معه رمز الدعوة.'),

  /// يظهر ويُدخَل مباشرة.
  open('مفتوح', 'يظهر في «المجالس العامة» وينضم إليه أي أحد فوراً.'),

  /// يظهر ويُطلب الانضمام، والمالك أو المشرف يوافق.
  approval('بموافقة', 'يظهر في «المجالس العامة» ويُطلب الانضمام، وأنت توافق.');

  final String label;
  final String hint;
  const JoinPolicy(this.label, this.hint);

  String get wire => name;

  static JoinPolicy parse(Object? raw) => switch (raw) {
        'open' => JoinPolicy.open,
        'approval' => JoinPolicy.approval,
        _ => JoinPolicy.code,
      };

  bool get isPublic => this != code;
}

class Group {
  final String id;
  final String name;

  /// رمز الدعوة — ستة أحرف بلا حروف ملتبسة (لا O ولا 0 ولا I)، لأنه
  /// يُملى صوتياً ويُلصق في واتساب.
  final String? inviteCode;

  /// رابط الدعوة الكامل — يبنيه السيرفر (هو من يعرف النطاق)، ويفتح
  /// التطبيق مباشرة على المثبّتين أو الموقع على غيرهم.
  final String? inviteUrl;
  final String? ownerId;

  /// صورة المجلس تحت /uploads/ — null = الحرف الأول أو شعار الدوري.
  final String? imageUrl;

  final JoinPolicy joinPolicy;

  /// لي طلب انضمام معلّق على هذا المجلس (من الاستكشاف).
  final bool hasRequest;

  /// طلبات معلّقة تنتظر البتّ — لشارة «طلبات (3)» عند المدير.
  final int pendingRequests;

  /// null = كل الدوريات. وإلا يُرتَّب الأعضاء بنقاط هذا الدوري وحده.
  final int? leagueId;
  final String? leagueName;
  final String? leagueLogo;

  final int membersCount;

  /// دوري أنا في هذا المجلس.
  final GroupRole role;

  const Group({
    required this.id,
    required this.name,
    this.inviteCode,
    this.inviteUrl,
    this.ownerId,
    this.imageUrl,
    this.joinPolicy = JoinPolicy.code,
    this.hasRequest = false,
    this.pendingRequests = 0,
    this.leagueId,
    this.leagueName,
    this.leagueLogo,
    this.membersCount = 0,
    this.role = GroupRole.none,
  });

  bool get isOwner => role == GroupRole.owner;
  bool get isMember => role.isMember;

  /// يظهر في الاستكشاف ويُدخَل بلا رمز (مباشرة أو بطلب).
  bool get isPublic => joinPolicy.isPublic;

  /// «كل الدوريات» أو اسم الدوري — ما يُقرأ تحت اسم المجلس.
  String get scopeLabel => leagueName ?? 'كل الدوريات';

  factory Group.fromJson(Map<String, dynamic> j) {
    // الدور يصل صريحاً من «مجالسي» والتفاصيل؛ ومن الاستكشاف يصل
    // is_member فقط (عضو أم لا) — ومن الإنشاء والانضمام لا يصل شيء،
    // فيُستنتج: من أنشأ فهو مالك، ومن انضمّ فهو عضو.
    var role = GroupRole.parse(j['role']);
    if (role == GroupRole.none) {
      if (j['is_owner'] == true) {
        role = GroupRole.owner;
      } else if (j['is_member'] == true) {
        role = GroupRole.member;
      }
    }
    return Group(
      id: j['id'].toString(),
      name: (j['name'] ?? '') as String,
      inviteCode: j['invite_code'] as String?,
      inviteUrl: j['invite_url'] as String?,
      ownerId: j['owner_id'] as String?,
      imageUrl: j['image_url'] as String?,
      joinPolicy: JoinPolicy.parse(j['join_policy']),
      hasRequest: j['has_request'] == true,
      pendingRequests: (j['pending_requests'] as num?)?.toInt() ?? 0,
      leagueId: (j['league_id'] as num?)?.toInt(),
      leagueName: j['league_name'] as String?,
      leagueLogo: j['league_logo'] as String?,
      membersCount: (j['members_count'] as num?)?.toInt() ?? 0,
      role: role,
    );
  }

  Group copyWith({GroupRole? role, int? membersCount, bool? hasRequest}) =>
      Group(
        id: id,
        name: name,
        inviteCode: inviteCode,
        inviteUrl: inviteUrl,
        ownerId: ownerId,
        imageUrl: imageUrl,
        joinPolicy: joinPolicy,
        hasRequest: hasRequest ?? this.hasRequest,
        pendingRequests: pendingRequests,
        leagueId: leagueId,
        leagueName: leagueName,
        leagueLogo: leagueLogo,
        membersCount: membersCount ?? this.membersCount,
        role: role ?? this.role,
      );
}

/// عضو في المجلس بدوره — لقائمة «من هنا ومن يدير؟».
class GroupMember {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final String? favoriteTeamLogo;
  final GroupRole role;
  final DateTime? joinedAt;

  const GroupMember({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.favoriteTeamLogo,
    required this.role,
    this.joinedAt,
  });

  factory GroupMember.fromJson(Map<String, dynamic> j) => GroupMember(
        userId: j['user_id'].toString(),
        displayName: (j['display_name'] ?? 'مشجع') as String,
        avatarUrl: j['avatar_url'] as String?,
        favoriteTeamLogo: j['favorite_team_logo'] as String?,
        role: GroupRole.parse(j['role']),
        joinedAt: j['joined_at'] != null
            ? DateTime.tryParse(j['joined_at'] as String)?.toLocal()
            : null,
      );
}

/// طلب انضمام معلّق — يراه المالك والمشرف فقط.
class JoinRequest {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final DateTime? requestedAt;

  const JoinRequest({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.requestedAt,
  });

  factory JoinRequest.fromJson(Map<String, dynamic> j) => JoinRequest(
        userId: j['user_id'].toString(),
        displayName: (j['display_name'] ?? 'مشجع') as String,
        avatarUrl: j['avatar_url'] as String?,
        requestedAt: j['requested_at'] != null
            ? DateTime.tryParse(j['requested_at'] as String)?.toLocal()
            : null,
      );
}

/// معاينة دعوة — ما يراه من فتح رابطاً قبل أن ينضم.
class InvitePreview {
  final Group group;
  final GroupRole viewerRole;
  const InvitePreview({required this.group, required this.viewerRole});

  factory InvitePreview.fromJson(Map<String, dynamic> j) {
    final role = GroupRole.parse(j['viewer_role']);
    return InvitePreview(
      group: Group.fromJson(j['group'] as Map<String, dynamic>).copyWith(role: role),
      viewerRole: role,
    );
  }
}

/// نتيجة «انضم» بمعرّف: إما عضوية فورية أو طلب معلّق حسب السياسة.
class JoinOutcome {
  final Group group;
  final bool requested;
  const JoinOutcome({required this.group, required this.requested});
}

/// تفاصيل مجلس واحد: بياناته وترتيب أعضائه وقائمتهم ودور الناظر.
///
/// صفوف الترتيب بنفس شكل صفوف العرش تماماً — نفس النموذج ونفس
/// الويدجت. لو اختلفا يوماً في الشكل اختلفا في الحساب أيضاً، وهذا
/// ما لا يجوز: المستخدم يقارن رقمه هنا برقمه هناك.
class GroupDetail {
  final Group group;
  final List<LeaderboardEntry> leaderboard;
  final List<GroupMember> members;
  final GroupRole viewerRole;

  /// الطلبات المعلّقة — فارغة لغير المدير.
  final List<JoinRequest> requests;

  /// الناظر ليس عضواً وله طلب معلّق.
  final bool viewerRequested;

  /// نطاق الترتيب المعروض: 'season' أو 'round'.
  final String scope;

  /// اسم الجولة الأخيرة كما يرسله المزود (لمجلس بدوري واحد)، أو null.
  final String? roundLabel;

  /// هل احتُسبت جولة أصلاً — بلا جولة لا معنى لمبدّل «هذه الجولة».
  final bool hasRound;

  const GroupDetail({
    required this.group,
    required this.leaderboard,
    required this.members,
    required this.viewerRole,
    this.requests = const [],
    this.viewerRequested = false,
    this.scope = 'season',
    this.roundLabel,
    this.hasRound = false,
  });

  factory GroupDetail.fromJson(Map<String, dynamic> j) {
    final viewerRole = GroupRole.parse(j['viewer_role']);
    return GroupDetail(
      // دور الناظر يُركَّب على المجلس نفسه: كل من يقرأ group.role
      // بعد ذلك (البطاقة، الخيارات) يجد الجواب الصحيح.
      group: Group.fromJson(j['group'] as Map<String, dynamic>)
          .copyWith(role: viewerRole, hasRequest: j['viewer_requested'] == true),
      leaderboard: (j['leaderboard'] as List? ?? [])
          .map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      members: (j['members'] as List? ?? [])
          .map((e) => GroupMember.fromJson(e as Map<String, dynamic>))
          .toList(),
      viewerRole: viewerRole,
      requests: (j['requests'] as List? ?? [])
          .map((e) => JoinRequest.fromJson(e as Map<String, dynamic>))
          .toList(),
      viewerRequested: j['viewer_requested'] == true,
      scope: (j['scope'] ?? 'season') as String,
      roundLabel: j['round_label'] as String?,
      hasRound: j['has_round'] == true,
    );
  }
}

/// توقع عضو على مباراة بعينها.
///
/// [predHome] فارغ يعني أحد أمرين لا ثالث لهما: إما أن العضو لم
/// يتوقع ([predicted] = false)، أو أنه توقع والباب ما زال مفتوحاً
/// فالسيرفر يخفي المحتوى ([revealed] = false في الرد). التمييز
/// بينهما هو ما يجعل عرض "8 من 10 توقعوا" ممكناً قبل الكشف.
class MemberPrediction {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final bool predicted;
  final int? predHome;
  final int? predAway;
  final int? points;

  const MemberPrediction({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.predicted,
    this.predHome,
    this.predAway,
    this.points,
  });

  factory MemberPrediction.fromJson(Map<String, dynamic> j) => MemberPrediction(
        userId: j['user_id'].toString(),
        displayName: (j['display_name'] ?? 'مشجع') as String,
        avatarUrl: j['avatar_url'] as String?,
        predicted: j['predicted'] == true,
        predHome: (j['pred_home'] as num?)?.toInt(),
        predAway: (j['pred_away'] as num?)?.toInt(),
        points: (j['points'] as num?)?.toInt(),
      );
}

/// رد شاشة "توقعات الجولة".
///
/// ثلاث حالات لا حالتان، ولكل واحدة رسالة مختلفة:
/// - [locked] = false: المباراة لم تنطلق، والتوقعات مخفية عن الجميع.
/// - [locked] = true و[viewerPredicted] = false: انطلقت، لكنك لم
///   تتوقّع — فلا ترى ما اختاره غيرك.
/// - [revealed] = true: انطلقت وقد توقّعت، فالكل مكشوف.
class GroupFixturePredictions {
  final bool revealed;
  final bool locked;
  final bool viewerPredicted;
  final List<MemberPrediction> predictions;

  const GroupFixturePredictions({
    required this.revealed,
    required this.locked,
    required this.viewerPredicted,
    required this.predictions,
  });

  factory GroupFixturePredictions.fromJson(Map<String, dynamic> j) =>
      GroupFixturePredictions(
        revealed: j['revealed'] == true,
        locked: j['locked'] == true,
        viewerPredicted: j['viewer_predicted'] == true,
        predictions: (j['predictions'] as List? ?? [])
            .map((e) => MemberPrediction.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
