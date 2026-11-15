import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/connectivity.dart';
import '../../../shared/widgets/status.dart';
import '../data/operator_repository.dart';
import '../module_tag.dart';
import '../providers.dart';

/// Operator home (Section 10.4 #1): site, today's counts, pending sync badge, big quick actions.
class OperatorHomeScreen extends ConsumerWidget {
  const OperatorHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    ref.watch(gradeQueueWorkerProvider);
    final summary = ref.watch(summaryProvider);
    final pending = ref.watch(pendingOpsProvider).value ?? 0;
    final draft = ref.watch(operatorDraftProvider).value;
    final session = ref.watch(sessionProvider);
    final site = summary.value?.siteName ?? (session is SignedIn ? session.me.siteName : null) ?? '';
    final t = Theme.of(context).textTheme;

    Widget count(String label, int? v, IconData icon) => Expanded(
          child: AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: context.tokens.flavorAccent),
              const SizedBox(height: AppSpacing.xs),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: (v ?? 0).toDouble()),
                duration: AppMotion.emphasised,
                builder: (_, x, _) => Text(v == null ? '–' : x.round().toString(), style: AppTypography.metric.copyWith(color: context.palette.textPrimary)),
              ),
              Text(label, style: t.bodySmall, maxLines: 2),
            ]),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(l.homeWelcome(session is SignedIn ? session.me.name : '')),
        actions: [
          IconButton(
            key: const Key('sync-badge'),
            tooltip: l.syncPending(pending),
            onPressed: () => context.push('/sync-queue'),
            icon: Badge(isLabelVisible: pending > 0, label: Text('$pending'), child: const Icon(Icons.sync_rounded)),
          ),
          IconButton(tooltip: l.settingsTitle, onPressed: () => context.push('/settings'), icon: const Icon(Icons.settings_rounded)),
        ],
      ),
      body: Column(children: [
        const OfflineBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(summaryProvider);
              await ref.read(syncSchedulerProvider)?.syncNow();
            },
            child: ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
              Text(l.todayAtSite(site), style: t.titleMedium),
              const SizedBox(height: AppSpacing.md),
              Row(children: [
                count(l.countRegistered, summary.value?.registered, Icons.add_box_rounded),
                const SizedBox(width: AppSpacing.sm),
                count(l.countGraded, summary.value?.graded, Icons.grade_rounded),
              ]),
              const SizedBox(height: AppSpacing.sm),
              Row(children: [
                count(l.countStored, summary.value?.stored, Icons.ac_unit_rounded),
                const SizedBox(width: AppSpacing.sm),
                count(l.countDispatched, summary.value?.dispatched, Icons.local_shipping_rounded),
              ]),
              if (draft != null) ...[
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  status: StatusLevel.watch,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.resumeDraft, style: t.titleSmall),
                    Wrap(alignment: WrapAlignment.end, children: [
                      TextButton(
                        onPressed: () async {
                          await ref.read(databaseProvider)!.clearDraft();
                          ref.invalidate(operatorDraftProvider);
                        },
                        child: Text(l.discardDraft),
                      ),
                      TextButton(key: const Key('resume-draft'), onPressed: () => context.push('/batch/resume'), child: Text(l.next)),
                    ]),
                  ]),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              AppButton(key: const Key('new-fish'), label: l.newFishBatch, icon: Icons.set_meal_rounded, onPressed: () => context.push('/batch/new/fish')),
              const SizedBox(height: AppSpacing.md),
              AppButton(key: const Key('new-produce'), label: l.newProduceBatch, icon: Icons.eco_rounded, kind: AppButtonKind.tonal, onPressed: () => context.push('/batch/new/produce')),
              const SizedBox(height: AppSpacing.md),
              Row(children: [
                Expanded(child: AppButton(key: const Key('receive'), label: l.receive, icon: Icons.move_to_inbox_rounded, kind: AppButtonKind.outlined, onPressed: () => context.push('/receive'))),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: AppButton(key: const Key('load'), label: l.loadTruck, icon: Icons.local_shipping_rounded, kind: AppButtonKind.outlined, onPressed: () => context.push('/load'))),
              ]),
              const SizedBox(height: AppSpacing.md),
              Row(children: [
                Expanded(child: AppButton(key: const Key('batches'), label: l.batches, icon: Icons.list_alt_rounded, kind: AppButtonKind.outlined, onPressed: () => context.push('/batches'))),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: AppButton(label: l.printer, icon: Icons.print_rounded, kind: AppButtonKind.outlined, onPressed: () => context.push('/printer'))),
              ]),
              const SizedBox(height: AppSpacing.xl),
              Text(kModuleTag, key: const Key('module-tag'), style: t.labelSmall, textAlign: TextAlign.center),
            ]),
          ),
        ),
      ]),
    );
  }
}
