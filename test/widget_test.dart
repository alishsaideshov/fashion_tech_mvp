import 'package:fashion_tech_mvp/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Outfit generator renders and starts generation', (tester) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const FashionAiPocApp());

    expect(find.text('Outfit Generator'), findsOneWidget);
    expect(find.text('Selected clothes'), findsOneWidget);
    expect(find.text('Outfit photo'), findsOneWidget);
    expect(find.text('Generate outfit photo'), findsOneWidget);

    await tester.tap(find.text('Generate outfit photo'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Generation error'), findsOneWidget);
  });
}
