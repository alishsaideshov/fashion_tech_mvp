import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fashion_tech_mvp/ai/ai_validation_models.dart';
import 'package:fashion_tech_mvp/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AiImageInput photo(String size, {String? name}) => AiImageInput(
  name: name ?? '$size.png',
  mimeType: 'image/png',
  base64Data: base64Encode(
    File(
      'android/app/src/main/res/mipmap-$size/ic_launcher.png',
    ).readAsBytesSync(),
  ),
);

void setViewport(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> tapLabel(WidgetTester tester, String label) async {
  final button = find.text(label);
  await tester.ensureVisible(button);
  if (label == 'Generate lookbook') {
    // Let the mocked HTTP stream drain outside the widget test's fake clock.
    await tester.runAsync(() async {
      await tester.tap(button);
      await Future<void>.delayed(Duration.zero);
    });
  } else {
    await tester.tap(button);
  }
  await tester.pumpAndSettle();
}

void main() {
  for (final count in [1, 2, 3]) {
    for (final responseMode in [
      'json',
      'sse',
      'duplicate',
      'failure',
      'partial',
      'empty',
    ]) {
      testWidgets('$count garments make $count isolated requests ($responseMode)', (
        tester,
      ) async {
        setViewport(tester, responseMode == 'sse' ? 1200 : 390);
        final person = photo('mdpi');
        final garments = [
          for (final size in ['hdpi', 'xhdpi', 'xxhdpi'].take(count))
            photo(
              size,
              name: responseMode == 'duplicate' ? 'same-name.png' : null,
            ),
        ];
        final requests = <Map<String, dynamic>>[];
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              MaterialApp(
                home: LookbookPage(
                  personPicker: () async => person,
                  garmentPicker: () async => garments,
                ),
              ),
            );
            for (final label in [
              'Upload your photo',
              'Upload clothes',
              'Generate lookbook',
            ]) {
              await tapLabel(tester, label);
            }
          },
          () => MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            requests.add(body);
            if (responseMode == 'failure' ||
                (responseMode == 'partial' && requests.length == 1)) {
              return http.Response('Test failure', 500);
            }
            final look = {
              'style': 'garment try-on',
              'variation': 1,
              'model': 'test-model',
              'prompt': 'Try on item ${requests.length}',
              'imageDataUrl':
                  'data:image/png;base64,${garments[requests.length - 1].base64Data}',
            };
            if (responseMode == 'sse' || responseMode == 'duplicate') {
              final event =
                  'data: ${jsonEncode({'type': 'look', 'look': look})}\n\n';
              return http.Response(
                '$event${responseMode == 'duplicate' ? event : ''}data: {"type":"done"}\n\n',
                200,
                headers: {'content-type': 'text/event-stream'},
              );
            }
            return http.Response(
              jsonEncode({
                'looks': responseMode == 'empty' ? [] : [look],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        expect(requests.length, count);
        for (var index = 0; index < count; index++) {
          expect(requests[index]['images'], [garments[index].toJson()]);
          expect(requests[index]['personImage'], person.toJson());
          expect(requests[index]['mode'], 'single_garment');
          expect(requests[index]['styles'], ['garment try-on']);
          expect(requests[index]['variation'], 1);
        }
        final looks = tester.widget<LookList>(find.byType(LookList)).looks;
        final expectedSuccess = switch (responseMode) {
          'failure' || 'empty' => 0,
          'partial' => count - 1,
          _ => count,
        };
        expect(looks.length, count);
        expect(
          looks.where((look) => look.imageDataUrl.isNotEmpty).length,
          expectedSuccess,
        );
        for (var index = 0; index < count; index++) {
          expect(looks[index].garmentName, garments[index].name);
          expect(looks[index].variation, index + 1);
          expect(looks[index].model, isNot('pending'));
          if (looks[index].imageDataUrl.isNotEmpty) {
            expect(
              looks[index].imageDataUrl,
              'data:image/png;base64,${garments[index].base64Data}',
            );
            expect(looks[index].prompt, 'Try on item ${index + 1}');
          }
        }
        expect(find.text('Automatic styles'), findsNothing);
        expect(
          find.text(
            count == 1 ? '1 item, 1 image' : '$count items, $count images',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            expectedSuccess == count
                ? 'Done. Generated all $count looks.'
                : 'Done. Generated $expectedSuccess of $count.',
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(find.byType(LookList));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final width in [390.0, 1200.0]) {
    testWidgets('selection supports add, cancel, limit and remove at $width', (
      tester,
    ) async {
      setViewport(tester, width);
      final photos = [photo('hdpi'), photo('xhdpi'), photo('xxhdpi')];
      var pickCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LookbookPage(
            garmentPicker: () async {
              pickCount++;
              return switch (pickCount) {
                1 => photos.take(2).toList(),
                2 => [],
                _ => [photos.last],
              };
            },
          ),
        ),
      );

      await tapLabel(tester, 'Upload clothes');
      expect(find.text('2/3 photos selected'), findsOneWidget);
      await tapLabel(tester, 'Add clothes');
      expect(find.text('2/3 photos selected'), findsOneWidget);
      await tapLabel(tester, 'Add clothes');
      expect(find.text('3/3 photos selected'), findsOneWidget);
      for (final photo in photos) {
        expect(find.text(photo.name), findsOneWidget);
      }
      final addButton = find.widgetWithText(OutlinedButton, 'Add clothes');
      expect(tester.widget<OutlinedButton>(addButton).onPressed, isNull);
      await tapLabel(tester, 'Add clothes');
      expect(pickCount, 3);
      final remove = find.byTooltip('Remove ${photos[1].name}');
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(find.text('2/3 photos selected'), findsOneWidget);
      expect(find.text(photos[1].name), findsNothing);
      expect(find.text(photos.first.name), findsOneWidget);
      expect(find.text(photos.last.name), findsOneWidget);
      expect(tester.widget<OutlinedButton>(addButton).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'four selected photos are rejected, no generation with zero garments',
    (tester) async {
      setViewport(tester, 390);
      var requests = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              home: LookbookPage(
                personPicker: () async => photo('mdpi'),
                garmentPicker: () async => [
                  photo('hdpi'),
                  photo('xhdpi'),
                  photo('xxhdpi'),
                  photo('xxxhdpi'),
                ],
              ),
            ),
          );
          for (final label in [
            'Upload your photo',
            'Upload clothes',
            'Generate lookbook',
          ]) {
            await tapLabel(tester, label);
          }
        },
        () => MockClient((request) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      expect(find.text('0/3 photos selected'), findsOneWidget);
      expect(find.textContaining('Up to 3 wardrobe photos'), findsOneWidget);
      expect(find.text('No wardrobe items uploaded.'), findsOneWidget);
      expect(find.byType(LookList), findsNothing);
      expect(requests, 0);
    },
  );

  testWidgets('generation and photo controls are locked during a request', (
    tester,
  ) async {
    setViewport(tester, 1200);
    var requests = 0;
    final response = Completer<http.Response>();
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            home: LookbookPage(
              personPicker: () async => photo('mdpi'),
              garmentPicker: () async => [photo('hdpi')],
            ),
          ),
        );
        await tapLabel(tester, 'Upload your photo');
        await tapLabel(tester, 'Upload clothes');
        final button = find.text('Generate lookbook');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Generating lookbook'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Replace photo'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Add clothes'),
              )
              .onPressed,
          isNull,
        );
        expect(find.byTooltip('Remove hdpi.png'), findsNothing);
        response.complete(http.Response('Test failure', 500));
        await tester.pumpAndSettle();
      },
      () => MockClient((request) {
        requests++;
        return response.future;
      }),
    );
    expect(requests, 1);
    expect(find.text('Done. Generated 0 of 1.'), findsOneWidget);
  });

  testWidgets('try-on requires a person photo and has no style selector', (
    tester,
  ) async {
    setViewport(tester, 1400);
    await tester.pumpWidget(const FashionAiPocApp());
    expect(find.text('AI Stylist Lookbook'), findsOneWidget);
    expect(find.text('Person'), findsOneWidget);
    expect(find.text('Wardrobe'), findsOneWidget);
    expect(find.text('Virtual try-on'), findsOneWidget);
    expect(find.text('0 items, 0 images'), findsOneWidget);
    expect(find.byType(FilterChip), findsNothing);
    expect(find.text('Generated lookbook'), findsOneWidget);
    await tapLabel(tester, 'Generate lookbook');
    expect(find.text('No person photo uploaded.'), findsOneWidget);
  });
}
