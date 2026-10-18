import 'dart:typed_data';

/// One app's aggregated usage across the pulled window.
class AppUsage {
  final String packageName;
  final String label;
  final Uint8List? icon;
  final int totalMinutes;
  final int sessionCount;

  const AppUsage({
    required this.packageName,
    required this.label,
    this.icon,
    required this.totalMinutes,
    required this.sessionCount,
  });
}

/// A single contiguous foreground session, reconstructed from FG/BG events.
class UsageSession {
  final String packageName;
  final DateTime start;
  final DateTime end;

  const UsageSession({
    required this.packageName,
    required this.start,
    required this.end,
  });

  int get minutes => end.difference(start).inMinutes;
  bool get isNight => start.hour >= 23 || start.hour < 6;
}

/// Per-day rollup.
class DayUsage {
  final DateTime date;
  final int totalMinutes;
  final int pickups;
  final int nightMinutes;
  final int longSessions;

  const DayUsage({
    required this.date,
    required this.totalMinutes,
    required this.pickups,
    required this.nightMinutes,
    required this.longSessions,
  });
}

/// Full report handed to UI and to the on-device coach.
class UsageReport {
  final List<DayUsage> days;
  final List<AppUsage> topApps;
  final List<UsageSession> longSessions;
  final int totalMinutes;
  final int totalPickups;
  final int nightMinutes;
  final int? peakHour;

  /// Every installed app keyed by package name — lets UI resolve any
  /// package the model echoes into a label + icon, not just top-10 apps.
  final Map<String, InstalledApp> catalog;

  const UsageReport({
    required this.days,
    required this.topApps,
    required this.longSessions,
    required this.totalMinutes,
    required this.totalPickups,
    required this.nightMinutes,
    required this.peakHour,
    required this.catalog,
  });

  InstalledApp? appFor(String? packageName) =>
      packageName == null ? null : catalog[packageName];

  int get dayCount => days.length;
  double get avgDailyMinutes => days.isEmpty ? 0 : totalMinutes / days.length;
}

/// One actionable item in the coach's plan.
class PlanAction {
  final String action; // 'cap' | 'protect' | 'replace'
  final String? appPackage;
  final int? limitMinutes;
  final String? window;
  final String? reason;
  final String? suggestion;

  const PlanAction({
    required this.action,
    this.appPackage,
    this.limitMinutes,
    this.window,
    this.reason,
    this.suggestion,
  });
}

/// Structured coaching digest parsed from the model's JSON output.
/// [parsed] is false when the model didn't return valid JSON and we fell
/// back to showing its raw text.
class CoachDigest {
  final String verdict;
  final String? patternInsight;
  final String? sinkApp;      // package name, resolved to an icon/label in UI
  final String? sinkWhy;
  final int? dailyGoalMinutes;
  final List<PlanAction> plan;
  final String? win;
  final String raw;
  final bool parsed;

  const CoachDigest({
    required this.verdict,
    this.patternInsight,
    this.sinkApp,
    this.sinkWhy,
    this.dailyGoalMinutes,
    this.plan = const [],
    this.win,
    required this.raw,
    required this.parsed,
  });
}

/// A scheduled freeze window for one app (minutes since midnight).
class FreezeRule {
  final String packageName;
  final int startMin;
  final int endMin;
  final bool enabled;

  /// When the rule was created (epoch ms). Null for legacy rules — "nights
  /// held" then counts from the start of the daily archive instead.
  final DateTime? createdAt;

  const FreezeRule({
    required this.packageName,
    required this.startMin,
    required this.endMin,
    this.enabled = true,
    this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'package': packageName,
        'startMin': startMin,
        'endMin': endMin,
        'enabled': enabled,
        if (createdAt != null) 'createdAt': createdAt!.millisecondsSinceEpoch,
      };

  factory FreezeRule.fromJson(Map<String, dynamic> j) => FreezeRule(
        packageName: j['package'] as String,
        startMin: j['startMin'] as int,
        endMin: j['endMin'] as int,
        enabled: (j['enabled'] as bool?) ?? true,
        createdAt: j['createdAt'] is num
            ? DateTime.fromMillisecondsSinceEpoch(j['createdAt'] as int)
            : null,
      );

  bool coversMinutes(int minuteOfDay) => startMin <= endMin
      ? minuteOfDay >= startMin && minuteOfDay < endMin
      : minuteOfDay >= startMin || minuteOfDay < endMin; // crosses midnight

  FreezeRule copyWith({int? startMin, int? endMin, bool? enabled}) =>
      FreezeRule(
        packageName: packageName,
        startMin: startMin ?? this.startMin,
        endMin: endMin ?? this.endMin,
        enabled: enabled ?? this.enabled,
        createdAt: createdAt,
      );
}

/// App catalog entry for label/icon resolution.
/// [type] is the Android store category (Social, Game, Video…).
class InstalledApp {
  final String packageName;
  final String label;
  final Uint8List? icon;
  final bool isSystem;
  final String type;

  const InstalledApp({
    required this.packageName,
    required this.label,
    this.icon,
    required this.isSystem,
    this.type = 'Undefined',
  });

  Map<String, dynamic> toJson() => {
        'name': label,
        'type': type,
        'system': isSystem,
      };
}
