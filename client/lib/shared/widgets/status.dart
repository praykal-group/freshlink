import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';

/// Icon for a status level: status is never shown by colour alone (Section 13.3).
IconData statusIcon(StatusLevel s) => switch (s) {
      StatusLevel.safe => Icons.check_circle_rounded,
      StatusLevel.watch => Icons.warning_amber_rounded,
      StatusLevel.critical => Icons.error_rounded,
      StatusLevel.info => Icons.info_rounded,
    };

String statusLabel(AppLocalizations l, StatusLevel s) => switch (s) {
      StatusLevel.safe => l.statusSafe,
      StatusLevel.watch => l.statusWatch,
      StatusLevel.critical => l.statusCritical,
      StatusLevel.info => l.statusInfo,
    };

/// Status chip: icon + label + colour.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.level, this.label});
  final StatusLevel level;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.palette.status(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.chip), border: Border.all(color: c.withValues(alpha: 0.6))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(statusIcon(level), size: 18, color: c),
        const SizedBox(width: AppSpacing.xs),
        Flexible(child: Text(label ?? statusLabel(context.l10n, level), style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

/// Grade chip: letter + icon + colour (A safe, B watch, C critical).
class GradeChip extends StatelessWidget {
  const GradeChip({super.key, required this.grade});
  final String grade;

  static StatusLevel levelOf(String g) => switch (g.toUpperCase()) {
        'A' => StatusLevel.safe,
        'B' => StatusLevel.watch,
        _ => StatusLevel.critical,
      };

  @override
  Widget build(BuildContext context) => Semantics(label: 'Grade $grade', child: StatusChip(level: levelOf(grade), label: grade.toUpperCase()));
}

/// Card with the optional 4 px left status strip (Section 13.3).
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.status, this.onTap, this.padding = const EdgeInsets.all(AppSpacing.lg)});
  final Widget child;
  final StatusLevel? status;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final strip = status == null ? null : context.palette.status(status!);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (strip != null) Container(width: AppSizes.statusStrip, color: strip),
            Expanded(child: Padding(padding: padding, child: child)),
          ]),
        ),
      ),
    );
  }
}
