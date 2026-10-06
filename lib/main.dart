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
  final api = AssetApi(apiUrl);
  runApp(scannerApp((tag) => Home(api: api, prefs: prefs, openTag: tag)));
}

/// [home] is given the asset tag when the app is opened from a QR link like `https://.../#/a/AV-67-0037`.
MaterialApp scannerApp(Widget Function(String? tag) home) {
  Route<void> route(String? name) {
    final tag = name != null && name.startsWith('/a/') ? tagFromScan('#$name') : null;
    return MaterialPageRoute<void>(builder: (_) => home(tag));
  }

  return MaterialApp(
    title: 'สแกนทรัพย์สิน',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    // A link opened while the app is already running.
    onGenerateRoute: (settings) => route(settings.name),
    // The link the app started with, as one page; by default Flutter would stack a page per path segment.
    onGenerateInitialRoutes: (name) => [route(name)],
  );
}

/// Signed out: the login screen. Signed in: the scanner.
class Home extends StatefulWidget {
  const Home({super.key, required this.api, required this.prefs, this.openTag});

  final AssetApi api;
  final SharedPreferences prefs;
  final String? openTag;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  /// Read when this page opens, so a page opened later by a link sees a sign-in made after start-up.
  late Session? _session = _savedSession();
  late String? _openTag = widget.openTag;

  Session? _savedSession() {
    final token = widget.prefs.getString('token');
    if (token == null) return null;
    return Session(
      token: token,
      name: widget.prefs.getString('name') ?? '',
      role: widget.prefs.getString('role') ?? '',
    );
  }

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
    final page = ModalRoute.of(context);
    Navigator.of(context).popUntil((route) => route == page);
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
  // fidelity keeps the brand blue itself as the primary colour instead of a softened tone of it.
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2563EB),
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  return ThemeData(
    colorScheme: scheme,
    fontFamily: 'IBM Plex Sans Thai',
    scaffoldBackgroundColor: brightness == Brightness.light ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
    cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  );
}
