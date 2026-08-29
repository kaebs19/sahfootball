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
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brand.dart';
import '../state/app_tab.dart';
import '../state/session.dart';
import '../widgets/brand_mark.dart';
import 'leaderboard_screen.dart';
import 'live_screen.dart';
import 'matches_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const _titles = ['المباريات', 'مباشر', 'العرش', 'ملفي'];
  static const _profileTab = 3;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user;
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
          if (index == _profileTab)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'الإعدادات',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          // الاسم في تبويب ملفي وحده. كان يظهر في كل شريط: تكرار
          // لا يضيف شيئاً — المستخدم يعرف من هو، وثلاث شاشات تعرض
          // مباريات وترتيباً لا علاقة لها باسمه، بينما الشريط أضيق
          // مكان في الشاشة.
          if (user != null && index == _profileTab)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 16),
              child: Center(
                child: Text(
                  user.nameOrFallback,
                  style: const TextStyle(
                      color: Brand.textMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
      body: IndexedStack(
        index: index,
        children: const [
          MatchesScreen(),
          LiveScreen(),
          LeaderboardScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        // خط فاصل رفيع فوق الشريط: الهوية تفصل الأسطح بالحدود لا
        // بالظلال.
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Brand.borderSoft)),
        ),
        child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => context.read<AppTab>().select(i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.sports_soccer_outlined),
                selectedIcon: Icon(Icons.sports_soccer),
                label: 'المباريات'),
            NavigationDestination(
                icon: Icon(Icons.sensors),
                selectedIcon: Icon(Icons.sensors),
                label: 'مباشر'),
            NavigationDestination(
                icon: Icon(Icons.workspace_premium_outlined),
                selectedIcon: Icon(Icons.workspace_premium),
                label: 'العرش'),
            NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'ملفي'),
          ],
        ),
      ),
    );
  }
}
