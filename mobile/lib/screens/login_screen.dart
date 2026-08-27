// شاشة الدخول — أول ظهور للعلامة، فتحمل الشعار والوعد.
//
// نمط معالجة الأخطاء الموحد في كل النماذج: الاستدعاء داخل try،
// ApiException رسالتها عربية جاهزة من السيرفر فتعرض كما هي تحت
// الزر — لا حوارات منبثقة تقطع السياق لخطأ متوقع كبيانات خاطئة.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../state/session.dart';
import '../widgets/brand_mark.dart';
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
  String? _error;

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
      await context.read<Session>().login(_email.text.trim(), _password.text);
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: BrandBadge(size: 100)),
                  const SizedBox(height: 22),
                  Text(
                    'ملك التوقعات',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineLarge
                        ?.copyWith(fontSize: 30),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'توقّع بذكاء. اجمع التاج. اجلس على العرش.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Brand.textMuted, fontSize: 14.5),
                  ),
                  if (reason != null) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Brand.wrong.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: Brand.wrong.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline,
                              size: 18, color: Brand.wrong),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              reason,
                              style: const TextStyle(
                                  color: Brand.wrong, fontSize: 13, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 34),
                  TextFormField(
                    controller: _email,
                    decoration:
                        const InputDecoration(labelText: 'البريد الإلكتروني'),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(color: Brand.text),
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'أدخل بريداً صحيحاً'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    decoration: const InputDecoration(labelText: 'كلمة المرور'),
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    style: const TextStyle(color: Brand.text),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'كلمة المرور مطلوبة' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Brand.wrong, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Brand.onAccent),
                          )
                        : const Text('دخول'),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const RegisterScreen())),
                    child: const Text('ما عندك حساب؟ سجّل الآن'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
