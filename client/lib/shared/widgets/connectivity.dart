import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/providers.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';

/// "Offline" banner when there is no connectivity (Section 10.2). Slides in/out.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineProvider).value ?? true;
    final p = context.palette;
    return AnimatedSize(
      duration: AppMotion.standard,
      curve: AppMotion.enter,
      child: online
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion: true,
              child: Container(
                width: double.infinity,
                color: p.watch.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                child: Row(children: [
                  Icon(Icons.cloud_off_rounded, color: p.watch, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(context.l10n.offlineBanner, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.textPrimary))),
                ]),
              ),
            ),
    );
  }
}

/// "Updated 3 min ago" under cached data.
class StaleLabel extends StatelessWidget {
  const StaleLabel({super.key, required this.updatedAt, this.now});
  final DateTime updatedAt;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final minutes = (now ?? DateTime.now()).difference(updatedAt).inMinutes;
    final l = context.l10n;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.history_rounded, size: 16, color: context.palette.textSecondary),
      const SizedBox(width: AppSpacing.xs),
      Flexible(child: Text(minutes < 1 ? l.updatedJustNow : l.updatedAgo(minutes), style: Theme.of(context).textTheme.bodySmall)),
    ]);
  }
}
