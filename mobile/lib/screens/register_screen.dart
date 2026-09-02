// شاشة إنشاء حساب — نفس نمط شاشة الدخول.
//
// لماذا شرط كلمة المرور 8 أحرف هنا أيضاً مع أن السيرفر يفرضه؟
// تحقق العميل للتجربة (رسالة فورية بلا رحلة شبكة)، وتحقق السيرفر
// للأمان (الحقيقة النهائية). الاثنان معاً دائماً، ولا يغني أحدهما
// عن الآخر.
//
// حقل إعادة كلمة المرور من نفس المنطق: السيرفر لا يستطيع أن يعرف
// أن المستخدم أخطأ في الكتابة — الحرف الزائد يمر التحقق ويقفل
// الحساب على كلمة لا يعرفها صاحبه. التأكيد يصطاد الخطأ في مكانه
// الوحيد الممكن: قبل الإرسال.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInput;
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../state/session.dart';
import '../widgets/password_field.dart';
import 'page_screen.dart';

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
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
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
      // النظام يعرض حفظ كلمة المرور الجديدة في الـ Keychain —
      // أثمن ما يكون لحساب أُنشئ للتو بكلمة لن يتذكرها أحد غداً.
      TextInput.finishAutofillContext();
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
              child: AutofillGroup(
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
                      autofillHints: const [AutofillHints.name],
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
                      autofillHints: const [AutofillHints.email],
                      style: const TextStyle(color: Brand.text),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'أدخل بريداً صحيحاً'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    PasswordField(
                      controller: _password,
                      label: 'كلمة المرور',
                      helperText: '8 أحرف على الأقل',
                      // newPassword لا password: بها يقترح iOS كلمة
                      // قوية بدل أن يعرض كلمة محفوظة لحساب آخر.
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
                      onFieldSubmitted: (_) => _submit(),
                    ),
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
                    const SizedBox(height: 16),
                    // سطر الموافقة القانونية. لا مربع اختيار: الضغط
                    // على «إنشاء الحساب» هو الموافقة (النمط المعتمد
                    // في المتاجر)، والرابطان يفتحان الصفحتين من
                    // السيرفر نفسه المعروضتين في الإعدادات — نص واحد
                    // يحرّره الأدمن، لا نسخة ثانية تتقادم.
                    //
                    // (أزرار Apple/جوجل هنا أُزيلت عمداً: التسجيل
                    // عبر مزوّد يتم من شاشة الدخول، وشاشة إنشاء
                    // الحساب مخصصة للبريد وكلمة المرور.)
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'بالضغط على التسجيل فإنك توافق على ',
                          style: TextStyle(
                              color: Brand.textFaint, fontSize: 12.5),
                        ),
                        _LegalLink(
                          label: 'سياسة الخصوصية',
                          slug: 'privacy',
                          enabled: !_busy,
                        ),
                        // «و» والرابط في صف واحد كي ينكسرا معاً —
                        // واو معلقة وحدها آخر السطر تقرأ خطأً.
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              ' و',
                              style: TextStyle(
                                  color: Brand.textFaint, fontSize: 12.5),
                            ),
                            _LegalLink(
                              label: 'شروط الاستخدام',
                              slug: 'terms',
                              enabled: !_busy,
                            ),
                          ],
                        ),
                      ],
                    ),
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

/// رابط قانوني داخل سطر الموافقة — نص بلون النص الأساسي وتحته خط،
/// يفتح صفحة السيرفر المقابلة (نفس PageScreen في الإعدادات).
class _LegalLink extends StatelessWidget {
  final String label;
  final String slug;
  final bool enabled;

  const _LegalLink({
    required this.label,
    required this.slug,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled
          ? () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PageScreen(slug: slug, fallbackTitle: label)))
          : null,
      child: Text(
        label,
        style: const TextStyle(
          color: Brand.text,
          fontSize: 12.5,
          decoration: TextDecoration.underline,
          decorationColor: Brand.textFaint,
        ),
      ),
    );
  }
}
