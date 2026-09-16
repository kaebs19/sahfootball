// «فريقي» — لعبة الفانتازي: تشكيلتك ونقاطك وعرشها.
//
// لعبةٌ ثانية لا شاشةٌ ثالثة (راجع FANTASY.md): التوقّعات تسأل
// «كم ستنتهي المباراة؟» وهذه تسأل «من سيلعب جيداً؟». ولهذا
// نقاطها وعرشها منفصلان تماماً.
//
// ثلاث شرائح لا ثلاثة تبويبات: كلها عن فريقك، والتنقّل بينها
// يجب ألا يكلّف رحلةً في الشريط السفلي.
//
// وقواعد اللعبة كلها في الخادم: هذه الشاشة لا تعرف أن التشكيلة
// خمسة عشر ولا أن الميزانية مئة — تسأل وتعرض ما يُقال لها. نسخةٌ
// ثانية من الأرقام هنا تعني شاشةً تمنع ما يقبله الخادم.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../format.dart';
import '../models/fantasy.dart';
import '../state/league_filter.dart';
import '../widgets/brand_widgets.dart';
import '../widgets/fantasy_pitch.dart';
import '../widgets/fantasy_market.dart';
import 'leagues_screen.dart';

class FantasyScreen extends StatefulWidget {
  const FantasyScreen({super.key});

  @override
  State<FantasyScreen> createState() => _FantasyScreenState();
}

class _FantasyScreenState extends State<FantasyScreen> {
  int _tab = 0;

  FantasyRules _rules = FantasyRules.fallback;
  List<FantasyPlayer> _squad = [];
  List<FantasyPlayer> _market = [];
  String _formation = '4-4-2';
  int? _clubTeamId;
  int _totalPoints = 0;

  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  bool _followRequired = false;
  String? _error;

  // نقاط الجولة والعرش — تُجلبان عند فتح شريحتهما لا مع الشاشة:
  // معظم الزيارات لبناء التشكيلة، وثلاثة طلبات في كل فتحة تكلّف
  // شبكةً وبطارية بلا أن يراها أحد.
  ({String? round, int total, List<FantasyRoundRow> rows})? _round;
  List<FantasyRankRow>? _ranks;

  LeagueFilter get _filter => context.read<LeagueFilter>();
  int? get _leagueId => _filter.selected ?? _filter.followed.firstOrNull?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _filter.load();
      if (!mounted) return;
      final api = context.read<ApiClient>();
      final results = await Future.wait([
        api.fantasySquad(leagueId: _leagueId),
        api.fantasyMarket(leagueId: _leagueId),
      ]);
      if (!mounted) return;

      final squad = results[0]
          as ({FantasySquad? squad, FantasyRules rules, bool followRequired});
      final market = results[1] as FantasyMarket;

      setState(() {
        _rules = market.rules;
        _market = market.players;
        _followRequired = squad.followRequired || market.followRequired;
        _squad = squad.squad?.players ?? [];
        _formation = squad.squad?.formation ?? '4-4-2';
        _clubTeamId = squad.squad?.clubTeamId;
        _totalPoints = squad.squad?.totalPoints ?? 0;
        _dirty = false;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => (_error = e.message, _loading = false));
    }
  }

  // ── تعديل التشكيلة ────────────────────────────────────────────

  /// اختيار لاعب لخانة: يستبدل من فيها أو يضيف إليها.
  ///
  /// الاستبدال لا الإضافة ثم الحذف: الثانية تمرّ بحالة فيها ستة
  /// عشر لاعباً، وكل فحصٍ يجري عليها يفشل.
  void _assign(PitchSlot slot, FantasyPlayer picked, {bool onBench = false}) {
    setState(() {
      final next = [..._squad];
      // من كان في الخانة يخرج، ومن اختير يدخل بمكانه ورايتيه.
      final outgoing = slot.player;
      if (outgoing != null) {
        final was = next.firstWhere((p) => p.id == outgoing.id);
        next.removeWhere((p) => p.id == outgoing.id);
        next.add(picked.copyWith(
          onBench: onBench,
          isCaptain: was.isCaptain,
          isVice: was.isVice,
        ));
      } else {
        next.add(picked.copyWith(onBench: onBench));
      }
      _squad = next;
      _dirty = true;
    });
  }

  void _setCaptain(FantasyPlayer player, {required bool vice}) {
    setState(() {
      _squad = _squad.map((p) {
        if (p.id == player.id) {
          return p.copyWith(isCaptain: !vice, isVice: vice);
        }
        // الرايتان تُنزعان من الجميع أولاً: كابتنان أو نائبان
        // ترفضهما القاعدة بفهرس فريد، والرفض يصل بعد الحفظ —
        // متأخراً جداً عن اللحظة التي أخطأ فيها.
        return p.copyWith(
          isCaptain: vice ? p.isCaptain && p.id != player.id : false,
          isVice: vice ? false : p.isVice && p.id != player.id,
        );
      }).toList();
      _dirty = true;
    });
  }

  void _toggleBench(FantasyPlayer player) {
    setState(() {
      _squad = _squad
          .map((p) => p.id == player.id
              ? p.copyWith(
                  onBench: !p.onBench,
                  // من ينزل الدكّة يفقد الشارة: كابتنٌ على الدكّة
                  // لا يضاعف شيئاً، وتركها له وعدٌ كاذب.
                  isCaptain: p.onBench ? p.isCaptain : false,
                  isVice: p.onBench ? p.isVice : false,
                )
              : p)
          .toList();
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final league = _leagueId;
    if (league == null) return;
    setState(() => _saving = true);
    try {
      final squad = await context.read<ApiClient>().saveFantasySquad(
            leagueId: league,
            formation: _formation,
            clubTeamId: _clubTeamId,
            players: _squad,
          );
      if (!mounted) return;
      setState(() {
        _squad = squad.players;
        _formation = squad.formation;
        _saving = false;
        _dirty = false;
      });
      _say('حُفظت تشكيلتك.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      // رسالة الخادم تُعرض كما هي: هو من يعرف القاعدة المكسورة،
      // وترجمتها هنا تعني نصّين يفترقان عند أول تعديل في القواعد.
      _say(e.message, error: true);
    }
  }

  void _say(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Brand.wrong : Brand.surface,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── البناء ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Brand.crown));
    }
    if (_error != null) {
      return BrandEmpty(icon: Icons.wifi_off, message: _error!, onRetry: _load);
    }
    if (_followRequired) {
      return BrandEmpty(
        icon: Icons.emoji_events_outlined,
        message: 'تابِع دورياً أولاً — تشكيلتك تُبنى من لاعبيه.',
        onRetry: () async {
          await Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const LeaguesScreen()));
          if (mounted) _load();
        },
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: BrandSegmented(
            labels: const ['تشكيلتي', 'نقاط الجولة', 'العرش'],
            selected: _tab,
            onChanged: (i) {
              setState(() => _tab = i);
              if (i == 1 && _round == null) _loadRound();
              if (i == 2 && _ranks == null) _loadRanks();
            },
          ),
        ),
        Expanded(
          child: switch (_tab) {
            0 => _buildSquad(),
            1 => _buildRound(),
            _ => _buildRanks(),
          },
        ),
      ],
    );
  }

  Future<void> _loadRound() async {
    try {
      final r = await context.read<ApiClient>().fantasyRound(leagueId: _leagueId);
      if (mounted) setState(() => _round = r);
    } on ApiException catch (e) {
      if (mounted) _say(e.message, error: true);
    }
  }

  Future<void> _loadRanks() async {
    try {
      final r =
          await context.read<ApiClient>().fantasyLeaderboard(leagueId: _leagueId);
      if (mounted) setState(() => _ranks = r);
    } on ApiException catch (e) {
      if (mounted) _say(e.message, error: true);
    }
  }

  // ── شريحة التشكيلة ────────────────────────────────────────────

  double get _spent =>
      _squad.fold<double>(0, (sum, p) => sum + p.price);

  Widget _buildSquad() {
    final starters = _squad.where((p) => !p.onBench).toList();
    final bench = _squad.where((p) => p.onBench).toList();
    final lines = pitchLines(_formation, starters);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      children: [
        _HeaderStats(
          spent: _spent,
          budget: _rules.budget,
          picked: _squad.length,
          size: _rules.squadSize,
          totalPoints: _totalPoints,
        ),
        const SizedBox(height: 10),
        _FormationPicker(
          formations: _rules.formations,
          selected: _formation,
          onChanged: (f) => setState(() {
            _formation = f;
            _dirty = true;
          }),
        ),
        const SizedBox(height: 10),
        FantasyPitch(lines: lines, onTapSlot: _onTapSlot),
        const SizedBox(height: 16),
        const BrandSectionLabel('الدكّة'),
        const SizedBox(height: 8),
        _BenchRow(
          bench: bench,
          quota: _rules.squadSize - _rules.starters,
          onTap: (p) => p == null ? _pickForBench() : _playerMenu(p),
        ),
        const SizedBox(height: 18),
        _SaveButton(
          enabled: _dirty && !_saving,
          saving: _saving,
          onPressed: _save,
        ),
        const SizedBox(height: 10),
        Text(
          '${_rules.minFromClub} لاعبين على الأقل من فريقك، '
          'و${_rules.maxFromClub} كحدّ أقصى من أي نادٍ.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Brand.textFaint, fontSize: 11.5),
        ),
      ],
    );
  }

  Future<void> _onTapSlot(PitchSlot slot) async {
    // خانةٌ فيها لاعب: القائمة أولاً — الأغلب أنه يريد الكابتن أو
    // الدكّة لا التبديل، والتبديل خيارٌ فيها.
    if (slot.player != null) return _playerMenu(slot.player!);
    await _openMarket(slot, onBench: false);
  }

  Future<void> _pickForBench() async {
    // الدكّة تقبل أي مركز ناقص عن الحصّة — فنفتح السوق بلا تصفية.
    await _openMarket(null, onBench: true);
  }

  Future<void> _openMarket(PitchSlot? slot, {required bool onBench}) async {
    final taken = _squad.map((p) => p.id).toSet();
    final picked = await showFantasyMarket(
      context,
      players: _market,
      position: slot?.position,
      taken: taken,
      budgetLeft: _rules.budget - _spent + (slot?.player?.price ?? 0),
    );
    if (picked != null && mounted) {
      _assign(slot ?? PitchSlot(position: picked.position), picked,
          onBench: onBench);
    }
  }

  Future<void> _playerMenu(FantasyPlayer player) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Brand.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Brand.radiusCardLarge)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Row(
                children: [
                  Text(player.name,
                      style: const TextStyle(
                          color: Brand.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('${player.teamName} · ${player.priceLabel}',
                      style: const TextStyle(color: Brand.textMuted, fontSize: 12)),
                ],
              ),
            ),
            if (!player.onBench) ...[
              _MenuItem(
                icon: Icons.workspace_premium_outlined,
                label: player.isCaptain ? 'هو الكابتن' : 'اجعله الكابتن',
                enabled: !player.isCaptain,
                value: 'captain',
              ),
              _MenuItem(
                icon: Icons.shield_outlined,
                label: player.isVice ? 'هو النائب' : 'اجعله نائب الكابتن',
                enabled: !player.isVice,
                value: 'vice',
              ),
            ],
            _MenuItem(
              icon: player.onBench ? Icons.arrow_upward : Icons.arrow_downward,
              label: player.onBench ? 'أدخله الأساسي' : 'أنزله الدكّة',
              value: 'bench',
            ),
            _MenuItem(
              icon: Icons.swap_horiz,
              label: 'استبدله بلاعب آخر',
              value: 'replace',
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case 'captain':
        _setCaptain(player, vice: false);
      case 'vice':
        _setCaptain(player, vice: true);
      case 'bench':
        _toggleBench(player);
      case 'replace':
        await _openMarket(
          PitchSlot(position: player.position, player: player),
          onBench: player.onBench,
        );
    }
  }

  // ── شريحة نقاط الجولة ─────────────────────────────────────────

  Widget _buildRound() {
    final round = _round;
    if (round == null) {
      return const Center(child: CircularProgressIndicator(color: Brand.crown));
    }
    if (round.rows.isEmpty) {
      return const BrandEmpty(
        icon: Icons.scoreboard_outlined,
        message: 'لا نقاط بعد — تُحتسب حين تنتهي مباريات الجولة.',
      );
    }

    final starters = round.rows.where((r) => !r.onBench).toList();
    final bench = round.rows.where((r) => r.onBench).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      children: [
        BrandCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(Fmt.round(round.round),
                    style: const TextStyle(color: Brand.textMuted, fontSize: 13)),
                const Spacer(),
                BrandNumber(Fmt.number(round.total), color: Brand.crown),
                const SizedBox(width: 6),
                const Text('نقطة',
                    style: TextStyle(color: Brand.textMuted, fontSize: 12)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (final row in [...starters, ...bench])
          _RoundRow(row: row),
      ],
    );
  }

  // ── شريحة العرش ───────────────────────────────────────────────

  Widget _buildRanks() {
    final ranks = _ranks;
    if (ranks == null) {
      return const Center(child: CircularProgressIndicator(color: Brand.crown));
    }
    if (ranks.isEmpty) {
      return const BrandEmpty(
        icon: Icons.emoji_events_outlined,
        message: 'لا تشكيلات في هذا الدوري بعد — كن أولهم.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
      itemCount: ranks.length,
      itemBuilder: (_, i) => _RankRow(row: ranks[i]),
    );
  }
}

// ── قطع صغيرة ───────────────────────────────────────────────────

class _HeaderStats extends StatelessWidget {
  final double spent;
  final double budget;
  final int picked;
  final int size;
  final int totalPoints;

  const _HeaderStats({
    required this.spent,
    required this.budget,
    required this.picked,
    required this.size,
    required this.totalPoints,
  });

  @override
  Widget build(BuildContext context) {
    final left = budget - spent;
    return BrandCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            _Stat(
              // المتبقّي أحمر حين يسلب: تجاوز الميزانية خطأٌ يجب
              // أن يُرى قبل الضغط على «احفظ» لا بعده.
              value: Fmt.number(left, decimals: 1),
              label: 'المتبقّي',
              color: left < 0 ? Brand.wrong : Brand.crown,
            ),
            const _Divider(),
            _Stat(value: '${Fmt.number(picked)}/${Fmt.number(size)}', label: 'اللاعبون'),
            const _Divider(),
            _Stat(value: Fmt.number(totalPoints), label: 'نقاط الموسم'),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final Color? color;
  const _Stat({required this.value, required this.label, this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                  color: color ?? Brand.text,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  fontFamily: Brand.displayFont,
                  fontFeatures: Brand.tabular,
                )),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(color: Brand.textFaint, fontSize: 11)),
          ],
        ),
      );
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 30, color: Brand.borderSoft);
}

class _FormationPicker extends StatelessWidget {
  final List<String> formations;
  final String selected;
  final ValueChanged<String> onChanged;

  const _FormationPicker({
    required this.formations,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: formations.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final f = formations[i];
          // الخطة أرقام لاتينية دائماً (4-4-2) لا عربية: هكذا
          // تُكتب في كل مكان يعرفه متابع الكرة.
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(f),
            child: BrandChip(
              label: f,
              tone: f == selected ? BrandTone.crown : BrandTone.neutral,
              solid: f == selected,
            ),
          );
        },
      ),
    );
  }
}

class _BenchRow extends StatelessWidget {
  final List<FantasyPlayer> bench;
  final int quota;
  final void Function(FantasyPlayer?) onTap;

  const _BenchRow({required this.bench, required this.quota, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var i = 0; i < quota; i++)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i < bench.length ? bench[i] : null),
              child: Column(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Brand.fill,
                      border: Border.all(color: Brand.border),
                    ),
                    child: i < bench.length
                        ? Text(bench[i].position.short,
                            style: const TextStyle(
                                color: Brand.textMuted, fontSize: 11))
                        : const Icon(Icons.add, color: Brand.textFaint, size: 18),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    i < bench.length ? bench[i].name.split(' ').last : 'بديل',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Brand.textFaint, fontSize: 10.5),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _SaveButton extends StatelessWidget {
  final bool enabled;
  final bool saving;
  final VoidCallback onPressed;

  const _SaveButton({
    required this.enabled,
    required this.saving,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: Brand.primaryButton,
          foregroundColor: Brand.onAccent,
          disabledBackgroundColor: Brand.fill,
          disabledForegroundColor: Brand.textFaint,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Brand.radiusChip),
          ),
        ),
        child: saving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Brand.onAccent))
            : Text(enabled ? 'احفظ التشكيلة' : 'محفوظة',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool enabled;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.value,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: enabled ? Brand.text : Brand.textFaint, size: 20),
        title: Text(label,
            style: TextStyle(
                color: enabled ? Brand.text : Brand.textFaint, fontSize: 14)),
        onTap: enabled ? () => Navigator.of(context).pop(value) : null,
      );
}

class _RoundRow extends StatelessWidget {
  final FantasyRoundRow row;
  const _RoundRow({required this.row});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: BrandCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(row.player.position.short,
                    style: const TextStyle(color: Brand.textFaint, fontSize: 11)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(row.player.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Brand.text,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600)),
                        ),
                        if (row.multiplier > 1) ...[
                          const SizedBox(width: 6),
                          const _Badge(text: 'كابتن ×2', color: Brand.crown),
                        ],
                        if (row.autoSubbed) ...[
                          const SizedBox(width: 6),
                          const _Badge(text: 'دخل بديلاً', color: Brand.textMuted),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      row.onBench && !row.autoSubbed
                          ? 'على الدكّة'
                          : row.player.teamName,
                      style: const TextStyle(color: Brand.textFaint, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Text(
                Fmt.number(row.points),
                style: TextStyle(
                  color: row.points > 0
                      ? Brand.crown
                      : row.points < 0
                          ? Brand.wrong
                          : Brand.textFaint,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  fontFamily: Brand.displayFont,
                  fontFeatures: Brand.tabular,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 9.5)),
      );
}

class _RankRow extends StatelessWidget {
  final FantasyRankRow row;
  const _RankRow({required this.row});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: BrandCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(Fmt.number(row.rank),
                    style: TextStyle(
                      color: row.rank <= 3 ? Brand.crown : Brand.textMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontFeatures: Brand.tabular,
                    )),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Brand.text,
                            fontSize: 14,
                            fontWeight:
                                row.isMe ? FontWeight.w700 : FontWeight.w500)),
                    if (row.clubName != null)
                      Text(row.clubName!,
                          style: const TextStyle(
                              color: Brand.textFaint, fontSize: 11)),
                  ],
                ),
              ),
              Text(Fmt.number(row.totalPoints),
                  style: const TextStyle(
                    color: Brand.crown,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFamily: Brand.displayFont,
                    fontFeatures: Brand.tabular,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
