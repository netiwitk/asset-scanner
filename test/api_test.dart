import 'dart:convert';

import 'package:asset_scanner/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The JSON shape of GET /api/assets/{tag}, as asset-laravel's ScannedAssetResource sends it.
Map<String, Object?> assetJson({List<String> actions = const ['receive_return']}) => {
  'data': {
    'tag': 'AV-67-0034',
    'name': 'โปรเจกเตอร์ Epson',
    'category': 'โสตทัศนูปกรณ์',
    'department': 'ฝ่ายทรัพยากรบุคคล',
    'location': 'อาคาร A ชั้น 2',
    'custodian': null,
    'condition': {'value': 'usable', 'label': 'ใช้งานได้', 'tone': 'success'},
    'availability': {'value': 'on_loan', 'label': 'ถูกยืม', 'tone': 'info'},
    'book_value': '12345.60',
    'loan': {
      'status': {'value': 'handed_over', 'label': 'ส่งมอบแล้ว', 'tone': 'primary'},
      'borrower': 'พนักงานทดลอง',
      'due_on': '1 ต.ค. 2569',
      'is_overdue': true,
      'purpose': null,
    },
    'actions': actions,
  },
};

/// Like Laravel: JSON with no charset in the content type.
http.Response jsonResponse(Object? body, int status) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

AssetApi apiReturning(http.Response response) =>
    AssetApi('https://example.test', client: MockClient((_) async => response))..token = 't';

void main() {
  group('tagFromScan', () {
    test('reads a bare tag and a link to the app', () {
      expect(tagFromScan(' AV-67-0037 \n'), 'AV-67-0037');
      expect(tagFromScan('https://scan.example/#/a/AV-67-0037'), 'AV-67-0037');
      expect(tagFromScan('https://scan.example/#/a/A%20B'), 'A B');
    });

    test('ignores an empty code', () {
      expect(tagFromScan('   '), isNull);
    });
  });

  test('sends the token and reads Thai text sent without a charset', () async {
    late http.BaseRequest sent;
    final api = AssetApi(
      'https://example.test',
      client: MockClient((request) async {
        sent = request;
        return jsonResponse(assetJson(), 200);
      }),
    )..token = 'secret';

    final asset = await api.fetch('AV-67-0034');

    expect(sent.url.toString(), 'https://example.test/api/assets/AV-67-0034');
    expect(sent.headers['Authorization'], 'Bearer secret');
    expect(asset.name, 'โปรเจกเตอร์ Epson');
    expect(asset.loan!.isOverdue, isTrue);
    expect(asset.actions, [AssetAction.receiveReturn]);
  });

  test('skips an action this build does not know', () async {
    final asset = await apiReturning(jsonResponse(assetJson(actions: ['receive_return', 'teleport']), 200)).fetch('X');

    expect(asset.actions, [AssetAction.receiveReturn]);
  });

  test('turns each failure into the error the screens handle', () async {
    Future<ApiError> failure(http.Response response) async {
      try {
        await apiReturning(response).fetch('X');
      } on ApiError catch (error) {
        return error;
      }
      fail('expected an ApiError');
    }

    expect(await failure(jsonResponse({'message': 'Unauthenticated.'}, 401)), isA<SignedOut>());
    expect(await failure(jsonResponse({'message': 'Not Found'}, 404)), isA<NotFound>());
    expect(
      (await failure(jsonResponse({'message': 'ทรัพย์สินต้องใช้งานได้และว่างอยู่'}, 422))).message,
      'ทรัพย์สินต้องใช้งานได้และว่างอยู่',
    );
    expect(
      (await failure(
        jsonResponse({
          'message': 'The email field is required. (and 1 more error)',
          'errors': {
            'email': ['อีเมลหรือรหัสผ่านไม่ถูกต้อง'],
          },
        }, 422),
      )).message,
      'อีเมลหรือรหัสผ่านไม่ถูกต้อง',
    );
    expect(await failure(http.Response('<html>waking up</html>', 502)), isA<Unreachable>());
    expect(await failure(http.Response('<html>ok?</html>', 200)), isA<Unreachable>());
  });

  test('a dropped connection is Unreachable, not a crash', () async {
    final api = AssetApi('https://example.test', client: MockClient((_) => throw http.ClientException('offline')));

    await expectLater(api.fetch('X'), throwsA(isA<Unreachable>()));
  });
}
