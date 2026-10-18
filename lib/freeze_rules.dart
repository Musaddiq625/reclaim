import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// Persists freeze rules to a local JSON file AND hands the file's path to
/// the native accessibility service, which reads it on every window event —
/// so rules keep working even when the Flutter UI isn't running.
class FreezeStore {
  static const _fileName = 'freeze_rules.json';

  static Future<File> file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<List<FreezeRule>> load() async {
    try {
      final f = await file();
      if (!f.existsSync()) return [];
      final list = jsonDecode(f.readAsStringSync()) as List;
      return list
          .map((e) => FreezeRule.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<FreezeRule> rules) async {
    final f = await file();
    await f.writeAsString(
        jsonEncode(rules.map((r) => r.toJson()).toList()));
    await FreezeBridge.setRulesFile(f.path);
  }
}

/// Parses model-emitted windows like "11pm-1am" or "9:30 PM - 7 AM"
/// into (startMin, endMin). Returns null on failure.
(int, int)? parseWindowToMinutes(String? window) {
  if (window == null) return null;
  final matches = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)', caseSensitive: false)
      .allMatches(window)
      .toList();
  if (matches.length < 2) return null;
  int toMin(RegExpMatch m) {
    var h = int.parse(m.group(1)!);
    final mm = int.parse(m.group(2) ?? '0');
    final mer = m.group(3)!.toLowerCase();
    if (mer == 'am') {
      if (h == 12) h = 0;
    } else {
      if (h != 12) h += 12;
    }
    return h * 60 + mm;
  }
  return (toMin(matches[0]), toMin(matches[1]));
}

/// One emergency-unlock event, written by the native freeze service.
class FreezeEvent {
  static const unlockMinutes = 5; // must match SNOOZE_MS in FreezeService

  final String packageName;
  final DateTime at;
  final bool cancelled;

  const FreezeEvent({
    required this.packageName,
    required this.at,
    this.cancelled = false,
  });

  DateTime get endsAt => at.add(const Duration(minutes: unlockMinutes));
  bool get isActive => !cancelled && DateTime.now().isBefore(endsAt);

  factory FreezeEvent.fromJson(Map<String, dynamic> j) => FreezeEvent(
        packageName: j['package'] as String,
        at: DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
        cancelled: j['cancelled'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'package': packageName,
        'at': at.millisecondsSinceEpoch,
        if (cancelled) 'cancelled': true,
      };
}

/// Reads unlock history written by the native service.
class FreezeEvents {
  static Future<File> _file() async {
    final rules = await FreezeStore.file();
    return File('${rules.parent.path}/freeze_events.json');
  }

  static Future<List<FreezeEvent>> load() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return [];
      final list = jsonDecode(f.readAsStringSync()) as List;
      return list
          .map((e) => FreezeEvent.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Marks a package's still-active unlock as revoked — the history count
  /// stays, but the pass no longer counts as live in the UI. (The native
  /// side clears its own snooze when the rules file is rewritten.)
  static Future<void> cancelActiveFor(String packageName) async {
    try {
      final events = await load();
      var changed = false;
      final next = events.map((e) {
        if (e.packageName == packageName && e.isActive) {
          changed = true;
          return FreezeEvent(
              packageName: e.packageName, at: e.at, cancelled: true);
        }
        return e;
      }).toList();
      if (changed) {
        final f = await _file();
        await f.writeAsString(
            jsonEncode(next.map((e) => e.toJson()).toList()));
      }
    } catch (_) {}
  }
}

/// Channel to the native accessibility freeze service.
class FreezeBridge {
  static const _channel = MethodChannel('reclaim/freeze');

  /// Whether the accessibility service is currently enabled in Settings.
  static Future<bool> isServiceEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isServiceEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens system Accessibility settings so the user can enable the service.
  static Future<void> openAccessibilitySettings() =>
      _channel.invokeMethod('openAccessibilitySettings');

  /// Registers the rules file path with the native side (stored in native
  /// SharedPreferences so the service finds it even after process death).
  static Future<void> setRulesFile(String path) =>
      _channel.invokeMethod('setRulesFile', {'path': path});
}
