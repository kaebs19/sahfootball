// يمنع افتراق رقم الإصدار المعروض في "حول التطبيق" عن pubspec.
//
// الرقمان يفترقان بصمت: من يرفع الإصدار للنشر لا سبب يجعله يفتح
// شاشة "حول التطبيق"، فيقرأ المستخدم رقماً قديماً — وهو أول ما
// نسأله عنه حين يبلّغ عن عطل.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/about_footer.dart';

void main() {
  test('AboutFooter.version يطابق pubspec.yaml', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    // "version: 1.0.0+1" → الجزء قبل + هو ما يراه المستخدم.
    final pubspec = line.split(':')[1].trim().split('+').first;
    expect(AboutFooter.version, pubspec);
  });
}
