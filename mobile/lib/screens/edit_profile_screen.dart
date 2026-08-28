// تعديل الملف الشخصي: الصورة والاسم والفريق المفضل.
//
// الحفظ زر واحد لكل الحقول لا حفظ لكل حقل: المستخدم يفتح الشاشة
// ليغيّر شيئاً ثم يخرج، وثلاثة أزرار حفظ تجعله يتساءل أيها ضغط.
// الصورة استثناء — رفعها يحدث فور اختيارها لأن الصورة تُرى نتيجتها
// فوراً وانتظارها زر حفظ يبدو معلقاً.
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../config.dart';
import '../models/profile_stats.dart';
import '../state/session.dart';
import '../widgets/brand_widgets.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name;
  List<FavoriteTeam>? _teams;
  int? _favoriteTeamId;
  bool _saving = false;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = context.read<Session>().user;
    _name = TextEditingController(text: user?.displayName ?? '');
    _favoriteTeamId = user?.favoriteTeamId;
    _loadTeams();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadTeams() async {
    try {
      final teams = await context.read<ApiClient>().teams();
      if (mounted) setState(() => _teams = teams);
    } on ApiException {
      // قائمة الفرق ليست شرطاً لتعديل الاسم: نتركها فارغة بدل أن
      // نمنع الشاشة كلها بسبب طلب ثانوي.
      if (mounted) setState(() => _teams = const []);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2 || name.length > 50) {
      setState(() => _error = 'الاسم يجب أن يكون بين حرفين و50 حرفاً');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final user = await context.read<ApiClient>().updateProfile(
            displayName: name,
            favoriteTeamId: _favoriteTeamId,
          );
      if (!mounted) return;
      context.read<Session>().setUser(user);
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAvatar() async {
    // قبل await المُنتقي: اختيار الصورة قد يطول ويعود المستخدم أثناءه.
    final api = context.read<ApiClient>();
    final session = context.read<Session>();

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // نصغّرها قبل الرفع: حدّ السيرفر 2 ميغابايت، وصورة كاميرا
      // حديثة تتجاوزه وحدها — فيفشل الرفع برسالة تبدو عطلاً.
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final user = await api.uploadAvatar(picked.path);
      session.setUser(user);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removeAvatar() async {
    setState(() => _uploading = true);
    try {
      final user = await context.read<ApiClient>().deleteAvatar();
      if (mounted) context.read<Session>().setUser(user);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<Session>().user;
    final avatarUrl = user?.avatarUrl;

    return Scaffold(
      appBar: AppBar(title: const Text('تعديل الملف الشخصي')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
        children: [
          Center(
            child: Column(
              children: [
                _AvatarPreview(
                  url: avatarUrl,
                  name: user?.nameOrFallback ?? 'م',
                  busy: _uploading,
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _uploading ? null : _pickAvatar,
                      child: const Text('تغيير الصورة'),
                    ),
                    if (avatarUrl != null)
                      TextButton(
                        onPressed: _uploading ? null : _removeAvatar,
                        style: TextButton.styleFrom(
                            foregroundColor: Brand.textFaint),
                        child: const Text('إزالة'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'الاسم الظاهر',
              helperText: 'هذا ما يراه بقية المتنافسين في العرش',
            ),
          ),
          const SizedBox(height: 18),
          const BrandSectionLabel('الفريق المفضل'),
          const SizedBox(height: 10),
          _TeamPicker(
            teams: _teams,
            selected: _favoriteTeamId,
            onChanged: (id) => setState(() => _favoriteTeamId = id),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!,
                style: const TextStyle(color: Brand.wrong, fontSize: 13)),
          ],
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'يُحفظ…' : 'حفظ'),
          ),
        ],
      ),
    );
  }
}

class _AvatarPreview extends StatelessWidget {
  final String? url;
  final String name;
  final bool busy;

  const _AvatarPreview({required this.url, required this.name, this.busy = false});

  @override
  Widget build(BuildContext context) {
    const size = 92.0;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url == null)
            Container(
              decoration:
                  const BoxDecoration(color: Brand.fill, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(
                name.characters.first,
                style: const TextStyle(
                  fontFamily: Brand.displayFont,
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: Brand.textMuted,
                ),
              ),
            )
          else
            ClipOval(
              child: Image.network(
                AppConfig.absoluteUrl(url!),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: Brand.fill,
                  alignment: Alignment.center,
                  child: const Icon(Icons.person, color: Brand.textFaint),
                ),
              ),
            ),
          if (busy)
            const DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0x99080F0C),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Brand.crown),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// اختيار الفريق: شرائح لا قائمة منسدلة. الفرق ثمانية عشر بشعارات
/// مألوفة، والشريحة تعرض الشعار — أسرع تعرّفاً من قراءة اسم في قائمة.
class _TeamPicker extends StatelessWidget {
  final List<FavoriteTeam>? teams;
  final int? selected;
  final ValueChanged<int?> onChanged;

  const _TeamPicker({
    required this.teams,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final list = teams;
    if (list == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(color: Brand.crown),
        ),
      );
    }
    if (list.isEmpty) {
      return const Text('تعذّر جلب قائمة الفرق',
          style: TextStyle(color: Brand.textFaint, fontSize: 12.5));
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _TeamChip(
          label: 'بلا فريق',
          selected: selected == null,
          onTap: () => onChanged(null),
        ),
        for (final t in list)
          _TeamChip(
            label: t.name,
            logo: t.logoUrl,
            selected: selected == t.id,
            // إعادة الضغط على المختار تلغيه: بلا ذلك لا طريق للرجوع
            // إلى "بلا فريق" غير البحث عن شريحة في أول القائمة.
            onTap: () => onChanged(selected == t.id ? null : t.id),
          ),
      ],
    );
  }
}

class _TeamChip extends StatelessWidget {
  final String label;
  final String? logo;
  final bool selected;
  final VoidCallback onTap;

  const _TeamChip({
    required this.label,
    this.logo,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Brand.crownWash(0.16) : Brand.fill,
      borderRadius: BorderRadius.circular(Brand.radiusChip),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Brand.radiusChip),
            border: Border.all(
              color: selected ? Brand.crownWash(0.45) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (logo != null) ...[
                Image.network(logo!,
                    width: 18,
                    height: 18,
                    errorBuilder: (_, _, _) => const SizedBox.shrink()),
                const SizedBox(width: 7),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? Brand.crown : Brand.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
