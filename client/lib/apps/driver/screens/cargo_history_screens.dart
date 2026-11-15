import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/async_view.dart';
import '../../../shared/widgets/status.dart';
import '../data/models.dart';
import '../providers.dart';
import '../widgets/driver_widgets.dart';

/// Section 10.5 #4 / DA-FR-05: per batch: product, grade, safe range, shelf-life countdown.
class CargoScreen extends ConsumerWidget {
  const CargoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final trip = ref.watch(currentTripProvider).value;
    if (trip == null) return Scaffold(appBar: AppBar(title: Text(l.cargoStatus)), body: EmptyState(title: l.noTripToday));
    final cargo = ref.watch(cargoProvider(trip.id));
    final lang = Localizations.localeOf(context).languageCode;
    return Scaffold(
      appBar: AppBar(title: Text(l.cargoStatus)),
      body: AsyncView<CargoStatus>(
        value: cargo,
        onRetry: () => ref.invalidate(cargoProvider(trip.id)),
        isEmpty: (c) => c.batches.isEmpty,
        empty: EmptyState(title: l.cargoEmpty, icon: Icons.inventory_2_rounded),
        data: (c) => ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
          CargoStrip(cargo: c),
          const SizedBox(height: AppSpacing.lg),
          for (final b in c.batches) ...[
            Builder(builder: (context) {
              final level = shelfLifeLevel(b.remainingH);
              return AppCard(
                key: Key('cargo-${b.code}'),
                status: level,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${productName(b.product, lang)} · ${b.code}', style: Theme.of(context).textTheme.titleSmall)),
                    if (b.grade != null) GradeChip(grade: b.grade!),
                  ]),
                  Text(l.podBatchWeight(b.weightKg.toStringAsFixed(1))),
                  if (b.safeMin != null && b.safeMax != null) Text(l.cargoSafeRange(b.safeMin!.toStringAsFixed(0), b.safeMax!.toStringAsFixed(0))),
                  const SizedBox(height: AppSpacing.xs),
                  Row(children: [
                    Icon(levelIcon(level), color: context.palette.status(level)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(shelfLifeText(l, b.remainingH))),
                  ]),
                ]),
              );
            }),
            const SizedBox(height: AppSpacing.md),
          ],
        ]),
      ),
    );
  }
}

final historyProvider = FutureProvider.autoDispose<List<TripHistoryItem>>((ref) => ref.watch(driverRepositoryProvider).history());

/// Section 10.5 #9 / DA-FR-13: past trips, PoD status, uploads still on the phone.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final pending = ref.watch(pendingOpsProvider).value ?? 0;
    final history = ref.watch(historyProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.tripHistory)),
      body: ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
        AppCard(
          key: const Key('pending-uploads'),
          status: pending > 0 ? StatusLevel.watch : StatusLevel.safe,
          child: Text(pending > 0 ? l.pendingUploads(pending) : l.allUploaded),
        ),
        const SizedBox(height: AppSpacing.lg),
        AsyncView<List<TripHistoryItem>>(
          value: history,
          onRetry: () => ref.invalidate(historyProvider),
          isEmpty: (v) => v.isEmpty,
          empty: EmptyState(title: l.noHistory, icon: Icons.history_rounded),
          data: (items) => Column(children: [
            for (final t in items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: AppCard(
                  status: t.status == 'COMPLETED' ? StatusLevel.safe : StatusLevel.info,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.code, style: Theme.of(context).textTheme.titleSmall),
                    Text('${MaterialLocalizations.of(context).formatShortDate(t.plannedStart)} · ${t.status}'),
                    Text(l.historyPods(t.podStops)),
                    if (t.distanceKm != null) Text('${t.distanceKm!.toStringAsFixed(1)} km'),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
