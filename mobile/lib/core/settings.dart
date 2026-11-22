import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'offline_data.dart';

/// Objectif d'etude quotidien (en minutes), conserve sur le telephone.
class DailyGoalController extends Notifier<int> {
  static const _key = 'settings:daily_goal';

  @override
  int build() {
    Future.microtask(_load);
    return 60;
  }

  Future<void> _load() async {
    final v = await DataCache.instance.get(_key);
    if (v is int && v > 0) state = v;
  }

  Future<void> set(int minutes) async {
    state = minutes.clamp(10, 600).toInt();
    await DataCache.instance.put(_key, state);
  }
}

final dailyGoalProvider = NotifierProvider<DailyGoalController, int>(DailyGoalController.new);