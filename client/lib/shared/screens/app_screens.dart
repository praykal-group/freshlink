import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/session.dart';
import '../../core/config/app_flavor.dart';
import '../../core/l10n/l10n.dart';
import '../../core/providers.dart';
import '../../core/storage/database.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/app_button.dart';
import '../widgets/async_view.dart';
import '../widgets/connectivity.dart';
import '../widgets/status.dart';

/// Splash: restoring the session (Section 10.3). The update check joins in M15.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(flavorConfigProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.ac_unit_rounded, size: 56, color: context.tokens.flavorAccent),
          const SizedBox(height: AppSpacing.lg),
          Text(config.appName, style: t.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.xl),
          SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3, semanticsLabel: context.l10n.loading)),
        ]),
      ),
    );
  }
}

/// Blocking screen after a 426 (Section 12.4). The download/install flow arrives in M15.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: EmptyState(
          icon: Icons.system_update_rounded,
          title: l.updateRequiredTitle,
          message: l.updateRequiredBody,
          actionLabel: l.cancel,
          onAction: () => SystemNavigator.pop(),
        ),
      ),
    );
  }
}

/// Home of a flavor until its real dashboard lands (M11–M13): greeting, module tag, sync badge.
class FlavorHomeScreen extends ConsumerWidget {
  const FlavorHomeScreen({super.key, required this.moduleTag});
  final String moduleTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final config = ref.watch(flavorConfigProvider);
    final session = ref.watch(sessionProvider);
    final name = session is SignedIn ? session.me.name : '';
    final pending = ref.watch(pendingOpsProvider).value ?? 0;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(config.appName),
        actions: [
          if (config.flavor.hasOfflineOutbox)
            IconButton(
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
          child: ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
            Text(l.homeWelcome(name), style: t.headlineSmall),
            if (session is SignedIn && session.me.siteName != null) Text(session.me.siteName!, style: t.bodyMedium?.copyWith(color: context.palette.textSecondary)),
            const SizedBox(height: AppSpacing.xl),
            AppCard(
              status: StatusLevel.info,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.homeComingSoon, style: t.bodyMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(moduleTag, key: const Key('module-tag'), style: t.bodySmall),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Settings (Section 10.3): language, theme, sync status, about, sign out.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final config = ref.watch(flavorConfigProvider);
    final version = ref.watch(appVersionProvider);
    final theme = ref.watch(themeModeProvider);
    final pending = ref.watch(pendingOpsProvider).value ?? 0;
    final t = Theme.of(context).textTheme;
    Widget section(String title) => Padding(padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.sm), child: Text(title, style: t.titleSmall));

    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: ListView(children: [
        section(l.settingsLanguage),
        const Padding(padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg), child: LanguagePickerChips()),
        section(l.settingsTheme),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            for (final (mode, label) in [(ThemeMode.system, l.themeSystem), (ThemeMode.light, l.themeLight), (ThemeMode.dark, l.themeDark)])
              ChoiceChip(label: Text(label), selected: theme == mode, onSelected: (_) => ref.read(themeModeProvider.notifier).set(mode)),
          ]),
        ),
        if (config.flavor.hasOfflineOutbox) ...[
          section(l.settingsSync),
          ListTile(
            leading: Icon(pending == 0 ? Icons.cloud_done_rounded : Icons.cloud_upload_rounded),
            title: Text(l.syncPending(pending)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/sync-queue'),
          ),
        ],
        section(l.settingsAbout),
        ListTile(leading: const Icon(Icons.info_outline_rounded), title: Text(config.appName), subtitle: Text(l.aboutVersion(version.name, '${version.code}'))),
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: AppButton(
            key: const Key('sign-out'),
            label: l.signOut,
            kind: AppButtonKind.outlined,
            icon: Icons.logout_rounded,
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text(l.signOutConfirm),
                  content: pending > 0 ? Text(l.signOutPendingWarning(pending)) : null,
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l.signOut)),
                  ],
                ),
              );
              if (ok == true) await ref.read(sessionProvider.notifier).signOut();
            },
          ),
        ),
      ]),
    );
  }
}

class LanguagePickerChips extends ConsumerWidget {
  const LanguagePickerChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(localeProvider).languageCode;
    const names = {'en': 'English', 'hi': 'हिन्दी', 'mr': 'मराठी'};
    return Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
      for (final e in names.entries) ChoiceChip(label: Text(e.value), selected: current == e.key, onSelected: (_) => ref.read(localeProvider.notifier).set(e.key)),
    ]);
  }
}

final _outboxListProvider = StreamProvider<List<OutboxOp>>((ref) => ref.watch(outboxProvider)?.watchAll() ?? Stream.value(const []));
final _filesListProvider = StreamProvider<List<PendingFile>>((ref) => ref.watch(outboxProvider)?.watchFiles() ?? Stream.value(const []));

/// Sync Queue (Section 10.2): every op not yet confirmed, "Needs attention" first, retry/discard.
class SyncQueueScreen extends ConsumerWidget {
  const SyncQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final ops = ref.watch(_outboxListProvider);
    final files = ref.watch(_filesListProvider).value ?? const [];
    final scheduler = ref.watch(syncSchedulerProvider);
    final outbox = ref.watch(outboxProvider);
    final time = DateFormat.Hm(Localizations.localeOf(context).toLanguageTag());

    return Scaffold(
      appBar: AppBar(title: Text(l.syncQueueTitle)),
      body: Column(children: [
        const OfflineBanner(),
        Expanded(
          child: AsyncView<List<OutboxOp>>(
            value: ops,
            isEmpty: (list) => list.isEmpty && files.isEmpty,
            empty: EmptyState(icon: Icons.cloud_done_rounded, title: l.syncPending(0), message: l.syncEmpty),
            data: (list) {
              final attention = list.where((o) => o.status == 'attention').toList();
              final waiting = list.where((o) => o.status != 'attention').toList();
              return ListView(padding: EdgeInsets.all(AppSpacing.screenPadding(context)), children: [
                if (attention.isNotEmpty) ...[
                  _Header(l.syncNeedsAttention, StatusLevel.critical),
                  for (final o in attention)
                    _OpTile(
                      op: o,
                      level: StatusLevel.critical,
                      subtitle: '${o.lastErrorCode ?? ''}: ${o.lastError ?? ''}',
                      actions: [
                        TextButton(onPressed: () => outbox?.retry(o.clientOpId), child: Text(l.retry)),
                        TextButton(
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(content: Text(l.discardConfirm), actions: [
                                TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.cancel)),
                                FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(l.discard)),
                              ]),
                            );
                            if (ok == true) await outbox?.discard(o.clientOpId);
                          },
                          child: Text(l.discard),
                        ),
                      ],
                    ),
                ],
                if (waiting.isNotEmpty) ...[
                  _Header(l.syncWaiting, StatusLevel.watch),
                  for (final o in waiting)
                    _OpTile(op: o, level: StatusLevel.watch, subtitle: o.nextAttemptAt == null ? '' : l.syncNextTry(time.format(o.nextAttemptAt!.toLocal()))),
                ],
                if (files.isNotEmpty) ...[
                  _Header(l.syncFiles, StatusLevel.info),
                  for (final f in files)
                    ListTile(
                      leading: Icon(f.status == 'attention' ? Icons.error_rounded : Icons.upload_file_rounded),
                      title: Text(f.purpose),
                      subtitle: Text('${(f.sizeBytes / 1024).round()} KB${f.lastError == null ? '' : ' · ${f.lastError}'}'),
                    ),
                ],
              ]);
            },
          ),
        ),
        if (scheduler != null)
          SafeArea(
            minimum: EdgeInsets.all(AppSpacing.screenPadding(context)),
            child: AppButton(label: l.syncNow, icon: Icons.sync_rounded, onPressed: () => scheduler.syncNow()),
          ),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text, this.level);
  final String text;
  final StatusLevel level;

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm), child: StatusChip(level: level, label: text));
}

class _OpTile extends StatelessWidget {
  const _OpTile({required this.op, required this.level, required this.subtitle, this.actions = const []});
  final OutboxOp op;
  final StatusLevel level;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final payload = jsonDecode(op.payload);
    final ref = payload is Map ? (payload['code'] ?? payload['tripId'] ?? payload['batchId'] ?? op.entityId) : op.entityId;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        status: level,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(op.type.replaceAll('_', ' '), style: t.titleSmall),
          Text('$ref · ${DateFormat.yMd().add_Hm().format(op.capturedAt.toLocal())}', style: t.bodySmall),
          if (subtitle.isNotEmpty) Text(subtitle, style: t.bodySmall),
          if (actions.isNotEmpty) Wrap(alignment: WrapAlignment.end, children: actions),
        ]),
      ),
    );
  }
}
