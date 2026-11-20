class StudySession {
  final String id;
  final String mode;
  final String? subjectId;
  final DateTime startedAt;
  final DateTime? pausedAt;
  final int pausedSeconds;
  final DateTime? endedAt;
  final int? targetSeconds;
  final int studySeconds;
  final bool isValidated;
  final Duration serverOffset; // serveur - telephone (corrige l'horloge)
  final bool local;            // true = seance geree hors-ligne sur le telephone

  StudySession({
    required this.id, required this.mode, this.subjectId, required this.startedAt,
    this.pausedAt, required this.pausedSeconds, this.endedAt, this.targetSeconds,
    required this.studySeconds, required this.isValidated, required this.serverOffset,
    this.local = false,
  });

  factory StudySession.fromJson(Map<String, dynamic> j) {
    final serverNow = DateTime.parse(j['serverNowUtc']).toUtc();
    DateTime? d(String k) => j[k] == null ? null : DateTime.parse(j[k]).toUtc();
    return StudySession(
      id: j['id'], mode: j['mode'], subjectId: j['subjectId'],
      startedAt: DateTime.parse(j['startedAtUtc']).toUtc(),
      pausedAt: d('pausedAtUtc'),
      pausedSeconds: j['pausedSeconds'],
      endedAt: d('endedAtUtc'),
      targetSeconds: j['targetSeconds'],
      studySeconds: j['studySeconds'],
      isValidated: j['isValidated'],
      serverOffset: serverNow.difference(DateTime.now().toUtc()),
    );
  }

  /// Sauvegarde d'une seance hors-ligne en cours (SQLite)
  Map<String, dynamic> toLocalJson() => {
        'id': id,
        'mode': mode,
        'subjectId': subjectId,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'pausedAt': pausedAt?.toUtc().toIso8601String(),
        'pausedSeconds': pausedSeconds,
        'targetSeconds': targetSeconds,
        'offsetMs': serverOffset.inMilliseconds,
      };

  factory StudySession.fromLocalJson(Map<String, dynamic> j) => StudySession(
        id: j['id'],
        mode: j['mode'],
        subjectId: j['subjectId'],
        startedAt: DateTime.parse(j['startedAt']).toUtc(),
        pausedAt: j['pausedAt'] == null ? null : DateTime.parse(j['pausedAt']).toUtc(),
        pausedSeconds: j['pausedSeconds'],
        targetSeconds: j['targetSeconds'],
        studySeconds: 0,
        isValidated: false,
        serverOffset: Duration(milliseconds: j['offsetMs'] ?? 0),
        local: true,
      );

  StudySession copyWith({DateTime? pausedAt, bool clearPaused = false, int? pausedSeconds, bool? local}) =>
      StudySession(
        id: id, mode: mode, subjectId: subjectId, startedAt: startedAt,
        pausedAt: clearPaused ? null : (pausedAt ?? this.pausedAt),
        pausedSeconds: pausedSeconds ?? this.pausedSeconds,
        endedAt: endedAt, targetSeconds: targetSeconds, studySeconds: studySeconds,
        isValidated: isValidated, serverOffset: serverOffset, local: local ?? this.local,
      );

  bool get isPaused => pausedAt != null;

  /// Temps ecoule recalcule a partir des horodatages (jamais un compteur local)
  Duration elapsed() {
    final now = DateTime.now().toUtc().add(serverOffset);
    final end = pausedAt ?? now;
    final d = end.difference(startedAt) - Duration(seconds: pausedSeconds);
    return d.isNegative ? Duration.zero : d;
  }
}
