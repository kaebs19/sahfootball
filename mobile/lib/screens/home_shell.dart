// الهيكل الرئيسي: شريط تبويبات سفلي يبدّل بين الشاشات الثلاث.
//
// IndexedStack بدل التبديل المباشر: يبقي كل الشاشات حية ويظهر
// واحدة — التنقل بين التبويبات لا يفقد موضع التمرير ولا يعيد جلب
// البيانات. نفس سلوك TabView في SwiftUI.
//
// تسمية "العرش" للصدارة من الهوية لا اختراعاً: اللغة جزء من العلامة
// مثل اللون تماماً، و"العرش" تحمل وعد التطبيق بينما "الصدارة" كلمة
// محايدة تصلح لأي تطبيق.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../brand.dart';
import '../state/session.dart';
import '../widgets/brand_mark.dart';
import 'leaderboard_screen.dart';
import 'live_screen.dart';
import 'matches_screen.dart';
import 'profile_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = ['المباريات', 'مباشر', 'ملفي', 'العرش'];

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            // العلامة في الشريط بالحجم الصغير: الدرجات محذوفة
            // تلقائياً (قاعدة الهوية) والحفر بلون الخلفية "ليل".
            const BrandMark(size: 22, carve: Brand.night),
            const SizedBox(width: 9),
            Text(_titles[_index]),
          ],
        ),
        actions: [
          if (user != null)
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
        index: _index,
        children: const [
          MatchesScreen(),
          LiveScreen(),
          ProfileScreen(),
          LeaderboardScreen(),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        // خط فاصل رفيع فوق الشريط: الهوية تفصل الأسطح بالحدود لا
        // بالظلال.
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Brand.borderSoft)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
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
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'ملفي'),
            NavigationDestination(
                icon: Icon(Icons.workspace_premium_outlined),
                selectedIcon: Icon(Icons.workspace_premium),
                label: 'العرش'),
          ],
        ),
      ),
    );
  }
}
