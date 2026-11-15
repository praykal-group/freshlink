import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n.dart';
import '../../core/theme/app_spacing.dart';
import 'providers.dart';

/// One place the shell can take the manager (Section 10.6 #1–#11).
class Destination {
  const Destination(this.path, this.icon, this.label, {this.adminOnly = false, this.onPhoneBar = false});
  final String path;
  final IconData icon;
  final String Function(AppLocalizations) label;
  final bool adminOnly;
  final bool onPhoneBar;
}

final destinations = <Destination>[
  Destination('/home', Icons.dashboard_rounded, (l) => l.mgrDashboard, onPhoneBar: true),
  Destination('/trips', Icons.local_shipping_rounded, (l) => l.mgrTrips, onPhoneBar: true),
  Destination('/alerts', Icons.notification_important_rounded, (l) => l.mgrAlerts, onPhoneBar: true),
  Destination('/planning', Icons.event_note_rounded, (l) => l.mgrPlanning, onPhoneBar: true),
  Destination('/forecast', Icons.insights_rounded, (l) => l.mgrForecast),
  Destination('/approvals', Icons.fact_check_rounded, (l) => l.mgrApprovals),
  Destination('/buyers', Icons.storefront_rounded, (l) => l.mgrBuyers),
  Destination('/reports', Icons.summarize_rounded, (l) => l.mgrReports),
  Destination('/releases', Icons.system_update_rounded, (l) => l.mgrReleases),
  Destination('/admin/masters', Icons.dataset_rounded, (l) => l.mgrMasters, adminOnly: true),
  Destination('/admin/users', Icons.manage_accounts_rounded, (l) => l.mgrUsers, adminOnly: true),
  Destination('/admin/config', Icons.tune_rounded, (l) => l.mgrConfig, adminOnly: true),
];

/// Rail at ≥ 840 px (tablet / web), extended labels at ≥ 1200 px.
const kRailBreakpoint = 840.0;

/// Section 10.6: phone = bottom navigation (4 main + More), tablet / web ≥ 840 px = navigation rail.
class ManagerShell extends ConsumerWidget {
  const ManagerShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final admin = ref.watch(isAdminProvider);
    final visible = [for (final d in destinations) if (!d.adminOnly || admin) d];
    final width = MediaQuery.sizeOf(context).width;
    int indexIn(List<Destination> list) {
      final i = list.indexWhere((d) => d.path == '/home' ? location == '/home' : location.startsWith(d.path));
      return i;
    }

    if (width >= kRailBreakpoint) {
      final i = indexIn(visible);
      final extended = width >= 1200;
      return Scaffold(
        body: Row(children: [
          SafeArea(
            child: NavigationRail(
              key: const Key('nav-rail'),
              scrollable: true, // 12 destinations overflow a short window
              extended: extended,
              selectedIndex: i < 0 ? null : i,
              labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
              onDestinationSelected: (n) => context.go(visible[n].path),
              trailing: IconButton(tooltip: l.settingsTitle, onPressed: () => context.push('/settings'), icon: const Icon(Icons.settings_rounded)),
              destinations: [for (final d in visible) NavigationRailDestination(icon: Icon(d.icon, key: Key('nav-${d.path}')), label: Text(d.label(l)))],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ]),
      );
    }

    final bar = [for (final d in visible) if (d.onPhoneBar) d];
    final barIndex = indexIn(bar);
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        key: const Key('nav-bar'),
        selectedIndex: barIndex < 0 ? bar.length : barIndex,
        onDestinationSelected: (n) => context.go(n < bar.length ? bar[n].path : '/more'),
        destinations: [
          for (final d in bar) NavigationDestination(icon: Icon(d.icon, key: Key('nav-${d.path}')), label: d.label(l)),
          NavigationDestination(icon: const Icon(Icons.more_horiz_rounded, key: Key('nav-/more')), label: l.mgrMore),
        ],
      ),
    );
  }
}

/// "More" on a phone: the destinations that do not fit the bottom bar.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final admin = ref.watch(isAdminProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.mgrMore)),
      body: ListView(padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm), children: [
        for (final d in destinations)
          if (!d.onPhoneBar && (!d.adminOnly || admin)) ListTile(key: Key('more-${d.path}'), leading: Icon(d.icon), title: Text(d.label(l)), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => context.go(d.path)),
        const Divider(),
        ListTile(leading: const Icon(Icons.settings_rounded), title: Text(l.settingsTitle), onTap: () => context.push('/settings')),
      ]),
    );
  }
}
