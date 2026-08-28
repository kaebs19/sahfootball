// شاشة صفحة نصية من السيرفر: الخصوصية، الشروط، عن التطبيق.
//
// شاشة واحدة لثلاث صفحات لأن الفرق بينها المعرّف (slug) فقط.
// نصوصها تعيش في القاعدة ويحرّرها الأدمن — تعديل بند في السياسة
// لا ينتظر إصداراً جديداً ولا مراجعة App Store.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../format.dart';
import '../models/site_page.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/markdown_view.dart';

class PageScreen extends StatefulWidget {
  final String slug;

  /// عنوان يُعرض قبل وصول الصفحة، كي لا يبقى الشريط فارغاً لحظة.
  final String fallbackTitle;

  /// يُلحق أسفل النص — تستعمله "عن التطبيق" لعرض رقم الإصدار.
  final Widget? footer;

  const PageScreen({
    super.key,
    required this.slug,
    required this.fallbackTitle,
    this.footer,
  });

  @override
  State<PageScreen> createState() => _PageScreenState();
}

class _PageScreenState extends State<PageScreen> {
  SitePage? _page;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final page = await context.read<ApiClient>().sitePage(widget.slug);
      if (mounted) setState(() => _page = page);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final updated = page?.updatedAt;

    return Scaffold(
      appBar: AppBar(title: Text(page?.title ?? widget.fallbackTitle)),
      body: _error != null
          ? BrandEmpty(icon: Icons.wifi_off, message: _error!, onRetry: _load)
          : page == null
              ? const Center(
                  child: CircularProgressIndicator(color: Brand.crown))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 40),
                  children: [
                    MarkdownView(source: page.body),
                    if (updated != null) ...[
                      const SizedBox(height: 18),
                      Text(
                        // تاريخ التحديث ليس زينة: في نص قانوني هو ما
                        // يخبر القارئ أي نسخة يقرأ.
                        'آخر تحديث: '
                        '${Fmt.date(intl.DateFormat('d MMMM yyyy', 'ar'), updated)}',
                        style: const TextStyle(
                          color: Brand.textFaint,
                          fontSize: 11.5,
                          fontFeatures: Brand.tabular,
                        ),
                      ),
                    ],
                    if (widget.footer != null) ...[
                      const SizedBox(height: 20),
                      widget.footer!,
                    ],
                  ],
                ),
    );
  }
}
