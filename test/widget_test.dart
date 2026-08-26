import 'dart:convert';
import 'dart:io';

import 'package:fashion_tech_mvp/ai/ai_validation_models.dart';
import 'package:fashion_tech_mvp/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [390.0, 1200.0]) {
    testWidgets(
      'wardrobe keeps multiple selections and supports removal at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final photos = [
          for (final size in ['hdpi', 'xhdpi', 'xxhdpi'])
            AiImageInput(
              name: '$size.png',
              mimeType: 'image/png',
              base64Data: base64Encode(
                File(
                  'android/app/src/main/res/mipmap-$size/ic_launcher.png',
                ).readAsBytesSync(),
              ),
            ),
        ];
        var pickCount = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: LookbookPage(
              garmentPicker: () async {
                pickCount++;
                return switch (pickCount) {
                  1 => photos.take(2).toList(),
                  2 => [photos.last],
                  _ => [],
                };
              },
            ),
          ),
        );
        Future<void> tapLabel(String label) async {
          final button = find.text(label);
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
        }

        await tapLabel('Upload clothes');
        expect(find.text('2/5 photos selected'), findsOneWidget);
        await tapLabel('Add clothes');
        expect(find.text('3/5 photos selected'), findsOneWidget);
        for (final photo in photos) {
          expect(find.text(photo.name), findsOneWidget);
        }
        await tapLabel('Add clothes');
        expect(find.text('3/5 photos selected'), findsOneWidget);
        final remove = find.byTooltip('Remove ${photos[1].name}');
        await tester.ensureVisible(remove);
        await tester.tap(remove);
        await tester.pumpAndSettle();
        expect(find.text('2/5 photos selected'), findsOneWidget);
        expect(find.text(photos[1].name), findsNothing);
        expect(find.text(photos.first.name), findsOneWidget);
        expect(find.text(photos.last.name), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('AI stylist uses automatic styles and requires uploads', (
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
    expect(find.text('Automatic styles'), findsOneWidget);
    expect(find.text('5 styles, up to 3 looks each'), findsOneWidget);
    expect(find.byType(FilterChip), findsNothing);
    expect(find.text('Generated lookbook'), findsOneWidget);
    expect(find.text('Generate lookbook'), findsOneWidget);

    final generateButton = find.text('Generate lookbook');
    await tester.ensureVisible(generateButton);
    await tester.pumpAndSettle();
    await tester.tap(generateButton);
    await tester.pumpAndSettle();

    expect(find.text('No person photo uploaded.'), findsOneWidget);
  });
}
