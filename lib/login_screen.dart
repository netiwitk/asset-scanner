import 'package:flutter/material.dart';

import 'api.dart';
import 'common.dart';

/// The seeded accounts behind the demo server's one-tap logins.
const _demoAccounts = [
  (account: 'officer', role: 'เจ้าหน้าที่พัสดุ', can: 'ส่งมอบและรับคืนของได้ ทุกหน่วยงาน'),
  (account: 'staff', role: 'พนักงาน', can: 'ดูได้อย่างเดียว เฉพาะของหน่วยงานตัวเอง'),
  (account: 'admin', role: 'ผู้ดูแลระบบ', can: 'ทำได้ทุกอย่างเหมือนเจ้าหน้าที่พัสดุ'),
];

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api, required this.onSignedIn});

  final AssetApi api;
  final Future<void> Function(Session session) onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn(Future<Session> Function() attempt) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSignedIn(await attempt());
    } on ApiError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final emailForm = [
      TextField(
        controller: _email,
        decoration: const InputDecoration(labelText: 'อีเมล'),
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _password,
        decoration: const InputDecoration(labelText: 'รหัสผ่าน'),
        obscureText: true,
        autofillHints: const [AutofillHints.password],
        onSubmitted: (_) => _busy ? null : _signIn(() => widget.api.login(_email.text.trim(), _password.text)),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: _busy ? null : () => _signIn(() => widget.api.login(_email.text.trim(), _password.text)),
        child: const Text('เข้าสู่ระบบ'),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              shrinkWrap: true,
              children: [
                Text('สแกนทรัพย์สิน', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('ส่องคิวอาร์โค้ดบนครุภัณฑ์ เห็นสถานะและผู้ยืมทันที ส่งมอบหรือรับคืนได้จากหน้างาน', style: muted),
                const SizedBox(height: 36),
                if (isDemo) ...[
                  Text('ทดลองใช้ เลือกบทบาท', style: muted.copyWith(fontSize: 13)),
                  const SizedBox(height: 8),
                  const Divider(),
                  for (final demo in _demoAccounts) ...[
                    ListTile(
                      minVerticalPadding: 14,
                      title: Text(demo.role, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(demo.can, style: muted),
                      trailing: const Icon(Icons.chevron_right),
                      enabled: !_busy,
                      onTap: () => _signIn(() => widget.api.demoLogin(demo.account)),
                    ),
                    const Divider(),
                  ],
                  const SizedBox(height: 12),
                  ExpansionTile(
                    title: Text('เข้าสู่ระบบด้วยอีเมล', style: muted),
                    childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
                    children: emailForm,
                  ),
                ] else
                  ...emailForm,
                if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: SlowHint()),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
