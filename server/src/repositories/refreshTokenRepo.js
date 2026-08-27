// refreshTokenRepo — جلسات التجديد.
//
// التوكن الخام لا يصل هذا الملف أصلاً: authService يحسب sha256
// ويمرر الـ hash فقط. القاعدة لا ترى التوكنات الحقيقية أبداً.
const db = require('../config/db');

async function create({ userId, tokenHash, expiresAt }) {
  await db.query(
    `INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
     VALUES ($1, $2, $3)`,
    [userId, tokenHash, expiresAt]
  );
}

// جلسة صالحة = موجودة + غير مُبطلة + لم تنتهِ صلاحيتها.
// الشروط الثلاثة في الاستعلام نفسه أبسط وأأمن من فحصها في الكود.
async function findValid(tokenHash) {
  const { rows } = await db.query(
    `SELECT id, user_id FROM refresh_tokens
     WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > now()`,
    [tokenHash]
  );
  return rows[0] ?? null;
}

async function revoke(id) {
  await db.query(
    `UPDATE refresh_tokens SET revoked_at = now() WHERE id = $1`,
    [id]
  );
}

// إبطال كل جلسات المستخدم — تُستدعى عند تغيير/استعادة كلمة السر:
// من غيّر كلمة سره يريد غالباً طرد أي شخص آخر يمسك حسابه.
async function revokeAllForUser(userId) {
  await db.query(
    `UPDATE refresh_tokens SET revoked_at = now()
     WHERE user_id = $1 AND revoked_at IS NULL`,
    [userId]
  );
}

module.exports = { create, findValid, revoke, revokeAllForUser };
