// المجلس — منافسة خاصة بين أصدقاء، بنفس قواعد العرش لكن بين أعضائه.
//
// التسمية من الهوية لا من التقنية: العرش عام والمجلس يجتمع حوله،
// والسيرفر يسميها groups لأن الاسم هناك بنية بيانات لا كلمة يقرؤها
// مستخدم. حدّ الترجمة هنا في نماذج العميل، وهو المكان الصحيح.
import 'leaderboard_entry.dart';

class Group {
  final String id;
  final String name;

  /// رمز الدعوة — ستة أحرف بلا حروف ملتبسة (لا O ولا 0 ولا I)، لأنه
  /// يُملى صوتياً ويُلصق في واتساب.
  final String? inviteCode;
  final bool isOwner;
  final int membersCount;

  const Group({
    required this.id,
    required this.name,
    this.inviteCode,
    this.isOwner = false,
    this.membersCount = 0,
  });

  factory Group.fromJson(Map<String, dynamic> j) => Group(
        id: j['id'].toString(),
        name: (j['name'] ?? '') as String,
        inviteCode: j['invite_code'] as String?,
        isOwner: j['is_owner'] == true,
        membersCount: (j['members_count'] as num?)?.toInt() ?? 0,
      );
}

/// تفاصيل مجلس واحد: بياناته وترتيب أعضائه.
///
/// صفوف الترتيب بنفس شكل صفوف العرش تماماً — نفس النموذج ونفس
/// الويدجت. لو اختلفا يوماً في الشكل اختلفا في الحساب أيضاً، وهذا
/// ما لا يجوز: المستخدم يقارن رقمه هنا برقمه هناك.
class GroupDetail {
  final Group group;
  final List<LeaderboardEntry> leaderboard;

  const GroupDetail({required this.group, required this.leaderboard});

  factory GroupDetail.fromJson(Map<String, dynamic> j) => GroupDetail(
        group: Group.fromJson(j['group'] as Map<String, dynamic>),
        leaderboard: (j['leaderboard'] as List? ?? [])
            .map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
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
