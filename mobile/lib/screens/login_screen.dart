// شاشة الدخول — أول ظهور للعلامة، فتحمل الشعار والوعد.
//
// نمط معالجة الأخطاء الموحد في كل النماذج: الاستدعاء داخل try،
// ApiException رسالتها عربية جاهزة من السيرفر فتعرض كما هي تحت
// الزر — لا حوارات منبثقة تقطع السياق لخطأ متوقع كبيانات خاطئة.
//
// AutofillGroup + finishAutofillContext هما "حفظ الحساب" الحقيقي:
// النظام (iCloud Keychain / مدير كلمات جوجل) يعرض حفظ كلمة المرور
// بعد أول دخول ناجح ويملؤها تلقائياً بعدها — نحن لا نلمس الكلمة،
// ونحفظ نحن البريد فقط (تذكرني) لتفتح الشاشة شبه جاهزة.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../state/remembered_email.dart';
import '../state/session.dart';
import '../widgets/brand_mark.dart';
import '../widgets/goal_splash.dart';
import '../widgets/password_field.dart';
import '../widgets/social_auth_buttons.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _remember = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // بريد آخر دخول — يملأ الحقل فيبقى للمستخدم كلمة المرور فقط
    // (وغالباً يملؤها النظام من الـ Keychain فلا يبقى شيء).
    RememberedEmail.load().then((saved) {
      if (!mounted || saved == null || saved.isEmpty) return;
      if (_email.text.isEmpty) _email.text = saved;
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final email = _email.text.trim();
      await context.read<Session>().login(email, _password.text);
      // إخبار النظام أن الرحلة نجحت — هنا يعرض iOS حفظ كلمة
      // المرور في الـ Keychain. قبل النجاح لا بعده بشاشات، وإلا
      // حُفظت بيانات ربما كانت خاطئة.
      TextInput.finishAutofillContext();
      await RememberedEmail.save(_remember ? email : null);
      // لا تنقّل هنا: نجاح الدخول يغير حالة Session و_Root في main
      // يستبدل هذه الشاشة بالرئيسية وحده.
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // سبب انتهاء الجلسة (إيقاف الحساب مثلاً) يظهر مرة واحدة هنا.
    // بدونه يجد المستخدم نفسه في شاشة الدخول فجأة بلا تفسير،
    // فيعيد إدخال بياناته مراراً ظاناً أنه أخطأ.
    final reason = context.watch<Session>().endedReason;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // الملعب ساكناً خلف النموذج — «تثبت على شاشة تسجيل الدخول»
          // في المواصفة. يُرسم مرة واحدة ولا يعاد رسمه، والحركة
          // الوحيدة زحف بطيء فوق طبقة مخزّنة. تفاصيل الاختيار
          // (ولماذا لا تتكرر الحركة) في GoalBackdrop.
          const GoalBackdrop(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 32,
                ),
                child: Form(
                  key: _formKey,
                  child: AutofillGroup(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: BrandBadge(size: 100)),
                        const SizedBox(height: 22),
                        Text(
                          'ملك التوقعات',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(fontSize: 30),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'توقّع بذكاء. اجمع التاج. اجلس على العرش.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Brand.textMuted,
                            fontSize: 14.5,
                          ),
                        ),
                        if (reason != null) ...[
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Brand.wrong.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Brand.wrong.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  size: 18,
                                  color: Brand.wrong,
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    reason,
                                    style: const TextStyle(
                                      color: Brand.wrong,
                                      fontSize: 13,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 34),
                        TextFormField(
                          controller: _email,
                          decoration: const InputDecoration(
                            labelText: 'البريد الإلكتروني',
                          ),
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textDirection: TextDirection.ltr,
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(color: Brand.text),
                          validator: (v) => (v == null || !v.contains('@'))
                              ? 'أدخل بريداً صحيحاً'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        PasswordField(
                          controller: _password,
                          label: 'كلمة المرور',
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.done,
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'كلمة المرور مطلوبة'
                              : null,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 6),
                        // تذكرني والاستعادة في سطر واحد — السطر التقليدي
                        // الذي تتوقعه العين تحت حقلي الدخول.
                        Row(
                          children: [
                            SizedBox(
                              width: 22,
                              height: 22,
                              child: Checkbox(
                                value: _remember,
                                onChanged: _busy
                                    ? null
                                    : (v) => setState(
                                        () => _remember = v ?? false,
                                      ),
                                side: const BorderSide(color: Brand.textFaint),
                                activeColor: Brand.text,
                                checkColor: Brand.onAccent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _busy
                                  ? null
                                  : () =>
                                        setState(() => _remember = !_remember),
                              child: const Text(
                                'تذكرني',
                                style: TextStyle(
                                  color: Brand.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ForgotPasswordScreen(
                                          initialEmail: _email.text.trim(),
                                        ),
                                      ),
                                    ),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'نسيت كلمة المرور؟',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Brand.wrong,
                              fontSize: 13,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Brand.onAccent,
                                  ),
                                )
                              : const Text('دخول'),
                        ),
                        const SizedBox(height: 22),
                        SocialAuthButtons(
                          enabled: !_busy,
                          onError: (m) => setState(() => _error = m),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const RegisterScreen(),
                                  ),
                                ),
                          child: const Text('ما عندك حساب؟ سجّل الآن'),
                        ),
                        // باب الضيف: يتصفح المباريات والعرش بلا حساب،
                        // وأول فعل يحتاج حساباً يعيده إلى هنا. مطلب
                        // مراجعة آبل أيضاً (5.1.1): التصفح قبل التسجيل.
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => context.read<Session>().enterGuest(),
                          child: const Text(
                            'تصفّح المباريات كضيف',
                            style: TextStyle(
                              color: Brand.textFaint,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
