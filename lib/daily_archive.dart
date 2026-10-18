import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// One archived day of usage — enough to compute streaks and trends.
class DayStat {
  final String date; // YYYY-MM-DD
  final int totalMinutes;
  final int pickups;
  final int nightMinutes;

  const DayStat({
    required this.date,
    required this.totalMinutes,
    required this.pickups,
    required this.nightMinutes,
  });

  factory DayStat.fromJson(Map<String, dynamic> j) => DayStat(
        date: j['date'] as String,
        totalMinutes: j['min'] as int,
        pickups: j['pickups'] as int? ?? 0,
        nightMinutes: j['night'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() =>
      {'date': date, 'min': totalMinutes, 'pickups': pickups, 'night': nightMinutes};
}

/// Long-term daily history. Android only retains ~7 days of usage events,
/// so every pull merges its per-day totals into this archive — the app
/// builds its own history beyond Android's window without tracking
/// anything live.
class DailyArchive {
  static const _fileName = 'daily_archive.json';

  static Future<File> file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static Future<List<DayStat>> load() async {
    try {
      final f = await file();
      if (!f.existsSync()) return [];
      final list = jsonDecode(f.readAsStringSync()) as List;
      final days =
          list.map((e) => DayStat.fromJson(e as Map<String, dynamic>)).toList();
      days.sort((a, b) => a.date.compareTo(b.date));
      return days;
    } catch (_) {
      return [];
    }
  }

  /// Merges the latest pull's per-day totals into the archive. Today's
  /// entry is partial and simply gets overwritten by the next pull.
  static Future<void> record(List<DayUsage> days) async {
    try {
      final existing = {for (final d in await load()) d.date: d};
      for (final d in days) {
        existing[_key(d.date)] = DayStat(
          date: _key(d.date),
          totalMinutes: d.totalMinutes,
          pickups: d.pickups,
          nightMinutes: d.nightMinutes,
        );
      }
      final merged = existing.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      final f = await file();
      await f.writeAsString(
          jsonEncode(merged.map((d) => d.toJson()).toList()));
    } catch (_) {}
  }
}
