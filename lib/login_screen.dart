import 'package:flutter/material.dart';

import 'api.dart';
import 'common.dart';

/// The seeded accounts behind the demo server's one-tap logins.
const _demoAccounts = [
  (account: 'officer', role: 'เจ้าหน้าที่พัสดุ', can: 'ส่งมอบและรับคืนของได้ ทุกหน่วยงาน', icon: Icons.badge_outlined),
  (account: 'staff', role: 'พนักงาน', can: 'ดูได้อย่างเดียว เฉพาะของหน่วยงานตัวเอง', icon: Icons.person_outline),
  (
    account: 'admin',
    role: 'ผู้ดูแลระบบ',
    can: 'ทำได้ทุกอย่างเหมือนเจ้าหน้าที่พัสดุ',
    icon: Icons.admin_panel_settings_outlined,
  ),
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
      const SizedBox(height: 12),
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
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Icon(Icons.qr_code_scanner, size: 48, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text('สแกนทรัพย์สิน', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                  'ส่องคิวอาร์โค้ดบนครุภัณฑ์ เห็นสถานะและผู้ยืมทันที ส่งมอบหรือรับคืนได้จากหน้างาน',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                if (isDemo) ...[
                  Text('ทดลองใช้ เลือกบทบาท', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  for (final demo in _demoAccounts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          leading: Icon(demo.icon),
                          title: Text(demo.role),
                          subtitle: Text(demo.can),
                          trailing: const Icon(Icons.chevron_right),
                          enabled: !_busy,
                          onTap: () => _signIn(() => widget.api.demoLogin(demo.account)),
                        ),
                      ),
                    ),
                  ExpansionTile(
                    title: const Text('เข้าสู่ระบบด้วยอีเมล'),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 8),
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
