import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';
import '../timer/timer_controller.dart';

class Subject {
  Subject(this.id, this.name, this.color, this.emoji);
  final String id, name, color, emoji;
  factory Subject.fromJson(Map<String, dynamic> j) =>
      Subject(j['id'], j['name'], j['color'], j['emoji']);
  Color get colorValue => hexColor(color);
}

Color hexColor(String hex) {
  final h = hex.replaceAll('#', '');
  return Color(int.parse(h.length == 6 ? 'FF$h' : h, radix: 16));
}

final subjectsProvider = FutureProvider<List<Subject>>((ref) async {
  final r = await ref.read(dioProvider).get('/api/subjects');
  return (r.data as List).map((j) => Subject.fromJson(j)).toList();
});

const _emojis = ['📘', '🧮', '💻', '🧪', '🌍', '🎨', '🎵', '📝', '⚙️', '🩺', '⚖️', '🗣️'];
const _colors = ['#8B7CFF', '#38E1C6', '#FFB74D', '#FF6B8B', '#4FC3F7', '#A5D66F', '#F06292', '#FFD54F'];

Future<void> showAddSubjectDialog(BuildContext context, WidgetRef ref) async {
  final name = TextEditingController();
  var emoji = _emojis.first;
  var color = _colors.first;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: const Text('Nouvelle matière'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: name,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'Nom (ex : Maths)'),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in _emojis)
                GestureDetector(
                  onTap: () => setS(() => emoji = e),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: e == emoji ? Colors.white : Colors.transparent, width: 2),
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 22)),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final c in _colors)
                GestureDetector(
                  onTap: () => setS(() => color = c),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: hexColor(c),
                      shape: BoxShape.circle,
                      border: Border.all(color: c == color ? Colors.white : Colors.transparent, width: 3),
                    ),
                  ),
                ),
            ]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              try {
                await ref.read(dioProvider).post('/api/subjects',
                    data: {'name': name.text.trim(), 'color': color, 'emoji': emoji});
                ref.invalidate(subjectsProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(errorMessage(e))));
                }
              }
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    ),
  );
}

Future<void> confirmDeleteSubject(BuildContext context, WidgetRef ref, Subject s) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Supprimer ${s.emoji} ${s.name} ?'),
      content: const Text('Tes séances gardent leur temps, mais ne sont plus liées à cette matière.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Supprimer')),
      ],
    ),
  );
  if (ok == true) {
    await ref.read(dioProvider).delete('/api/subjects/${s.id}');
    ref.invalidate(subjectsProvider);
  }
}
