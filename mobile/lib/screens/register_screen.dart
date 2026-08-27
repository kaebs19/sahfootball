// شاشة إنشاء حساب — نفس نمط شاشة الدخول.
//
// لماذا شرط كلمة المرور 8 أحرف هنا أيضاً مع أن السيرفر يفرضه؟
// تحقق العميل للتجربة (رسالة فورية بلا رحلة شبكة)، وتحقق السيرفر
// للأمان (الحقيقة النهائية). الاثنان معاً دائماً، ولا يغني أحدهما
// عن الآخر.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../state/session.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
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
      await context.read<Session>().register(
            _email.text.trim(),
            _password.text,
            displayName: _name.text.trim(),
          );
      // نجاح التسجيل يبدل الجذر للرئيسية، لكن هذه الشاشة مدفوعة فوق
      // شاشة الدخول بـ push فنزيلها يدوياً.
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
      appBar: AppBar(title: const Text('انضم للمنافسة')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'ابدأ من رتبة مشجّع، واصعد حتى العرش.',
                    style: TextStyle(color: Brand.textMuted, fontSize: 14),
                  ),
                  const SizedBox(height: 26),
                  TextFormField(
                    controller: _name,
                    decoration:
                        const InputDecoration(labelText: 'الاسم المعروض'),
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(color: Brand.text),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _email,
                    decoration:
                        const InputDecoration(labelText: 'البريد الإلكتروني'),
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(color: Brand.text),
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'أدخل بريداً صحيحاً'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور',
                      helperText: '8 أحرف على الأقل',
                      helperStyle: TextStyle(color: Brand.textFaint),
                    ),
                    obscureText: true,
                    style: const TextStyle(color: Brand.text),
                    validator: (v) => (v == null || v.length < 8)
                        ? 'كلمة المرور 8 أحرف على الأقل'
                        : null,
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
                        : const Text('إنشاء الحساب'),
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
