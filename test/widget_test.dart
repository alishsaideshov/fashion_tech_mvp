import 'package:fashion_tech_mvp/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AI stylist lookbook renders and starts generation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const FashionAiPocApp());

    expect(find.text('AI Stylist Lookbook'), findsOneWidget);
    expect(find.text('Person'), findsOneWidget);
    expect(find.text('Wardrobe'), findsOneWidget);
    expect(find.text('Style variations'), findsOneWidget);
    expect(find.text('Generated lookbook'), findsOneWidget);
    expect(find.text('Generate lookbook'), findsOneWidget);

    final generateButton = find.text('Generate lookbook');
    await tester.ensureVisible(generateButton);
    await tester.pumpAndSettle();
    await tester.tap(generateButton);
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('Casual'), findsAtLeastNWidgets(1));
    expect(find.text('Old Money'), findsAtLeastNWidgets(1));
    expect(find.text('Minimal Fashion'), findsAtLeastNWidgets(1));
  });
}
