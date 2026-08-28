// الخصوصية — ما نحفظه عنك، ولماذا، وما تملك أن تفعله به.
//
// لماذا شاشة شرح لا مفاتيح؟ لأن المفاتيح الوحيدة الصادقة اليوم
// موجودة فعلاً في مكانها الطبيعي: حذف الحساب في إعدادات الحساب،
// والصورة والاسم في تعديل الملف. اختراع مفاتيح "خصوصية" لا شيء
// خلفها يعطي إحساساً بالتحكم لا يقابله تحكم.
//
// والشفافية نفسها ميزة: من يعرف أننا لا نطلب موقعه ولا جهات اتصاله
// يثق بما يعرف، لا بما نعِد به.
import 'package:flutter/material.dart';

import '../brand.dart';
import '../widgets/brand_widgets.dart';
import 'account_settings_screen.dart';
import 'page_screen.dart';

class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key});

  static const _stored = [
    ('بريدك', 'للدخول واستعادة كلمة السر. لا يُعرض لأحد غيرك.'),
    ('اسمك الظاهر وصورتك', 'يراهما بقية المتنافسين في العرش ومجموعاتك.'),
    ('توقعاتك ونقاطك', 'أساس المنافسة نفسها — وترتيبك يظهر للجميع.'),
    ('فريقك المفضل', 'اختياري، ولك أن تزيله في أي وقت.'),
  ];

  static const _notStored = [
    'موقعك الجغرافي',
    'جهات اتصالك أو صورك (نقرأ الصورة التي تختارها وحدها)',
    'أي تتبّع إعلاني',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الخصوصية')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
        children: [
          const BrandSectionLabel('ما نحفظه'),
          const SizedBox(height: 10),
          for (final (title, why) in _stored) _StoredRow(title: title, why: why),
          const SizedBox(height: 20),
          const BrandSectionLabel('ما لا نطلبه'),
          const SizedBox(height: 10),
          BrandCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in _notStored)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.close, size: 14, color: Brand.textFaint),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(item,
                              style: const TextStyle(
                                  color: Brand.textMuted,
                                  fontSize: 13,
                                  height: 1.7)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const BrandSectionLabel('حقوقك'),
          const SizedBox(height: 10),
          BrandCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _ActionRow(
                  icon: Icons.delete_outline,
                  label: 'حذف حسابك وكل بياناته',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AccountSettingsScreen())),
                ),
                const Divider(
                    height: 1, thickness: 1, color: Brand.borderSoft, indent: 46),
                _ActionRow(
                  icon: Icons.privacy_tip_outlined,
                  label: 'سياسة الخصوصية الكاملة',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const PageScreen(
                        slug: 'privacy', fallbackTitle: 'سياسة الخصوصية'),
                  )),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoredRow extends StatelessWidget {
  final String title;
  final String why;
  const _StoredRow({required this.title, required this.why});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BrandCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: Brand.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(why,
                style: const TextStyle(
                    color: Brand.textMuted, fontSize: 12.5, height: 1.7)),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionRow({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        child: Row(
          children: [
            Icon(icon, size: 19, color: Brand.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: Brand.text, fontSize: 13.5)),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Brand.textFaint),
          ],
        ),
      ),
    );
  }
}
