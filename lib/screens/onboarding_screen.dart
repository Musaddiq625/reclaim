import 'package:flutter/material.dart';

/// Permission onboarding — explains why Usage Access is needed and that the
/// data never leaves the phone. The whole pitch in one screen.
class OnboardingScreen extends StatelessWidget {
  final VoidCallback onGrant;
  const OnboardingScreen({super.key, required this.onGrant});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const Icon(Icons.lock_outline, size: 56),
              const SizedBox(height: 20),
              Text('Your usage never leaves this phone', style: t.headlineSmall),
              const SizedBox(height: 12),
              Text(
                'Reclaim reads the last 7 days of app usage Android already '
                'keeps on-device, then a local AI model coaches you on the '
                'patterns. No account. No server. No upload.',
                style: t.bodyLarge,
              ),
              const SizedBox(height: 28),
              const _Step(
                n: '1',
                text: 'Tap below — Android opens "Apps with usage access".',
              ),
              const _Step(n: '2', text: 'Find Reclaim and toggle it on.'),
              const _Step(n: '3', text: 'Come back — the app picks up from there.'),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onGrant,
                  icon: const Icon(Icons.settings),
                  label: const Text('Grant usage access'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String n;
  final String text;
  const _Step({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 13, child: Text(n, style: const TextStyle(fontSize: 13))),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
