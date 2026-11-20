import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/widgets.dart';
import '../subjects/subjects.dart';
import '../timer/session_model.dart';
import '../../core/sync.dart';
import '../../core/offline_data.dart';
import '../timer/timer_controller.dart';

final historyProvider = FutureProvider.autoDispose<List<StudySession>>((ref) async {
  ref.watch(syncProvider.select((s) => s.version));
  ref.watch(syncProvider.select((s) => s.pending));
  final data = await cachedGet(ref.read(dioProvider), '/api/sessions/history');
  final server = (data as List).map((j) => StudySession.fromJson(j)).toList();
  final ids = server.map((s) => s.id).toSet();
  // seances faites hors-ligne, pas encore envoyees : on les affiche quand meme
  final waiting = (await pendingSessions()).where((s) => !ids.contains(s.id)).toList();
  final all = [...waiting, ...server];
  all.sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return all;
});

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(historyProvider);
    final subjects = ref.watch(subjectsProvider).maybeWhen(data: (d) => d, orElse: () => const <Subject>[]);
    const modes = {'Focus': 'Focus', 'Pomodoro': 'Pomodoro', 'Stopwatch': 'Chrono'};

    return Scaffold(
      appBar: AppBar(title: const Text('Historique')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorMessage(e))),
        data: (list) => list.isEmpty
            ? const Center(child: Text('Aucune séance pour le moment'))
            : RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(historyProvider);
                  await ref.read(historyProvider.future);
                },
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final s = list[i];
                    final local = s.startedAt.toLocal();
                    final sub = subjects.where((x) => x.id == s.subjectId).firstOrNull;
                    String two(int n) => n.toString().padLeft(2, '0');
                    return GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(children: [
                        CircleAvatar(
                          backgroundColor: (sub?.colorValue ?? Colors.grey).withValues(alpha: 0.25),
                          child: Text(sub?.emoji ?? '📚'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${s.studySeconds ~/ 60} min ${s.studySeconds % 60} s  ·  ${sub?.name ?? 'Sans matière'}',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}  ·  ${modes[s.mode] ?? s.mode}',
                              style: const TextStyle(color: Colors.white60, fontSize: 12),
                            ),
                          ]),
                        ),
                        Icon(s.isValidated ? Icons.check_circle : Icons.cancel_outlined,
                            color: s.isValidated ? AppColors.green : Colors.white38),
                      ]),
                    );
                  },
                ),
              ),
      ),
    );
  }
}


