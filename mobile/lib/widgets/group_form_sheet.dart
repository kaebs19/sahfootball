// نموذج المجلس — الاسم، عام أم خاص، وعلى أي دوري.
//
// ورقة واحدة للإنشاء والتعديل معاً: الحقول نفسها والقواعد نفسها
// (السيرفر يفحص الاسم والدوري في create وupdate بنفس الدالتين)،
// ونموذجان متشابهان يتباعدان عند أول حقل يُضاف إلى أحدهما.
//
// ويدجت ذات حالة تملك المتحكّم وتتخلص منه في dispose الخاص بها —
// إنشاؤه في دالة ثم التخلص منه فور عودة الورقة يفجّر التأكيد
// «_dependents.isEmpty» لأن الورقة ما زالت تتحرك خارج الشاشة وحقلها
// حيّ (راجع _PromptDialog في شاشة العرش).
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../config.dart';
import '../models/champion.dart';
import '../models/group.dart';
import 'brand_widgets.dart';

/// ما يعود من الورقة: null لو ألغى المستخدم.
class GroupForm {
  final String name;
  final JoinPolicy joinPolicy;

  /// null = كل الدوريات.
  final int? leagueId;

  const GroupForm({
    required this.name,
    required this.joinPolicy,
    required this.leagueId,
  });
}

class GroupFormSheet extends StatefulWidget {
  final String title;
  final String action;
  final GroupForm? initial;

  const GroupFormSheet({
    super.key,
    required this.title,
    required this.action,
    this.initial,
  });

  static Future<GroupForm?> show(
    BuildContext context, {
    required String title,
    required String action,
    GroupForm? initial,
  }) {
    return showModalBottomSheet<GroupForm>(
      context: context,
      backgroundColor: Brand.surface,
      // الورقة تعلو مع لوحة المفاتيح بدل أن تختفي خلفها.
      isScrollControlled: true,
      builder: (_) =>
          GroupFormSheet(title: title, action: action, initial: initial),
    );
  }

  @override
  State<GroupFormSheet> createState() => _GroupFormSheetState();
}

const _policies = [JoinPolicy.code, JoinPolicy.approval, JoinPolicy.open];

class _GroupFormSheetState extends State<GroupFormSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late JoinPolicy _policy = widget.initial?.joinPolicy ?? JoinPolicy.code;
  late int? _leagueId = widget.initial?.leagueId;
  List<LeagueFollow>? _leagues;
  String? _leaguesError;

  @override
  void initState() {
    super.initState();
    _loadLeagues();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadLeagues() async {
    try {
      // كل دوريات اللعبة لا المتابَعة وحدها: من يؤسّس مجلساً
      // للإسباني قد لا يتابعه هو نفسه بعد.
      final leagues = await context.read<ApiClient>().leagues();
      if (mounted) setState(() => _leagues = leagues);
    } on ApiException catch (e) {
      if (mounted) setState(() => _leaguesError = e.message);
    }
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.length < 2) return;
    Navigator.pop(
      context,
      GroupForm(name: name, joinPolicy: _policy, leagueId: _leagueId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontFamily: Brand.displayFont,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Brand.text,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _name,
                autofocus: widget.initial == null,
                textInputAction: TextInputAction.done,
                maxLength: 50,
                decoration: const InputDecoration(
                  labelText: 'اسم المجلس',
                  hintText: 'مثلاً: شباب الحي',
                  counterText: '',
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 18),
              const BrandSectionLabel('من يدخل؟'),
              const SizedBox(height: 8),
              // ثلاث سياسات بترتيب الانفتاح: بالرمز ← بموافقة ← مفتوح.
              // الرمز يعمل في الثلاث: من معه الرمز مدعوّ، والدعوة تسبق
              // الموافقة.
              BrandSegmented(
                labels: [for (final p in _policies) p.label],
                selected: _policies.indexOf(_policy),
                onChanged: (i) => setState(() => _policy = _policies[i]),
              ),
              const SizedBox(height: 6),
              Text(
                _policy.hint,
                style: const TextStyle(
                    color: Brand.textMuted, fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 18),
              const BrandSectionLabel('على أي دوري؟'),
              const SizedBox(height: 4),
              const Text(
                'يُرتَّب الأعضاء بنقاط هذا الدوري وحده — ومجلس «كل الدوريات» يجمع كل نقاطهم.',
                style: TextStyle(
                    color: Brand.textMuted, fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 10),
              if (_leaguesError != null)
                Text(_leaguesError!,
                    style: const TextStyle(color: Brand.wrong, fontSize: 12))
              else if (_leagues == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Brand.crown),
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _LeagueChip(
                      label: 'كل الدوريات',
                      selected: _leagueId == null,
                      onTap: () => setState(() => _leagueId = null),
                    ),
                    for (final l in _leagues!)
                      _LeagueChip(
                        label: l.name,
                        logoUrl: l.logoUrl,
                        selected: _leagueId == l.id,
                        onTap: () => setState(() => _leagueId = l.id),
                      ),
                  ],
                ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _name,
                      builder: (_, v, _) => FilledButton(
                        onPressed: v.text.trim().length >= 2 ? _submit : null,
                        child: Text(widget.action),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// شريحة دوري بنفس شكل LeagueStrip — ذهبية حين تُختار، لأنها تجيب
/// «أي بيانات؟» لا «أي عرض؟».
class _LeagueChip extends StatelessWidget {
  final String label;
  final String? logoUrl;
  final bool selected;
  final VoidCallback onTap;

  const _LeagueChip({
    required this.label,
    this.logoUrl,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Brand.crown : Brand.fill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? Brand.crown : Brand.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (logoUrl != null) ...[
              CachedNetworkImage(
                imageUrl: AppConfig.absoluteUrl(logoUrl!),
                width: 16,
                height: 16,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Brand.onAccent : Brand.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
