import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/l10n/l10n.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import 'app_button.dart';

/// Every list/detail renders through this (Section 10.2): skeleton → content, empty state with an
/// action, or an error card with Retry.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.data, this.onRetry, this.isEmpty, this.empty, this.skeleton});

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final bool Function(T data)? isEmpty;
  final Widget? empty;
  final Widget? skeleton;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.standard,
      child: value.when(
        skipLoadingOnRefresh: true,
        loading: () => KeyedSubtree(key: const ValueKey('loading'), child: skeleton ?? const SkeletonList()),
        error: (e, _) => KeyedSubtree(key: const ValueKey('error'), child: ErrorCard(error: e, onRetry: onRetry)),
        data: (d) => KeyedSubtree(key: const ValueKey('data'), child: (isEmpty?.call(d) ?? false) ? (empty ?? EmptyState(title: context.l10n.emptyTitle)) : data(d)),
      ),
    );
  }
}

/// Custom shimmer (no package): a gradient sweeping over grey blocks, max 1.5 s loop (Section 13.4).
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 16, this.width = double.infinity, this.radius = AppRadius.input});
  final double height;
  final double width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: AppMotion.shimmerLoop);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 + 3 * _c.value - 1, 0),
              end: Alignment(-1 + 3 * _c.value, 0),
              colors: [p.surfaceVariant, p.outline.withValues(alpha: 0.6), p.surfaceVariant],
            ),
          ),
        ),
      ),
    );
  }
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 5});
  final int rows;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.loading,
      child: ListView.separated(
        padding: EdgeInsets.all(AppSpacing.screenPadding(context)),
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: rows,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (_, _) => const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Skeleton(height: 18, width: 180),
          SizedBox(height: AppSpacing.sm),
          Skeleton(height: 14),
          SizedBox(height: AppSpacing.xs),
          Skeleton(height: 14, width: 220),
        ]),
      ),
    );
  }
}

/// Empty state: simple illustration with a subtle float + one action.
class EmptyState extends StatefulWidget {
  const EmptyState({super.key, required this.title, this.message, this.icon = Icons.inventory_2_rounded, this.actionLabel, this.onAction});
  final String title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<EmptyState> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 3));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AppMotion.reduced(context) && !_c.isAnimating) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(AppSpacing.screenPadding(context)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedBuilder(
            animation: _c,
            builder: (_, child) => Transform.translate(offset: Offset(0, -6 * Curves.easeInOut.transform(_c.value)), child: child),
            child: CircleAvatar(radius: 40, backgroundColor: p.primaryContainer, child: Icon(widget.icon, size: 40, color: p.primary)),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(widget.title, style: t.titleLarge, textAlign: TextAlign.center),
          if (widget.message != null) ...[const SizedBox(height: AppSpacing.sm), Text(widget.message!, style: t.bodyMedium?.copyWith(color: p.textSecondary), textAlign: TextAlign.center)],
          if (widget.actionLabel != null && widget.onAction != null) ...[
            const SizedBox(height: AppSpacing.xl),
            AppButton(label: widget.actionLabel!, onPressed: widget.onAction, kind: AppButtonKind.tonal, expand: false),
          ],
        ]),
      ),
    );
  }
}

/// Error card with Retry. Shows the AppException message (already user-facing from the server).
class ErrorCard extends StatelessWidget {
  const ErrorCard({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final message = error is AppException
        ? ((error as AppException).status == null ? l.authNetwork : (error as AppException).message)
        : l.authUnknown;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(AppSpacing.screenPadding(context)),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.error_outline_rounded, color: p.critical, size: 36),
              const SizedBox(height: AppSpacing.sm),
              Text(l.errorTitle, style: t.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xs),
              Text(message, style: t.bodyMedium?.copyWith(color: p.textSecondary), textAlign: TextAlign.center),
              if (onRetry != null) ...[const SizedBox(height: AppSpacing.lg), AppButton(label: l.retry, onPressed: onRetry, kind: AppButtonKind.tonal, icon: Icons.refresh_rounded, expand: false)],
            ]),
          ),
        ),
      ),
    );
  }
}
