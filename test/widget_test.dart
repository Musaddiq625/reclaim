import 'package:flutter_test/flutter_test.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:reclaim/aggregator.dart';
import 'package:reclaim/models.dart';
import 'package:reclaim/usage_service.dart';

void main() {
  test('aggregator reconstructs sessions and ignores system packages', () {
    final base = DateTime(2026, 10, 14, 23, 0);
    EventUsageInfo fg(String pkg, DateTime t) => EventUsageInfo(
        packageName: pkg,
        eventType: '1',
        timeStamp: '${t.millisecondsSinceEpoch}');
    EventUsageInfo bg(String pkg, DateTime t) => EventUsageInfo(
        packageName: pkg,
        eventType: '2',
        timeStamp: '${t.millisecondsSinceEpoch}');

    final raw = RawUsage(
      stats: [
        UsageInfo(
          packageName: 'com.instagram.android',
          totalTimeInForeground: '${45 * 60000}',
        ),
        UsageInfo(
          packageName: 'com.android.systemui',
          totalTimeInForeground: '${999 * 60000}',
        ),
      ],
      events: [
        fg('com.instagram.android', base),
        bg('com.instagram.android', base.add(const Duration(minutes: 25))),
        fg('com.android.systemui', base),
        bg('com.android.systemui', base.add(const Duration(minutes: 10))),
      ],
      catalog: const [
        InstalledApp(
            packageName: 'com.instagram.android',
            label: 'Instagram',
            isSystem: false),
      ],
    );

    final report = Aggregator().build(raw);

    expect(report.totalMinutes, 45); // systemui excluded
    expect(report.totalPickups, 1);
    expect(report.topApps.single.label, 'Instagram');
    expect(report.topApps.single.sessionCount, 1);
    expect(report.longSessions.length, 1); // 25 min session
    expect(report.nightMinutes, 25); // started at 23:00
  });
}
