import 'models.dart';
import 'usage_service.dart';

/// Turns raw usage rows into a [UsageReport]. All math lives here —
/// the model narrates these numbers, it never computes them.
class Aggregator {
  /// Packages that are never "usage": launchers, system UI, ourselves.
  static const _hidden = {
    'com.reclaim.musaddiq625',
    'com.android.systemui',
    'com.android.launcher',
    'com.android.launcher3',
    'com.google.android.apps.nexuslauncher',
    'com.sec.android.app.launcher',
    'com.miui.home',
    'com.huawei.android.launcher',
    'com.android.settings',
    'com.google.android.permissioncontroller',
  };

  /// Sessions of the same app separated by less than this get merged
  /// (notification glance, quick switch away and back).
  static const _mergeGap = Duration(seconds: 60);

  /// A session at or above this length counts as a long/"doomscroll" session.
  static const _longSession = Duration(minutes: 20);

  /// Shorter than this isn't a real open — filter noise.
  static const _minSession = Duration(seconds: 10);

  static bool _isVisible(String pkg) =>
      !_hidden.contains(pkg) && !pkg.startsWith('com.android.');

  UsageReport build(RawUsage raw) {
    final catalog = {for (final a in raw.catalog) a.packageName: a};

    // --- Totals from queryUsageStats (ground truth for minutes) ---
    final totalByPkg = <String, int>{};
    for (final s in raw.stats) {
      final pkg = s.packageName;
      final ms = s.totalTimeInForegroundMs;
      if (pkg == null || ms == null || ms <= 0 || !_isVisible(pkg)) continue;
      totalByPkg[pkg] = (totalByPkg[pkg] ?? 0) + ms;
    }

    // --- Sessions reconstructed from the event stream ---
    final events = raw.events
        .where((e) => e.packageName != null && e.timeStampDate != null)
        .where((e) => _isVisible(e.packageName!))
        .toList()
      ..sort((a, b) => a.timeStampDate!.compareTo(b.timeStampDate!));

    final openAt = <String, DateTime>{};
    final rawSessions = <UsageSession>[];
    var pickups = 0;

    for (final e in events) {
      final pkg = e.packageName!;
      final ts = e.timeStampDate!;
      // 1 = MOVE_TO_FOREGROUND / ACTIVITY_RESUMED, 2 = MOVE_TO_BACKGROUND / ACTIVITY_PAUSED
      if (e.eventTypeValue == 1) {
        pickups++;
        openAt.putIfAbsent(pkg, () => ts);
      } else if (e.eventTypeValue == 2) {
        final start = openAt.remove(pkg);
        if (start != null && ts.isAfter(start)) {
          rawSessions.add(UsageSession(packageName: pkg, start: start, end: ts));
        }
      }
    }

    // Merge rapid-fire same-app sessions, drop blips.
    final sessions = <UsageSession>[];
    for (final s in rawSessions) {
      final last = sessions.isEmpty ? null : sessions.last;
      if (last != null &&
          last.packageName == s.packageName &&
          s.start.difference(last.end) < _mergeGap) {
        sessions[sessions.length - 1] = UsageSession(
          packageName: last.packageName,
          start: last.start,
          end: s.end,
        );
      } else {
        sessions.add(s);
      }
    }
    sessions.removeWhere((s) => s.end.difference(s.start) < _minSession);

    // --- Per-day rollups ---
    final byDay = <String, _DayAcc>{};
    final hourMinutes = List<int>.filled(24, 0);

    for (final s in sessions) {
      final key = '${s.start.year}-${s.start.month}-${s.start.day}';
      final acc = byDay.putIfAbsent(key, () => _DayAcc(s.start));
      acc.minutes += s.minutes;
      acc.pickups++;
      if (s.isNight) {
        acc.night += s.minutes;
      }
      if (s.end.difference(s.start) >= _longSession) {
        acc.longSessions++;
      }
      hourMinutes[s.start.hour] += s.minutes;
    }

    final days = byDay.entries
        .map(
          (e) => DayUsage(
            date: e.value.date,
            totalMinutes: e.value.minutes,
            pickups: e.value.pickups,
            nightMinutes: e.value.night,
            longSessions: e.value.longSessions,
          ),
        )
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final sessionCount = <String, int>{};
    for (final s in sessions) {
      sessionCount[s.packageName] = (sessionCount[s.packageName] ?? 0) + 1;
    }

    final top = totalByPkg.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topApps = top
        .take(10)
        .map(
          (e) => AppUsage(
            packageName: e.key,
            label: catalog[e.key]?.label ?? e.key,
            icon: catalog[e.key]?.icon,
            totalMinutes: e.value ~/ 60000,
            sessionCount: sessionCount[e.key] ?? 0,
          ),
        )
        .toList();

    var peakHour = 0;
    for (var h = 1; h < 24; h++) {
      if (hourMinutes[h] > hourMinutes[peakHour]) peakHour = h;
    }

    return UsageReport(
      days: days,
      topApps: topApps,
      longSessions:
          sessions.where((s) => s.end.difference(s.start) >= _longSession).toList(),
      totalMinutes: totalByPkg.values.fold(0, (a, b) => a + b) ~/ 60000,
      totalPickups: pickups,
      nightMinutes: days.fold(0, (a, d) => a + d.nightMinutes),
      peakHour: hourMinutes.every((m) => m == 0) ? null : peakHour,
      catalog: catalog,
    );
  }
}

class _DayAcc {
  final DateTime date;
  int minutes = 0;
  int pickups = 0;
  int night = 0;
  int longSessions = 0;
  _DayAcc(this.date);
}
