// Links — روابط الدعوة التي تفتح التطبيق.
//
// sahfootball.com/join/XXXXXX يصل من واتساب أو من المتصفح، والنظام
// يسلّمه للتطبيق (Universal Links في iOS، App Links في أندرويد)
// بدل أن يفتح الموقع. هذا الملف يترجم الرابط إلى «افتح الدعوة
// برمز كذا» ويضعها في AppTab — نفس آلية الإشعارات: طبقة خارج
// الشجرة تضع طلباً، وويدجت داخلها ينفّذه.
//
// حالتان يجب ألا تُنسى إحداهما:
// - التطبيق مغلق والرابط يشغّله: الرابط يصل قبل أن تُبنى الشجرة،
//   فنقرؤه من getInitialLink عند الإقلاع.
// - التطبيق يعمل في الخلفية: يصل عبر البثّ (uriLinkStream).
import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'app_tab.dart';

class Links {
  final AppTab tab;
  final _links = AppLinks();
  StreamSubscription<Uri>? _sub;

  Links(this.tab);

  Future<void> start() async {
    try {
      final initial = await _links.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (e) {
      debugPrint('[links] تعذّر قراءة رابط الإقلاع: $e');
    }
    _sub = _links.uriLinkStream.listen(_handle, onError: (Object e) {
      debugPrint('[links] رابط غير مقروء: $e');
    });
  }

  /// /join/<code> فقط. أي مسار آخر على النطاق ليس لنا وإن وصل.
  void _handle(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length >= 2 && segments[0] == 'join') {
      final code = segments[1].trim();
      if (code.isNotEmpty) tab.openInvite(code);
    }
  }

  void dispose() {
    _sub?.cancel();
  }
}
