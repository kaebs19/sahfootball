// الإعدادات — كل ما ليس لعباً.
//
// شاشة مستقلة لا قسم في "ملفي": الملف الشخصي يُفتح يومياً لرؤية
// النقاط والسجل، والإعدادات تُفتح مرات معدودة في عمر الحساب.
// وضعها في نفس التمريرة يعني أن ما يُقرأ كل يوم يزاحمه ما يُقرأ
// مرة واحدة.
//
// المجموعات الأربع تتبع سؤال المستخدم لا بنية الكود: حسابي ←
// تفضيلاتي ← قانوني ودعم ← الخروج.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brand.dart';
import '../state/session.dart';
import '../widgets/brand_widgets.dart';
import 'about_footer.dart';
import 'account_settings_screen.dart';
import 'contact_screen.dart';
import 'edit_profile_screen.dart';
import 'page_screen.dart';
import 'privacy_settings_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user;

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 30),
        children: [
          const _GroupLabel('الحساب'),
          _SettingsGroup(
            children: [
              _SettingsTile(
                icon: Icons.person_outline,
                title: 'تعديل الملف الشخصي',
                subtitle: user?.nameOrFallback,
                onTap: () => _open(context, const EditProfileScreen()),
              ),
              _SettingsTile(
                icon: Icons.lock_outline,
                title: 'إعدادات الحساب',
                subtitle: 'البريد وكلمة السر وحذف الحساب',
                onTap: () => _open(context, const AccountSettingsScreen()),
              ),
            ],
          ),

          const _GroupLabel('التفضيلات'),
          _SettingsGroup(
            children: [
              // الإشعارات معطّلة لا مخفية: إخفاؤها يوحي بأنها لن توجد،
              // ومفتاح يعمل بلا بنية إشعارات خلفه أسوأ — يظن المستخدم
              // أنه فعّلها ثم ينتظر تنبيهاً لن يصل أبداً.
              const _SettingsTile(
                icon: Icons.notifications_none,
                title: 'الإشعارات',
                subtitle: 'تنبيه قبل إقفال التوقع وعند احتساب النقاط',
                trailingLabel: 'قريباً',
              ),
              _SettingsTile(
                icon: Icons.shield_outlined,
                title: 'الخصوصية',
                subtitle: 'بياناتك وما نفعله بها',
                onTap: () => _open(context, const PrivacySettingsScreen()),
              ),
              // المظهر واللغة صفّا معلومات لا خيارين: الهوية داكنة
              // بلا ثيم فاتح، والتطبيق عربي بلا لغة ثانية. عرضهما
              // كقائمة بخيار واحد يعد بخيار غير موجود.
              const _SettingsTile(
                icon: Icons.dark_mode_outlined,
                title: 'المظهر',
                subtitle: 'داكن — هوية ملك التوقعات داكنة دائماً',
                trailingLabel: 'داكن',
              ),
              const _SettingsTile(
                icon: Icons.language,
                title: 'اللغة',
                subtitle: 'العربية',
                trailingLabel: 'العربية',
              ),
            ],
          ),

          const _GroupLabel('عن التطبيق'),
          _SettingsGroup(
            children: [
              _SettingsTile(
                icon: Icons.privacy_tip_outlined,
                title: 'سياسة الخصوصية',
                onTap: () => _open(
                  context,
                  const PageScreen(
                      slug: 'privacy', fallbackTitle: 'سياسة الخصوصية'),
                ),
              ),
              _SettingsTile(
                icon: Icons.description_outlined,
                title: 'شروط الاستخدام',
                onTap: () => _open(
                  context,
                  const PageScreen(
                      slug: 'terms', fallbackTitle: 'شروط الاستخدام'),
                ),
              ),
              _SettingsTile(
                icon: Icons.mail_outline,
                title: 'اتصل بنا',
                onTap: () => _open(context, const ContactScreen()),
              ),
              _SettingsTile(
                icon: Icons.info_outline,
                title: 'حول التطبيق',
                subtitle: 'الإصدار ${AboutFooter.version}',
                onTap: () => _open(
                  context,
                  const PageScreen(
                    slug: 'about',
                    fallbackTitle: 'حول التطبيق',
                    footer: AboutFooter(),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),
          _LogoutButton(),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _GroupLabel extends StatelessWidget {
  final String label;
  const _GroupLabel(this.label);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Text(
          label,
          style: const TextStyle(
            color: Brand.textFaint,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

/// بطاقة واحدة تضم صفوفاً بينها خطوط — لا بطاقة لكل صف. المجموعة
/// المرئية هي ما يجعل القائمة الطويلة قابلة للمسح بالعين.
class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              const Divider(
                  height: 1, thickness: 1, color: Brand.borderSoft, indent: 52),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  /// نص صغير على الطرف: قيمة حالية ("العربية") أو حالة ("قريباً").
  final String? trailingLabel;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // بلا onTap = صف معلوماتي: نخفّت لونه كي لا ينتظر المستخدم
    // استجابة من ضغطة لن تحدث.
    final enabled = onTap != null;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        child: Row(
          children: [
            Icon(icon,
                size: 20, color: enabled ? Brand.textMuted : Brand.textFaint),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: enabled ? Brand.text : Brand.textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Brand.textFaint, fontSize: 11.5),
                    ),
                  ],
                ],
              ),
            ),
            if (trailingLabel != null)
              Text(
                trailingLabel!,
                style:
                    const TextStyle(color: Brand.textFaint, fontSize: 11.5),
              ),
            if (enabled) ...[
              const SizedBox(width: 6),
              // chevron_right لا left: فلاتر يعكس الأيقونات الاتجاهية
              // في الواجهة العربية، فـ right يُرسم "‹" مشيراً لجهة
              // الشاشة التالية. كتابة left تعطي سهماً يشير كزر الرجوع.
              const Icon(Icons.chevron_right, size: 20, color: Brand.textFaint),
            ],
          ],
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  /// تأكيد قبل الخروج: الدخول مرة أخرى يحتاج كلمة السر، وضغطة
  /// خاطئة على زر أحمر في آخر قائمة طويلة واردة جداً.
  Future<void> _confirm(BuildContext context) async {
    final session = context.read<Session>();
    final navigator = Navigator.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Brand.surface,
        title: const Text('تسجيل الخروج'),
        content: const Text('متأكد تبي تسجل خروج؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Brand.wrong),
            child: const Text('خروج'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await session.logout();
      // بلا هذا تبقى شاشة الإعدادات معروضة فوق شاشة الدخول.
      navigator.popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _confirm(context),
      icon: const Icon(Icons.logout, size: 18),
      label: const Text('تسجيل الخروج'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Brand.wrong,
        side: const BorderSide(color: Brand.wrong),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}
