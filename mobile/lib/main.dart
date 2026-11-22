import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/api_client.dart';
import 'core/sync.dart';
import 'core/sync_banner.dart';
import 'core/widgets.dart';
import 'features/auth/auth_repository.dart';
import 'features/auth/login_screen.dart';
import 'features/history/history_screen.dart';
import 'features/planner/planner_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/stats/stats_screen.dart';
import 'features/timer/timer_screen.dart';

void main() => runApp(const ProviderScope(child: FocuselyApp()));

class FocuselyApp extends StatelessWidget {
  const FocuselyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Focusely',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        builder: (context, child) => AppBackground(child: child ?? const SizedBox()),
        home: const AuthGate(),
      );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _repo = AuthRepository(createDio());
  bool? _loggedIn;

  @override
  void initState() {
    super.initState();
    _repo.isLoggedIn().then((v) => setState(() => _loggedIn = v));
  }

  @override
  Widget build(BuildContext context) {
    if (_loggedIn == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loggedIn!) {
      return HomeShell(onLogout: () async {
        await _repo.logout();
        setState(() => _loggedIn = false);
      });
    }
    return LoginScreen(onLoggedIn: () => setState(() => _loggedIn = true));
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.onLogout});
  final VoidCallback onLogout;
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  int _index = 0;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() => ref.read(syncProvider.notifier).syncNow());
    // Tant qu'il reste des elements en attente, on reessaie toutes les 30 s
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (ref.read(syncProvider).pending > 0) ref.read(syncProvider.notifier).syncNow();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.read(syncProvider.notifier).syncNow();
  }

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Les 5 pages restent en memoire : on garde ta saisie et ton defilement en changeant d'onglet
      body: IndexedStack(index: _index, children: [
        TimerScreen(onLogout: widget.onLogout),
        const StatsScreen(),
        const HistoryScreen(),
        PlannerScreen(onOpenTimer: () => _go(0)),
        ProfileScreen(onLogout: widget.onLogout),
      ]),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        const SyncBanner(),
        NavigationBar(
          height: 68,
          selectedIndex: _index,
          onDestinationSelected: _go,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          backgroundColor: const Color(0xF20B0B1E),
          indicatorColor: AppColors.accent.withValues(alpha: 0.35),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.timer_outlined), selectedIcon: Icon(Icons.timer), label: 'Focus'),
            NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Stats'),
            NavigationDestination(icon: Icon(Icons.history), selectedIcon: Icon(Icons.history_toggle_off), label: 'Historique'),
            NavigationDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note), label: 'Planning'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profil'),
          ],
        ),
      ]),
    );
  }
}