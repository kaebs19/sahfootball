// عارض Markdown صغير — للصفحات القانونية القادمة من السيرفر.
//
// لماذا لا نستعمل body_html في WebView؟ لأن WebView محرك متصفح
// كامل داخل شاشة نصية: بطيء الإقلاع، وخطوطه وألوانه ليست خطوط
// التطبيق فتبدو الصفحة غريبة عن كل ما حولها، ونصه لا يُنسخ ولا
// يُكبَّر مع إعدادات النظام كما يفعل نص Flutter.
//
// ولماذا لا مكتبة Markdown جاهزة؟ لأن ما تحتاجه نصوص الخصوصية
// والشروط أربعة أشكال فقط: عنوان، فقرة، عنصر قائمة، ونص عريض.
// المكتبات تجرّ معها جداول وصوراً وشيفرة وHTML مضمّناً — سطح لا
// نعرضه ولا نريد أن نصونه.
//
// ما لا يُفهم يُعرض كفقرة عادية: نص قانوني ناقص أسوأ من نص بمظهر
// غير مثالي.
import 'package:flutter/material.dart';

import '../brand.dart';

class MarkdownView extends StatelessWidget {
  final String source;
  const MarkdownView({super.key, required this.source});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _blocks(source).toList(),
    );
  }

  Iterable<Widget> _blocks(String md) sync* {
    // الفقرة تنتهي بسطر فارغ. نجمع الأسطر المتتابعة كي لا ينكسر
    // النص عند حدود أسطر المحرر.
    final buffer = <String>[];

    Widget? flush() {
      if (buffer.isEmpty) return null;
      final text = buffer.join(' ');
      buffer.clear();
      return _paragraph(text);
    }

    for (final raw in md.split('\n')) {
      final line = raw.trimRight();
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        final p = flush();
        if (p != null) yield p;
        continue;
      }

      final heading = RegExp(r'^(#{1,4})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        final p = flush();
        if (p != null) yield p;
        yield _heading(heading.group(2)!, heading.group(1)!.length);
        continue;
      }

      final bullet = RegExp(r'^[-*•]\s+(.*)$').firstMatch(trimmed);
      if (bullet != null) {
        final p = flush();
        if (p != null) yield p;
        yield _bullet(bullet.group(1)!);
        continue;
      }

      buffer.add(trimmed);
    }

    final last = flush();
    if (last != null) yield last;
  }

  Widget _heading(String text, int level) => Padding(
        padding: EdgeInsets.only(top: level == 1 ? 6 : 18, bottom: 8),
        child: Text(
          _inline(text),
          style: TextStyle(
            fontFamily: Brand.displayFont,
            fontSize: level == 1 ? 20 : (level == 2 ? 16.5 : 14.5),
            fontWeight: FontWeight.w700,
            color: Brand.text,
            height: 1.5,
          ),
        ),
      );

  Widget _paragraph(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          _inline(text),
          style: const TextStyle(
            color: Brand.textMuted,
            fontSize: 14,
            height: 1.9,
          ),
        ),
      );

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Icon(Icons.circle, size: 5, color: Brand.crown),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                _inline(text),
                style: const TextStyle(
                  color: Brand.textMuted,
                  fontSize: 14,
                  height: 1.9,
                ),
              ),
            ),
          ],
        ),
      );

  /// التشكيل داخل السطر لا نرسمه بأنماط مختلفة بل ننزع علاماته:
  /// نجمتان حول كلمة تعنيان تشديداً، وعرضهما كما هي ("**نحن**")
  /// أسوأ من عرض الكلمة عادية.
  String _inline(String text) => text
      .replaceAll('**', '')
      .replaceAll('__', '')
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1)!);
}
