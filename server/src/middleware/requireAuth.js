// requireAuth — حارس المسارات المحمية.
//
// الـ middleware في Express: دالة تعمل قبل معالج المسار. هذه تقرأ
// ترويسة Authorization، تتحقق من الـ JWT، وتضع هوية المستخدم في
// req.userId ليجدها المعالج جاهزة. لو فشل التحقق توقف الطلب بـ 401
// ولا يصل المعالج أصلاً.
//
// الاستخدام: router.get('/me', requireAuth, handler)
const jwt = require('jsonwebtoken');
const userRepo = require('../repositories/userRepo');

async function requireAuth(req, res, next) {
  // الشكل القياسي: Authorization: Bearer <token>
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');

  if (scheme !== 'Bearer' || !token) {
    return res.status(401).json({ error: 'Authorization header مفقود' });
  }

  let payload;
  try {
    // jwt.verify تتحقق من التوقيع ومن انتهاء الصلاحية معاً،
    // وترمي خطأ لو فشل أي منهما.
    payload = jwt.verify(token, process.env.JWT_SECRET);
  } catch (err) {
    // نميز انتهاء الصلاحية برسالة خاصة: تطبيق iOS يعتمد عليها
    // ليعرف أن الحل هو التجديد عبر /refresh وليس إعادة تسجيل الدخول.
    const message = err.name === 'TokenExpiredError'
      ? 'انتهت صلاحية التوكن'
      : 'توكن غير صالح';
    return res.status(401).json({ error: message, code: err.name });
  }

  // ── فحص الإيقاف: استعلام واحد على كل طلب محمي ──────────────────
  //
  // ثمنه صريح ونعرفه: هذا الحارس كان تحققاً رياضياً بحتاً من توقيع
  // بلا أي لمسة للقاعدة، والآن صار كل طلب محمي يحمل ذهاباً وإياباً
  // إلى PostgreSQL ويستهلك اتصالاً من الـ Pool (عشرة فقط).
  //
  // ولماذا قبلنا الثمن؟ البديل الوحيد المجاني هو الاكتفاء بفحص
  // الإيقاف عند الدخول والتجديد — وحينها يبقى الموقوف يستعمل التطبيق
  // بتوكنه الحالي حتى ١٥ دقيقة (عمر توكن الوصول). إيقاف يبدأ مفعوله
  // بعد ربع ساعة ليس إيقافاً: الحالة التي نوقف فيها حساباً أصلاً هي
  // حالة عاجلة (إساءة، اختراق) وربع الساعة فيها دهر. هذا نفس منطق
  // requireAdmin: استعلام لأجل إبطال فوري بدل صلاحية عالقة في توكن.
  //
  // والاستعلام ليس مسحاً للجدول: بحث بالمفتاح الأساسي (UUID مفهرس)
  // يرجع عمودين — نفس ترتيب كلفة requireAdmin الذي يعمل منذ البداية.
  //
  // التحسين الواضح لاحقاً — حين تصير هذه القراءة مؤلمة فعلاً — هو
  // تخزين مجموعة المعرّفات الموقوفة في Redis (المجموعة صغيرة جداً:
  // حفنة صفوف مقابل كل المستخدمين) وتحديثها عند كل إيقاف ورفع، لا
  // إسقاط الفحص. أي حل يعيدنا إلى "الإيقاف يبدأ بعد ١٥ دقيقة" هو
  // تراجع عن المتطلّب نفسه لا تحسين له.
  const status = await userRepo.findSuspension(payload.sub);

  // الحساب اختفى بينما توكنه ما زال حياً (حذفه الأدمن للتو).
  // 401 هنا وليس 403: لا هوية أصلاً، والتطبيق يجب أن يمسح جلسته.
  if (!status) {
    return res.status(401).json({ error: 'الحساب لم يعد موجوداً', code: 'ACCOUNT_NOT_FOUND' });
  }

  if (status.suspended_at) {
    // 403 وليس 401: التوكن سليم تماماً ولا فائدة من تجديده — لو
    // رددنا 401 لدار تطبيق iOS في حلقة /refresh لا تنتهي. و code
    // مستقل حتى يميز العميل "حسابك موقوف" (اعرض السبب وسجّل الخروج)
    // عن "انتهت صلاحية التوكن" (جدّد بصمت).
    return res.status(403).json({
      error: status.suspended_reason
        ? `تم إيقاف حسابك: ${status.suspended_reason}`
        : 'تم إيقاف حسابك، تواصل مع الإدارة',
      code: 'ACCOUNT_SUSPENDED',
    });
  }

  req.userId = payload.sub;
  next(); // مرّر الطلب للمعالج التالي
}

module.exports = requireAuth;
