import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../features/timer/session_model.dart';
import 'api_client.dart';
import 'local_db.dart';

/// Cache JSON (SQLite) : donnees du serveur + file des matieres creees/supprimees hors-ligne.
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

DateTime _offlineUntil = DateTime.fromMillisecondsSinceEpoch(0);

/// GET avec cache. Jamais d'erreur reseau visible : cache, sinon valeur par defaut (fallback).
/// Apres un echec reseau, on ne reessaie pas pendant 15 s (affichage instantane hors-ligne).
Future<dynamic> cachedGet(
  Dio dio,
  String path, {
  Map<String, dynamic>? query,
  String? cacheKey,
  Object? fallback,
  bool preferCache = false,
}) async {
  final uid = await currentUid() ?? 'anon';
  final key = '$uid:${cacheKey ?? path}';
  final cached = await DataCache.instance.get(key);

  if (cached != null) {
    if (preferCache) {
      // affichage immediat, mise a jour du cache en arriere-plan
      unawaited(dio.get(path, queryParameters: query).then((r) => DataCache.instance.put(key, r.data)).catchError((_) {}));
      return cached;
    }
    if (DateTime.now().isBefore(_offlineUntil)) return cached;
  } else if (fallback != null && DateTime.now().isBefore(_offlineUntil)) {
    return fallback;
  }

  try {
    final r = await dio.get(path, queryParameters: query);
    _offlineUntil = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await DataCache.instance.put(key, r.data);
    } catch (_) {}
    return r.data;
  } catch (e) {
    if (!isOfflineError(e)) rethrow;
    _offlineUntil = DateTime.now().add(const Duration(seconds: 15));
    if (cached != null) return cached;
    if (fallback != null) return fallback;
    rethrow;
  }
}

// ---------------------------------------------------------------- matieres hors-ligne
Future<List<Map<String, dynamic>>> loadSubjectOps(String uid) async {
  final raw = await DataCache.instance.get('$uid:subject_ops');
  if (raw is! List) return [];
  return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

Future<void> saveSubjectOps(String uid, List<Map<String, dynamic>> ops) =>
    DataCache.instance.put('$uid:subject_ops', ops);

Future<Map<String, String>> loadSubjectMap(String uid) async {
  final raw = await DataCache.instance.get('$uid:subject_map');
  if (raw is! Map) return {};
  return raw.map((k, v) => MapEntry(k as String, v as String));
}

Future<void> saveSubjectMap(String uid, Map<String, String> m) =>
    DataCache.instance.put('$uid:subject_map', m);

Future<int> subjectOpsCount(String uid) async => (await loadSubjectOps(uid)).length;

Future<void> queueSubjectAdd(String name, String color, String emoji) async {
  final uid = await currentUid();
  if (uid == null) return;
  final ops = await loadSubjectOps(uid);
  ops.add({'op': 'add', 'localId': 'local-${const Uuid().v4()}', 'name': name, 'color': color, 'emoji': emoji});
  await saveSubjectOps(uid, ops);
}

Future<void> queueSubjectDelete(String id) async {
  final uid = await currentUid();
  if (uid == null) return;
  final ops = await loadSubjectOps(uid);
  if (id.startsWith('local-')) {
    final notSentYet = ops.any((o) => o['op'] == 'add' && o['localId'] == id);
    if (notSentYet) {
      ops.removeWhere((o) => o['localId'] == id);
    } else {
      ops.add({'op': 'del', 'localId': id});
    }
  } else if (!ops.any((o) => o['op'] == 'del' && o['id'] == id)) {
    ops.add({'op': 'del', 'id': id});
  }
  await saveSubjectOps(uid, ops);
}

/// Liste du serveur + matieres creees hors-ligne - matieres supprimees hors-ligne.
Future<List<dynamic>> subjectsWithOps(List<dynamic> server) async {
  final uid = await currentUid();
  if (uid == null) return server;
  final ops = await loadSubjectOps(uid);
  if (ops.isEmpty) return server;
  final map = await loadSubjectMap(uid);
  final deletedIds = <dynamic>{};
  final deletedLocal = <dynamic>{};
  for (final o in ops) {
    if (o['op'] != 'del') continue;
    if (o['id'] != null) deletedIds.add(o['id']);
    if (o['localId'] != null) {
      deletedLocal.add(o['localId']);
      final m = map[o['localId']];
      if (m != null) deletedIds.add(m);
    }
  }
  final out = server.where((s) => !deletedIds.contains(s['id'])).toList();
  for (final o in ops) {
    if ((o['op'] == 'add' || o['op'] == 'resolve') && !deletedLocal.contains(o['localId'])) {
      out.add({'id': o['localId'], 'name': o['name'], 'color': o['color'], 'emoji': o['emoji']});
    }
  }
  return out;
}

// ---------------------------------------------------------------- seances en attente
int _studySeconds(Map<String, Object?> r) {
  final s = DateTime.parse(r['started_at'] as String);
  final e = DateTime.parse(r['ended_at'] as String);
  final v = e.difference(s).inSeconds - (r['paused_seconds'] as int);
  return v < 0 ? 0 : v;
}

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

/// Stats a zero (premiere ouverture sans reseau et sans cache).
Map<String, dynamic> emptyStats() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final days = <Map<String, dynamic>>[];
  for (var i = 34; i >= 0; i--) {
    final d = today.subtract(Duration(days: i));
    days.add({'date': '${d.year}-${_two(d.month)}-${_two(d.day)}', 'seconds': 0});
  }
  return {
    'todaySeconds': 0, 'weekSeconds': 0, 'monthSeconds': 0, 'totalSeconds': 0,
    'sessions': 0, 'streak': 0, 'xp': 0, 'level': 1, 'levelXp': 0, 'nextLevelXp': 100,
    'days': days, 'bySubject': <dynamic>[],
  };
}

/// Ajoute aux stats les seances validees pas encore envoyees (temps, XP, serie).
Future<void> addPendingToStats(Map<String, dynamic> j) async {
  final list = (await pendingSessions()).where((s) => s.isValidated).toList();
  if (list.isEmpty) return;
  final todayBefore = j['todaySeconds'] as int;
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
  // la serie compte les jours avec au moins 10 min : si aujourd'hui passe le seuil, +1
  if (todayBefore < 600 && (j['todaySeconds'] as int) >= 600) {
    j['streak'] = (j['streak'] as int) + 1;
  }
}