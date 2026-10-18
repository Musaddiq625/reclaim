import 'package:installed_apps/installed_apps.dart';
import 'package:usage_stats/usage_stats.dart';

import 'models.dart';

/// Bulk-pulls app usage history via Android's UsageStatsManager.
/// One-shot query — no background service, no live tracking.
class UsageService {
  /// Android retains roughly a week of detailed usage stats.
  static const int historyDays = 7;

  Future<bool> hasPermission() async =>
      await UsageStats.checkUsagePermission() ?? false;

  /// Opens system Settings → "Apps with usage access".
  Future<void> requestPermission() => UsageStats.grantUsagePermission();

  /// Pulls everything UsageStatsManager has retained: per-app foreground
  /// totals plus the raw foreground/background event stream.
  Future<RawUsage> pullHistory() async {
    final end = DateTime.now();
    final start = end.subtract(const Duration(days: historyDays));

    final results = await Future.wait([
      UsageStats.queryUsageStats(start, end),
      UsageStats.queryEvents(start, end),
      InstalledApps.getInstalledApps(withIcon: true, excludeSystemApps: false),
    ]);

    return RawUsage(
      stats: results[0] as List<UsageInfo>,
      events: results[1] as List<EventUsageInfo>,
      catalog: (results[2] as List)
          .map(
            (a) => InstalledApp(
              packageName: a.packageName,
              label: a.name,
              icon: a.icon,
              isSystem: a.isSystemApp,
              type: a.category.name,
            ),
          )
          .toList(),
    );
  }
}

/// The raw pull, before aggregation.
class RawUsage {
  final List<UsageInfo> stats;
  final List<EventUsageInfo> events;
  final List<InstalledApp> catalog;

  const RawUsage({
    required this.stats,
    required this.events,
    required this.catalog,
  });
}
