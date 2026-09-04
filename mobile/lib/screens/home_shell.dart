// الهيكل الرئيسي: شريط تبويبات سفلي يبدّل بين الشاشات الأربع.
//
// IndexedStack بدل التبديل المباشر: يبقي كل الشاشات حية ويظهر
// واحدة — التنقل بين التبويبات لا يفقد موضع التمرير ولا يعيد جلب
// البيانات. نفس سلوك TabView في SwiftUI.
//
// ترتيب التبويبات يتبع رحلة المستخدم لا عدد الشاشات: المباريات
// (يتوقع) ← مباشر (يتابع) ← العرش (يقارن نفسه بالناس) ← ملفي
// (حسابه). وملفي في الطرف كما في كل تطبيق — الطرف هو المكان الذي
// تبحث فيه اليد عن "أنا" بلا تفكير.
//
// تسمية "العرش" للصدارة من الهوية لا اختراعاً: اللغة جزء من العلامة
// مثل اللون تماماً، و"العرش" تحمل وعد التطبيق بينما "الصدارة" كلمة
// محايدة تصلح لأي تطبيق.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brand.dart';
import '../config.dart';
import '../state/app_tab.dart';
import '../state/session.dart';
import '../widgets/brand_mark.dart';
import '../widgets/ads.dart';
import '../widgets/guest_gate.dart';
import 'leaderboard_screen.dart';
import 'live_screen.dart';
import 'group_screen.dart';
import 'invite_screen.dart';
import 'matches_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

/// يلتقط طلب «افتح المجلس» الآتي من إشعار ويدفع شاشته.
///
/// ويدجت صغيرة داخل الشجرة لأن الدفع يحتاج Navigator، والإشعار خارج
/// الشجرة لا يملكه؛ AppTab يحمل الطلب وهذه تنفّذه بعد أول إطار —
/// الدفع أثناء البناء ممنوع في فلاتر.
class _GroupOpener extends StatefulWidget {
  final Widget child;
  const _GroupOpener({required this.child});

  @override
  State<_GroupOpener> createState() => _GroupOpenerState();
}

class _GroupOpenerState extends State<_GroupOpener> {
  @override
  Widget build(BuildContext context) {
    final tab = context.watch<AppTab>();
    final pending = tab.takePendingGroup();
    final invite = tab.takePendingInvite();
    if (pending != null || invite != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => invite != null
                ? InviteScreen(code: invite)
                : GroupScreen(groupId: pending!, groupName: 'المجلس'),
          ),
        );
      });
    }
    return widget.child;
  }
}

/// أيقونة تبويب «ملفي»: صورة المستخدم إن وُجدت، وإلا أيقونة الشخص.
/// الحلقة الذهبية حين يكون التبويب مختاراً — التاج للمستخدم نفسه.
class _ProfileTabIcon extends StatelessWidget {
  final String? url;
  final bool selected;
  const _ProfileTabIcon({required this.url, required this.selected});

  @override
  Widget build(BuildContext context) {
    if (url == null) {
      return Icon(selected ? Icons.person : Icons.person_outline);
    }
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? Brand.crown : Brand.border,
          width: selected ? 2 : 1,
        ),
        image: DecorationImage(
          image: CachedNetworkImageProvider(AppConfig.absoluteUrl(url!)),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const _titles = ['المباريات', 'مباشر', 'العرش', 'ملفي'];
  static const _profileTab = 3;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final user = session.user;
    // الضيف يرى الهيكل نفسه: المباريات والعرش مسارات عامة في
    // الخادم تعمل بلا توكن، وما يحتاج حساباً (مباشر بتوقعاتك،
    // ملفك) يُستبدل بدعوة تسجيل في مكانه — التبويب يبقى ليعرف
    // الضيف ماذا سيكسب، ولا يختفي فيظن التطبيق ناقصاً.
    final guest = session.status == SessionStatus.guest;
    // watch لا read: فتح التطبيق من إشعار يغيّر التبويب من خارج
    // هذه الشجرة، ولا بد أن يُعاد البناء حينها.
    final index = context.watch<AppTab>().index;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            // العلامة في الشريط بالحجم الصغير: الدرجات محذوفة
            // تلقائياً (قاعدة الهوية) والحفر بلون الخلفية "ليل".
            const BrandMark(size: 22, carve: Brand.night),
            const SizedBox(width: 9),
            Text(_titles[index]),
          ],
        ),
        actions: [
          // الترس في تبويب ملفي وحده: الإعدادات جزء من "أنا" لا من
          // المباريات، وإظهاره في كل تبويب يجعله زينة تُتجاهل.
          // والضيف بلا إعدادات أصلاً — كلها شؤون حساب.
          if (!guest && index == _profileTab)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'الإعدادات',
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
          // ولا اسم في الشريط: ترويسة «ملفي» تعرضه كبيراً تحت الصورة
          // مباشرة، واسمٌ ثانٍ فوقه بخط صغير تكرارٌ لا يضيف شيئاً.
        ],
      ),
      body: _GroupOpener(
        child: IndexedStack(
          index: index,
          children: guest
              ? const [
                  MatchesScreen(),
                  GuestGate(
                    icon: Icons.sensors,
                    title: 'مباشر يحتاج حساباً',
                    message:
                        'تبويب مباشر يعرض ما يحدث لتوقّعك الآن — '
                        'النتيجة لحظة بلحظة وماذا تعني لنقاطك. '
                        'سجّل وتوقّع لتكون لك مباراة تتابعها.',
                  ),
                  LeaderboardScreen(),
                  GuestGate(
                    icon: Icons.person_outline,
                    title: 'ملفك ينتظرك',
                    message:
                        'رتبتك ودقتك وسلسلتك وأوسمتك — كلها تُبنى '
                        'من توقعاتك. أنشئ حساباً وابدأ من رتبة مشجّع.',
                  ),
                ]
              : const [
                  MatchesScreen(),
                  LiveScreen(),
                  LeaderboardScreen(),
                  ProfileScreen(),
                ],
        ),
      ),
      // البانر فوق الشريط لا داخل الشاشات: مكانٌ واحد يظهر في كل
      // التبويبات، ولا يُنسى في تبويب ولا يتكرر في آخر. ويختفي وحده
      // عند المشتركين وحين لا يصل إعلان (راجع BannerAdSlot).
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BannerAdSlot(),
          DecoratedBox(
            // خط فاصل رفيع فوق الشريط: الهوية تفصل الأسطح بالحدود لا
            // بالظلال.
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Brand.borderSoft)),
            ),
            child: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => context.read<AppTab>().select(i),
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.sports_soccer_outlined),
                  selectedIcon: Icon(Icons.sports_soccer),
                  label: 'المباريات',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.sensors),
                  selectedIcon: Icon(Icons.sensors),
                  label: 'مباشر',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.workspace_premium_outlined),
                  selectedIcon: Icon(Icons.workspace_premium),
                  label: 'العرش',
                ),
                // صورة المستخدم مكان أيقونة «ملفي» حين يرفع واحدة: الوجه
                // في الشريط هو ما تفعله التطبيقات المألوفة، ويجعل التبويب
                // «أنا» لا «ملفاً». بلا صورة تبقى الأيقونة.
                NavigationDestination(
                  icon: _ProfileTabIcon(url: user?.avatarUrl, selected: false),
                  selectedIcon: _ProfileTabIcon(
                    url: user?.avatarUrl,
                    selected: true,
                  ),
                  label: 'ملفي',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
