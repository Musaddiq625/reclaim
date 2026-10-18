import 'package:flutter/material.dart';

import '../aggregator.dart';
import '../app_catalog.dart';
import '../daily_archive.dart';
import '../freeze_rules.dart';
import '../coach_service.dart';
import '../models.dart';
import '../usage_service.dart';
import 'coach_screen.dart';
import 'dashboard_screen.dart';
import 'onboarding_screen.dart';

/// Owns the permission gate and the pulled [UsageReport]. Re-pulling is
/// manual (refresh button) — nothing runs in the background.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _usage = UsageService();
  final _coach = CoachService();

  bool _checking = true;
  bool _granted = false;
  bool _loading = false;
  UsageReport? _report;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _coach.tryAttach();
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Re-check permission when returning from the Settings toggle.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_granted) _check();
  }

  Future<void> _check() async {
    final granted = await _usage.hasPermission();
    setState(() {
      _granted = granted;
      _checking = false;
    });
    if (granted && _report == null) _pull();
  }

  Future<void> _pull() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await _usage.pullHistory();
      final report = Aggregator().build(raw);
      AppCatalogStore.save(report.catalog); // fire-and-forget local JSON
      DailyArchive.record(report.days); // grow history beyond Android's 7d
      FreezeStore.file().then(
          (f) => FreezeBridge.setRulesFile(f.path)); // sync path to native
      setState(() => _report = report);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_granted) {
      return OnboardingScreen(onGrant: _usage.requestPermission);
    }
    return DashboardScreen(
      report: _report,
      loading: _loading,
      error: _error,
      onRefresh: _pull,
      onOpenCoach: _report == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      CoachScreen(coach: _coach, report: _report!),
                ),
              ),
    );
  }
}
