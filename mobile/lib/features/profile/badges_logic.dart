import '../timer/session_model.dart';

/// Logique pure (sans Flutter) : series de jours et badges, calcules a partir des seances.
const streakThresholdSeconds = 600; // 10 min d'etude = jour valide (RG05)

String dayKey(DateTime d) {
  final l = d.toLocal();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
}

bool isNightStart(DateTime d) {
  final h = d.toLocal().hour;
  return h >= 22 || h < 5;
}

/// Secondes d'etude validees par jour (date locale).
Map<String, int> studyByDay(List<StudySession> sessions) {
  final m = <String, int>{};
  for (final s in sessions) {
    if (!s.isValidated) continue;
    final k = dayKey(s.startedAt);
    m[k] = (m[k] ?? 0) + s.studySeconds;
  }
  return m;
}

/// Serie en cours : si aujourd'hui n'est pas encore valide, elle reste vivante jusqu'a hier.
int computeStreak(Map<String, int> byDay, DateTime now) {
  var day = DateTime(now.year, now.month, now.day);
  if ((byDay[dayKey(day)] ?? 0) < streakThresholdSeconds) {
    day = DateTime(day.year, day.month, day.day - 1);
  }
  var n = 0;
  while ((byDay[dayKey(day)] ?? 0) >= streakThresholdSeconds) {
    n++;
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return n;
}

/// Meilleure serie jamais atteinte (sert a debloquer Consistency pour de bon).
int bestStreak(Map<String, int> byDay) {
  final days = byDay.entries.where((e) => e.value >= streakThresholdSeconds).map((e) {
    final p = e.key.split('-');
    return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }).toList()
    ..sort();
  var best = 0, run = 0;
  DateTime? prev;
  for (final d in days) {
    run = (prev != null && d.difference(prev).inDays == 1) ? run + 1 : 1;
    if (run > best) best = run;
    prev = d;
  }
  return best;
}

class BadgeProgress {
  const BadgeProgress(this.key, this.name, this.description, this.current, this.target);
  final String key, name, description;
  final num current;
  final num target;

  bool get unlocked => current >= target;
  double get ratio => target == 0 ? 1.0 : (current / target).clamp(0.0, 1.0).toDouble();
}

List<BadgeProgress> computeBadges(List<StudySession> sessions, {DateTime? now}) {
  final valid = sessions.where((s) => s.isValidated).toList();
  final totalSeconds = valid.fold<int>(0, (a, s) => a + s.studySeconds);
  final hours = totalSeconds / 3600;
  final night = valid.where((s) => isNightStart(s.startedAt)).length;
  final pomodoros = valid.where((s) => s.mode.toLowerCase() == 'pomodoro').length;
  final longestMin = valid.fold<int>(0, (a, s) => s.studySeconds > a ? s.studySeconds : a) / 60;
  final subjects = valid.map((s) => s.subjectId).whereType<String>().toSet().length;
  final best = bestStreak(studyByDay(sessions));

  return [
    BadgeProgress('first_step', 'First Step', 'Termine ta première séance', valid.length, 1),
    BadgeProgress('focus_master', 'Focus Master', '10 heures d\'étude au total', hours, 10),
    BadgeProgress('night_owl', 'Night Owl', '5 séances nocturnes (22h–5h)', night, 5),
    BadgeProgress('consistency', 'Consistency', '7 jours consécutifs', best, 7),
    BadgeProgress('study_champion', 'Study Champion', '100 heures d\'étude', hours, 100),
    BadgeProgress('marathon', 'Marathon', 'Une séance de 2 heures', longestMin, 120),
    BadgeProgress('pomodoro_fan', 'Pomodoro Fan', '10 séances Pomodoro', pomodoros, 10),
    BadgeProgress('polyvalent', 'Polyvalent', '3 matières différentes étudiées', subjects, 3),
  ];
}