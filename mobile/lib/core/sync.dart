import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';
import 'local_db.dart';
import 'providers.dart';

class SyncState {
  const SyncState({this.pending = 0, this.syncing = false, this.offline = false, this.version = 0, this.rejected = 0});
  final int pending;
  final bool syncing;
  final bool offline;
  final int version;   // +1 a chaque synchro reussie : stats et historique se rechargent
  final int rejected;  // seances refusees par le serveur (anti-fraude)

  SyncState copyWith({int? pending, bool? syncing, bool? offline, int? version, int? rejected}) => SyncState(
        pending: pending ?? this.pending,
        syncing: syncing ?? this.syncing,
        offline: offline ?? this.offline,
        version: version ?? this.version,
        rejected: rejected ?? this.rejected,
      );
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
    final n = await LocalDb.instance.pendingCount(uid);
    state = state.copyWith(pending: n);
  }

  void clearRejected() => state = state.copyWith(rejected: 0);

  /// Envoie les seances en attente, une par une. Idempotent cote serveur (meme Id = meme seance).
  Future<void> syncNow() async {
    if (state.syncing) return;
    final uid = await currentUid();
    if (uid == null) return;
    final db = LocalDb.instance;
    final rows = await db.pending(uid);
    if (rows.isEmpty) {
      state = state.copyWith(pending: 0, offline: false);
      return;
    }

    state = state.copyWith(syncing: true);
    final dio = ref.read(dioProvider);
    var ok = 0, rejected = 0;
    var offline = false;

    for (final row in rows) {
      final id = row['id'] as String;
      try {
        await dio.post('/api/sessions/import', data: {
          'id': id,
          'mode': row['mode'],
          'subjectId': row['subject_id'],
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

    final n = await db.pendingCount(uid);
    state = state.copyWith(
      pending: n,
      syncing: false,
      offline: offline,
      version: ok > 0 ? state.version + 1 : state.version,
      rejected: state.rejected + rejected,
    );
  }
}

final syncProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);
