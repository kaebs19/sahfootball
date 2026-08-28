// إعدادات الحساب: البريد، كلمة السر، وحذف الحساب.
//
// الثلاثة في شاشة واحدة لأنها تشترك في شيء واحد: كلها تطلب كلمة
// السر الحالية. البريد قناة استعادة الحساب ومن يملكه يملك الحساب،
// فتغييره من جلسة مفتوحة على هاتف منسي يجب ألا يكون ممكناً بلا سر.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../state/session.dart';
import '../widgets/brand_widgets.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user;

    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات الحساب')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
        children: [
          BrandCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('البريد الحالي',
                    style: TextStyle(color: Brand.textFaint, fontSize: 11.5)),
                const SizedBox(height: 4),
                Text(
                  user?.email ?? '—',
                  style: const TextStyle(color: Brand.text, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const _ChangeEmailForm(),
          const SizedBox(height: 26),
          const _ChangePasswordForm(),
          const SizedBox(height: 30),
          const Divider(color: Brand.borderSoft),
          const SizedBox(height: 18),
          const _DeleteAccountSection(),
        ],
      ),
    );
  }
}

class _ChangeEmailForm extends StatefulWidget {
  const _ChangeEmailForm();

  @override
  State<_ChangeEmailForm> createState() => _ChangeEmailFormState();
}

class _ChangeEmailFormState extends State<_ChangeEmailForm> {
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await context.read<ApiClient>().changeEmail(
            newEmail: _email.text.trim(),
            currentPassword: _password.text,
          );
      if (!mounted) return;
      context.read<Session>().setUser(user);
      _email.clear();
      _password.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تغيير البريد')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BrandSectionLabel('تغيير البريد'),
        const SizedBox(height: 10),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'البريد الجديد'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'كلمة السر الحالية'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!,
              style: const TextStyle(color: Brand.wrong, fontSize: 12.5)),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'يُحفظ…' : 'تغيير البريد'),
        ),
      ],
    );
  }
}

class _ChangePasswordForm extends StatefulWidget {
  const _ChangePasswordForm();

  @override
  State<_ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends State<_ChangePasswordForm> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      if (!mounted) return;
      _current.clear();
      _next.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        // الطرد من الأجهزة الأخرى أثر جانبي يجب أن يُقال: من لا
        // يعرفه سيظن أن جهازه الثاني تعطّل.
        const SnackBar(
            content: Text('تم تغيير كلمة السر — خرجت من أجهزتك الأخرى')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BrandSectionLabel('تغيير كلمة السر'),
        const SizedBox(height: 10),
        TextField(
          controller: _current,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'كلمة السر الحالية'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _next,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'كلمة السر الجديدة',
            helperText: '8 أحرف على الأقل',
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!,
              style: const TextStyle(color: Brand.wrong, fontSize: 12.5)),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'يُحفظ…' : 'تغيير كلمة السر'),
        ),
      ],
    );
  }
}

/// حذف الحساب — نهائي.
///
/// وجوده داخل التطبيق شرط في App Store (بند 5.1.1(v)): من يستطيع
/// إنشاء حساب من التطبيق يجب أن يستطيع حذفه منه.
///
/// حاجزان قبل التنفيذ: نافذة تأكيد تقول بالضبط ما سيضيع، ثم كلمة
/// السر. الأول يمنع الضغطة الخاطئة والثاني يمنع من أمسك الهاتف.
class _DeleteAccountSection extends StatefulWidget {
  const _DeleteAccountSection();

  @override
  State<_DeleteAccountSection> createState() => _DeleteAccountSectionState();
}

class _DeleteAccountSectionState extends State<_DeleteAccountSection> {
  bool _busy = false;

  Future<void> _confirm() async {
    // نلتقط الخدمات قبل انتظار النافذة: بعد await قد تكون الشاشة
    // نُزعت من الشجرة، وقراءة context حينها خطأ زمن تشغيل.
    final api = context.read<ApiClient>();
    final session = context.read<Session>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final password = TextEditingController();
    String? error;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: Brand.surface,
          title: const Text('حذف الحساب نهائياً؟'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ستختفي توقعاتك ونقاطك وأوسمتك ولا يمكن استرجاعها. '
                'القروبات التي أنشأتها تنتقل لأقدم عضو فيها، وتُحذف '
                'إن كنت عضوها الوحيد.',
                style: TextStyle(color: Brand.textMuted, height: 1.8, fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'كلمة السر'),
              ),
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!,
                    style: const TextStyle(color: Brand.wrong, fontSize: 12.5)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('تراجع'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Brand.wrong),
              onPressed: () {
                if (password.text.isEmpty) {
                  setDialogState(() => error = 'أدخل كلمة السر للتأكيد');
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('احذف حسابي'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) {
      password.dispose();
      return;
    }

    setState(() => _busy = true);
    try {
      await api.deleteAccount(password: password.text);
      // لا نستدعي logout: الحساب اختفى وتوكناته أُبطلت، فنداء الخروج
      // سيرد 401 ويُظهر خطأً على فعل نجح.
      await session.forgetSession();
      // الجذر يبدّل إلى شاشة الدخول، لكن الشاشات المدفوعة فوقه
      // (الإعدادات ثم هذه) تبقى مكانها — فيرى المستخدم إعدادات حساب
      // لم يعد موجوداً. نُفرغ المكدس حتى الجذر بعد نجاح الحذف.
      navigator.popUntil((route) => route.isFirst);
    } on ApiException catch (e) {
      if (mounted) setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      password.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BrandSectionLabel('حذف الحساب'),
        const SizedBox(height: 8),
        const Text(
          'حذف نهائي لحسابك وكل ما فيه. لا يمكن التراجع.',
          style: TextStyle(color: Brand.textMuted, fontSize: 12.5, height: 1.7),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _busy ? null : _confirm,
          style: OutlinedButton.styleFrom(
            foregroundColor: Brand.wrong,
            side: const BorderSide(color: Brand.wrong),
          ),
          child: Text(_busy ? 'يُحذف…' : 'حذف حسابي'),
        ),
      ],
    );
  }
}
