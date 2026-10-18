import 'models.dart';
import 'daily_archive.dart';
import 'freeze_rules.dart';

/// How the coach should talk to the user — decided in code, narrated by
/// the model. The 1B model is never trusted to decide whether the user
/// deserves praise; it is only told what to say.
enum CoachTone { celebrate, coach, support }

/// Everything the app can congratulate the user on, computed
/// deterministically from the report, the daily archive, freeze rules and
/// unlock history.
class WinsSummary {
  /// Minutes under the world daily benchmark, across the pulled window.
  /// Positive = user beat the average.
  final int savedMinutes;
  final int streak;     // consecutive days under the benchmark, ending today
  final int bestStreak; // best streak in the archive
  final int heldNights; // freeze windows completed with no emergency unlock
  final InstalledApp? heldApp; // app whose freeze was held the longest
  final List<String> milestones;
  final CoachTone tone;

  const WinsSummary({
    required this.savedMinutes,
    required this.streak,
    required this.bestStreak,
    required this.heldNights,
    this.heldApp,
    required this.milestones,
    required this.tone,
  });

  bool get hasWins =>
      savedMinutes > 0 || streak >= 2 || heldNights > 0 || milestones.isNotEmpty;
}

class Wins {
  /// Global daily screen-time benchmark (kept in sync with
  /// assets/benchmarks.json → comparisons.daily_minutes).
  static const benchmarkMinutes = 400;

  static Future<WinsSummary> compute(UsageReport r) async {
    final archive = await DailyArchive.load();
    final rules = await FreezeStore.load();
    final events = await FreezeEvents.load();

    // ---- time saved vs the world ----
    final saved =
        ((benchmarkMinutes - r.avgDailyMinutes) * r.dayCount).round();

    // ---- streak: consecutive days under the benchmark, ending today ----
    var streak = 0;
    for (var i = archive.length - 1; i >= 0; i--) {
      if (archive[i].totalMinutes <= benchmarkMinutes) {
        streak++;
      } else {
        break;
      }
    }
    var best = streak;
    var run = 0;
    for (final d in archive) {
      run = d.totalMinutes <= benchmarkMinutes ? run + 1 : 0;
      if (run > best) best = run;
    }

    // ---- freeze nights held ----
    // A day counts as held for a rule when the rule was enabled that day
    // and no emergency unlock event exists for that package on that date.
    var held = 0;
    InstalledApp? heldApp;
    for (final rule in rules.where((r) => r.enabled)) {
      final unlockDays = events
          .where((e) => e.packageName == rule.packageName)
          .map((e) => _dayKey(e.at))
          .toSet();
      final daysActive = _daysActive(rule, archive);
      final heldDays = daysActive - unlockDays.length;
      if (heldDays > held) {
        held = heldDays;
        heldApp = r.catalog[rule.packageName];
      }
    }

    // ---- milestones ----
    final milestones = <String>[];
    if (r.avgDailyMinutes > 0 &&
        r.avgDailyMinutes <= benchmarkMinutes) {
      milestones.add('Under the world average');
    }
    if (r.longSessions.isEmpty && r.totalMinutes > 0) {
      milestones.add('Zero doom-scroll sessions');
    }
    if (r.totalMinutes > 0 && r.nightMinutes == 0) {
      milestones.add('Fully quiet nights');
    }
    if (_improvement(archive) >= 15) {
      milestones.add('Trending down ${_improvement(archive)}%');
    }
    if (streak >= 2) {
      milestones.add('$streak-day streak');
    }
    if (held > 0) {
      milestones.add('Freeze held $held ${held == 1 ? 'night' : 'nights'}');
    }

    // ---- tone ----
    final tone = saved > 0 || _improvement(archive) >= 15
        ? CoachTone.celebrate
        : (r.avgDailyMinutes > benchmarkMinutes * 1.2 ||
                _nightShare(r) > 0.25)
            ? CoachTone.support
            : CoachTone.coach;

    return WinsSummary(
      savedMinutes: saved,
      streak: streak,
      bestStreak: best,
      heldNights: held,
      heldApp: heldApp,
      milestones: milestones,
      tone: tone,
    );
  }

  /// Lightweight variant for the coach — same tone decision, no extra
  /// fields needed.
  static Future<CoachTone> toneFor(UsageReport r) async =>
      (await compute(r)).tone;

  static double _nightShare(UsageReport r) =>
      r.totalMinutes <= 0 ? 0 : r.nightMinutes / r.totalMinutes;

  /// Percentage drop of the last 3 archived days vs the 3 before them.
  /// Zero when there isn't enough history.
  static int _improvement(List<DayStat> archive) {
    if (archive.length < 4) return 0;
    final recent = archive.sublist(archive.length - 3);
    final prior = archive.sublist(
        archive.length - 6 < 0 ? 0 : archive.length - 6, archive.length - 3);
    if (prior.isEmpty) return 0;
    final priorAvg =
        prior.fold<int>(0, (s, d) => s + d.totalMinutes) / prior.length;
    final recentAvg =
        recent.fold<int>(0, (s, d) => s + d.totalMinutes) / recent.length;
    if (priorAvg <= 0 || recentAvg >= priorAvg) return 0;
    return (((priorAvg - recentAvg) / priorAvg) * 100).round();
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// How many days the rule has existed inside known history — from its
  /// creation date (or the start of the archive for legacy rules) through
  /// today.
  static int _daysActive(FreezeRule rule, List<DayStat> archive) {
    final now = DateTime.now();
    final created = rule.createdAt ?? (archive.isEmpty ? now : DateTime.parse(archive.first.date));
    var days = now.difference(created).inDays + 1;
    if (days < 1) days = 1;
    if (days > 30) days = 30;
    return days;
  }
}
