import 'dart:convert';

import 'package:asset_scanner/api.dart';
import 'package:asset_scanner/asset_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'api_test.dart' show assetJson, jsonResponse;

void main() {
  testWidgets('shows only the server\'s buttons and takes back a damaged asset', (tester) async {
    final posted = <String, Object?>{};
    final api = AssetApi(
      'https://example.test',
      client: MockClient((request) async {
        if (request.method == 'GET') return jsonResponse(assetJson(), 200);
        posted
          ..['path'] = request.url.path
          ..addAll(jsonDecode(request.body) as Map<String, Object?>);
        final returned = assetJson(actions: []);
        ((returned['data'] as Map<String, Object?>)..['loan'] = null)['condition'] = {
          'value': 'damaged',
          'label': 'ชำรุด',
          'tone': 'warning',
        };
        return jsonResponse(returned, 200);
      }),
    )..token = 't';

    // A phone-sized screen, as the app is used.
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: AssetScreen(api: api, tag: 'AV-67-0034', onSignOut: ({bool expired = false}) async {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('โปรเจกเตอร์ Epson'), findsOneWidget);
    expect(find.text('฿12,345.60'), findsOneWidget);
    expect(find.text('เกินกำหนด'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'รับคืน'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'ส่งมอบ'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'รับคืน'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ชำรุด'));
    await tester.enterText(find.byType(TextField), '  จอแตกมุมขวา ');
    await tester.tap(find.text('ยืนยันรับคืน'));
    await tester.pumpAndSettle();

    expect(posted, {'path': '/api/assets/AV-67-0034/receive-return', 'condition': 'damaged', 'note': 'จอแตกมุมขวา'});
    expect(find.text('รับคืนแล้ว'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'รับคืน'), findsNothing);
    expect(find.text('ตอนนี้ไม่มีรายการที่คุณทำกับชิ้นนี้ได้'), findsOneWidget);
  });
}
