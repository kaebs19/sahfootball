// اختبار دخان: هل تُبنى شجرة التطبيق ويظهر مؤشر الانتظار أثناء
// استعادة الجلسة؟ Session تبدأ بحالة restoring قبل أي طلب شبكة،
// فلا حاجة لسيرفر — نركّب نفس المزودات التي يركبها main() ونتحقق.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/api/api_client.dart';
import 'package:mobile/main.dart';
import 'package:mobile/state/app_tab.dart';
import 'package:mobile/state/session.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('التطبيق يقلع ويعرض مؤشر الانتظار', (WidgetTester tester) async {
    final api = ApiClient();
    final tab = AppTab();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider.value(value: api),
          ChangeNotifierProvider.value(value: tab),
          ChangeNotifierProvider.value(value: Session(api, tab)),
        ],
        child: const SahApp(),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
