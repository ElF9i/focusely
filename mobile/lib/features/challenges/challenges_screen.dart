import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/offline_data.dart';
import '../../core/providers.dart';
import '../../core/sync.dart';
import '../../core/widgets.dart';

final badgesProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  ref.watch(syncProvider.select((s) => s.version));
  final tz = DateTime.now().timeZoneOffset.inMinutes;
  final d = await cachedGet(ref.read(dioProvider), '/api/badges',
      query: {'tz': tz}, cacheKey: 'badges', fallback: <dynamic>[]);
  return List<dynamic>.from(d as List);
});

final challengesProvider = FutureProvider.autoDispose<List<dynamic>>((ref) async {
  ref.watch(syncProvider.select((s) => s.version));
  final d = await cachedGet(ref.read(dioProvider), '/api/challenges',
      cacheKey: 'challenges', fallback: <dynamic>[]);
  return List<dynamic>.from(d as List);
});

final leaderboardProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  ref.watch(syncProvider.select((s) => s.version));
  final tz = DateTime.now().timeZoneOffset.inMinutes;
  final d = await cachedGet(ref.read(dioProvider), '/api/leaderboard/weekly',
      query: {'tz': tz},
      cacheKey: 'leaderboard',
      fallback: <String, dynamic>{'myRank': 0, 'mySeconds': 0, 'entries': <dynamic>[]});
  return Map<String, dynamic>.from(d as Map);
});

final rankingProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final d = await cachedGet(ref.read(dioProvider), '/api/challenges/$id',
      cacheKey: 'challenge:$id', fallback: <String, dynamic>{'ranking': <dynamic>[]});
  return Map<String, dynamic>.from(d as Map);
});

String _netMsg(Object e) =>
    isOfflineError(e) ? 'Il faut du r\u00E9seau pour cette action.' : errorMessage(e);

class ChallengesScreen extends StatelessWidget {
  const ChallengesScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('D\u00E9fis'),
            bottom: const TabBar(tabs: [
              Tab(text: 'D\u00E9fis'),
              Tab(text: 'Badges'),
              Tab(text: 'Classement'),
            ]),
          ),
          body: const TabBarView(children: [_ChallengesTab(), _BadgesTab(), _LeaderboardTab()]),
        ),
      );
}

// ---------------------------------------------------------------- badges
class _BadgesTab extends ConsumerWidget {
  const _BadgesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(badgesProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(errorMessage(e))),
      data: (list) {
        if (list.isEmpty) {
          return const Center(child: Text('Badges indisponibles : ouvre cet onglet une fois en ligne.'));
        }
        final unlocked = list.where((b) => b['unlocked'] == true).length;
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(badgesProvider);
            await ref.read(badgesProvider.future);
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
            Center(
              child: Text('$unlocked / ${list.length} d\u00E9bloqu\u00E9s',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.95,
              children: [for (final b in list) _BadgeTile(b)],
            ),
          ]),
        );
      },
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile(this.b);
  final dynamic b;

  @override
  Widget build(BuildContext context) {
    final on = b['unlocked'] == true;
    final target = b['target'] as int;
    final progress = b['progress'] as int;
    return Opacity(
      opacity: on ? 1 : 0.55,
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(on ? b['emoji'] as String : '\u{1F512}', style: const TextStyle(fontSize: 34)),
          const SizedBox(height: 6),
          Text(b['name'] as String,
              textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(b['description'] as String,
              textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(height: 8),
          if (!on)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: target == 0 ? 0 : progress / target,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.10),
                color: AppColors.accent2,
              ),
            ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- defis
class _ChallengesTab extends ConsumerWidget {
  const _ChallengesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(challengesProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(errorMessage(e))),
      data: (list) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(challengesProvider);
          await ref.read(challengesProvider.future);
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          FilledButton.icon(
            onPressed: () => _create(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Nouveau d\u00E9fi'),
          ),
          const SizedBox(height: 12),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Aucun d\u00E9fi pour le moment. Cr\u00E9e le premier !')),
            ),
          for (final c in list)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: _ChallengeCard(c)),
        ]),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    var type = 'TimeGoal';
    var minutes = 120;
    var hours = 24;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Nouveau d\u00E9fi'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: title,
                maxLength: 40,
                decoration: const InputDecoration(labelText: 'Titre (ex : Semaine d\'examens)'),
              ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'TimeGoal', label: Text('Objectif')),
                  ButtonSegment(value: 'SpeedRace', label: Text('Course')),
                ],
                selected: {type},
                onSelectionChanged: (s) => setS(() => type = s.first),
              ),
              const SizedBox(height: 6),
              Text(
                type == 'TimeGoal'
                    ? 'Atteins le temps d\'\u00E9tude avant la fin du d\u00E9fi.'
                    : 'Le premier \u00E0 atteindre le temps d\'\u00E9tude gagne.',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 14),
              const Text('Temps \u00E0 atteindre'),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                for (final m in const [30, 60, 120, 300, 600])
                  ChoiceChip(
                    label: Text(fmtDur(m * 60)),
                    selected: minutes == m,
                    onSelected: (_) => setS(() => minutes = m),
                  ),
              ]),
              const SizedBox(height: 14),
              const Text('Dur\u00E9e du d\u00E9fi'),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                for (final h in const [(24, '24 h'), (72, '3 jours'), (168, '7 jours')])
                  ChoiceChip(
                    label: Text(h.$2),
                    selected: hours == h.$1,
                    onSelected: (_) => setS(() => hours = h.$1),
                  ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty) return;
                try {
                  await ref.read(dioProvider).post('/api/challenges', data: {
                    'title': title.text.trim(),
                    'type': type,
                    'targetMinutes': minutes,
                    'durationHours': hours,
                  });
                  ref.invalidate(challengesProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(_netMsg(e))));
                  }
                }
              },
              child: const Text('Cr\u00E9er'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChallengeCard extends ConsumerWidget {
  const _ChallengeCard(this.c);
  final dynamic c;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final race = c['type'] == 'SpeedRace';
    final target = c['targetSeconds'] as int;
    final my = c['mySeconds'] as int;
    final joined = c['joined'] == true;
    final active = c['active'] == true;
    final finished = c['finished'] == true;
    final left = DateTime.parse(c['endsAtUtc'] as String).toLocal().difference(DateTime.now());
    final leftText = !active
        ? 'Termin\u00E9'
        : left.inHours >= 24
            ? '${left.inDays} j restants'
            : left.inHours >= 1
                ? '${left.inHours} h restantes'
                : '${left.inMinutes.clamp(0, 59)} min restantes';

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.bg2,
        builder: (_) => _RankingSheet(id: c['id'] as String, title: c['title'] as String),
      ),
      child: GlassCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(c['title'] as String,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            Text(race ? '\u{1F3C1} Course' : '\u{1F3AF} Objectif',
                style: const TextStyle(color: AppColors.accent2, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          Text('${fmtDur(target)}  \u00B7  ${c['participants']} participant(s)  \u00B7  $leftText',
              style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          const SizedBox(height: 10),
          if (joined) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: target == 0 ? 0 : (my / target).clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: Colors.white.withValues(alpha: 0.10),
                color: finished ? AppColors.green : AppColors.accent,
              ),
            ),
            const SizedBox(height: 4),
            Text(finished ? '\u2705 Objectif atteint (${fmtDur(my)})' : '${fmtDur(my)} / ${fmtDur(target)}',
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ] else if (active)
            FilledButton.tonal(onPressed: () => _join(context, ref), child: const Text('Rejoindre')),
        ]),
      ),
    );
  }

  Future<void> _join(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(dioProvider).post('/api/challenges/${c['id']}/join');
      ref.invalidate(challengesProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_netMsg(e))));
      }
    }
  }
}

class _RankingSheet extends ConsumerWidget {
  const _RankingSheet({required this.id, required this.title});
  final String id;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(rankingProvider(id));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Classement', style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 12),
          async.when(
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text(errorMessage(e)),
            data: (d) {
              final list = (d['ranking'] as List?) ?? const [];
              if (list.isEmpty) return const Text('Classement indisponible.');
              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                child: ListView(shrinkWrap: true, children: [
                  for (final r in list)
                    _RankRow(
                      rank: r['rank'] as int,
                      name: r['username'] as String,
                      seconds: r['seconds'] as int,
                      isMe: r['isMe'] == true,
                      done: r['finished'] == true,
                    ),
                ]),
              );
            },
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- classement
class _LeaderboardTab extends ConsumerWidget {
  const _LeaderboardTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(leaderboardProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(errorMessage(e))),
      data: (d) {
        final entries = (d['entries'] as List?) ?? const [];
        final myRank = (d['myRank'] as int?) ?? 0;
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(leaderboardProvider);
            await ref.read(leaderboardProvider.future);
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
            GlassCard(
              child: Row(children: [
                const Text('\u{1F3C5}', style: TextStyle(fontSize: 30)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Cette semaine', style: TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      myRank == 0
                          ? 'Fais une s\u00E9ance pour entrer au classement.'
                          : 'Tu es ${myRank}${myRank == 1 ? 'er' : 'e'}  \u00B7  ${fmtDur((d['mySeconds'] as int?) ?? 0)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Classement vide (ouvre cet onglet une fois en ligne).')),
              ),
            for (final r in entries)
              _RankRow(
                rank: r['rank'] as int,
                name: r['username'] as String,
                seconds: r['seconds'] as int,
                isMe: r['isMe'] == true,
                done: false,
              ),
          ]),
        );
      },
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.rank, required this.name, required this.seconds, required this.isMe, required this.done});
  final int rank;
  final String name;
  final int seconds;
  final bool isMe;
  final bool done;

  @override
  Widget build(BuildContext context) {
    const medals = ['\u{1F947}', '\u{1F948}', '\u{1F949}'];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? AppColors.accent.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        SizedBox(
          width: 34,
          child: Text(rank <= 3 ? medals[rank - 1] : '$rank', style: const TextStyle(fontSize: 18)),
        ),
        Expanded(
          child: Text(isMe ? '$name (toi)' : name,
              style: TextStyle(fontWeight: isMe ? FontWeight.w700 : FontWeight.w500)),
        ),
        if (done) const Padding(padding: EdgeInsets.only(right: 8), child: Text('\u2705')),
        Text(fmtDur(seconds), style: const TextStyle(color: Colors.white70)),
      ]),
    );
  }
}