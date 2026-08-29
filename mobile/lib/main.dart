// نقطة الدخول — تركيب الطبقات وقرار الشاشة الجذرية.
//
// شجرة التطبيق: ApiClient (بلا حالة واجهة) → Session (حالة الدخول،
// ChangeNotifier) → MaterialApp. الشاشة الجذرية دالة في حالة الجلسة:
//   restoring → شاشة انتظار،  loggedOut → دخول،  loggedIn → الرئيسية
// لا أحد "ينتقل" لشاشة الدخول — تغيّر الحالة يعيد بناء الجذر.
// نفس نمط  WindowGroup { if session.isLoggedIn ... }  في SwiftUI.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'api/api_client.dart';
import 'brand.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'state/app_tab.dart';
import 'state/session.dart';
import 'widgets/brand_mark.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // تحميل رموز التاريخ العربية (أسماء الأيام والشهور) لمكتبة intl —
  // بدونها DateFormat('EEEE', 'ar') يرمي استثناء.
  await initializeDateFormatting('ar');

  final api = ApiClient();
  final tab = AppTab();
  final session = Session(api, tab);
  // نبدأ استعادة الجلسة قبل runApp حتى لا يرى المستخدم وميض شاشة
  // الدخول ثم قفزة للرئيسية. لا ننتظرها (بلا await) — الواجهة تعرض
  // شاشة الانتظار وتتحدث وحدها عند الانتهاء.
  session.restore();

  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: api),
        ChangeNotifierProvider.value(value: tab),
        ChangeNotifierProvider.value(value: session),
      ],
      child: const SahApp(),
    ),
  );
}

class SahApp extends StatelessWidget {
  const SahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ملك التوقعات',
      debugShowCheckedModeBanner: false,
      // سمة واحدة داكنة: الهوية مبنية على "ليل" ولا تعرّف وضعاً
      // فاتحاً، واختراع واحد سيكسر قواعد الذهبي والأخضر.
      theme: buildBrandTheme(),
      // locale عربية = اتجاه RTL تلقائياً لكل الشاشات، ونصوص
      // الويدجتس الجاهزة (أزرار الحوارات مثلاً) بالعربية.
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    // watch = أعد بناء هذا الويدجت عند كل notifyListeners من Session
    final session = context.watch<Session>();
    switch (session.status) {
      case SessionStatus.restoring:
        // شاشة الإقلاع تعرض العلامة لا مؤشراً عارياً: اللحظة قصيرة
        // لكنها أول ما يراه المستخدم، والعلامة تملأها بمعنى.
        return const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandBadge(size: 100),
                SizedBox(height: 22),
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Brand.crown),
                ),
              ],
            ),
          ),
        );
      case SessionStatus.loggedOut:
        return const LoginScreen();
      case SessionStatus.loggedIn:
        return const HomeShell();
    }
  }
}
