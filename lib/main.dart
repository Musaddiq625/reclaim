import 'package:flutter/material.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_mediapipe/flutter_edge_ai_mediapipe.dart';

import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterEdgeAi.initialize(
    inferenceEngines: [MediaPipeEngine()],
  );
  runApp(const ReclaimApp());
}

class ReclaimApp extends StatelessWidget {
  const ReclaimApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reclaim',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
      builder: (context, child) => Column(
        children: [
          Expanded(
            child: MediaQuery(
              data: MediaQuery.of(context).removePadding(removeBottom: true),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
          const _CreditFooter(),
        ],
      ),
    );
  }
}

class _CreditFooter extends StatelessWidget {
  const _CreditFooter();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Center(
            child: Text(
              'Built with ❤️ by Musaddiq625',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
