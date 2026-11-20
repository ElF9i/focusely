import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/widgets.dart';
import '../subjects/subjects.dart';
import '../../core/sync.dart';
import '../timer/timer_controller.dart';

class DayStat {
  DayStat(this.date, this.seconds);
  final String date;
  final int seconds;
}

class SubjectStat {
  SubjectStat(this.name, this.color, this.emoji, this.seconds);
  final String name, color, emoji;
  final int seconds;
}

class Stats {
  Stats.fromJson(Map<String, dynamic> j)
      : today = j['todaySeconds'],
        week = j['weekSeconds'],
        month = j['monthSeconds'],
        total = j['totalSeconds'],
        sessions = j['sessions'],
        streak = j['streak'],
        xp = j['xp'],
        level = j['level'],
        levelXp = j['levelXp'],
        nextLevelXp = j['nextLevelXp'],
        days = (j['days'] as List).map((d) => DayStat(d['date'], d['seconds'])).toList(),
        bySubject = (j['bySubject'] as List)
            .map((d) => SubjectStat(d['name'], d['color'], d['emoji'], d['seconds']))
            .toList();

  final int today, week, month, total, sessions, streak, xp, level, levelXp, nextLevelXp;
  final List<DayStat> days;
  final List<SubjectStat> bySubject;
}

final statsProvider = FutureProvider.autoDispose<Stats>((ref) async {
  ref.watch(syncProvider.select((s) => s.version));
  final tz = DateTime.now().timeZoneOffset.inMinutes;
  final r = await ref.read(dioProvider).get('/api/stats/dashboard', queryParameters: {'tz': tz});
  return Stats.fromJson(r.data);
});

const _ranks = ['Novice', 'Curieux', 'Appliqué', 'Persévérant', 'Studieux', 'Expert', 'Maître', 'Légende'];

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(statsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Statistiques')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorMessage(e))),
        data: (s) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(statsProvider);
            await ref.read(statsProvider.future);
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
            _LevelCard(s),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _MiniStat('Aujourd\'hui', fmtDur(s.today))),
              const SizedBox(width: 10),
              Expanded(child: _MiniStat('Semaine', fmtDur(s.week))),
              const SizedBox(width: 10),
              Expanded(child: _MiniStat('Mois', fmtDur(s.month))),
            ]),
            const SizedBox(height: 12),
            GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('7 derniers jours', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                _WeekBars(s.days.sublist(s.days.length - 7)),
              ]),
            ),
            const SizedBox(height: 12),
            GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Régularité (35 jours)', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                _Heatmap(s.days),
              ]),
            ),
            const SizedBox(height: 12),
            GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Par matière (30 jours)', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                if (s.bySubject.isEmpty)
                  const Text('Pas encore de séance.', style: TextStyle(color: Colors.white70)),
                for (final b in s.bySubject) _SubjectRow(b, s.bySubject.first.seconds),
              ]),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text('${s.sessions} séances au total  ·  ${fmtDur(s.total)}',
                  style: const TextStyle(color: Colors.white60)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard(this.s);
  final Stats s;

  @override
  Widget build(BuildContext context) {
    final rank = _ranks[(s.level - 1).clamp(0, _ranks.length - 1)];
    final span = s.nextLevelXp - s.levelXp;
    final frac = span <= 0 ? 0.0 : ((s.xp - s.levelXp) / span).clamp(0.0, 1.0);
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Niv. ${s.level}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          Text(rank, style: const TextStyle(color: AppColors.accent2, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('🔥 ${s.streak} j', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: frac,
            minHeight: 10,
            backgroundColor: Colors.white.withValues(alpha: 0.10),
            color: AppColors.accent2,
          ),
        ),
        const SizedBox(height: 6),
        Text('${s.xp - s.levelXp} / $span XP vers le niveau ${s.level + 1}',
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        const Text('Série : 10 min d\'étude par jour. 2 XP par minute + 10 XP par séance.',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
      ]),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        child: Column(children: [
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      );
}

class _WeekBars extends StatelessWidget {
  const _WeekBars(this.days);
  final List<DayStat> days;

  @override
  Widget build(BuildContext context) {
    const letters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    var maxV = 1;
    for (final d in days) {
      if (d.seconds > maxV) maxV = d.seconds;
    }
    return SizedBox(
      height: 150,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < days.length; i++)
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text(days[i].seconds == 0 ? '' : '${days[i].seconds ~/ 60}',
                  style: const TextStyle(fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 4),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: days[i].seconds / maxV),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (_, t, _) => Container(
                  height: 4 + 90 * t,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: days[i].seconds == 0
                        ? null
                        : const LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [AppColors.accent, AppColors.accent2],
                          ),
                    color: days[i].seconds == 0 ? Colors.white.withValues(alpha: 0.10) : null,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(letters[DateTime.parse(days[i].date).weekday - 1],
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: i == days.length - 1 ? FontWeight.w700 : FontWeight.w400,
                      color: i == days.length - 1 ? Colors.white : Colors.white60)),
            ]),
          ),
      ]),
    );
  }
}

class _Heatmap extends StatelessWidget {
  const _Heatmap(this.days);
  final List<DayStat> days;

  Color _color(int seconds) {
    if (seconds <= 0) return Colors.white.withValues(alpha: 0.07);
    final a = seconds < 900 ? 0.30 : seconds < 2700 ? 0.50 : seconds < 5400 ? 0.75 : 1.0;
    return AppColors.accent2.withValues(alpha: a);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      for (var row = 0; row < 5; row++)
        Row(children: [
          for (var col = 0; col < 7; col++)
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: _color(days[row * 7 + col].seconds),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
        ]),
    ]);
  }
}

class _SubjectRow extends StatelessWidget {
  const _SubjectRow(this.b, this.maxSeconds);
  final SubjectStat b;
  final int maxSeconds;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Text(b.emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(b.name)),
                Text(fmtDur(b.seconds), style: const TextStyle(color: Colors.white70)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: maxSeconds == 0 ? 0 : b.seconds / maxSeconds,
                  minHeight: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  color: hexColor(b.color),
                ),
              ),
            ]),
          ),
        ]),
      );
}


