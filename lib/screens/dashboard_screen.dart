import 'dart:math' show cos, sin;

import 'package:confetti/confetti.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../benchmarks.dart';
import '../models.dart';
import '../wins.dart';
import 'freeze_rules_screen.dart';

/// Stats dashboard — every number here is computed in Dart, not by the model.
class DashboardScreen extends StatelessWidget {
  final UsageReport? report;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  final VoidCallback? onOpenCoach;

  const DashboardScreen({
    super.key,
    required this.report,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onOpenCoach,
  });

  static String _h(int mins) =>
      mins >= 60 ? '${(mins / 60).toStringAsFixed(1)}h' : '${mins}m';

  static String _fmtHour(int h) =>
      h == 0 ? '12am' : h < 12 ? '${h}am' : h == 12 ? '12pm' : '${h - 12}pm';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reclaim'),
        actions: [
          TextButton(onPressed: loading ? null : onRefresh, child: const Text('Refresh')),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onOpenCoach,
        icon: const Icon(Icons.psychology_alt),
        label: const Text('AI coach'),
      ),
      body: _body(context, t),
    );
  }

  Widget _body(BuildContext context, TextTheme t) {
    if (loading && report == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(error!)));
    }
    final r = report;
    if (r == null) {
      return const Center(child: Text('Pull to load your usage history.'));
    }
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Row(
            children: [
              _StatCard('Total (7d)', _h(r.totalMinutes)),
              _StatCard('Avg / day', _h(r.avgDailyMinutes.round())),
              _StatCard('Pickups', '${r.totalPickups}'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _StatCard('After 11pm', _h(r.nightMinutes)),
              _StatCard('20m+ sessions', '${r.longSessions.length}'),
              _StatCard('Peak hour',
                  r.peakHour == null ? '—' : _fmtHour(r.peakHour!)),
            ],
          ),
          const SizedBox(height: 16),
          _WinsSection(report: r),
          const SizedBox(height: 24),
          Text('Screen time by day', style: t.titleMedium),
          const SizedBox(height: 12),
          SizedBox(height: 160, child: _DayChart(days: r.days)),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.ac_unit),
              title: const Text('Freeze apps'),
              subtitle: const Text('Schedule windows where apps can\'t open'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FreezeRulesScreen(catalog: r.catalog),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _BenchmarkSection(report: r),
          const SizedBox(height: 24),
          Text('Top apps', style: t.titleMedium),
          const SizedBox(height: 8),
          for (final a in r.topApps.take(8))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: a.icon != null
                  ? Image.memory(a.icon!, width: 32, height: 32, gaplessPlayback: true)
                  : const Icon(Icons.apps),
              title: Text(a.label, overflow: TextOverflow.ellipsis),
              subtitle: Text('${a.sessionCount} sessions', style: t.bodySmall),
              trailing: Text(_h(a.totalMinutes), style: t.titleSmall),
            ),
        ],
      ),
    );
  }
}

/// Celebration zone — every win here is computed in code ([Wins]),
/// never invented by the model. Confetti fires once per section load
/// when the tone is celebratory.
class _WinsSection extends StatefulWidget {
  final UsageReport report;
  const _WinsSection({required this.report});

  @override
  State<_WinsSection> createState() => _WinsSectionState();
}

class _WinsSectionState extends State<_WinsSection> {
  late final Future<WinsSummary> _future =
      Wins.compute(widget.report);
  final _confetti =
      ConfettiController(duration: const Duration(seconds: 2));
  bool _played = false;

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  static String _h(int mins) => mins >= 60
      ? '${(mins / 60).toStringAsFixed(1)}h'
      : '${mins}m';

  void _maybeCelebrate(WinsSummary w) {
    if (!_played && w.tone == CoachTone.celebrate && w.hasWins) {
      _played = true;
      _confetti.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return FutureBuilder<WinsSummary>(
      future: _future,
      builder: (_, snap) {
        final w = snap.data;
        if (w == null || !w.hasWins) return const SizedBox.shrink();
        _maybeCelebrate(w);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.topCenter,
              children: [
                Column(
                  children: [
                    if (w.savedMinutes > 0)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF14532D), Color(0xFF166534)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.emoji_events,
                                color: Colors.amberAccent, size: 36),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text('You saved ${_h(w.savedMinutes)}',
                                      style: t.titleLarge?.copyWith(
                                          color: Colors.white)),
                                  Text(
                                    'vs the average person this week',
                                    style: t.bodySmall?.copyWith(
                                        color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (w.heldNights > 0) ...[
                      const SizedBox(height: 8),
                      Card(
                        child: ListTile(
                          leading: w.heldApp?.icon != null
                              ? Image.memory(w.heldApp!.icon!,
                                  width: 32,
                                  height: 32,
                                  gaplessPlayback: true)
                              : const Icon(Icons.ac_unit),
                          title: Text(
                            'Freeze held ${w.heldNights} '
                            '${w.heldNights == 1 ? 'night' : 'nights'}',
                          ),
                          subtitle: Text(
                            w.heldApp != null
                                ? 'No emergency unlocks on '
                                    '${w.heldApp!.label}'
                                : 'No emergency unlocks used',
                            style: t.bodySmall,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                ConfettiWidget(
                  confettiController: _confetti,
                  blastDirectionality: BlastDirectionality.explosive,
                  numberOfParticles: 18,
                  maxBlastForce: 14,
                  minBlastForce: 6,
                  gravity: 0.35,
                  shouldLoop: false,
                  colors: const [
                    Colors.greenAccent,
                    Colors.amberAccent,
                    Colors.lightBlueAccent,
                    Colors.pinkAccent,
                  ],
                ),
              ],
            ),
            if (w.streak >= 2 ||
                w.bestStreak >= 2 ||
                w.milestones.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (w.streak >= 2)
                    _Chip(
                      icon: Icons.local_fire_department,
                      label: w.bestStreak > w.streak
                          ? '${w.streak}-day streak · best ${w.bestStreak}'
                          : '${w.streak}-day streak',
                      color: Colors.orangeAccent,
                    ),
                  for (final m in w.milestones)
                    _Chip(
                      icon: Icons.military_tech,
                      label: m,
                      color: Colors.lightBlueAccent,
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// "You vs the world" — gauge cards comparing the user to benchmarks.
class _BenchmarkSection extends StatelessWidget {
  final UsageReport report;
  const _BenchmarkSection({required this.report});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Comparison>>(
      future: Benchmarks.comparisons(),
      builder: (_, snap) {
        final items = snap.data ?? const <Comparison>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            items.length == 1
                ? Center(
                    child: SizedBox(
                      width: 190,
                      child: _GaugeCard(c: items.first, report: report),
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final c in items)
                        Expanded(child: _GaugeCard(c: c, report: report)),
                    ],
                  ),
          ],
        );
      },
    );
  }
}

/// A semicircle dial: your arc vs the world-average marker.
class _GaugeCard extends StatelessWidget {
  final Comparison c;
  final UsageReport report;
  const _GaugeCard({required this.c, required this.report});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final user = c.userValue(report);
    final ratio = c.benchmark == 0 ? 1.0 : user / c.benchmark;
    final under = user <= c.benchmark;
    final color = under ? Colors.greenAccent : Colors.orangeAccent;
    final pct = (ratio * 100).round();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
        child: Column(
          children: [
            Text(c.label, style: t.labelSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: CustomPaint(
                size: const Size(104, 52),
                painter: _GaugePainter(
                  // benchmark marker sits at 2/3 of the dial, so "at
                  // average" = two-thirds full; 1.5x avg fills it
                  fraction: (ratio / 1.5).clamp(0.0, 1.0),
                  marker: 1 / 1.5,
                  color: color,
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Text(c.fmt(user),
                      style: t.titleLarge?.copyWith(color: color)),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                under ? 'below avg' : '$pct% of avg',
                style: t.labelSmall?.copyWith(color: color),
              ),
            ),
            const SizedBox(height: 4),
            Text('${c.note}: ${c.fmt(c.benchmark)}',
                style: t.labelSmall?.copyWith(color: Colors.white38),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double fraction; // 0..1 of the dial filled
  final double marker;   // 0..1 position of the world marker
  final Color color;

  const _GaugePainter({
    required this.fraction,
    required this.marker,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.height - 6;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = -3.14159; // left
    const sweep = 3.14159;  // half circle

    final track = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, track);

    if (fraction > 0) {
      final fill = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, start, sweep * fraction, false, fill);
    }

    // world-average marker — a short tick across the arc
    final a = start + sweep * marker;
    final inner = Offset(
      center.dx + (radius - 10) * cos(a),
      center.dy + (radius - 10) * sin(a),
    );
    final outer = Offset(
      center.dx + (radius + 4) * cos(a),
      center.dy + (radius + 4) * sin(a),
    );
    canvas.drawLine(inner, outer, Paint()
      ..color = Colors.white70
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction || old.marker != marker || old.color != color;
}

class _DayChart extends StatelessWidget {
  final List<DayUsage> days;
  const _DayChart({required this.days});

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const Center(child: Text('No usage events yet.'));
    final max = days.map((d) => d.totalMinutes).reduce((a, b) => a > b ? a : b);
    return BarChart(
      BarChartData(
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  DateFormat('E').format(days[v.toInt()].date),
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < days.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: days[i].totalMinutes.toDouble(),
                  width: 18,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            ),
        ],
        maxY: max * 1.15,
      ),
    );
  }
}
