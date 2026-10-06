import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'common.dart';
import 'login_screen.dart';
import 'scan_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Screen readers, and on the web real DOM nodes that browser tests can find.
  SemanticsBinding.instance.ensureSemantics();

  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token');
  final saved = token == null
      ? null
      : Session(token: token, name: prefs.getString('name') ?? '', role: prefs.getString('role') ?? '');

  final home = Home(api: AssetApi(apiUrl), prefs: prefs, saved: saved, openTag: _tagInLink());
  runApp(
    MaterialApp(
      title: 'สแกนทรัพย์สิน',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      // The URL hash may hold `/a/<tag>`. It is read by _tagInLink, not looked up as a route name.
      onGenerateInitialRoutes: (_) => [MaterialPageRoute<void>(builder: (_) => home)],
    ),
  );
}

/// A QR label can hold a link like `https://.../#/a/AV-67-0037`; opening it shows that asset.
String? _tagInLink() {
  final link = Uri.base.toString();
  return link.contains('#/a/') ? tagFromScan(link) : null;
}

/// Signed out: the login screen. Signed in: the scanner.
class Home extends StatefulWidget {
  const Home({super.key, required this.api, required this.prefs, this.saved, this.openTag});

  final AssetApi api;
  final SharedPreferences prefs;
  final Session? saved;
  final String? openTag;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late Session? _session = widget.saved;
  late String? _openTag = widget.openTag;

  @override
  void initState() {
    super.initState();
    widget.api.token = _session?.token;
  }

  Future<void> _signIn(Session session) async {
    await widget.prefs.setString('token', session.token);
    await widget.prefs.setString('name', session.name);
    await widget.prefs.setString('role', session.role);
    setState(() => _session = session);
  }

  /// [expired]: the server already refused the token, so there is nothing to revoke.
  Future<void> _signOut({bool expired = false}) async {
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (!expired) await widget.api.logout();
    widget.api.token = null;
    await widget.prefs.remove('token');
    setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) return LoginScreen(api: widget.api, onSignedIn: _signIn);
    return ScanScreen(
      key: ValueKey(session.token),
      api: widget.api,
      session: session,
      openTag: _openTag,
      onOpened: () => _openTag = null,
      onSignOut: _signOut,
    );
  }
}

ThemeData _theme(Brightness brightness) {
  // Blue and slate, the same palette as the asset-laravel web panel.
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB), brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: brightness == Brightness.light ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
    cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  );
}
