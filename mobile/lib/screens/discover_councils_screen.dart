// المجالس العامة — «فيه مجلس أنضم له؟»
//
// الرمز يفترض أنك تعرف أحداً. هذه الشاشة لمن لا يعرف: مجالس
// مفتوحة يراها الجميع ويدخلها أي أحد بضغطة. الأكثر أعضاءً أولاً
// (ترتيب السيرفر) — مجلسٌ فيه ناس أدعى للانضمام من مجلس فارغ.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../models/group.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/group_avatar.dart';
import 'group_screen.dart';

class DiscoverCouncilsScreen extends StatefulWidget {
  const DiscoverCouncilsScreen({super.key});

  @override
  State<DiscoverCouncilsScreen> createState() => _DiscoverCouncilsScreenState();
}

class _DiscoverCouncilsScreenState extends State<DiscoverCouncilsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Group>? _groups;
  String? _error;
  String? _joiningId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final groups =
          await context.read<ApiClient>().publicGroups(search: _search.text);
      if (mounted) setState(() => _groups = groups);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// تأخير قصير بعد آخر حرف: طلب مع كل ضغطة يغرق السيرفر ويعرض
  /// نتائج متأخرة فوق نتائج أحدث.
  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _join(Group g) async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _joiningId = g.id);
    try {
      final outcome = await api.joinPublicGroup(g.id);
      if (!mounted) return;
      setState(() {
        _groups = _groups
            ?.map((x) => x.id != g.id
                ? x
                : outcome.requested
                    ? x.copyWith(hasRequest: true)
                    : x.copyWith(
                        role: GroupRole.member,
                        membersCount: x.membersCount + 1))
            .toList();
      });
      messenger.showSnackBar(SnackBar(
        content: Text(outcome.requested
            ? 'أُرسل طلبك إلى ${g.name} — بانتظار الموافقة'
            : 'انضممت إلى ${g.name}'),
      ));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _joiningId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return Scaffold(
      appBar: AppBar(title: const Text('المجالس العامة')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'ابحث باسم المجلس',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
            ),
          ),
          Expanded(
            child: _error != null
                ? BrandEmpty(
                    icon: Icons.wifi_off, message: _error!, onRetry: _load)
                : groups == null
                    ? const Center(
                        child: CircularProgressIndicator(color: Brand.crown))
                    : groups.isEmpty
                        ? BrandEmpty(
                            icon: Icons.groups_outlined,
                            message: _search.text.trim().isEmpty
                                ? 'لا مجالس عامة بعد — أنشئ أول مجلس عام'
                                : 'لا مجلس بهذا الاسم',
                            onRefresh: _load,
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            color: Brand.crown,
                            backgroundColor: Brand.surface,
                            child: ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(14, 8, 14, 24),
                              itemCount: groups.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) => _PublicCard(
                                group: groups[i],
                                busy: _joiningId == groups[i].id,
                                onJoin: () => _join(groups[i]),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _PublicCard extends StatelessWidget {
  final Group group;
  final bool busy;
  final VoidCallback onJoin;

  const _PublicCard({
    required this.group,
    required this.busy,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final g = group;
    return BrandCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GroupScreen(groupId: g.id, groupName: g.name),
        ),
      ),
      child: Row(
        children: [
          GroupAvatar(group: g, size: 40),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  g.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: Brand.displayFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Brand.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${g.scopeLabel} · ${g.joinPolicy.label} · ${g.membersCount} عضو',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Brand.textFaint,
                    fontSize: 11.5,
                    fontFeatures: Brand.tabular,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (g.isMember)
            const BrandChip(label: 'عضو', icon: Icons.check)
          else if (g.hasRequest)
            const BrandChip(label: 'بانتظار الموافقة', icon: Icons.schedule)
          else
            SizedBox(
              height: 34,
              child: FilledButton(
                onPressed: busy ? null : onJoin,
                // ثيم التطبيق يجعل الأزرار بعرض الشاشة (minimumSize
                // لانهائي)، وداخل Row ذلك «عرض لانهائي» يفجّر التخطيط
                // بلا أثر مرئي في نسخة الإصدار — فنُصغّر الحدّ هنا.
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(g.joinPolicy == JoinPolicy.approval
                        ? 'اطلب'
                        : 'انضم'),
              ),
            ),
        ],
      ),
    );
  }
}
