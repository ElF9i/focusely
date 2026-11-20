import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/api_client.dart';
import '../../core/local_db.dart';
import '../../core/providers.dart';
import '../../core/sync.dart';
import 'session_model.dart';

export '../../core/providers.dart';

class TimerState {
  final StudySession? session;
  final Duration elapsed;
  const TimerState({this.session, this.elapsed = Duration.zero});
}

class TimerController extends Notifier<TimerState> {
  Timer? _ticker;

  @override
  TimerState build() {
    ref.onDispose(() => _ticker?.cancel());
    return const TimerState();
  }

  Dio get _dio => ref.read(dioProvider);

  DateTime _now(StudySession s) => DateTime.now().toUtc().add(s.serverOffset);

  Future<void> _persist(StudySession s) async {
    final uid = await currentUid();
    if (uid != null) await LocalDb.instance.saveActive(uid, jsonEncode(s.toLocalJson()));
  }

  Future<void> _clearActive() async {
    final uid = await currentUid();
    if (uid != null) await LocalDb.instance.clearActive(uid);
  }

  // Recuperer une seance apres redemarrage de l'app (hors-ligne d'abord, puis serveur)
  Future<void> restore() async {
    final uid = await currentUid();
    if (uid != null) {
      final raw = await LocalDb.instance.loadActive(uid);
      if (raw != null) {
        _set(StudySession.fromLocalJson(jsonDecode(raw)));
        return;
      }
    }
    try {
      final r = await _dio.get('/api/sessions/active');
      if (r.statusCode == 200 && r.data is Map<String, dynamic>) {
        _set(StudySession.fromJson(r.data));
      }
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
    }
  }

  Future<void> start({String mode = 'Focus', int? target, String? subjectId}) async {
    final id = const Uuid().v4(); // genere cote client : sert d'identifiant d'idempotence
    try {
      final r = await _dio.post('/api/sessions/start', data: {
        'id': id,
        'mode': mode,
        'targetSeconds': target,
        'subjectId': subjectId,
      });
      _set(StudySession.fromJson(r.data));
    } catch (e) {
      if (!isOfflineError(e)) rethrow;
      // Pas de reseau : on demarre la seance sur le telephone
      final s = StudySession(
        id: id, mode: mode, subjectId: subjectId,
        startedAt: DateTime.now().toUtc(), pausedSeconds: 0, targetSeconds: target,
        studySeconds: 0, isValidated: false, serverOffset: Duration.zero, local: true,
      );
      await _persist(s);
      _set(s);
    }
  }

  Future<void> pause() async {
    final cur = state.session;
    if (cur == null) return;
    if (!cur.local) {
      try {
        _set(StudySession.fromJson((await _dio.post('/api/sessions/pause')).data));
        return;
      } catch (e) {
        if (!isOfflineError(e)) rethrow;
      }
    }
    final s = cur.copyWith(pausedAt: _now(cur), local: true);
    await _persist(s);
    _set(s);
  }

  Future<void> resume() async {
    final cur = state.session;
    if (cur == null) return;
    if (!cur.local) {
      try {
        _set(StudySession.fromJson((await _dio.post('/api/sessions/resume')).data));
        return;
      } catch (e) {
        if (!isOfflineError(e)) rethrow;
      }
    }
    final paused = cur.pausedAt;
    if (paused == null) return;
    final s = cur.copyWith(
      clearPaused: true,
      pausedSeconds: cur.pausedSeconds + _now(cur).difference(paused).inSeconds,
      local: true,
    );
    await _persist(s);
    _set(s);
  }

  Future<StudySession> stop() async {
    final cur = state.session;
    if (cur == null) throw StateError('Aucune séance active.');

    if (!cur.local) {
      try {
        final s = StudySession.fromJson((await _dio.post('/api/sessions/stop')).data);
        _ticker?.cancel();
        state = const TimerState();
        return s;
      } catch (e) {
        if (!isOfflineError(e)) rethrow;
      }
    }

    // Arret hors-ligne : on calcule la seance avec les horodatages et on la met en file d'attente
    final end = _now(cur);
    var paused = cur.pausedSeconds;
    if (cur.pausedAt != null) paused += end.difference(cur.pausedAt!).inSeconds;
    final total = end.difference(cur.startedAt).inSeconds;
    final study = (total - paused) < 0 ? 0 : (total - paused);

    final done = StudySession(
      id: cur.id, mode: cur.mode, subjectId: cur.subjectId, startedAt: cur.startedAt,
      pausedSeconds: paused, endedAt: end, targetSeconds: cur.targetSeconds,
      studySeconds: study, isValidated: study >= 60, serverOffset: cur.serverOffset, local: true,
    );

    final uid = await currentUid();
    if (uid != null) {
      await LocalDb.instance.addPending({
        'id': done.id,
        'uid': uid,
        'mode': done.mode,
        'subject_id': done.subjectId,
        'target_seconds': done.targetSeconds,
        'started_at': done.startedAt.toUtc().toIso8601String(),
        'ended_at': end.toUtc().toIso8601String(),
        'paused_seconds': paused,
      });
    }
    await _clearActive();
    _ticker?.cancel();
    state = const TimerState();

    final sync = ref.read(syncProvider.notifier);
    await sync.refresh();
    unawaited(sync.syncNow()); // reessaie tout de suite ; sinon plus tard automatiquement
    return done;
  }

  void clear() {
    _ticker?.cancel();
    state = const TimerState();
  }

  void _set(StudySession s) {
    _ticker?.cancel();
    state = TimerState(session: s, elapsed: s.elapsed());
    if (!s.isPaused) {
      // Le ticker ne sert qu'a rafraichir l'affichage ; le temps vient des horodatages
      _ticker = Timer.periodic(const Duration(seconds: 1),
          (_) => state = TimerState(session: s, elapsed: s.elapsed()));
    }
  }
}

final timerProvider = NotifierProvider<TimerController, TimerState>(TimerController.new);
