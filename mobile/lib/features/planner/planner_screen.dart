import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/api_client.dart';
import '../../core/offline_data.dart';
import '../../core/widgets.dart';
import '../history/history_screen.dart';
import '../subjects/subjects.dart';
import '../timer/session_model.dart';
import '../timer/timer_controller.dart';

// ------------------------------------------------------------------ donnees
class Task {
  Task({
    required this.id,
    required this.title,
    this.subjectId,
    this.due,
    this.allDay = true,
    this.estimateMin = 25,
    this.priority = 1,
    this.done = false,
  });

  final String id, title;
  final String? subjectId;
  final DateTime? due;      // echeance (23h59 si "toute la journee")
  final bool allDay;
  final int estimateMin;
  final int priority;       // 0 basse, 1 normale, 2 haute
  final bool done;

  Task copyWith({bool? done}) => Task(
        id: id, title: title, subjectId: subjectId, due: due, allDay: allDay,
        estimateMin: estimateMin, priority: priority, done: done ?? this.done,
      );

  bool isOverdue(DateTime now) => !done && due != null && due!.isBefore(now);

  Map<String, dynamic> toJson() => {
        'id': id, 'title': title, 'subjectId': subjectId, 'due': due?.toIso8601String(),
        'allDay': allDay, 'estimateMin': estimateMin, 'priority': priority, 'done': done,
      };

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'],
        title: j['title'],
        subjectId: j['subjectId'],
        due: j['due'] == null ? null : DateTime.parse(j['due']),
        allDay: j['allDay'] ?? true,
        estimateMin: j['estimateMin'] ?? 25,
        priority: j['priority'] ?? 1,
        done: j['done'] ?? false,
      );
}

/// Taches stockees sur le telephone (SQLite) : le planificateur marche toujours hors-ligne.
class TasksController extends Notifier<List<Task>> {
  @override
  List<Task> build() {
    Future.microtask(reload);
    return const [];
  }

  Future<String> _prefix() async => await currentUid() ?? 'anon';

  Future<void> reload() async {
    final raw = await DataCache.instance.get('${await _prefix()}:tasks');
    state = raw is List ? raw.map((e) => Task.fromJson(Map<String, dynamic>.from(e as Map))).toList() : <Task>[];
  }

  Future<void> _save() async =>
      DataCache.instance.put('${await _prefix()}:tasks', state.map((t) => t.toJson()).toList());

  Future<void> add(Task t) async {
    state = [...state, t];
    await _save();
  }

  Future<void> toggle(String id) async {
    state = [for (final t in state) t.id == id ? t.copyWith(done: !t.done) : t];
    await _save();
  }

  Future<void> remove(String id) async {
    state = state.where((t) => t.id != id).toList();
    await _save();
  }

  /// Associe une seance a une tache (le temps etudie s'affiche sur la tache).
  Future<void> linkSession(String sessionId, String taskId) async {
    final key = '${await _prefix()}:task_links';
    final raw = await DataCache.instance.get(key);
    final m = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    m[sessionId] = taskId;
    await DataCache.instance.put(key, m);
  }
}

final tasksProvider = NotifierProvider<TasksController, List<Task>>(TasksController.new);

final taskLinksProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final raw = await DataCache.instance.get('${await currentUid() ?? 'anon'}:task_links');
  if (raw is! Map) return <String, String>{};
  return raw.map((k, v) => MapEntry(k as String, v as String));
});

// ------------------------------------------------------------------ outils dates
DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));
bool _same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';

const _months = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
];
const _weekdays = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

int _byTime(Task a, Task b) {
  if (a.done != b.done) return a.done ? 1 : -1;
  return a.due!.compareTo(b.due!);
}

// ------------------------------------------------------------------ ecran
class PlannerScreen extends ConsumerStatefulWidget {
  const PlannerScreen({super.key, required this.onOpenTimer});
  final VoidCallback onOpenTimer;

  @override
  ConsumerState<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends ConsumerState<PlannerScreen> {
  late DateTime _day = _dateOnly(DateTime.now());
  late DateTime _weekStart = _mondayOf(_dateOnly(DateTime.now()));

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(tasksProvider.notifier).reload());
  }

  Subject? _subject(List<Subject> list, String? id) {
    for (final s in list) {
      if (s.id == id) return s;
    }
    return null;
  }

  void _shiftWeek(int days) =>
      setState(() => _weekStart = DateTime(_weekStart.year, _weekStart.month, _weekStart.day + days));

  Future<void> _study(Task t) async {
    if (ref.read(timerProvider).session != null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Une séance est déjà en cours.')));
      widget.onOpenTimer();
      return;
    }
    try {
      await ref.read(timerProvider.notifier).start(mode: 'Focus', target: t.estimateMin * 60, subjectId: t.subjectId);
      final id = ref.read(timerProvider).session?.id;
      if (id != null) await ref.read(tasksProvider.notifier).linkSession(id, t.id);
      ref.invalidate(taskLinksProvider);
      widget.onOpenTimer();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  Future<void> _add(List<Subject> subjects) async {
    final title = TextEditingController();
    String? subjectId;
    var date = _day;
    TimeOfDay? time;
    var noDate = false;
    var minutes = 25;
    var priority = 1;

    final created = await showModalBottomSheet<Task>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Nouvelle tâche', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: title,
                autofocus: true,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Que dois-tu faire ?'),
              ),
              if (subjects.isNotEmpty) ...[
                const Text('Matière'),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  for (final s in subjects)
                    ChoiceChip(
                      label: Text('${s.emoji} ${s.name}'),
                      selected: subjectId == s.id,
                      onSelected: (v) => setS(() => subjectId = v ? s.id : null),
                    ),
                ]),
                const SizedBox(height: 12),
              ],
              const Text('Échéance'),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: [
                FilterChip(
                  label: const Text('Sans date'),
                  selected: noDate,
                  onSelected: (v) => setS(() => noDate = v),
                ),
                if (!noDate)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text('${date.day}/${date.month}/${date.year}'),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                      );
                      if (d != null) setS(() => date = d);
                    },
                  ),
                if (!noDate)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.schedule, size: 16),
                    label: Text(time == null ? 'Heure (facultatif)' : _hm(DateTime(2000, 1, 1, time!.hour, time!.minute))),
                    onPressed: () async {
                      final t = await showTimePicker(context: ctx, initialTime: time ?? const TimeOfDay(hour: 18, minute: 0));
                      if (t != null) setS(() => time = t);
                    },
                  ),
              ]),
              const SizedBox(height: 12),
              const Text('Durée estimée'),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                for (final m in [15, 25, 45, 60, 90])
                  ChoiceChip(
                    label: Text('$m min'),
                    selected: minutes == m,
                    onSelected: (_) => setS(() => minutes = m),
                  ),
              ]),
              const SizedBox(height: 12),
              const Text('Priorité'),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Basse')),
                  ButtonSegment(value: 1, label: Text('Normale')),
                  ButtonSegment(value: 2, label: Text('Haute')),
                ],
                selected: {priority},
                onSelectionChanged: (s) => setS(() => priority = s.first),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    final text = title.text.trim();
                    if (text.isEmpty) return;
                    final tm = time;
                    DateTime? due;
                    if (!noDate) {
                      due = tm == null
                          ? DateTime(date.year, date.month, date.day, 23, 59)
                          : DateTime(date.year, date.month, date.day, tm.hour, tm.minute);
                    }
                    Navigator.pop(
                      ctx,
                      Task(
                        id: const Uuid().v4(),
                        title: text,
                        subjectId: subjectId,
                        due: due,
                        allDay: tm == null,
                        estimateMin: minutes,
                        priority: priority,
                      ),
                    );
                  },
                  child: const Text('Ajouter'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    if (created != null) await ref.read(tasksProvider.notifier).add(created);
  }

  Widget _section(String text, {Color? color}) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(text, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color ?? Colors.white70)),
      );

  Widget _dayCell(DateTime d, String letter, List<Task> tasks, DateTime today) {
    final selected = _same(d, _day);
    final has = tasks.any((t) => !t.done && t.due != null && _same(t.due!, d));
    final isToday = _same(d, today);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _day = d),
      child: Column(children: [
        Text(letter, style: const TextStyle(fontSize: 12, color: Colors.white60)),
        const SizedBox(height: 6),
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? AppColors.accent : Colors.transparent,
            border: isToday && !selected ? Border.all(color: AppColors.accent2) : null,
          ),
          child: Text('${d.day}',
              style: TextStyle(fontWeight: FontWeight.w600, color: selected ? const Color(0xFF14102E) : null)),
        ),
        const SizedBox(height: 4),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: has ? AppColors.warm : Colors.transparent),
        ),
      ]),
    );
  }

  Widget _tile(Task t, List<Subject> subjects, Map<String, int> spent) {
    final subj = _subject(subjects, t.subjectId);
    final prioColor = [AppColors.accent2, AppColors.accent, AppColors.pink][t.priority];
    final parts = <String>[
      if (t.due != null && !t.allDay) _hm(t.due!),
      if (subj != null) '${subj.emoji} ${subj.name}',
      '${t.estimateMin} min prévues',
      if ((spent[t.id] ?? 0) > 0) '${fmtDur(spent[t.id]!)} étudiées',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(4, 6, 0, 6),
        child: Row(children: [
          IconButton(
            icon: Icon(t.done ? Icons.check_circle : Icons.radio_button_unchecked,
                color: t.done ? AppColors.green : prioColor),
            onPressed: () => ref.read(tasksProvider.notifier).toggle(t.id),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                t.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  decoration: t.done ? TextDecoration.lineThrough : null,
                  color: t.done ? Colors.white54 : null,
                ),
              ),
              const SizedBox(height: 2),
              Text(parts.join(' · '), style: const TextStyle(fontSize: 12.5, color: Colors.white60)),
            ]),
          ),
          if (!t.done)
            IconButton(
              tooltip: 'Étudier',
              icon: const Icon(Icons.play_circle_outline, color: AppColors.accent2),
              onPressed: () => _study(t),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'del') ref.read(tasksProvider.notifier).remove(t.id);
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'del', child: Text('Supprimer'))],
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(tasksProvider);
    final subjects = ref.watch(subjectsProvider).maybeWhen(data: (d) => d, orElse: () => <Subject>[]);
    final history = ref.watch(historyProvider).maybeWhen(data: (d) => d, orElse: () => <StudySession>[]);
    final links = ref.watch(taskLinksProvider).maybeWhen(data: (d) => d, orElse: () => <String, String>{});

    final now = DateTime.now();
    final today = _dateOnly(now);
    final spent = <String, int>{};
    for (final s in history) {
      final tid = links[s.id];
      if (tid != null && s.isValidated) spent[tid] = (spent[tid] ?? 0) + s.studySeconds;
    }

    final overdue = tasks.where((t) => t.isOverdue(now)).toList()..sort((a, b) => a.due!.compareTo(b.due!));
    final dayTasks = tasks.where((t) => t.due != null && _same(t.due!, _day)).toList()..sort(_byTime);
    final undated = tasks.where((t) => t.due == null).toList();
    final days = List.generate(7, (i) => DateTime(_weekStart.year, _weekStart.month, _weekStart.day + i));
    const letters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    final dayLabel = _same(_day, today)
        ? 'Aujourd\'hui'
        : '${_weekdays[_day.weekday - 1]} ${_day.day} ${_months[_day.month - 1]}';

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(subjects),
        icon: const Icon(Icons.add),
        label: const Text('Tâche'),
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
          const Text('Planning', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Column(children: [
              Row(children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shiftWeek(-7)),
                Expanded(
                  child: Text(
                    '${_months[_weekStart.month - 1]} ${_weekStart.year}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shiftWeek(7)),
              ]),
              Row(children: [
                for (var i = 0; i < 7; i++) Expanded(child: _dayCell(days[i], letters[i], tasks, today)),
              ]),
            ]),
          ),
          if (overdue.isNotEmpty) ...[
            _section('En retard (${overdue.length})', color: AppColors.pink),
            for (final t in overdue) _tile(t, subjects, spent),
          ],
          _section(dayLabel),
          if (dayTasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Rien de prévu ce jour-là.', style: TextStyle(color: Colors.white54)),
            ),
          for (final t in dayTasks) _tile(t, subjects, spent),
          if (undated.isNotEmpty) ...[
            _section('Sans date'),
            for (final t in undated) _tile(t, subjects, spent),
          ],
        ]),
      ),
    );
  }
}