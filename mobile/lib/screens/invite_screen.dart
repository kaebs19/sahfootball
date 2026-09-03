// شاشة الدعوة — ما يراه من فتح رابط sahfootball.com/join/XXXXXX.
//
// معاينة قبل الانضمام لا انضمام صامت: من ضغط رابطاً في واتساب لا
// يعرف بعدُ ما وراءه، والصورة والاسم والدوري والعدد هي ما يجعله
// يقرّر. والرمز دعوةٌ تسبق سياسة المجلس: بالرمز يدخل مباشرة ولو
// كان المجلس «بموافقة».
//
// تعمل للضيف ولمن لم يسجّل بعد: المعاينة عامة في السيرفر، والزرّ
// يتبدّل إلى «سجّل الدخول للانضمام» — الرابط هو أقوى سبب لإنشاء
// حساب، فلا نضيّعه بشاشة دخول باردة.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../models/group.dart';
import '../state/session.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/group_avatar.dart';
import 'group_screen.dart';

class InviteScreen extends StatefulWidget {
  final String code;
  const InviteScreen({super.key, required this.code});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  InvitePreview? _preview;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final preview = await context.read<ApiClient>().invitePreview(widget.code);
      if (mounted) setState(() => _preview = preview);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _join() async {
    final api = context.read<ApiClient>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final group = await api.joinGroup(widget.code);
      _openGroup(navigator, group);
    } on ApiException catch (e) {
      // عضو بالفعل (409): ليس خطأً — نفتح المجلس.
      final id = _preview?.group.id;
      if (e.statusCode == 409 && id != null) {
        _openGroup(navigator, _preview!.group);
      } else {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// استبدال لا دفع: العودة من المجلس يجب ألا تمرّ بالدعوة ثانيةً.
  void _openGroup(NavigatorState navigator, Group group) {
    navigator.pushReplacement(
      MaterialPageRoute(
        builder: (_) => GroupScreen(groupId: group.id, groupName: group.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final signedIn = session.status == SessionStatus.loggedIn;
    final p = _preview;

    return Scaffold(
      appBar: AppBar(title: const Text('دعوة إلى مجلس')),
      body: _error != null
          ? BrandEmpty(
              icon: Icons.link_off,
              message: _error!,
              onRetry: _load,
            )
          : p == null
              ? const Center(
                  child: CircularProgressIndicator(color: Brand.crown))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                  children: [
                    Center(child: GroupAvatar(group: p.group, size: 96, ringed: true)),
                    const SizedBox(height: 16),
                    Text(
                      p.group.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: Brand.displayFont,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Brand.text,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${p.group.scopeLabel} · ${p.group.membersCount} عضو',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Brand.textMuted,
                        fontSize: 13,
                        fontFeatures: Brand.tabular,
                      ),
                    ),
                    const SizedBox(height: 26),
                    BrandCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ماذا يعني الانضمام؟',
                            style: TextStyle(
                              color: Brand.text,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            p.group.leagueName == null
                                ? 'ترتيبٌ بينك وبين الأعضاء بمجموع نقاطك من كل الدوريات — نفس نقاطك في العرش، بلا حساب جديد.'
                                : 'ترتيبٌ بينك وبين الأعضاء بنقاطك في ${p.group.leagueName} وحده — نفس نقاطك في العرش، بلا حساب جديد.',
                            style: const TextStyle(
                                color: Brand.textMuted, fontSize: 12.5, height: 1.7),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (p.viewerRole.isMember)
                      FilledButton(
                        onPressed: () =>
                            _openGroup(Navigator.of(context), p.group),
                        child: const Text('أنت عضو — افتح المجلس'),
                      )
                    else if (signedIn)
                      FilledButton(
                        onPressed: _busy ? null : _join,
                        child: Text(_busy ? '…' : 'انضم إلى المجلس'),
                      )
                    else
                      FilledButton(
                        // الضيف أو غير المسجّل: شاشة الدخول، والدعوة تبقى
                        // في AppTab حتى يعود فتُفتح من جديد.
                        onPressed: () {
                          Navigator.of(context).pop();
                          session.leaveGuest();
                        },
                        child: const Text('سجّل الدخول للانضمام'),
                      ),
                  ],
                ),
    );
  }
}
