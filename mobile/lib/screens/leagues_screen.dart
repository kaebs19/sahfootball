// شاشة "دورياتي" — أي الدوريات أتابع؟
//
// المتابعة ليست تفضيلاً بصرياً: عليها تُبنى بطاقات رهان الأبطال،
// وعليها يُقاس نطاق تذكيرات المباريات. ولهذا هي في الإعدادات لا
// مخفيّة في ركن — قرارٌ يغيّر ثلاثة أشياء يجب أن يكون له باب
// معروف.
//
// والحفظ صريح بزرّ لا عند كل ضغطة: القائمة تُبدَّل عدة مرات في
// الجلسة الواحدة، وإرسال كل ضغطة يعني ست رحلات لقرار واحد —
// وتراجعاً غير ممكن إن غيّر رأيه في منتصفها.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/api_client.dart';
import '../brand.dart';
import '../config.dart';
import '../models/champion.dart';

class LeaguesScreen extends StatefulWidget {
  const LeaguesScreen({super.key});

  @override
  State<LeaguesScreen> createState() => _LeaguesScreenState();
}

class _LeaguesScreenState extends State<LeaguesScreen> {
  List<LeagueFollow>? _leagues;
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
      final leagues = await context.read<ApiClient>().leagues();
      if (mounted) setState(() => _leagues = leagues);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _save() async {
    final leagues = _leagues;
    if (leagues == null) return;
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().setFollowedLeagues(
            leagues.where((l) => l.followed).map((l) => l.id).toList(),
          );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final leagues = _leagues;
    return Scaffold(
      appBar: AppBar(title: const Text('دورياتي')),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Brand.textMuted)),
              ),
            )
          : leagues == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(18, 14, 18, 6),
                      child: Text(
                        'توقّعاتك وتذكيراتك ورهانات الأبطال تتبع هذه القائمة.',
                        style:
                            TextStyle(color: Brand.textFaint, fontSize: 12.5),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                        itemCount: leagues.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final l = leagues[i];
                          return _LeagueRow(
                            league: l,
                            onChanged: (v) => setState(
                                () => leagues[i] = l.copyWith(followed: v)),
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _busy ? null : _save,
                            child: _busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Brand.onAccent),
                                  )
                                : const Text('حفظ'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _LeagueRow extends StatelessWidget {
  final LeagueFollow league;
  final ValueChanged<bool> onChanged;

  const _LeagueRow({required this.league, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final on = league.followed;
    return InkWell(
      onTap: () => onChanged(!on),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: on ? Brand.crownWash(0.10) : Brand.fill,
          border: Border.all(color: on ? Brand.crown : Brand.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              on ? Icons.check_box : Icons.check_box_outline_blank,
              color: on ? Brand.crown : Brand.textFaint,
              size: 21,
            ),
            const SizedBox(width: 11),
            if (league.logoUrl != null)
              CachedNetworkImage(
                imageUrl: AppConfig.absoluteUrl(league.logoUrl!),
                width: 26,
                height: 26,
                errorWidget: (_, _, _) =>
                    const Icon(Icons.emoji_events_outlined, size: 22),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                league.name,
                style: TextStyle(
                  color: on ? Brand.text : Brand.textMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
