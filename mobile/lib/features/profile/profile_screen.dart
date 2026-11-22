import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/settings.dart';
import '../../core/sync.dart';
import '../../core/widgets.dart';
import '../history/history_screen.dart';
import '../timer/session_model.dart';
import 'badges_logic.dart';

IconData _badgeIcon(String key) => switch (key) {
      'first_step' => Icons.directions_walk,
      'focus_master' => Icons.timer,
      'night_owl' => Icons.nightlight_round,
      'consistency' => Icons.local_fire_department,
      'study_champion' => Icons.emoji_events,
      'marathon' => Icons.directions_run,
      'pomodoro_fan' => Icons.hourglass_bottom,
      _ => Icons.palette,
    };

String _num(num n) => n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(1);

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, required this.onLogout});
  final VoidCallback onLogout;

  Future<void> _serverDialog(BuildContext context) async {
    final c = TextEditingController(text: await currentBaseUrl());
    if (!context.mounted) return;
    String? msg;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Adresse du serveur'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: c,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: 'http://192.168.1.14:8080'),
            ),
            if (msg != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(msg!)),
          ]),
          actions: [
            TextButton(
              onPressed: () async {
                final ok = await pingServer(c.text.trim().replaceAll(RegExp(r'/+$'), ''));
                setS(() => msg = ok ? 'Serveur joignable ✓' : 'Serveur injoignable ✗');
              },
              child: const Text('Tester'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                await storage.write(key: 'server_url', value: c.text.trim().replaceAll(RegExp(r'/+$'), ''));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text('Les séances en attente restent sur le téléphone et seront envoyées à ta prochaine connexion.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Déconnexion')),
        ],
      ),
    );
    if (ok == true) onLogout();
  }

  Widget _badge(BadgeProgress b) {
    final color = b.unlocked ? AppColors.warm : Colors.white38;
    return Opacity(
      opacity: b.unlocked ? 1 : 0.7,
      child: GlassCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(_badgeIcon(b.key), color: color, size: 26),
            const Spacer(),
            if (b.unlocked) const Icon(Icons.check_circle, color: AppColors.green, size: 18),
          ]),
          const SizedBox(height: 8),
          Text(b.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(b.description,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: Colors.white60)),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: b.ratio,
              minHeight: 6,
              backgroundColor: Colors.white12,
              color: b.unlocked ? AppColors.green : AppColors.accent,
            ),
          ),
          const SizedBox(height: 4),
          Text('${_num(b.current > b.target ? b.target : b.current)} / ${_num(b.target)}',
              style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider).maybeWhen(data: (d) => d, orElse: () => <StudySession>[]);
    final goal = ref.watch(dailyGoalProvider);
    final now = DateTime.now();
    final byDay = studyByDay(history);
    final todaySec = byDay[dayKey(now)] ?? 0;
    final streak = computeStreak(byDay, now);
    final badges = computeBadges(history, now: now);
    final unlocked = badges.where((b) => b.unlocked).length;
    final ratio = goal == 0 ? 0.0 : (todaySec / (goal * 60)).clamp(0.0, 1.0).toDouble();

    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
          const Text('Profil', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          GlassCard(
            child: Row(children: [
              FocusRing(
                size: 120,
                progress: ratio,
                c1: AppColors.accent,
                c2: AppColors.accent2,
                child: Text('${(ratio * 100).round()}%', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Objectif du jour', style: TextStyle(fontSize: 13, color: Colors.white60)),
                  Text('${fmtDur(todaySec)} / ${fmtDur(goal * 60)}',
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(children: [
                    IconButton.filledTonal(
                      onPressed: () => ref.read(dailyGoalProvider.notifier).set(goal - 10),
                      icon: const Icon(Icons.remove),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: () => ref.read(dailyGoalProvider.notifier).set(goal + 10),
                      icon: const Icon(Icons.add),
                    ),
                  ]),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Row(children: [
              const Icon(Icons.local_fire_department, color: AppColors.warm, size: 30),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  streak == 0 ? 'Étudie 10 min aujourd\'hui pour lancer ta série' : '$streak jour(s) de série',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          Text('Badges ($unlocked/${badges.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.0,
            children: [for (final b in badges) _badge(b)],
          ),
          const SizedBox(height: 20),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Adresse du serveur'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _serverDialog(context),
              ),
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Synchroniser maintenant'),
                onTap: () {
                  ref.read(syncProvider.notifier).syncNow();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Synchronisation lancée')));
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: AppColors.pink),
                title: const Text('Se déconnecter'),
                onTap: () => _confirmLogout(context),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}