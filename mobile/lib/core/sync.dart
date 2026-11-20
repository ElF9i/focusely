import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';
import 'local_db.dart';
import 'offline_data.dart';
import 'providers.dart';

class SyncState {
  const SyncState({this.pending = 0, this.syncing = false, this.offline = false, this.version = 0, this.rejected = 0});
  final int pending;   // seances + matieres en attente d'envoi
  final bool syncing;
  final bool offline;
  final int version;   // +1 a chaque synchro reussie : stats, historique et matieres se rechargent
  final int rejected;  // seances refusees par le serveur (anti-fraude)

  SyncState copyWith({int? pending, bool? syncing, bool? offline, int? version, int? rejected}) => SyncState(
        pending: pending ?? this.pending,
        syncing: syncing ?? this.syncing,
        offline: offline ?? this.offline,
        version: version ?? this.version,
        rejected: rejected ?? this.rejected,
      );
}

/// Envoie les matieres creees/supprimees hors-ligne, dans l'ordre.
Future<({bool offline, bool changed})> _syncSubjects(Dio dio, String uid) async {
  final ops = await loadSubjectOps(uid);
  final map = await loadSubjectMap(uid);
  var changed = false;

  while (ops.isNotEmpty) {
    final op = ops.first;
    try {
      if (op['op'] == 'add') {
        await dio.post('/api/subjects', data: {'name': op['name'], 'color': op['color'], 'emoji': op['emoji']});
        // la matiere existe maintenant sur le serveur : on ne la recree jamais, on cherche juste son id
        ops[0] = {...op, 'op': 'resolve'};
        await saveSubjectOps(uid, ops);
        changed = true;
        continue;
      } else if (op['op'] == 'resolve') {
        final r = await dio.get('/api/subjects');
        final known = map.values.toSet();
        final match = (r.data as List).where((s) => s['name'] == op['name'] && !known.contains(s['id'])).toList();
        if (match.isNotEmpty) map[op['localId'] as String] = match.last['id'] as String;
        await DataCache.instance.put('$uid:/api/subjects', r.data);
        ops.removeAt(0);
        changed = true;
      } else if (op['op'] == 'del') {
        final target = op['id'] ?? map[op['localId']];
        if (target != null) await dio.delete('/api/subjects/$target');
        ops.removeAt(0);
        changed = true;
      } else {
        ops.removeAt(0);
      }
    } on DioException catch (e) {
      if (isOfflineError(e)) return (offline: true, changed: changed);
      final code = e.response?.statusCode;
      if (code == 400 || code == 404 || code == 409) {
        ops.removeAt(0); // refusee ou deja faite : inutile de reessayer
        changed = true;
      } else {
        return (offline: false, changed: changed); // 401, 500... : on garde et on reessaiera
      }
    }
    await saveSubjectOps(uid, ops);
    await saveSubjectMap(uid, map);
  }

  if (changed) {
    try {
      final r = await dio.get('/api/subjects');
      await DataCache.instance.put('$uid:/api/subjects', r.data);
    } on DioException catch (_) {}
  }
  return (offline: false, changed: changed);
}

class SyncController extends Notifier<SyncState> {
  @override
  SyncState build() {
    Future.microtask(refresh);
    return const SyncState();
  }

  Future<void> refresh() async {
    final uid = await currentUid();
    if (uid == null) return;
    final n = await LocalDb.instance.pendingCount(uid) + await subjectOpsCount(uid);
    state = state.copyWith(pending: n);
  }

  void clearRejected() => state = state.copyWith(rejected: 0);

  /// Matieres d'abord (les seances peuvent en dependre), puis seances une par une.
  /// Idempotent cote serveur : meme Id = meme seance.
  Future<void> syncNow() async {
    if (state.syncing) return;
    final uid = await currentUid();
    if (uid == null) return;
    final db = LocalDb.instance;
    final rows = await db.pending(uid);
    final hasOps = (await subjectOpsCount(uid)) > 0;
    if (rows.isEmpty && !hasOps) {
      state = state.copyWith(pending: 0, offline: false);
      return;
    }

    state = state.copyWith(syncing: true);
    final dio = ref.read(dioProvider);
    var ok = 0, rejected = 0;
    var offline = false, changed = false;

    try {
      if (hasOps) {
        final r = await _syncSubjects(dio, uid);
        offline = r.offline;
        changed = r.changed;
      }

      if (!offline) {
        final map = await loadSubjectMap(uid);
        final opsLeft = await loadSubjectOps(uid);
        for (final row in rows) {
          final id = row['id'] as String;
          var sid = row['subject_id'] as String?;
          if (sid != null && sid.startsWith('local-')) {
            final mapped = map[sid];
            if (mapped != null) {
              sid = mapped;
            } else if (opsLeft.any((o) => o['localId'] == sid)) {
              continue; // la matiere n'est pas encore creee sur le serveur : on attend
            } else {
              sid = null; // matiere perdue : la seance est envoyee sans matiere
            }
          }
          try {
            await dio.post('/api/sessions/import', data: {
              'id': id,
              'mode': row['mode'],
              'subjectId': sid,
              'targetSeconds': row['target_seconds'],
              'startedAtUtc': row['started_at'],
              'endedAtUtc': row['ended_at'],
              'pausedSeconds': row['paused_seconds'],
            });
            await db.deletePending(id);
            ok++;
          } on DioException catch (e) {
            if (isOfflineError(e)) {
              offline = true;
              break;
            }
            final code = e.response?.statusCode;
            if (code == 400 || code == 409) {
              await db.deletePending(id); // refusee par le serveur (RG03) : inutile de reessayer
              rejected++;
            } else {
              break; // 401, 500... : on garde la seance et on reessaiera
            }
          }
        }
      }
    } catch (_) {
      // erreur inattendue : on garde tout en file et on reessaiera au prochain passage
    }

    final n = await db.pendingCount(uid) + await subjectOpsCount(uid);
    state = state.copyWith(
      pending: n,
      syncing: false,
      offline: offline,
      version: (ok > 0 || changed) ? state.version + 1 : state.version,
      rejected: state.rejected + rejected,
    );
  }
}

final syncProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);