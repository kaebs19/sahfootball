// اتصل بنا — نموذج يصل صندوق الرسائل في لوحة التحكم.
//
// نفس مسار نموذج الموقع (POST /api/site/contact) بحدّه على عدد
// الرسائل من نفس العنوان: النموذج داخل التطبيق ليس أقل عرضة
// للإغراق من نموذج الويب.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../state/session.dart';

class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  late final TextEditingController _email;
  final _subject = TextEditingController();
  final _message = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // بريد الحساب جاهز في الحقل: هو الأرجح، وكتابته مرة أخرى خطوة
    // بلا فائدة — ويبقى قابلاً للتعديل لمن أراد رداً على بريد آخر.
    _email = TextEditingController(
        text: context.read<Session>().user?.email ?? '');
  }

  @override
  void dispose() {
    _email.dispose();
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().sendContact(
            email: _email.text.trim(),
            subject: _subject.text.trim(),
            message: _message.text.trim(),
            name: context.read<Session>().user?.displayName,
          );
      if (mounted) setState(() => _sent = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اتصل بنا')),
      body: _sent
          ? const _SentState()
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
              children: [
                const Text(
                  'اكتب لنا: عطل واجهك، فريق ناقص، أو فكرة تريدها في التطبيق.',
                  style: TextStyle(
                      color: Brand.textMuted, fontSize: 13.5, height: 1.8),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'بريدك',
                    helperText: 'عليه نرد',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _subject,
                  decoration: const InputDecoration(labelText: 'الموضوع (اختياري)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _message,
                  maxLines: 6,
                  maxLength: 4000,
                  decoration: const InputDecoration(
                    labelText: 'رسالتك',
                    alignLabelWithHint: true,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Text(_error!,
                      style:
                          const TextStyle(color: Brand.wrong, fontSize: 12.5)),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy ? null : _send,
                  child: Text(_busy ? 'تُرسل…' : 'إرسال'),
                ),
              ],
            ),
    );
  }
}

class _SentState extends StatelessWidget {
  const _SentState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mark_email_read_outlined,
                size: 46, color: Brand.correct),
            const SizedBox(height: 16),
            const Text(
              'وصلتنا رسالتك',
              style: TextStyle(
                fontFamily: Brand.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Brand.text,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'نقرأ كل رسالة ونرد على بريدك.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Brand.textMuted, height: 1.8),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('رجوع'),
            ),
          ],
        ),
      ),
    );
  }
}
