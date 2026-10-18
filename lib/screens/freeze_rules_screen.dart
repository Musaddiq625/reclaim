import 'dart:async';

import 'package:flutter/material.dart';

import '../freeze_rules.dart';
import '../models.dart';

/// Freeze rules editor — user-controlled list of apps with their daily
/// freeze windows. Saved to a local JSON file the native service reads.
class FreezeRulesScreen extends StatefulWidget {
  final Map<String, InstalledApp> catalog;
  const FreezeRulesScreen({super.key, required this.catalog});

  @override
  State<FreezeRulesScreen> createState() => _FreezeRulesScreenState();
}

class _FreezeRulesScreenState extends State<FreezeRulesScreen>
    with WidgetsBindingObserver {
  List<FreezeRule> _rules = [];
  List<FreezeEvent> _events = [];
  bool _serviceOn = false;
  bool _loaded = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
    // Refresh every 15s so an "unlocked until" badge expires on screen.
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check the toggle when returning from system Settings.
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _reload() async {
    final rules = await FreezeStore.load();
    final events = await FreezeEvents.load();
    final on = await FreezeBridge.isServiceEnabled();
    if (mounted) {
      setState(() {
        _rules = rules;
        _events = events;
        _serviceOn = on;
        _loaded = true;
      });
    }
  }

  int _unlocksFor(String pkg) =>
      _events.where((e) => e.packageName == pkg).length;

  FreezeEvent? _lastUnlock(String pkg) {
    final list = _events.where((e) => e.packageName == pkg).toList();
    if (list.isEmpty) return null;
    list.sort((a, b) => b.at.compareTo(a.at));
    return list.first;
  }

  Future<void> _save() async {
    await FreezeStore.save(_rules);
    if (mounted) setState(() {});
  }

  static String _fmtMin(int m) {
    final h24 = m ~/ 60;
    final mm = m % 60;
    final suffix = h24 >= 12 ? 'PM' : 'AM';
    final h12 = h24 == 0 ? 12 : h24 > 12 ? h24 - 12 : h24;
    return '$h12:${mm.toString().padLeft(2, '0')} $suffix';
  }

  Future<void> _addRule() async {
    final apps = widget.catalog.values
        .where((a) => !a.isSystem && a.packageName != 'com.reclaim.musaddiq625')
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    final picked = await showModalBottomSheet<InstalledApp>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AppPicker(apps: apps),
    );
    if (picked == null || !mounted) return;

    final start = await _pickTime('Freeze from');
    if (start == null) return;
    final end = await _pickTime('Until');
    if (end == null) return;

    setState(() {
      _rules.add(FreezeRule(
        packageName: picked.packageName,
        startMin: start,
        endMin: end,
        createdAt: DateTime.now(),
      ));
    });
    await _save();
  }

  Future<void> _editRule(int i) async {
    final rule = _rules[i];
    final start = await _pickTime('Freeze from', initial: rule.startMin);
    if (start == null) return;
    final end = await _pickTime('Until', initial: rule.endMin);
    if (end == null) return;
    await FreezeEvents.cancelActiveFor(rule.packageName);
    setState(() => _rules[i] = rule.copyWith(startMin: start, endMin: end));
    await _save();
    _reload();
  }

  Future<int?> _pickTime(String title, {int? initial}) async {
    final now = initial ?? 0;
    final t = await showTimePicker(
      context: context,
      helpText: title,
      initialTime: TimeOfDay(hour: now ~/ 60, minute: now % 60),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Freeze windows')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _serviceOn ? _addRule : null,
        icon: const Icon(Icons.add),
        label: const Text('Add freeze'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!_serviceOn)
                  Card(
                    color: const Color(0xFF4A2A1E),
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber),
                      title: const Text('Freeze engine is off'),
                      subtitle: const Text(
                          'Enable "Reclaim" in Accessibility settings to enforce freezes.'),
                      trailing: TextButton(
                        onPressed: () async {
                          await FreezeBridge.openAccessibilitySettings();
                        },
                        child: const Text('Enable'),
                      ),
                    ),
                  ),
                if (_rules.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: Center(
                      child: Text(
                        'No freezes yet.\nThe AI coach will propose them —\nor add your own.',
                        textAlign: TextAlign.center,
                        style: t.bodyLarge,
                      ),
                    ),
                  ),
                if (_events.isNotEmpty)
                  Card(
                    color: const Color(0xFF3A2A4A),
                    child: ListTile(
                      leading: const Icon(Icons.door_front_door_outlined),
                      title: Text('${_events.length} emergency unlocks'),
                      subtitle: Text(
                          'Each unlock is a 5-minute pass — they add up.'),
                    ),
                  ),
                for (var i = 0; i < _rules.length; i++)
                  _RuleTile(
                    rule: _rules[i],
                    app: widget.catalog[_rules[i].packageName],
                    unlocks: _unlocksFor(_rules[i].packageName),
                    lastUnlock: _lastUnlock(_rules[i].packageName),
                    fmt: _fmtMin,
                    onToggle: (v) async {
                      // Toggling a rule revokes any live emergency unlock.
                      await FreezeEvents.cancelActiveFor(
                          _rules[i].packageName);
                      setState(
                          () => _rules[i] = _rules[i].copyWith(enabled: v));
                      await _save();
                      _reload();
                    },
                    onEdit: () => _editRule(i),
                    onDelete: () async {
                      final pkg = _rules[i].packageName;
                      await FreezeEvents.cancelActiveFor(pkg);
                      setState(() => _rules.removeAt(i));
                      await _save();
                      _reload();
                    },
                  ),
              ],
            ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  final FreezeRule rule;
  final InstalledApp? app;
  final int unlocks;
  final FreezeEvent? lastUnlock;
  final String Function(int) fmt;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RuleTile({
    required this.rule,
    required this.app,
    required this.unlocks,
    required this.lastUnlock,
    required this.fmt,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  static String _fmtAt(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'today ${_fmtClock(d)}';
    }
    return '${d.month}/${d.day} ${_fmtClock(d)}';
  }

  static String _fmtClock(DateTime d) {
    final h = d.hour == 0 ? 12 : d.hour > 12 ? d.hour - 12 : d.hour;
    return '$h:${d.minute.toString().padLeft(2, '0')} '
        '${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final active = lastUnlock?.isActive ?? false;
    final left = active
        ? lastUnlock!.endsAt.difference(DateTime.now()).inMinutes + 1
        : 0;
    return Card(
      child: ListTile(
        onTap: onEdit,
        leading: app?.icon != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(app!.icon!,
                    width: 36, height: 36, gaplessPlayback: true),
              )
            : const Icon(Icons.apps),
        title: Text(app?.label ?? rule.packageName,
            overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${fmt(rule.startMin)} – ${fmt(rule.endMin)} · tap to edit',
              style: t.bodySmall,
            ),
            if (active)
              Text(
                'Unlocked until ${_fmtClock(lastUnlock!.endsAt)}'
                ' · $left min left',
                style: t.bodySmall?.copyWith(color: Colors.orangeAccent),
              )
            else if (unlocks > 0)
              Text(
                '$unlocks past unlock${unlocks == 1 ? '' : 's'}'
                '${lastUnlock != null ? ' · last ${_fmtAt(lastUnlock!.at)}' : ''}',
                style: t.bodySmall?.copyWith(color: Colors.white38),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: rule.enabled, onChanged: onToggle),
            IconButton(
                icon: const Icon(Icons.delete_outline), onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}

class _AppPicker extends StatefulWidget {
  final List<InstalledApp> apps;
  const _AppPicker({required this.apps});

  @override
  State<_AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends State<_AppPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _q.isEmpty
        ? widget.apps
        : widget.apps
            .where((a) =>
                a.label.toLowerCase().contains(_q.toLowerCase()) ||
                a.packageName.toLowerCase().contains(_q.toLowerCase()))
            .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (_, ctrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search apps…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: ctrl,
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final a = filtered[i];
                return ListTile(
                  dense: true,
                  leading: a.icon != null
                      ? Image.memory(a.icon!,
                          width: 28, height: 28, gaplessPlayback: true)
                      : const Icon(Icons.apps),
                  title: Text(a.label),
                  subtitle: a.type != 'Undefined' ? Text(a.type) : null,
                  onTap: () => Navigator.pop(context, a),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
