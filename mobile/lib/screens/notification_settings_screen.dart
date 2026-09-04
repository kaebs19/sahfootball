// إعدادات الإشعارات — مفتاحان، وشرح صادق لما يصل ومتى.
//
// لماذا مفتاحان لا مفتاح واحد؟ لأنهما إشعاران مختلفان في طبيعتهما:
// التذكير عاجل ويطلب فعلاً قبل وقت محدد، والنتيجة خبر بعد انتهاء
// كل شيء. من يريد أحدهما دون الآخر لا يجد أمامه — بمفتاح واحد —
// إلا إيقاف الإشعارات من إعدادات الهاتف، وحينها نفقده نهائياً:
// iOS لا يعيد سؤال الإذن أبداً بعد رفضه.
//
// والحفظ فوري بلا زر "حفظ": المفتاح يعِد بأثر فوري، وزر حفظ خلفه
// يجعل من يغلق الشاشة بعد تحريكه يظن أنه أوقف الإشعارات وهي تعمل.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../models/notification_prefs.dart';
import '../widgets/brand_widgets.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  NotificationPrefs? _prefs;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await context.read<ApiClient>().notificationPrefs();
      if (!mounted) return;
      setState(() => _prefs = prefs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'تعذّر تحميل الإعدادات');
    }
  }

  /// التحديث المتفائل: نحرّك المفتاح فوراً ونتراجع عند الفشل.
  ///
  /// البديل (انتظار السيرفر ثم التحريك) يجعل المفتاح يتجمّد نصف
  /// ثانية عند كل لمسة على شبكة بطيئة، فيلمسه المستخدم مرة أخرى
  /// ظاناً أنها لم تُسجّل — ويعود لحيث بدأ.
  Future<void> _set({bool? reminders, bool? results, bool? live}) async {
    final current = _prefs;
    if (current == null || _saving) return;

    setState(() {
      _saving = true;
      _prefs = current.copyWith(reminders: reminders, results: results, live: live);
    });

    try {
      final saved = await context.read<ApiClient>().updateNotificationPrefs(
          reminders: reminders, results: results, live: live);
      if (!mounted) return;
      setState(() => _prefs = saved);
    } catch (e) {
      if (!mounted) return;
      setState(() => _prefs = current); // تراجع للحالة الحقيقية
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر حفظ التغيير')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = _prefs;

    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: _error != null
          ? BrandEmpty(
              icon: Icons.notifications_off_outlined,
              message: 'تعذّر تحميل إعدادات الإشعارات',
              onRetry: () {
                setState(() => _error = null);
                _load();
              },
            )
          : prefs == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
                  children: [
                    const BrandSectionLabel('ما يصلك'),
                    const SizedBox(height: 10),
                    _SwitchCard(
                      icon: Icons.alarm,
                      title: 'قبل المباراة',
                      subtitle:
                          'قبل الإقفال بساعتين إن لم تتوقّع، وقبل الانطلاق '
                          'بنصف ساعة بتوقّعك إن توقّعت.',
                      value: prefs.reminders,
                      onChanged: (v) => _set(reminders: v),
                    ),
                    const SizedBox(height: 10),
                    _SwitchCard(
                      icon: Icons.sports_soccer,
                      title: 'أثناء المباراة',
                      subtitle:
                          'هدفٌ بهدف في مباراة توقّعتها، والنتيجة الجارية '
                          'على شاشة القفل.',
                      value: prefs.live,
                      onChanged: (v) => _set(live: v),
                    ),
                    const SizedBox(height: 10),
                    _SwitchCard(
                      icon: Icons.emoji_events_outlined,
                      title: 'بعد المباراة',
                      subtitle: 'النتيجة وتوقّعك ونقاطك — فور الصافرة.',
                      value: prefs.results,
                      onChanged: (v) => _set(results: v),
                    ),
                    const SizedBox(height: 22),
                    // ملاحظة إذن النظام. بدونها يبقى المستخدم الذي
                    // رفض الإذن يحرّك مفتاحين لا أثر لهما ويظن
                    // التطبيق معطّلاً.
                    BrandCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              size: 18, color: Brand.textMuted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'إن أوقفت إشعارات التطبيق من إعدادات الهاتف '
                              'فلن يصلك شيء مهما كانت هذه المفاتيح.',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.6,
                                color: Brand.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _SwitchCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      child: Row(
        children: [
          Icon(icon, size: 20, color: Brand.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: Brand.textMuted)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
