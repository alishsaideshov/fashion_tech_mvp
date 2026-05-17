import 'package:fashion_tech_mvp/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Visual AI POC renders and runs validation', (tester) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const FashionAiPocApp());

    expect(find.text('Visual AI POC'), findsOneWidget);
    expect(find.text('Input set'), findsOneWidget);
    expect(find.text('Output examples'), findsOneWidget);

    final runButton = find.text('Generate validation run');
    await tester.ensureVisible(runButton);
    await tester.pumpAndSettle();
    await tester.tap(runButton);
    await tester.pump();

    expect(find.text('Running validation'), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_top), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));

    expect(find.text('18.4s mock'), findsOneWidget);
    expect(find.text('ship to review'), findsOneWidget);
  });
}
