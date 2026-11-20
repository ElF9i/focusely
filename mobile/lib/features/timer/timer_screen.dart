import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../../core/widgets.dart';
import '../challenges/challenges_screen.dart';
import '../history/history_screen.dart';
import '../stats/stats_screen.dart';
import '../subjects/subjects.dart';
import 'session_model.dart';
import 'timer_controller.dart';

class TimerScreen extends ConsumerStatefulWidget {
  const TimerScreen({super.key, required this.onLogout});
  final VoidCallback onLogout;
  @override
  ConsumerState<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends ConsumerState<TimerScreen> {
  String _mode = 'Focus'; // Focus | Pomodoro | Stopwatch
  int _minutes = 25;
  String? _subjectId;
  String? _notifiedFor;
  DateTime? _breakEnd;
  Timer? _breakTicker;

  static const _focusChoices = [15, 25, 45, 60, 90];
  static const _pomoWork = 25;
  static const _pomoBreak = 5;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _run(() => ref.read(timerProvider.notifier).restore()));
  }

  @override
  void dispose() {
    _breakTicker?.cancel();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  int? get _targetSeconds => switch (_mode) {
        'Focus' => _minutes * 60,
        'Pomodoro' => _pomoWork * 60,
        _ => null,
      };

  Future<void> _start() => _run(() => ref
      .read(timerProvider.notifier)
      .start(mode: _mode, target: _targetSeconds, subjectId: _subjectId));

  Future<void> _finish({bool breakAfter = false}) => _run(() async {
        final done = await ref.read(timerProvider.notifier).stop();
        ref.invalidate(statsProvider);
        ref.invalidate(historyProvider);
        ref.invalidate(challengesProvider);
        ref.invalidate(badgesProvider);
        ref.invalidate(leaderboardProvider);
        if (!mounted) return;
        final xp = (done.studySeconds ~/ 60) * 2 + 10;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(done.isValidated
              ? 'Séance validée : ${done.studySeconds ~/ 60} min  ·  +$xp XP'
              : 'Séance trop courte (< 1 min), non comptabilisée'),
        ));
        if (breakAfter && done.isValidated) _startBreak();
      });

  void _startBreak() {
    _breakEnd = DateTime.now().add(const Duration(minutes: _pomoBreak));
    _breakTicker?.cancel();
    _breakTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (DateTime.now().isAfter(_breakEnd!)) {
        _endBreak(haptic: true);
      } else {
        setState(() {});
      }
    });
    setState(() {});
  }

  void _endBreak({bool haptic = false}) {
    _breakTicker?.cancel();
    _breakEnd = null;
    if (haptic) HapticFeedback.heavyImpact();
    if (mounted) setState(() {});
  }

  Future<void> _onTargetReached(StudySession s) async {
    HapticFeedback.heavyImpact();
    if (!mounted) return;
    final pomo = s.mode == 'Pomodoro';
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Objectif atteint 🎉'),
        content: Text(pomo
            ? 'Bloc Pomodoro terminé. Prends $_pomoBreak minutes de pause ?'
            : 'Tu as atteint ton objectif. Terminer la séance ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'continue'), child: const Text('Continuer')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'finish'),
            child: Text(pomo ? 'Terminer + pause' : 'Terminer'),
          ),
        ],
      ),
    );
    if (res == 'finish') await _finish(breakAfter: pomo);
  }

  (Color, Color) _colorsFor(String mode, bool onBreak) {
    if (onBreak) return (AppColors.green, AppColors.accent2);
    return switch (mode) {
      'Pomodoro' => (AppColors.pink, AppColors.warm),
      'Stopwatch' => (AppColors.accent2, const Color(0xFF4FC3F7)),
      _ => (AppColors.accent, AppColors.accent2),
    };
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<TimerState>(timerProvider, (prev, next) {
      final s = next.session;
      if (s != null &&
          s.targetSeconds != null &&
          !s.isPaused &&
          next.elapsed.inSeconds >= s.targetSeconds! &&
          _notifiedFor != s.id) {
        _notifiedFor = s.id;
        _onTargetReached(s);
      }
    });

    final st = ref.watch(timerProvider);
    final ctrl = ref.read(timerProvider.notifier);
    final s = st.session;
    final subjects = ref.watch(subjectsProvider).maybeWhen(data: (d) => d, orElse: () => const <Subject>[]);
    final stats = ref.watch(statsProvider).maybeWhen(data: (d) => d, orElse: () => null);

    final onBreak = _breakEnd != null;
    final mode = s?.mode ?? _mode;
    final (c1, c2) = _colorsFor(mode, onBreak);
    final curSubject =
        subjects.where((x) => x.id == (s?.subjectId ?? _subjectId)).firstOrNull;

    // ----- valeurs de l'anneau -----
    String timeText;
    double progress;
    String label;
    if (onBreak) {
      final remain = _breakEnd!.difference(DateTime.now()).inSeconds;
      timeText = fmtClock(remain);
      progress = 1 - (remain / (_pomoBreak * 60)).clamp(0.0, 1.0);
      label = 'PAUSE';
    } else {
      final target = s != null ? s.targetSeconds : _targetSeconds;
      final elapsed = st.elapsed.inSeconds;
      if (target != null) {
        final remain = target - elapsed;
        timeText = remain >= 0 ? fmtClock(remain) : '+${fmtClock(-remain)}';
        progress = elapsed / target;
      } else {
        timeText = fmtClock(elapsed);
        progress = s == null || s.isPaused ? 0 : (elapsed % 60) / 60;
      }
      label = s == null
          ? 'PRÊT'
          : s.isPaused
              ? 'EN PAUSE'
              : (curSubject != null ? '${curSubject.emoji} ${curSubject.name}'.toUpperCase() : 'EN COURS');
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(children: [
          // ----- en-tete -----
          Row(children: [
            const Text('Focusely', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (stats != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('🔥 ${stats.streak}   ·   Niv. ${stats.level}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Déconnexion',
              onPressed: () {
                ctrl.clear();
                widget.onLogout();
              },
            ),
          ]),
          const SizedBox(height: 16),

          // ----- choix du mode (avant de demarrer) -----
          if (s == null && !onBreak) ...[
            Wrap(spacing: 8, children: [
              for (final m in const [('Focus', 'Focus'), ('Pomodoro', 'Pomodoro'), ('Stopwatch', 'Chrono')])
                ChoiceChip(
                  label: Text(m.$2),
                  selected: _mode == m.$1,
                  onSelected: (_) => setState(() => _mode = m.$1),
                ),
            ]),
            if (_mode == 'Focus') ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final m in _focusChoices)
                  ChoiceChip(
                    label: Text('$m min'),
                    selected: _minutes == m,
                    onSelected: (_) => setState(() => _minutes = m),
                  ),
              ]),
            ],
            if (_mode == 'Pomodoro')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('25 min de travail · 5 min de pause', style: TextStyle(color: Colors.white70)),
              ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final sub in subjects)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onLongPress: () => _run(() => confirmDeleteSubject(context, ref, sub)),
                      child: ChoiceChip(
                        avatar: CircleAvatar(backgroundColor: sub.colorValue, radius: 6),
                        label: Text('${sub.emoji} ${sub.name}'),
                        selected: _subjectId == sub.id,
                        onSelected: (v) => setState(() => _subjectId = v ? sub.id : null),
                      ),
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Matière'),
                  onPressed: () => showAddSubjectDialog(context, ref),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 24),

          // ----- anneau -----
          FocusRing(
            progress: progress,
            c1: c1,
            c2: c2,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(timeText, style: const TextStyle(fontSize: 54, fontWeight: FontWeight.w200)),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(letterSpacing: 2, fontSize: 12, color: Colors.white70)),
            ]),
          ),
          const SizedBox(height: 32),

          // ----- boutons -----
          if (onBreak)
            OutlinedButton(onPressed: _endBreak, child: const Text('Passer la pause'))
          else if (s == null)
            SizedBox(
              width: 220,
              height: 54,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: c1),
                onPressed: _start,
                child: const Text('Démarrer', style: TextStyle(fontSize: 18)),
              ),
            )
          else
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(
                width: 140,
                height: 50,
                child: s.isPaused
                    ? FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: c1),
                        onPressed: () => _run(ctrl.resume),
                        child: const Text('Reprendre'))
                    : FilledButton.tonal(
                        onPressed: () => _run(ctrl.pause), child: const Text('Pause')),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 140,
                height: 50,
                child: OutlinedButton(
                  onPressed: () => _finish(),
                  child: const Text('Terminer'),
                ),
              ),
            ]),
        ]),
      ),
    );
  }
}
