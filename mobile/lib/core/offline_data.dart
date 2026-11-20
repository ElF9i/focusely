import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import '../features/timer/session_model.dart';
import 'api_client.dart';
import 'local_db.dart';

/// Cache JSON (SQLite) des donnees lues sur le serveur : matieres, historique, stats.
class DataCache {
  DataCache._();
  static final instance = DataCache._();
  Database? _db;

  Future<Database> get _d async => _db ??= await openDatabase(
        '${await getDatabasesPath()}/focusely_cache.db',
        version: 1,
        onCreate: (d, v) => d.execute('CREATE TABLE kv (k TEXT PRIMARY KEY, v TEXT NOT NULL)'),
      );

  Future<void> put(String key, Object json) async {
    final d = await _d;
    await d.insert('kv', {'k': key, 'v': jsonEncode(json)}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<dynamic> get(String key) async {
    final d = await _d;
    final rows = await d.query('kv', where: 'k = ?', whereArgs: [key]);
    return rows.isEmpty ? null : jsonDecode(rows.first['v'] as String);
  }
}

/// GET avec cache : en ligne on met le cache a jour, hors-ligne on relit le cache.
/// S'il n'y a pas encore de cache, l'erreur reseau d'origine est relancee.
Future<dynamic> cachedGet(Dio dio, String path, {Map<String, dynamic>? query, String? cacheKey}) async {
  final uid = await currentUid() ?? 'anon';
  final key = '$uid:${cacheKey ?? path}';
  try {
    final r = await dio.get(path, queryParameters: query);
    try {
      await DataCache.instance.put(key, r.data);
    } catch (_) {
      // un echec du cache ne doit jamais casser l'ecran
    }
    return r.data;
  } catch (e) {
    if (!isOfflineError(e)) rethrow;
    final cached = await DataCache.instance.get(key);
    if (cached == null) rethrow;
    return cached;
  }
}

int _studySeconds(Map<String, Object?> r) {
  final s = DateTime.parse(r['started_at'] as String);
  final e = DateTime.parse(r['ended_at'] as String);
  final v = e.difference(s).inSeconds - (r['paused_seconds'] as int);
  return v < 0 ? 0 : v;
}

/// Seances terminees hors-ligne et pas encore envoyees au serveur.
Future<List<StudySession>> pendingSessions() async {
  final uid = await currentUid();
  if (uid == null) return [];
  final rows = await LocalDb.instance.pending(uid);
  return rows.map((r) {
    final study = _studySeconds(r);
    return StudySession(
      id: r['id'] as String,
      mode: r['mode'] as String,
      subjectId: r['subject_id'] as String?,
      startedAt: DateTime.parse(r['started_at'] as String).toUtc(),
      pausedSeconds: r['paused_seconds'] as int,
      endedAt: DateTime.parse(r['ended_at'] as String).toUtc(),
      targetSeconds: r['target_seconds'] as int?,
      studySeconds: study,
      isValidated: study >= 60,
      serverOffset: Duration.zero,
      local: true,
    );
  }).toList();
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Ajoute aux stats (JSON du serveur) les seances validees en attente d'envoi.
Future<void> addPendingToStats(Map<String, dynamic> j) async {
  final list = (await pendingSessions()).where((s) => s.isValidated).toList();
  if (list.isEmpty) return;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  for (final s in list) {
    final sec = s.studySeconds;
    final l = s.startedAt.toLocal();
    final day = DateTime(l.year, l.month, l.day);
    final age = today.difference(day).inDays;
    if (age == 0) j['todaySeconds'] = (j['todaySeconds'] as int) + sec;
    if (age < 7) j['weekSeconds'] = (j['weekSeconds'] as int) + sec;
    if (age < 30) j['monthSeconds'] = (j['monthSeconds'] as int) + sec;
    j['totalSeconds'] = (j['totalSeconds'] as int) + sec;
    j['sessions'] = (j['sessions'] as int) + 1;
    j['xp'] = (j['xp'] as int) + (sec ~/ 60) * 2 + 10;
    final key = '${l.year}-${_two(l.month)}-${_two(l.day)}';
    for (final d in (j['days'] as List)) {
      if (d['date'] == key) d['seconds'] = (d['seconds'] as int) + sec;
    }
  }
}