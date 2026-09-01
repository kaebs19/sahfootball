// استعادة كلمة المرور — رحلة من خطوتين في شاشة واحدة.
//
// الخطوة 1: البريد ← السيرفر يرسل رمزاً من 6 أرقام (صالح 10 دقائق).
// الخطوة 2: الرمز + كلمة جديدة بتأكيدها ← السيرفر يبدّل الكلمة
// ويرد بجلسة كاملة، فيدخل المستخدم مباشرة بلا شاشة دخول إضافية
// (أثبت ملكية بريده للتو — إجباره على الدخول بعدها بيروقراطية).
//
// شاشة واحدة لا اثنتان: البريد المُدخل في الخطوة الأولى هو نفسه
// المطلوب في الثانية، وفصلهما يعني تمريره بين شاشتين أو — أسوأ —
// طلبه مرتين. والعودة بزر الرجوع من منتصف الرحلة تلغيها كاملة
// بشكل بديهي.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../state/session.dart';
import '../widgets/password_field.dart';

class ForgotPasswordScreen extends StatefulWidget {
  /// ما كتبه المستخدم في شاشة الدخول قبل أن يضغط "نسيت" — يُنسخ
  /// هنا فلا يكتب بريده مرتين في نفس الدقيقة.
  final String initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _busy = false;
  bool _codeSent = false;
  String? _error;

  // عدّاد إعادة الإرسال: يمنع النقر المتكرر الذي يستهلك حد السيرفر
  // (الرمز الأحدث يلغي الأقدم فتضيع رسالة وصلت للتو)، ويطمئن
  // المستخدم أن "أعد الإرسال" ستعود — البريد قد يتأخر دقيقة.
  Timer? _cooldownTimer;
  int _cooldown = 0;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown -= 1);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'أدخل بريداً صحيحاً');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().forgotPassword(email);
      setState(() => _codeSent = true);
      _startCooldown();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<Session>().resetPassword(
            email: _email.text.trim(),
            code: _code.text.trim(),
            newPassword: _password.text,
          );
      TextInput.finishAutofillContext();
      // الجلسة صارت loggedIn والجذر تبدّل للرئيسية — هذه الشاشة
      // مدفوعة فوقه فتُنزَل يدوياً (نفس فخ التسجيل الموثّق في main).
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استعادة كلمة المرور')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
            child: Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _codeSent
                          ? 'أدخل الرمز المرسل إلى بريدك، ثم اختر كلمة مرور جديدة.'
                          : 'اكتب بريدك وسنرسل لك رمز استعادة من 6 أرقام.',
                      style: const TextStyle(
                          color: Brand.textMuted, fontSize: 14, height: 1.6),
                    ),
                    const SizedBox(height: 26),
                    TextFormField(
                      controller: _email,
                      // بعد إرسال الرمز يقفل الحقل: الرمز مربوط بهذا
                      // البريد تحديداً، وتغييره الآن يصنع حالة "رمز
                      // صحيح لبريد آخر" التي تفشل بلا تفسير مفهوم.
                      enabled: !_codeSent,
                      decoration:
                          const InputDecoration(labelText: 'البريد الإلكتروني'),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                          color:
                              _codeSent ? Brand.textMuted : Brand.text),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'أدخل بريداً صحيحاً'
                          : null,
                    ),
                    if (_codeSent) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _code,
                        decoration: const InputDecoration(
                          labelText: 'رمز الاستعادة',
                          helperText: 'وصلك في بريدك — صالح 10 دقائق',
                          helperStyle: TextStyle(color: Brand.textFaint),
                          counterText: '',
                        ),
                        keyboardType: TextInputType.number,
                        // oneTimeCode: يلتقط iOS الرمز من الرسالة
                        // ويعرضه فوق لوحة المفاتيح.
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        maxLength: 6,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Brand.text,
                          fontFamily: Brand.displayFont,
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 8,
                        ),
                        validator: (v) => (v == null || v.length != 6)
                            ? 'الرمز 6 أرقام'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      PasswordField(
                        controller: _password,
                        label: 'كلمة المرور الجديدة',
                        helperText: '8 أحرف على الأقل',
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
                        validator: (v) => (v == null || v.length < 8)
                            ? 'كلمة المرور 8 أحرف على الأقل'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      PasswordField(
                        controller: _confirm,
                        label: 'إعادة كلمة المرور',
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        validator: (v) => (v != _password.text)
                            ? 'كلمتا المرور غير متطابقتين'
                            : null,
                        onFieldSubmitted: (_) => _reset(),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(color: Brand.wrong, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _busy ? null : (_codeSent ? _reset : _sendCode),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Brand.onAccent),
                            )
                          : Text(_codeSent
                              ? 'تغيير كلمة المرور'
                              : 'أرسل رمز الاستعادة'),
                    ),
                    if (_codeSent) ...[
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed:
                            (_busy || _cooldown > 0) ? null : _sendCode,
                        child: Text(
                          _cooldown > 0
                              ? 'أعد الإرسال بعد $_cooldown ثانية'
                              : 'لم يصلك؟ أعد الإرسال',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
