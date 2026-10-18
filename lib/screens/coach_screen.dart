import 'package:flutter/material.dart';

import '../coach_service.dart';
import '../freeze_rules.dart';
import '../models.dart';

/// AI coach — model download + structured digest, fully on-device.
class CoachScreen extends StatefulWidget {
  final CoachService coach;
  final UsageReport report;

  const CoachScreen({super.key, required this.coach, required this.report});

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  final _tokenCtrl = TextEditingController();
  final _fileCtrl = TextEditingController();
  CoachDigest? _digest;

  /// Plan actions already turned into freeze rules this session.
  final Set<String> _frozen = {};

  @override
  void initState() {
    super.initState();
    widget.coach.savedToken().then((t) => _tokenCtrl.text = t ?? '');
    widget.coach.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.coach.removeListener(_rebuild);
    _tokenCtrl.dispose();
    _fileCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() => _digest = null);
    final out = await widget.coach.generateDigest(widget.report);
    if (mounted) setState(() => _digest = out);
  }

  /// Tap "Freeze it" → confirmation dialog → only then is the rule saved.
  Future<void> _freezeFromPlan(PlanAction a) async {
    final pkg = a.appPackage ?? _digest?.sinkApp;
    if (pkg == null) return;
    final window = parseWindowToMinutes(a.window) ??
        (23 * 60, 7 * 60); // default night window
    final ok = await _showFreezeConfirm(pkg, window);
    if (ok != true || !mounted) return;

    final rules = await FreezeStore.load();
    if (!rules.any((r) =>
        r.packageName == pkg &&
        r.startMin == window.$1 &&
        r.endMin == window.$2)) {
      rules.add(FreezeRule(
        packageName: pkg,
        startMin: window.$1,
        endMin: window.$2,
        createdAt: DateTime.now(),
      ));
      await FreezeStore.save(rules);
    }
    if (!mounted) return;
    setState(() => _frozen.add('${a.action}|$pkg|${a.window}'));
  }

  static String _fmtMin(int m) {
    final h24 = m ~/ 60, mm = m % 60;
    final suffix = h24 >= 12 ? 'PM' : 'AM';
    final h12 = h24 == 0 ? 12 : h24 > 12 ? h24 - 12 : h24;
    return '$h12:${mm.toString().padLeft(2, '0')} $suffix';
  }

  Future<bool?> _showFreezeConfirm(String pkg, (int, int) window) {
    final app = widget.report.appFor(pkg);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (app?.icon != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(app!.icon!,
                    width: 44, height: 44, gaplessPlayback: true),
              )
            else
              const Icon(Icons.ac_unit,
                  size: 40, color: Colors.lightBlueAccent),
            const SizedBox(height: 10),
            Text(
              'Freeze ${app?.label ?? pkg}?',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '${_fmtMin(window.$1)} — ${_fmtMin(window.$2)}',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: Colors.lightBlueAccent),
            ),
            const SizedBox(height: 4),
            Text(
              'The app will be blocked every day in this window.\n'
              'You can change or remove it in Freeze windows.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.ac_unit, size: 16),
            label: const Text('Freeze it'),
          ),
        ],
      ),
    );
  }

  /// Resolves any package the model echoes. Top-10 apps keep their real
  /// stats; anything else falls back to the catalog (icon + label only).
  AppUsage? _appFor(String? packageName) {
    if (packageName == null) return null;
    for (final a in widget.report.topApps) {
      if (a.packageName == packageName) return a;
    }
    final meta = widget.report.appFor(packageName);
    if (meta == null) return null;
    return AppUsage(
      packageName: meta.packageName,
      label: meta.label,
      icon: meta.icon,
      totalMinutes: 0,
      sessionCount: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.coach;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AI coach')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
        children: [
          if (!c.modelReady) ...[
            Text('Set up the on-device model', style: t.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Gemma 3 1B (~0.6 GB) downloads once and runs entirely on your '
              'phone. Hugging Face requires a free token: create one at '
              'huggingface.co/settings/tokens after accepting the Gemma '
              'license, or load a .task file manually.',
              style: t.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tokenCtrl,
              decoration: const InputDecoration(
                labelText: 'Hugging Face token',
                hintText: 'hf_…',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: c.downloadProgress != null
                    ? null
                    : () => c.setupModel(hfToken: _tokenCtrl.text.trim()),
                icon: const Icon(Icons.download),
                label: const Text('Download & load model'),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _fileCtrl,
              decoration: InputDecoration(
                labelText: '…or load .task file from a path',
                hintText: '/sdcard/Download/model.task',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.check),
                  onPressed: () =>
                      c.setupModel(filePath: _fileCtrl.text.trim()),
                ),
              ),
            ),
            if (c.downloadProgress != null) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: (c.downloadProgress! / 100)),
              const SizedBox(height: 4),
              Text('${c.downloadProgress!.toStringAsFixed(0)}%',
                  style: t.bodySmall),
            ],
          ] else ...[
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.greenAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${c.modelName ?? 'Gemma'} ready — fully offline',
                    style: t.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: c.busy ? null : _generate,
                icon: const Icon(Icons.auto_awesome),
                label: Text(c.busy ? 'Thinking…' : 'Generate my digest'),
              ),
            ),
            const SizedBox(height: 16),
            if (c.busy)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    if (c.stage != null) ...[
                      const SizedBox(height: 12),
                      Text(c.stage!, style: t.bodySmall),
                    ],
                  ],
                ),
              ),
            if (_digest != null && !c.busy) _DigestView(
              digest: _digest!,
              appFor: _appFor,
              onFreeze: _freezeFromPlan,
              isFrozen: (a) => _frozen
                  .contains('${a.action}|${a.appPackage}|${a.window}'),
            ),
          ],
          if (c.error != null) ...[
            const SizedBox(height: 12),
            Text(c.error!, style: TextStyle(color: Colors.red.shade300)),
          ],
        ],
      ),
    );
  }
}

/// Designed digest — verdict banner, insight, sink card with real app icon,
/// daily goal, plan actions (freezable), win card. Falls back to raw text.
class _DigestView extends StatelessWidget {
  final CoachDigest digest;
  final AppUsage? Function(String?) appFor;
  final void Function(PlanAction) onFreeze;
  final bool Function(PlanAction) isFrozen;

  const _DigestView({
    required this.digest,
    required this.appFor,
    required this.onFreeze,
    required this.isFrozen,
  });

  @override
  Widget build(BuildContext context) {
    if (!digest.parsed) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(digest.raw,
              style: Theme.of(context).textTheme.bodyLarge),
        ),
      );
    }
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _VerdictCard(text: digest.verdict),
        if (digest.patternInsight != null) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.insights, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(digest.patternInsight!, style: t.bodyMedium)),
            ],
          ),
        ],
        const SizedBox(height: 12),
        if (digest.sinkApp != null || digest.sinkWhy != null)
          _SinkCard(app: appFor(digest.sinkApp), why: digest.sinkWhy ?? ''),
        if (digest.dailyGoalMinutes != null) ...[
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFF1B3B4A),
            child: ListTile(
              leading: const Icon(Icons.flag),
              title: const Text('Daily target'),
              trailing: Text(
                _fmtGoal(digest.dailyGoalMinutes!),
                style: t.titleLarge,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text('Your plan', style: t.titleMedium),
        const SizedBox(height: 8),
        for (final a in digest.plan)
          _PlanCard(
              action: a,
              appFor: appFor,
              onFreeze: onFreeze,
              frozen: isFrozen(a)),
        if (digest.win != null) ...[
          const SizedBox(height: 12),
          _WinCard(text: digest.win!),
        ],
      ],
    );
  }

  static String _fmtGoal(int m) =>
      m >= 60 ? '${(m / 60).toStringAsFixed(1)}h' : '${m}m';
}

class _PlanCard extends StatelessWidget {
  final PlanAction action;
  final AppUsage? Function(String?) appFor;
  final void Function(PlanAction) onFreeze;
  final bool frozen;

  const _PlanCard({
    required this.action,
    required this.appFor,
    required this.onFreeze,
    required this.frozen,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final app = appFor(action.appPackage);
    final freezable = action.appPackage != null || action.action == 'cap';

    final (icon, title, body) = switch (action.action) {
      'cap' => (
          Icons.timelapse,
          'Cap ${app?.label ?? action.appPackage ?? ''}'
              '${action.limitMinutes != null ? ' · ${action.limitMinutes}m' : ''}',
          action.reason,
        ),
      'protect' => (
          Icons.shield_outlined,
          app != null ? 'Protect from ${app.label}' : 'Protected time',
          action.reason,
        ),
      'replace' => (
          Icons.swap_horiz,
          app != null ? 'Swap ${app.label}' : 'Swap the habit',
          action.suggestion ?? action.reason,
        ),
      _ => (Icons.lightbulb_outline, 'Note', action.reason ?? action.suggestion),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (app?.icon != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(app!.icon!,
                        width: 24, height: 24, gaplessPlayback: true),
                  )
                else
                  Icon(icon, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: t.titleSmall)),
                if (app?.icon != null) Icon(icon, size: 16, color: Colors.white38),
              ],
            ),
            if (body != null && body.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(body, style: t.bodyMedium),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (action.window != null)
                  Chip(
                    avatar: const Icon(Icons.schedule, size: 15),
                    label: Text(action.window!),
                    visualDensity: VisualDensity.compact,
                  ),
                const Spacer(),
                if (freezable)
                  frozen
                      ? const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle,
                                size: 18, color: Colors.greenAccent),
                            SizedBox(width: 4),
                            Text('Frozen'),
                          ],
                        )
                      : TextButton.icon(
                          onPressed: () => onFreeze(action),
                          icon: const Icon(Icons.ac_unit, size: 16),
                          label: const Text('Freeze it'),
                        ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VerdictCard extends StatelessWidget {
  final String text;
  const _VerdictCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF6C63FF), Color(0xFF3A3B8F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.format_quote, color: Colors.white70),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SinkCard extends StatelessWidget {
  final AppUsage? app;
  final String why;
  const _SinkCard({required this.app, required this.why});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('BIGGEST TIME SINK',
                style: t.labelSmall?.copyWith(letterSpacing: 1.2)),
            const SizedBox(height: 12),
            Row(
              children: [
                if (app?.icon != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(app!.icon!,
                        width: 44, height: 44, gaplessPlayback: true),
                  )
                else
                  const Icon(Icons.apps, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(app?.label ?? 'Unknown app',
                          style: t.titleMedium,
                          overflow: TextOverflow.ellipsis),
                      if (app != null && app!.totalMinutes > 0)
                        Text(_fmt(app!.totalMinutes),
                            style: t.headlineSmall
                                ?.copyWith(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ],
            ),
            if (why.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(why, style: t.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }

  static String _fmt(int m) => m >= 60
      ? '${(m / 60).toStringAsFixed(1)} hours'
      : '$m minutes';
}

class _WinCard extends StatelessWidget {
  final String text;
  const _WinCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF143A2A),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.emoji_events, color: Colors.greenAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: Theme.of(context).textTheme.bodyLarge),
            ),
          ],
        ),
      ),
    );
  }
}
