import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'benchmarks.dart';
import 'models.dart';
import 'secrets.dart';
import 'wins.dart';

/// On-device Gemma coach. All inference stays on the phone — nothing is
/// uploaded. Two-pass design: pass 1 analyzes, pass 2 plans. The model
/// narrates stats computed by [Aggregator]; it is never asked to do
/// arithmetic.
class CoachService extends ChangeNotifier {
  /// Non-gated mirrors don't exist for Gemma — Hugging Face requires a free
  /// account token after accepting the model license once on the site.
  static const defaultModelUrl =
      'https://huggingface.co/litert-community/Gemma3-1B-IT/'
      'resolve/main/Gemma3-1B-IT_multi-prefill-seq_q4_block128_ekv4096.task';
  static const _tokenKey = 'hf_token';
  static const _modelSrcKey = 'model_source';

  double? downloadProgress;
  bool modelReady = false;
  bool busy = false;
  String? error;

  /// What the model is doing right now, shown under the spinner.
  String? stage;

  /// Human-friendly name of the installed model, e.g.
  /// "Gemma 3 1B IT · 4K context". Derived from the install source.
  String? modelName;

  String? _errDetail;

  static String _nameFor(String src) {
    final file = Uri.parse(src).pathSegments.last;
    if (file.contains('ekv4096')) return 'Gemma 3 1B IT · 4K context';
    if (file.contains('Gemma3-1B')) return 'Gemma 3 1B IT';
    return file.replaceAll(RegExp(r'\.task$'), '');
  }

  InferenceChat? _chat;

  Future<String?> savedToken() async =>
      (await SharedPreferences.getInstance()).getString(_tokenKey) ??
      (Secrets.hfToken.isNotEmpty ? Secrets.hfToken : null);

  /// Downloads (once) and loads the .task model. [filePath] is the escape
  /// hatch: adb-push any .task model and point at it.
  Future<void> setupModel({String? hfToken, String? filePath}) async {
    error = null;
    downloadProgress = 0.0;
    notifyListeners();
    try {
      final builder = FlutterEdgeAi.installModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.task,
      );
      if (filePath != null && filePath.isNotEmpty) {
        await builder.fromFile(filePath).install();
        modelName = _nameFor(filePath);
      } else {
        final token = (hfToken == null || hfToken.isEmpty)
            ? Secrets.hfToken
            : hfToken;
        await builder
            .fromNetwork(defaultModelUrl, token: token)
            .withProgress((p) {
              downloadProgress = p.toDouble();
              notifyListeners();
            })
            .install();
        modelName = _nameFor(defaultModelUrl);
        if (hfToken != null && hfToken.isNotEmpty) {
          (await SharedPreferences.getInstance())
              .setString(_tokenKey, hfToken);
        }
      }
      (await SharedPreferences.getInstance()).setString(
          _modelSrcKey, filePath?.isNotEmpty == true ? filePath! : defaultModelUrl);
      downloadProgress = null;
      await _openChat();
    } catch (e) {
      error = 'Model setup failed: $e';
      downloadProgress = null;
      notifyListeners();
    }
  }

  /// Reattach to an already-installed model (e.g. after app restart).
  Future<void> tryAttach() async {
    try {
      final src = (await SharedPreferences.getInstance())
          .getString(_modelSrcKey);
      if (src != null) modelName = _nameFor(src);
      await _openChat();
    } catch (_) {
      // No installed model yet — setup screen will handle it.
    }
  }

  Future<void> _openChat() async {
    final model = await FlutterEdgeAi.getActiveModel(maxTokens: 1024);
    _chat = await model.createChat(
      temperature: 0.4,
      topK: 40,
      topP: 0.9,
      modelType: ModelType.gemmaIt,
    );
    modelReady = true;
    notifyListeners();
  }

  /// Two-pass digest: analysis first, then the plan. Narrow prompts keep a
  /// small model reliable.
  Future<CoachDigest?> generateDigest(UsageReport r) async {
    if (!modelReady || busy) return null;
    busy = true;
    error = null;
    _errDetail = null;
    notifyListeners();
    try {
      final benchmarks = await Benchmarks.select(r);
      final tone = await Wins.toneFor(r);

      stage = 'Analyzing your week…';
      notifyListeners();
      final pass1 =
          await _runPass(_analysisPrompt(r, benchmarks, tone));
      if (pass1 == null) {
        error = 'Model returned nothing usable'
            '${_errDetail != null ? ' — $_errDetail' : ''}.';
        notifyListeners();
        return null;
      }

      stage = 'Writing your plan…';
      notifyListeners();
      final pass2 = await _runPass(
        _planPrompt(r, benchmarks, pass1['verdict'] as String?, tone),
      );

      return _merge(pass1, pass2, r);
    } catch (e) {
      error = 'Generation failed: $e';
      notifyListeners();
      return null;
    } finally {
      busy = false;
      stage = null;
      notifyListeners();
    }
  }

  /// Fresh chat per pass — keeps each call isolated.
  /// Async stream with timeout; falls back to the sync call if the stream
  /// hangs or produces nothing.
  Future<Map<String, dynamic>?> _runPass(String prompt) async {
    var raw = await _generateStreaming(prompt)
        .timeout(const Duration(seconds: 150), onTimeout: () {
      _errDetail = 'generation exceeded 150s';
      return '';
    });
    if (raw.isEmpty) {
      debugPrint('[coach] stream empty — retrying sync');
      raw = await _generateSync(prompt);
    }
    debugPrint('[coach] raw output (${raw.length} chars): $raw');
    if (raw.isEmpty) return null;
    final j = _extractJson(raw);
    if (j == null) _errDetail = 'output was not valid JSON';
    return j;
  }

  Future<String> _generateStreaming(String prompt) async {
    try {
      await _openChat();
      await _chat!.addQuery(Message.text(text: prompt, isUser: true));
      final buf = StringBuffer();
      await for (final res in _chat!
          .generateChatResponseAsync()
          .timeout(const Duration(seconds: 45), onTimeout: (_) {
        throw TimeoutException('token stream stalled');
      })) {
        if (res is TextResponse && res.token.isNotEmpty) {
          buf.write(res.token);
        } else if (res is ThinkingResponse &&
            res.content.isNotEmpty) {
          buf.write(res.content);
        }
      }
      return buf.toString().trim();
    } catch (e) {
      debugPrint('[coach] streaming failed: $e');
      _errDetail = 'stream: $e';
      return '';
    }
  }

  Future<String> _generateSync(String prompt) async {
    try {
      await _openChat();
      await _chat!.addQuery(Message.text(text: prompt, isUser: true));
      final res = await _chat!
          .generateChatResponse()
          .timeout(const Duration(seconds: 90));
      if (res is TextResponse) return res.token.trim();
      _errDetail = 'sync: no text in response';
      return '';
    } catch (e) {
      debugPrint('[coach] sync failed: $e');
      _errDetail = 'sync: $e';
      return '';
    }
  }

  static Map<String, dynamic>? _extractJson(String raw) {
    try {
      final start = raw.indexOf('{');
      final end = raw.lastIndexOf('}');
      if (start == -1 || end <= start) return null;
      return jsonDecode(raw.substring(start, end + 1))
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  CoachDigest _merge(
    Map<String, dynamic>? a,
    Map<String, dynamic>? p,
    UsageReport r,
  ) {
    String? str(Map<String, dynamic>? j, String k) =>
        j != null && j[k] is String ? j[k] as String : null;
    int? num_(Map<String, dynamic>? j, String k) =>
        j != null && j[k] is num ? (j[k] as num).toInt() : null;

    final plan = <PlanAction>[];
    final rawPlan = p?['plan'];
    if (rawPlan is List) {
      for (final item in rawPlan) {
        if (item is! Map) continue;
        final m = item.cast<String, dynamic>();
        plan.add(PlanAction(
          action: (m['action'] as String?) ?? 'note',
          appPackage: m['app'] as String?,
          limitMinutes: m['limit_minutes'] is num
              ? (m['limit_minutes'] as num).toInt()
              : null,
          window: m['window'] as String?,
          reason: m['reason'] as String?,
          suggestion: m['suggestion'] as String?,
        ));
      }
    }

    final raw = jsonEncode({'analysis': a, 'plan': p});
    return CoachDigest(
      verdict: str(a, 'verdict') ?? '',
      patternInsight: str(a, 'pattern_insight'),
      sinkApp: str(a, 'sink_app'),
      sinkWhy: str(a, 'sink_why'),
      dailyGoalMinutes: num_(p, 'daily_goal_minutes'),
      plan: plan,
      win: str(p, 'win') ?? str(a, 'win'),
      raw: raw,
      parsed: a != null || p != null,
    );
  }

  static String _fmtHour(int h) =>
      h == 0 ? '12am' : h < 12 ? '${h}am' : h == 12 ? '12pm' : '${h - 12}pm';

  String _stats(UsageReport r) {
    String fmtH(int mins) => '${(mins / 60).toStringAsFixed(1)}h';
    final appLines = r.topApps
        .take(5)
        .map((a) =>
            '${a.packageName} (${a.label}): ${fmtH(a.totalMinutes)}, ${a.sessionCount} sessions')
        .join('; ');
    return '''${r.dayCount} days: ${fmtH(r.totalMinutes)} total, ${r.totalPickups} opens, ${fmtH(r.nightMinutes)} after 11pm, ${r.longSessions.length} 20m+ sessions${r.peakHour != null ? ', peak ${_fmtHour(r.peakHour!)}' : ''}. Top apps: $appLines''';
  }

  /// Code decides the user's emotional state, the model only voices it.
  static String _toneInstruction(CoachTone tone) => switch (tone) {
        CoachTone.celebrate =>
          'The user is doing genuinely well. Open with real praise that names the specific number they beat. Celebrate first, advise second.',
        CoachTone.support =>
          'The numbers are heavy. Be extra gentle — zero shame, zero lecturing. Frame everything as a small experiment, not a failure.',
        CoachTone.coach =>
          'Balanced tone: honest read, one clear strength, one clear opportunity.',
      };

  String _analysisPrompt(
      UsageReport r, List<String> benchmarks, CoachTone tone) {
    final facts = benchmarks.map((f) => '- $f').join('\n');
    return '''You are a kind digital-wellbeing coach. Never invent numbers.

Tone for this reply: ${_toneInstruction(tone)}

Phone usage: ${_stats(r)}

World context:
$facts

Reply with ONLY a JSON object (no markdown, no prose) with these keys, each value ONE short sentence:
- "verdict": honest encouraging read on the pattern
- "pattern_insight": the WHY behind it
- "sink_app": worst app, copy its package name exactly from above
- "sink_why": when/how it's used
- "win": one encouraging observation''';
  }

  String _planPrompt(
      UsageReport r, List<String> benchmarks, String? verdict,
      CoachTone tone) {
    final facts = benchmarks.take(3).map((f) => '- $f').join('\n');
    final appChoices = r.topApps
        .take(5)
        .map((a) => '${a.packageName} (${a.label})')
        .join(', ');
    return '''You are a kind digital-wellbeing coach. Usage: ${_stats(r)}

Tone for this reply: ${_toneInstruction(tone)}
${tone == CoachTone.celebrate ? 'The plan should mostly protect what is already working — reinforce good windows rather than adding new restrictions.' : ''}
Verdict already given: "${verdict ?? ''}"
Context: $facts

Write an action plan — small concrete moves, supportive tone. 2-3 items. Reply with ONLY a JSON object with keys:
- "daily_goal_minutes": integer, ~15% below current average
- "plan": array of objects, each with keys:
    "action": one of "cap" (limit an app in a window), "protect" (keep a window app-free), "replace" (swap a habit)
    "app": package name copied exactly from [$appChoices], or null
    "limit_minutes": integer or null
    "window": 12h format like "11pm-1am", or null
    "reason": one short sentence
    "suggestion": for "replace" only, else null
- "win": one short encouraging observation''';
  }
}
