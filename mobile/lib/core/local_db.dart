import 'package:sqflite/sqflite.dart';

/// Base locale : seances terminees hors-ligne (file d'attente) + seance hors-ligne en cours.
class LocalDb {
  LocalDb._();
  static final instance = LocalDb._();
  Database? _db;

  Future<Database> get db async => _db ??= await openDatabase(
        '${await getDatabasesPath()}/focusely.db',
        version: 1,
        onCreate: (d, v) async {
          await d.execute('CREATE TABLE pending_sessions ('
              'id TEXT PRIMARY KEY, uid TEXT NOT NULL, mode TEXT NOT NULL, subject_id TEXT, '
              'target_seconds INTEGER, started_at TEXT NOT NULL, ended_at TEXT NOT NULL, '
              'paused_seconds INTEGER NOT NULL)');
          await d.execute('CREATE TABLE local_active (uid TEXT PRIMARY KEY, json TEXT NOT NULL)');
        },
      );

  // ----- file d'attente -----
  Future<void> addPending(Map<String, Object?> row) async {
    final d = await db;
    // REPLACE : l'id de la seance est la cle => jamais deux fois la meme seance dans la file
    await d.insert('pending_sessions', row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> pending(String uid) async {
    final d = await db;
    return d.query('pending_sessions', where: 'uid = ?', whereArgs: [uid], orderBy: 'started_at ASC');
  }

  Future<void> deletePending(String id) async {
    final d = await db;
    await d.delete('pending_sessions', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> pendingCount(String uid) async {
    final d = await db;
    return Sqflite.firstIntValue(
            await d.rawQuery('SELECT COUNT(*) FROM pending_sessions WHERE uid = ?', [uid])) ??
        0;
  }

  // ----- seance hors-ligne en cours (survit a un redemarrage de l'app) -----
  Future<void> saveActive(String uid, String json) async {
    final d = await db;
    await d.insert('local_active', {'uid': uid, 'json': json}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> loadActive(String uid) async {
    final d = await db;
    final rows = await d.query('local_active', where: 'uid = ?', whereArgs: [uid]);
    return rows.isEmpty ? null : rows.first['json'] as String;
  }

  Future<void> clearActive(String uid) async {
    final d = await db;
    await d.delete('local_active', where: 'uid = ?', whereArgs: [uid]);
  }
}
