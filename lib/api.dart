import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A status with its Thai label from the server, e.g. `on_loan` / "ถูกยืม",
/// and its tone, the web panel's badge colour name (success, warning, info...).
class Labelled {
  const Labelled(this.value, this.label, this.tone);

  Labelled.fromJson(Map<String, dynamic> json)
    : value = json['value'] as String,
      label = json['label'] as String,
      tone = json['tone'] as String? ?? 'gray';

  final String value;
  final String label;
  final String tone;
}

class ActiveLoan {
  ActiveLoan.fromJson(Map<String, dynamic> json)
    : status = Labelled.fromJson(json['status'] as Map<String, dynamic>),
      borrower = json['borrower'] as String,
      dueOn = json['due_on'] as String?,
      isOverdue = json['is_overdue'] as bool,
      purpose = json['purpose'] as String?;

  final Labelled status;
  final String borrower;
  final String? dueOn;
  final bool isOverdue;
  final String? purpose;
}

/// The buttons the server may offer. It decides who may press what; the app only draws them.
enum AssetAction {
  handOver('hand_over', 'hand-over', 'ส่งมอบ'),
  receiveReturn('receive_return', 'receive-return', 'รับคืน');

  const AssetAction(this.key, this.path, this.label);

  final String key;
  final String path;
  final String label;
}

class ScannedAsset {
  ScannedAsset.fromJson(Map<String, dynamic> json)
    : tag = json['tag'] as String,
      name = json['name'] as String,
      category = json['category'] as String,
      department = json['department'] as String,
      location = json['location'] as String?,
      custodian = json['custodian'] as String?,
      condition = Labelled.fromJson(json['condition'] as Map<String, dynamic>),
      availability = Labelled.fromJson(json['availability'] as Map<String, dynamic>),
      bookValue = json['book_value'] as String?,
      loan = json['loan'] == null ? null : ActiveLoan.fromJson(json['loan'] as Map<String, dynamic>),
      // An action this build does not know is skipped, so an older app keeps working after a server update.
      actions = [for (final key in json['actions'] as List) ...AssetAction.values.where((action) => action.key == key)];

  final String tag;
  final String name;
  final String category;
  final String department;
  final String? location;
  final String? custodian;
  final Labelled condition;
  final Labelled availability;
  final String? bookValue;
  final ActiveLoan? loan;
  final List<AssetAction> actions;
}

class Session {
  const Session({required this.token, required this.name, required this.role});

  Session.fromJson(Map<String, dynamic> json)
    : token = json['token'] as String,
      name = json['name'] as String,
      role = json['role'] as String;

  final String token;
  final String name;
  final String role;
}

/// Every way a request can fail, so each screen handles all of them.
sealed class ApiError implements Exception {
  const ApiError(this.message);

  final String message;
}

/// The token is missing, expired, revoked, or wiped by the demo's nightly reset.
class SignedOut extends ApiError {
  const SignedOut() : super('หมดเวลาเข้าใช้งาน กรุณาเข้าสู่ระบบใหม่');
}

class NotFound extends ApiError {
  const NotFound() : super('ไม่พบรหัสนี้ หรือทรัพย์สินนี้ไม่ได้อยู่ในหน่วยงานของคุณ');
}

/// The server understood the request and said no, with a reason in Thai.
class Refused extends ApiError {
  const Refused(super.message);
}

class Unreachable extends ApiError {
  const Unreachable() : super('เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ ลองอีกครั้ง');
}

/// Reads an asset tag from a scanned QR code: either the bare tag,
/// or a link to this app that ends in `#/a/<tag>` so a phone's own camera can open it.
String? tagFromScan(String raw) {
  final text = raw.trim();
  final link = RegExp(r'#/a/([^/?#]+)$').firstMatch(text);
  final tag = link == null ? text : Uri.decodeComponent(link.group(1)!);
  return tag.isEmpty ? null : tag;
}

class AssetApi {
  AssetApi(this.baseUrl, {http.Client? client}) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  /// Set after login; every other request sends it as a Bearer token.
  String? token;

  // The free demo server sleeps when idle and takes about a minute to wake.
  static const _timeout = Duration(seconds: 90);

  Future<Session> demoLogin(String account) async =>
      _signedIn(Session.fromJson(await _send('POST', '/api/tokens/demo/$account')));

  Future<Session> login(String email, String password) async =>
      _signedIn(Session.fromJson(await _send('POST', '/api/tokens', {'email': email, 'password': password})));

  Future<void> logout() async {
    try {
      await _send('DELETE', '/api/tokens/current');
    } on ApiError {
      // Signing out locally is what matters; a dead token is already signed out.
    }
    token = null;
  }

  Future<ScannedAsset> fetch(String tag) async => _asset(await _send('GET', _assetPath(tag)));

  Future<ScannedAsset> perform(String tag, AssetAction action, [Map<String, Object?> body = const {}]) async =>
      _asset(await _send('POST', '${_assetPath(tag)}/${action.path}', body));

  Session _signedIn(Session session) {
    token = session.token;
    return session;
  }

  String _assetPath(String tag) => '/api/assets/${Uri.encodeComponent(tag)}';

  ScannedAsset _asset(Map<String, dynamic> json) => ScannedAsset.fromJson(json['data'] as Map<String, dynamic>);

  Future<Map<String, dynamic>> _send(String method, String path, [Map<String, Object?>? body]) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers.addAll({
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      });
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request).timeout(_timeout));
    } on TimeoutException {
      throw const Unreachable();
    } on http.ClientException {
      throw const Unreachable();
    }

    Object? json;
    try {
      json = response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      json = null; // e.g. the host's HTML page while the server is still waking up
    }

    final status = response.statusCode;
    if (status == 401) throw const SignedOut();
    if (status == 404) throw const NotFound();
    if (status == 403 || status == 422 || status == 429) throw Refused(_reason(json, status));
    if (status == 204) return {};
    if (status >= 200 && status < 300 && json is Map<String, dynamic>) return json;
    throw const Unreachable();
  }

  /// A validation error's first field message reads better than Laravel's summary line.
  static String _reason(Object? json, int status) {
    if (status == 429) return 'ส่งคำขอถี่เกินไป รอสักครู่แล้วลองใหม่';
    if (json is! Map<String, dynamic>) return 'ทำรายการไม่สำเร็จ';
    final errors = json['errors'];
    if (errors is Map && errors.isNotEmpty) return (errors.values.first as List).first as String;
    return json['message'] as String? ?? 'ทำรายการไม่สำเร็จ';
  }
}
