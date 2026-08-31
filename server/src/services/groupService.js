// groupService — قواعد المجالس (الدوريات الخاصة)، في مكان واحد.
//
// كانت هذه القواعد داخل routes/groups مباشرة، وذلك كافٍ ما دام
// للمجالس باب واحد. ثم صار للموقع باب ثانٍ — ونسخ القواعد في
// الملفين يعني أن أول تعديل عليها (رفع سقف الأعضاء، أو منع
// المالك من المغادرة) يجب تذكّره مرتين، وأن نسيانه يفتح ثغرة في
// الباب المنسي لا خطأً ظاهراً.
//
// نفس العلاج الذي طُبِّق على التوقّع في predictionService.
const crypto = require('node:crypto');
const groupRepo = require('../repositories/groupRepo');

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

async function create({ ownerId, name }) {
  const clean = String(name || '').trim();
  if (clean.length < 2 || clean.length > 50) {
    throw new GroupError(400, 'اسم المجلس يجب أن يكون بين حرفين و50 حرفاً');
  }
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
      });
    } catch (err) {
      // 23505 = رمز PostgreSQL الثابت لانتهاك قيد UNIQUE
      if (err.code !== '23505') throw err;
    }
  }
  throw new GroupError(503, 'تعذّر توليد رمز دعوة — حاول مرة أخرى');
}

async function join({ userId, code }) {
  const group = await groupRepo.findByCode(normalizeCode(code));
  if (!group) throw new GroupError(404, 'رمز الدعوة غير صحيح');

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
  const group = await groupRepo.findById(groupId).catch(() => null);
  if (!group) throw new GroupError(404, 'المجلس غير موجود');
  if (group.owner_id !== userId) {
    throw new GroupError(403, 'حذف المجلس لمالكه فقط');
  }
  await groupRepo.remove(group.id);
  return group;
}

/**
 * عرض المجلس لعضوه.
 *
 * 404 لغير العضو لا 403: المجالس خاصة، ووجود المجلس نفسه معلومة
 * لا نؤكّدها لمن يجرّب المعرّفات.
 */
async function view({ userId, groupId }) {
  if (!(await groupRepo.isMember(groupId, userId).catch(() => false))) {
    throw new GroupError(404, 'المجلس غير موجود');
  }
  const [group, members] = await Promise.all([
    groupRepo.findById(groupId),
    groupRepo.leaderboard(groupId),
  ]);
  return { group, members };
}

module.exports = {
  create, join, leave, remove, view,
  normalizeCode, generateCode,
  GroupError, MAX_GROUPS_OWNED, MAX_MEMBERS,
};
