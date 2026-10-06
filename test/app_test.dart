import 'package:asset_scanner/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a QR link opens one home page that is handed the asset tag', (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/a/AV-67-0037';
    addTearDown(tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);

    await tester.pumpWidget(scannerApp((tag) => Text('home $tag')));

    expect(find.text('home AV-67-0037', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('home', skipOffstage: false), findsOneWidget);
  });

  testWidgets('a plain start opens home with no tag', (tester) async {
    await tester.pumpWidget(scannerApp((tag) => Text('home $tag')));

    expect(find.text('home null'), findsOneWidget);
  });
}
