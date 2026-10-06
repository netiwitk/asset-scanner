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

/// Minimal: ink on a plain page, hairlines instead of boxes, and the brand blue only on the main action.
ThemeData _theme(Brightness brightness) {
  final light = brightness == Brightness.light;
  final page = light ? Colors.white : const Color(0xFF0B1120);
  final ink = light ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
  final muted = light ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
  final line = light ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B);
  // The same blue as the asset-laravel web panel.
  final blue = light ? const Color(0xFF2563EB) : const Color(0xFF3B82F6);

  final scheme = ColorScheme.fromSeed(seedColor: blue, brightness: brightness).copyWith(
    primary: blue,
    onPrimary: Colors.white,
    surface: page,
    onSurface: ink,
    onSurfaceVariant: muted,
    outline: muted,
    outlineVariant: line,
    surfaceTint: Colors.transparent,
    surfaceContainerLow: page,
    surfaceContainerHigh: page,
    inverseSurface: ink,
    onInverseSurface: page,
  );
  final rounded = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
  final hairline = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: line),
  );

  return ThemeData(
    colorScheme: scheme,
    fontFamily: 'IBM Plex Sans Thai',
    scaffoldBackgroundColor: page,
    appBarTheme: AppBarTheme(
      backgroundColor: page,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'IBM Plex Sans Thai',
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
    ),
    dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: rounded,
        textStyle: const TextStyle(fontFamily: 'IBM Plex Sans Thai', fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: rounded,
        foregroundColor: ink,
        side: BorderSide(color: line),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: ink, shape: rounded),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: hairline,
      enabledBorder: hairline,
      focusedBorder: hairline.copyWith(borderSide: BorderSide(color: blue, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(color: muted),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: rounded,
        side: BorderSide(color: line),
        selectedBackgroundColor: line,
        selectedForegroundColor: ink,
        foregroundColor: muted,
      ),
    ),
    listTileTheme: ListTileThemeData(contentPadding: EdgeInsets.zero, iconColor: muted),
    expansionTileTheme: ExpansionTileThemeData(
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: EdgeInsets.zero,
      iconColor: muted,
      collapsedIconColor: muted,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: page,
      dragHandleColor: line,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: page,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: rounded),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: blue, linearTrackColor: line, linearMinHeight: 2),
  );
}
