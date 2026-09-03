// groupService — قواعد المجالس (الدوريات الخاصة والعامة)، في مكان واحد.
//
// كانت هذه القواعد داخل routes/groups مباشرة، وذلك كافٍ ما دام
// للمجالس باب واحد. ثم صار للموقع باب ثانٍ — ونسخ القواعد في
// الملفين يعني أن أول تعديل عليها (رفع سقف الأعضاء، أو منع
// المالك من المغادرة) يجب تذكّره مرتين، وأن نسيانه يفتح ثغرة في
// الباب المنسي لا خطأً ظاهراً.
//
// نفس العلاج الذي طُبِّق على التوقّع في predictionService.
//
// الأدوار الثلاثة وحدودها (المرجع الوحيد — الواجهات تعكسه ولا
// تزيد عليه):
// - المالك: كل شيء — الإعدادات، الحذف، تعيين المشرفين وعزلهم،
//   إضافة أي عضو وإزالته. لا يغادر؛ خياره الحذف.
// - المشرف: يضيف الأعضاء ويزيل الأعضاء العاديين. لا يمسّ المالك
//   ولا مشرفاً آخر ولا الإعدادات — مساعد لا شريك في الملكية.
// - العضو: يشارك ويغادر.
const crypto = require('node:crypto');
const groupRepo = require('../repositories/groupRepo');
const userRepo = require('../repositories/userRepo');
const leagueRepo = require('../repositories/leagueRepo');
const pushService = require('./pushService');
const logger = require('../utils/logger');
const { deleteAvatarFile } = require('../utils/avatarFile');

/**
 * رابط الدعوة الكامل — يُبنى هنا لا في العميل: النطاق يعرفه السيرفر
 * (SITE_URL)، والتطبيق الذي يركّبه بنفسه يكسر أول تغيير نطاق.
 * وهو الرابط نفسه الذي يفتح التطبيق (Universal Link) أو الموقع.
 */
function inviteUrl(code) {
  const base = (process.env.SITE_URL || '').replace(/\/+$/, '');
  return base ? `${base}/join/${code}` : null;
}

/** المجلس كما يخرج للعميل: مع رابط دعوته. */
function decorate(group) {
  if (!group) return group;
  return { ...group, invite_url: group.invite_code ? inviteUrl(group.invite_code) : null };
}

// سياسة الانضمام (الهجرة 025): code = بالرمز وحده، open = يظهر
// ويُدخَل مباشرة، approval = يظهر ويُطلب الانضمام فيوافق المدير.
const JOIN_POLICIES = ['code', 'open', 'approval'];

/** خطأ متوقّع برمز HTTP ورسالة صالحة للعرض — نفس عقد AuthError. */
class GroupError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
    this.expose = true;
  }
}

// حدود منطقية تمنع العبث (حسابات تنشئ آلاف المجالس).
const MAX_GROUPS_OWNED = 10;
const MAX_MEMBERS = 100;

// رمز الدعوة: 6 أحرف من أبجدية بلا حروف ملتبسة (لا O/0 ولا I/1/L)
// — الرمز يُملى شفهياً ويُنسخ من واتساب، والالتباس عدو التجربة.
// 31^6 ≈ 887 مليون احتمال: التصادم نادر (نعيد المحاولة لو حدث)
// والتخمين العشوائي غير عملي.
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

function generateCode() {
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += CODE_ALPHABET[crypto.randomInt(CODE_ALPHABET.length)];
  }
  return code;
}

/** تطبيع رمز وصل من مستخدم: مسافات وحروف صغيرة لا تُفشل الانضمام. */
const normalizeCode = (raw) => String(raw || '').trim().toUpperCase();

/** فحص شكل UUID قبل السؤال: معرّف مشوّه يجعل pg يرمي خطأ نوع لا صفراً. */
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isUuid = (v) => UUID_RE.test(String(v || ''));

function cleanName(name) {
  const clean = String(name || '').trim();
  if (clean.length < 2 || clean.length > 50) {
    throw new GroupError(400, 'اسم المجلس يجب أن يكون بين حرفين و50 حرفاً');
  }
  return clean;
}

/**
 * دوري المجلس: null = كل الدوريات، وإلا دوري داخل اللعبة (in_app).
 *
 * الدوري المفعّل على الموقع فقط لا يصلح: مبارياته لا تُعرض في
 * التطبيق أصلاً، فمجلسٌ عليه لا يجد أعضاؤه ما يتوقّعونه.
 */
async function cleanLeague(leagueId) {
  if (leagueId === null || leagueId === undefined || leagueId === '') return null;
  const id = Number(leagueId);
  if (!Number.isInteger(id)) throw new GroupError(400, 'الدوري غير صالح');
  const league = await leagueRepo.findById(id);
  if (!league || !league.in_app) throw new GroupError(400, 'الدوري غير متاح في اللعبة');
  return id;
}

function cleanPolicy(raw) {
  if (raw === undefined || raw === null) return 'code';
  if (!JOIN_POLICIES.includes(raw)) throw new GroupError(400, 'سياسة الانضمام غير معروفة');
  return raw;
}

/**
 * إشعار مجلس — لا يرمي أبداً ولا يُنتظر: الإشعار تابعٌ للفعل، وفشل
 * التسليم (جهاز ميت، مزوّد متعطّل) يجب ألا يفشل الطلب ولا يبطئه.
 * data.type = 'group' والتطبيق يفتح شاشة المجلس منه.
 */
function notify(userIds, groupId, title, body) {
  for (const userId of userIds) {
    pushService.sendToUser(userId, { title, body, data: { type: 'group', groupId } })
      .catch((err) => logger.error(`[groups] إشعار لم يُرسل: ${err.message}`));
  }
}

async function displayName(userId) {
  const user = await userRepo.findById(userId).catch(() => null);
  return user?.display_name || 'مشجع';
}

async function create({ ownerId, name, isPublic, joinPolicy, leagueId = null }) {
  const clean = cleanName(name);
  const league = await cleanLeague(leagueId);
  // is_public من نسخة 024 من التطبيق يُترجم: عام = مفتوح.
  const policy = cleanPolicy(joinPolicy ?? (isPublic === true ? 'open' : undefined));
  if (await groupRepo.countOwnedBy(ownerId) >= MAX_GROUPS_OWNED) {
    throw new GroupError(400, `الحد الأقصى ${MAX_GROUPS_OWNED} مجالس لكل حساب`);
  }

  // حلقة التصادم: لو صادف الرمز المولّد رمزاً موجوداً (قيد UNIQUE
  // يرفضه) نولّد غيره. خمس محاولات أكثر من كافية إحصائياً.
  for (let attempt = 0; attempt < 5; attempt += 1) {
    try {
      return await groupRepo.create({
        name: clean,
        inviteCode: generateCode(),
        ownerId,
        joinPolicy: policy,
        leagueId: league,
      });
    } catch (err) {
      // 23505 = رمز PostgreSQL الثابت لانتهاك قيد UNIQUE
      if (err.code !== '23505') throw err;
    }
  }
  throw new GroupError(503, 'تعذّر توليد رمز دعوة — حاول مرة أخرى');
}

/**
 * صورة المجلس — للمالك وحده. imageUrl فارغ = إزالة.
 *
 * القديمة تُحذف بعد نجاح حفظ الجديدة، بالترتيب المعاكس قد يبقى
 * المجلس بلا صورة لو فشلت الخطوة الثانية (نفس قرار الصورة الشخصية).
 */
async function setImage({ userId, groupId, imageUrl }) {
  const group = await requireGroup(groupId);
  if (group.owner_id !== userId) throw new GroupError(403, 'صورة المجلس لمالكه فقط');
  const updated = await groupRepo.update(group.id, { imageUrl: imageUrl || null });
  if (group.image_url && group.image_url !== imageUrl) await deleteAvatarFile(group.image_url);
  return updated;
}

/**
 * معاينة دعوة برمزها — ما يراه من فتح الرابط قبل أن ينضم: الاسم
 * والصورة والدوري والعدد. بلا الأعضاء ولا الترتيب: الرمز دعوة إلى
 * مجلس لا نافذة عليه.
 */
async function invitePreview({ code, userId = null }) {
  const group = await groupRepo.findByCode(normalizeCode(code));
  if (!group) throw new GroupError(404, 'رمز الدعوة غير صحيح');
  const role = userId ? await groupRepo.memberRole(group.id, userId) : null;
  return {
    group: {
      id: group.id,
      name: group.name,
      image_url: group.image_url,
      league_id: group.league_id,
      league_name: group.league_name,
      league_logo: group.league_logo,
      join_policy: group.join_policy,
      members_count: group.members_count,
      invite_code: group.invite_code,
      invite_url: inviteUrl(group.invite_code),
    },
    viewer_role: role,
  };
}

/** تعديل الاسم أو العلنية أو الدوري — للمالك وحده. */
async function update({ userId, groupId, name, isPublic, joinPolicy, leagueId }) {
  const group = await requireGroup(groupId);
  if (group.owner_id !== userId) throw new GroupError(403, 'إعدادات المجلس لمالكه فقط');

  const changes = {};
  if (name !== undefined) changes.name = cleanName(name);
  if (joinPolicy !== undefined) changes.joinPolicy = cleanPolicy(joinPolicy);
  else if (isPublic !== undefined) changes.joinPolicy = isPublic ? 'open' : 'code';
  if (leagueId !== undefined) changes.leagueId = await cleanLeague(leagueId);
  return groupRepo.update(group.id, changes);
}

async function join({ userId, code }) {
  const group = await groupRepo.findByCode(normalizeCode(code));
  if (!group) throw new GroupError(404, 'رمز الدعوة غير صحيح');
  return enroll(group, userId);
}

/**
 * الانضمام إلى مجلس بمعرّفه — من الاستكشاف أو من رابط.
 *
 * حسب سياسته: المفتوح يُدخل فوراً، وبالموافقة يُسجَّل طلباً ويُخطَر
 * المديرون، وبالرمز لا يُدخَل بمعرّفه ولو عُرف: الرمز هو الباب،
 * والمعرّف يظهر في روابط كثيرة (توقعات، ترتيب) ولا يُعدّ سراً.
 *
 * يرجع { group, already, requested }: requested = طلبٌ سُجّل الآن أو
 * كان معلّقاً، فالمتصل يعرض «بانتظار الموافقة» لا «انضممت».
 */
async function joinPublic({ userId, groupId }) {
  const group = await requireGroup(groupId);
  if (group.join_policy === 'code') throw new GroupError(404, 'المجلس غير موجود');
  if (await groupRepo.isMember(group.id, userId)) {
    return { group, already: true, requested: false };
  }
  if (group.join_policy === 'open') return { ...(await enroll(group, userId)), requested: false };

  // بالموافقة: الطلب المكرر ليس خطأً — من ضغط مرتين ينتظر مرتين.
  if (await groupRepo.hasRequest(group.id, userId)) {
    return { group, already: false, requested: true };
  }
  if (await groupRepo.memberCount(group.id) >= MAX_MEMBERS) {
    throw new GroupError(409, 'المجلس ممتلئ');
  }
  await groupRepo.addRequest(group.id, userId);
  const name = await displayName(userId);
  notify(await groupRepo.managerIds(group.id), group.id,
    group.name, `${name} يطلب الانضمام إلى المجلس`);
  return { group, already: false, requested: true };
}

/** قبول طلب — للمالك والمشرف. */
async function approveRequest({ actorId, groupId, userId }) {
  const group = await requireGroup(groupId);
  const actorRole = await groupRepo.memberRole(group.id, actorId);
  if (actorRole !== 'owner' && actorRole !== 'moderator') {
    throw new GroupError(403, 'قبول الطلبات للمالك والمشرفين');
  }
  if (!(await groupRepo.hasRequest(group.id, userId))) {
    throw new GroupError(404, 'لا طلب معلّقاً لهذا المستخدم');
  }
  if (await groupRepo.memberCount(group.id) >= MAX_MEMBERS) {
    throw new GroupError(409, 'المجلس ممتلئ');
  }
  await groupRepo.acceptRequest(group.id, userId);
  notify([userId], group.id, group.name, 'قُبل طلبك — أنت الآن عضو في المجلس');
  return group;
}

/**
 * سحب طلب: المدير يرفضه، أو صاحبه يلغيه. الرفض صامت — لا إشعار:
 * «رُفض طلبك» رسالة تجرح ولا تُفيد، والطالب يرى ببساطة أن زر
 * الطلب عاد.
 */
async function withdrawRequest({ actorId, groupId, userId }) {
  const group = await requireGroup(groupId);
  if (userId !== actorId) {
    const actorRole = await groupRepo.memberRole(group.id, actorId);
    if (actorRole !== 'owner' && actorRole !== 'moderator') {
      throw new GroupError(403, 'رفض الطلبات للمالك والمشرفين');
    }
  }
  if (!(await groupRepo.removeRequest(group.id, userId))) {
    throw new GroupError(404, 'لا طلب معلّقاً');
  }
  return group;
}

/** الخطوة المشتركة بين الانضمام بالرمز والانضمام العلني. */
async function enroll(group, userId) {
  // العضو القائم لا يُعدّ خطأً في الويب: من ضغط رابط الدعوة مرتين
  // يريد الوصول إلى المجلس، لا رسالة تصفه بالمخطئ. نرجعه ومعه
  // already ليقرّر المستدعي كيف يعرضها.
  if (await groupRepo.isMember(group.id, userId)) {
    return { group, already: true };
  }
  if (await groupRepo.memberCount(group.id) >= MAX_MEMBERS) {
    throw new GroupError(409, 'المجلس ممتلئ');
  }
  await groupRepo.addMember(group.id, userId);
  return { group, already: false };
}

/**
 * إضافة عضو بمعرّفه — للمالك والمشرف.
 *
 * الإضافة بلا موافقة المُضاف قرار مقصود للنسخة الأولى: المجلس بين
 * معارف، والمُضاف يستطيع المغادرة بضغطة. طلبات الانضمام المعلّقة
 * تحتاج جدولاً وإشعاراً وشاشةً — تُبنى حين يطلبها أحد.
 */
async function addMember({ actorId, groupId, userId }) {
  const group = await requireGroup(groupId);
  const actorRole = await groupRepo.memberRole(group.id, actorId);
  if (actorRole !== 'owner' && actorRole !== 'moderator') {
    throw new GroupError(403, 'إضافة الأعضاء للمالك والمشرفين');
  }
  if (!isUuid(userId)) throw new GroupError(400, 'المستخدم غير صالح');
  const target = await userRepo.findById(userId);
  if (!target) throw new GroupError(404, 'المستخدم غير موجود');
  if (await groupRepo.isMember(group.id, userId)) {
    throw new GroupError(409, 'هذا المستخدم عضو بالفعل');
  }
  if (await groupRepo.memberCount(group.id) >= MAX_MEMBERS) {
    throw new GroupError(409, 'المجلس ممتلئ');
  }
  // إضافة من له طلب معلّق تُغلق طلبه — القبول والإضافة شيء واحد.
  await groupRepo.removeRequest(group.id, userId);
  await groupRepo.addMember(group.id, userId);
  notify([userId], group.id, group.name, `أضافك ${await displayName(actorId)} إلى المجلس`);
  return group;
}

/**
 * إزالة عضو.
 *
 * سلّم الصلاحية صريح لا ضمني: المالك يزيل الجميع عدا نفسه (له
 * الحذف)، والمشرف يزيل الأعضاء العاديين وحدهم — إزالة مشرف لمشرف
 * تجعل أول خلاف بينهما سباقاً على الضغطة الأسرع.
 */
async function removeMember({ actorId, groupId, userId }) {
  const group = await requireGroup(groupId);
  const actorRole = await groupRepo.memberRole(group.id, actorId);
  if (actorRole !== 'owner' && actorRole !== 'moderator') {
    throw new GroupError(403, 'إزالة الأعضاء للمالك والمشرفين');
  }
  if (userId === actorId) throw new GroupError(400, 'لإزالة نفسك استعمل «مغادرة المجلس»');

  const targetRole = await groupRepo.memberRole(group.id, userId);
  if (!targetRole) throw new GroupError(404, 'ليس عضواً في المجلس');
  if (targetRole === 'owner') throw new GroupError(403, 'لا يُزال مالك المجلس');
  if (targetRole === 'moderator' && actorRole !== 'owner') {
    throw new GroupError(403, 'عزل المشرف للمالك فقط');
  }
  await groupRepo.removeMember(group.id, userId);
  return group;
}

/** تعيين مشرف أو عزله — للمالك وحده. */
async function setRole({ actorId, groupId, userId, role }) {
  if (role !== 'moderator' && role !== 'member') {
    throw new GroupError(400, 'الدور غير معروف');
  }
  const group = await requireGroup(groupId);
  if (group.owner_id !== actorId) throw new GroupError(403, 'تعيين المشرفين للمالك فقط');
  const targetRole = await groupRepo.memberRole(group.id, userId);
  if (!targetRole) throw new GroupError(404, 'ليس عضواً في المجلس');
  if (targetRole === 'owner') throw new GroupError(400, 'المالك فوق الأدوار كلها');
  await groupRepo.setRole(group.id, userId, role);
  return group;
}

async function leave({ userId, groupId }) {
  const group = await groupRepo.findById(groupId).catch(() => null);
  if (!group || !(await groupRepo.isMember(groupId, userId))) {
    throw new GroupError(404, 'المجلس غير موجود');
  }
  // المالك لا يغادر: مجلس بلا مالك لا أحد يستطيع حذفه أو إدارته.
  // خياره هو الحذف الكامل.
  if (group.owner_id === userId) {
    throw new GroupError(400, 'مالك المجلس لا يغادره — يستطيع حذفه');
  }
  await groupRepo.removeMember(groupId, userId);
  return group;
}

async function remove({ userId, groupId }) {
  const group = await requireGroup(groupId);
  if (group.owner_id !== userId) {
    throw new GroupError(403, 'حذف المجلس لمالكه فقط');
  }
  await groupRepo.remove(group.id);
  return group;
}

/**
 * ترتيب الأعضاء بنطاق: الموسم أو الجولة الأخيرة.
 *
 * فضّ التعادل بالأقدمية (من انضمّ أولاً يعلو) — مكتوب هنا مرة واحدة
 * ويُطبَّق ثلاث مرات: للنطاق المطلوب، وللموسم «قبل الجولة الأخيرة»
 * كي نشتقّ حركة المراكز. الحركة تُحسب لا تُخزَّن: لقطة ترتيب بعد كل
 * جولة تحتاج وظيفة مجدولة وجدولاً وحالة يمكن أن تفوت جولة؛ أما
 * «الموسم ناقص آخر جولة» فحقيقة تُستنتج من البيانات نفسها في أي
 * لحظة. الثمن أن السهم يعني «منذ آخر جولة محتسبة» لا «منذ آخر مرة
 * فتحت الشاشة» — وهو المعنى الأوضح للمستخدم أصلاً.
 */
function rankMembers(rows, scope) {
  const points = (r) => (scope === 'round' ? r.round_points : r.season_points);
  const settled = (r) => (scope === 'round' ? r.round_settled : r.season_settled);
  const hits = (r) => (scope === 'round' ? r.round_hits : r.season_hits);
  const byPoints = (get) => (a, b) =>
    get(b) - get(a) || new Date(a.joined_at) - new Date(b.joined_at);

  const ordered = [...rows].sort(byPoints(points));
  // المراكز قبل الجولة الأخيرة: موسم ناقص جولة. لا معنى لها في نطاق
  // الجولة نفسه فتبقى null هناك.
  const before = [...rows].sort(byPoints((r) => r.season_points - r.round_points));
  const rankBefore = new Map(before.map((r, i) => [r.user_id, i + 1]));

  return ordered.map((r, i) => ({
    user_id: r.user_id,
    display_name: r.display_name,
    avatar_url: r.avatar_url,
    favorite_team_id: r.favorite_team_id,
    favorite_team_logo: r.favorite_team_logo,
    role: r.role,
    joined_at: r.joined_at,
    rank: i + 1,
    total_points: points(r),
    settled_predictions: settled(r),
    accuracy: settled(r) ? Math.round((100 * hits(r)) / settled(r)) : null,
    season_points: r.season_points,
    round_points: r.round_points,
    // موجب = صعد، سالب = هبط، صفر = ثابت. لا حركة لمن لم يُحتسب له
    // شيء في الجولة الأخيرة ولا قبلها — سهمٌ لعضو جديد كذبة.
    movement: scope === 'round' || (r.round_settled === 0 && r.season_settled === 0)
      ? null
      : rankBefore.get(r.user_id) - (i + 1),
  }));
}

/**
 * عرض المجلس: بياناته وترتيبه وأعضاؤه ودور الطالب فيه.
 *
 * scope: 'season' (الافتراضي) أو 'round' — ترتيب الجولة الأخيرة وحدها.
 * الموسم يجمّد المراكز بعد شهرين ويقتل الحماس؛ الجولة تعطي كل أسبوع
 * منافسة جديدة بنفس الصفوف.
 *
 * الخاص لأعضائه: 404 لغيرهم لا 403، فوجود المجلس نفسه معلومة لا
 * نؤكّدها لمن يجرّب المعرّفات. والعام يراه الجميع — بلا ترتيب أو
 * أعضاء لا يقرّر أحد إن كان يريد الانضمام — لكن توقعات أعضائه على
 * مباراة تبقى للأعضاء (راجع مسار التوقعات).
 *
 * الترتيب بدوري المجلس: هذا ما يجعل «مجلس الدوري الإنجليزي» يرتّب
 * أعضاءه بنقاط الإنجليزي لا بمجموعهم في كل مكان.
 */
async function view({ userId, groupId, scope = 'season' }) {
  const group = await requireGroup(groupId);
  const viewerRole = await groupRepo.memberRole(group.id, userId);
  if (!viewerRole && group.join_policy === 'code') throw new GroupError(404, 'المجلس غير موجود');
  const chosen = scope === 'round' ? 'round' : 'season';

  const manages = viewerRole === 'owner' || viewerRole === 'moderator';
  const [rows, members, requests, viewerRequested] = await Promise.all([
    groupRepo.standings(group.id, group.league_id),
    groupRepo.members(group.id),
    // قائمة الطلبات لمن يبتّ فيها وحده؛ غيره لا يعرف من طلب.
    manages ? groupRepo.requests(group.id) : Promise.resolve([]),
    viewerRole ? Promise.resolve(false) : groupRepo.hasRequest(group.id, userId),
  ]);
  const leaderboard = rankMembers(rows, chosen);
  // اسم الجولة يُعرض حين تكون واحدة (مجلس بدوري)؛ ومجلس كل الدوريات
  // يجمع جولات مختلفة فلا اسم لها سوى «آخر جولة».
  const latest = rows[0]?.latest_rounds || [];
  const roundLabel = latest.length === 1 ? latest[0].round : null;
  return {
    group, leaderboard, members, requests, viewerRole, viewerRequested,
    scope: chosen, roundLabel, hasRound: latest.length > 0,
  };
}

/** المجالس العامة للاستكشاف. */
async function discover({ userId, search }) {
  const clean = String(search || '').trim().slice(0, 50);
  return groupRepo.findPublic({ search: clean, userId, limit: 50 });
}

/** المجلس أو 404 — المعرّف المشوّه «غير موجود» أيضاً لا خطأ 500. */
async function requireGroup(groupId) {
  if (!isUuid(groupId)) throw new GroupError(404, 'المجلس غير موجود');
  const group = await groupRepo.findById(groupId);
  if (!group) throw new GroupError(404, 'المجلس غير موجود');
  return group;
}

module.exports = {
  create, update, join, joinPublic, approveRequest, withdrawRequest,
  addMember, removeMember, setRole, setImage, invitePreview,
  leave, remove, view, discover, decorate, inviteUrl,
  normalizeCode, generateCode, isUuid,
  GroupError, MAX_GROUPS_OWNED, MAX_MEMBERS,
};
