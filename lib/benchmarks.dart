import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'models.dart';

/// Bundled world-benchmark facts — "world data" with zero network calls.
/// Selection is deterministic: only facts matching the detected pattern
/// reach the model, so it can't hallucinate numbers it never saw.
class Benchmarks {
  static List<_Fact>? _facts;
  static List<Comparison>? _comparisons;

  static Future<void> preload() async {
    if (_facts != null) return;
    final raw = await rootBundle.loadString('assets/benchmarks.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    _facts = (j['facts'] as List)
        .map((f) => _Fact(f['topic'], f['text']))
        .toList();
    _comparisons = (j['comparisons'] as List)
        .map((c) => Comparison(
              key: c['key'] as String,
              label: c['label'] as String,
              benchmark: (c['benchmark'] as num).toDouble(),
              unit: c['unit'] as String,
              note: c['note'] as String,
            ))
        .toList();
  }

  /// Structured you-vs-world comparisons for the dashboard.
  static Future<List<Comparison>> comparisons() async {
    await preload();
    return _comparisons ?? [];
  }

  /// Picks the 3-5 most relevant facts for this report.
  static Future<List<String>> select(UsageReport r) async {
    await preload();
    final facts = _facts ?? [];
    final topics = <String>{'total', 'goal'};

    if (r.totalPickups > 70) topics.add('pickups');
    if (r.dayCount > 0 && r.nightMinutes / r.totalMinutes.clamp(1, 99999) > 0.15 ||
        r.nightMinutes > 60) {
      topics.add('night');
    }
    if (r.topApps.any((a) =>
        (r.catalog[a.packageName]?.type == 'Social') &&
        a.totalMinutes > 60)) {
      topics.add('social');
    }
    if (r.longSessions.isNotEmpty) topics.add('sessions');

    return facts
        .where((f) => topics.contains(f.topic))
        .map((f) => f.text)
        .toList();
  }
}

class _Fact {
  final String topic;
  final String text;
  const _Fact(this.topic, this.text);
}

/// A user-vs-world benchmark comparison.
class Comparison {
  final String key;
  final String label;
  final double benchmark;
  final String unit; // 'min' | 'pct' | ''
  final String note;
  const Comparison({
    required this.key,
    required this.label,
    required this.benchmark,
    required this.unit,
    required this.note,
  });

  /// The user's corresponding value, computed from the report.
  double userValue(UsageReport r) => switch (key) {
        'daily_minutes' => r.avgDailyMinutes,
        _ => 0,
      };

  String fmt(double v) => switch (unit) {
        'min' => v >= 60 ? '${(v / 60).toStringAsFixed(1)}h' : '${v.round()}m',
        'pct' => '${(v * 100).round()}%',
        _ => v.round().toString(),
      };
}
