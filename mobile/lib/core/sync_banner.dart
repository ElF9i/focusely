import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/timer/timer_controller.dart';
import 'sync.dart';
import 'widgets.dart';

class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncProvider);
    final local = ref.watch(timerProvider).session?.local ?? false;
    if (!local && sync.pending == 0 && sync.rejected == 0) return const SizedBox.shrink();

    late final String text;
    late final IconData icon;
    late final Color color;
    if (local) {
      text = 'Mode hors ligne : ta séance est enregistrée sur le téléphone';
      icon = Icons.cloud_off;
      color = AppColors.warm;
    } else if (sync.pending > 0) {
      text = sync.syncing
          ? 'Synchronisation en cours…'
          : '${sync.pending} séance(s) en attente · touche pour synchroniser';
      icon = sync.syncing ? Icons.sync : Icons.cloud_upload_outlined;
      color = AppColors.accent;
    } else {
      text = '${sync.rejected} séance(s) refusée(s) par le serveur (horodatage invalide). Touche pour fermer.';
      icon = Icons.error_outline;
      color = AppColors.pink;
    }

    return InkWell(
      onTap: () {
        final n = ref.read(syncProvider.notifier);
        if (!local && sync.pending == 0) {
          n.clearRejected();
        } else {
          n.syncNow();
        }
      },
      child: Container(
        width: double.infinity,
        color: color.withValues(alpha: 0.22),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
        ]),
      ),
    );
  }
}
