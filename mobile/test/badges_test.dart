import 'package:flutter_test/flutter_test.dart';
import 'package:focusely/features/profile/badges_logic.dart';
import 'package:focusely/features/timer/session_model.dart';

StudySession _s(DateTime start, int seconds, {String mode = 'Focus', String? subject}) => StudySession(
      id: '${start.microsecondsSinceEpoch}-$seconds-$mode',
      mode: mode,
      subjectId: subject,
      startedAt: start,
      pausedSeconds: 0,
      endedAt: start.add(Duration(seconds: seconds)),
      studySeconds: seconds,
      isValidated: seconds >= 60,
      serverOffset: Duration.zero,
    );

BadgeProgress _b(List<BadgeProgress> l, String key) => l.firstWhere((b) => b.key == key);

void main() {
  test('First Step : debloque apres une seance validee, pas apres une seance trop courte', () {
    expect(_b(computeBadges([_s(DateTime(2026, 11, 20, 10), 1500)]), 'first_step').unlocked, isTrue);
    expect(_b(computeBadges([_s(DateTime(2026, 11, 20, 10), 30)]), 'first_step').unlocked, isFalse);
  });

  test('Night Owl : compte seulement les seances demarrees entre 22h et 5h', () {
    final nights = [for (var i = 1; i <= 5; i++) _s(DateTime(2026, 11, i, 23, 10), 1200)];
    final days = [for (var i = 1; i <= 5; i++) _s(DateTime(2026, 11, i, 14, 0), 1200)];
    expect(_b(computeBadges(nights), 'night_owl').unlocked, isTrue);
    expect(_b(computeBadges(days), 'night_owl').unlocked, isFalse);
    expect(_b(computeBadges(nights.take(4).toList()), 'night_owl').unlocked, isFalse);
  });

  test('Focus Master : 10 heures cumulees', () {
    final ten = [for (var i = 1; i <= 10; i++) _s(DateTime(2026, 11, i, 9), 3600)];
    expect(_b(computeBadges(ten), 'focus_master').unlocked, isTrue);
    expect(_b(computeBadges(ten.take(9).toList()), 'focus_master').unlocked, isFalse);
  });

  test('Serie : jours consecutifs de 10 min minimum', () {
    final now = DateTime(2026, 11, 20, 12);
    final three = [for (final d in [18, 19, 20]) _s(DateTime(2026, 11, d, 10), 700)];
    expect(computeStreak(studyByDay(three), now), 3);
    // aujourd'hui pas encore valide : la serie tient jusqu'a hier
    expect(computeStreak(studyByDay(three.take(2).toList()), now), 2);
    // un trou casse la serie
    final gap = [for (final d in [17, 19, 20]) _s(DateTime(2026, 11, d, 10), 700)];
    expect(computeStreak(studyByDay(gap), now), 2);
    // moins de 10 minutes ne compte pas
    expect(computeStreak(studyByDay([_s(DateTime(2026, 11, 20, 10), 500)]), now), 0);
  });

  test('Consistency : meilleure serie historique de 7 jours', () {
    final week = [for (var d = 1; d <= 7; d++) _s(DateTime(2026, 11, d, 10), 700)];
    expect(_b(computeBadges(week), 'consistency').unlocked, isTrue);
    expect(bestStreak(studyByDay([for (final d in [1, 2, 3, 10, 11]) _s(DateTime(2026, 11, d, 10), 700)])), 3);
  });
}