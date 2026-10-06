import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';

/// Set at build time: `--dart-define=API_URL=https://...`.
const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'https://asset-laravel.onrender.com');

/// The portfolio build shows one-tap demo logins; a client build leaves this off.
const isDemo = bool.fromEnvironment('DEMO');

/// A progress bar that, after a few seconds, explains why the free demo server is slow.
class SlowHint extends StatefulWidget {
  const SlowHint({super.key});

  @override
  State<SlowHint> createState() => _SlowHintState();
}

class _SlowHintState extends State<SlowHint> {
  bool _slow = false;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 4), () => setState(() => _slow = true));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LinearProgressIndicator(),
        if (_slow)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'เซิร์ฟเวอร์ทดลองใช้แบบฟรีกำลังตื่น อาจใช้เวลาราว 1 นาที',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

/// A status as a dot coloured like the web panel's badge for the same status, then its label.
class StatusDot extends StatelessWidget {
  const StatusDot(this.status, {super.key});

  final Labelled status;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: toneColor(Theme.of(context).colorScheme, status.tone),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 7),
        Text(status.label, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }
}

Color toneColor(ColorScheme scheme, String tone) {
  final dark = scheme.brightness == Brightness.dark;
  return switch (tone) {
    'success' => dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
    'warning' => dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
    'danger' => scheme.error,
    'info' => dark ? const Color(0xFF22D3EE) : const Color(0xFF0E7490),
    'primary' => scheme.primary,
    _ => scheme.onSurfaceVariant,
  };
}

/// "12345.60" → "฿12,345.60"
String baht(String amount) {
  final [whole, ...fraction] = amount.split('.');
  final grouped = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');
  return '฿$grouped${fraction.isEmpty ? '' : '.${fraction.first}'}';
}
