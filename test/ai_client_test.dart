import 'dart:convert';

import 'package:fashion_tech_mvp/ai/ai_client_io.dart' as native;
import 'package:fashion_tech_mvp/ai/ai_client_web.dart' as web;
import 'package:fashion_tech_mvp/ai/ai_validation_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const person = AiImageInput(
  name: 'selfie',
  mimeType: 'image/jpeg',
  base64Data: 'person',
);
final garments = List.generate(
  5,
  (index) => AiImageInput(
    name: 'garment-$index',
    mimeType: 'image/jpeg',
    base64Data: 'garment-$index',
  ),
);

void main() {
  for (final entry in {
    'native': native.runAiValidation,
    'web': web.runAiValidation,
  }.entries) {
    final run = entry.value;
    final name = entry.key;
    test('$name: single-garment streamed response completes', () async {
      final callbacks = <StyleLook>[];
      final result = await http.runWithClient(
        () => run(
          route: 0,
          images: [garments.first],
          personImage: person,
          singleGarment: true,
          onLookReady: callbacks.add,
        ),
        () => MockClient(
          (request) async => http.Response(
            'data: {"type":"look","look":{"style":"garment try-on","garmentName":"garment-0","imageDataUrl":"generated"}}\n\ndata: {"type":"done"}\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          ),
        ),
      );
      expect(result.looks.single.garmentName, 'garment-0');
      expect(callbacks.length, 1);
    });
    test(
      '$name: each try-on sends only its garment and the same selfie',
      () async {
        var requests = 0;
        for (final garment in garments.take(3)) {
          final client = MockClient((request) async {
            requests++;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['personImage'], person.toJson());
            expect(body['images'], [garment.toJson()]);
            expect(body['mode'], 'single_garment');
            expect(body['styles'], ['garment try-on']);
            expect(body['variation'], 1);
            return http.Response(
              jsonEncode({
                'looks': [
                  {
                    'style': 'garment try-on',
                    'garmentName': garment.name,
                    'imageDataUrl': 'generated',
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          });
          final result = await http.runWithClient(
            () => run(
              route: 0,
              images: [garment],
              personImage: person,
              singleGarment: true,
              styles: ['casual', 'smart casual', 'old money'],
              variation: 3,
            ),
            () => client,
          );
          expect(result.looks.single.garmentName, garment.name);
        }
        expect(requests, 3);
      },
    );

    test('$name: invalid try-on input is rejected without requests', () async {
      var requests = 0;
      await http.runWithClient(
        () async {
          for (final images in [
            <AiImageInput>[],
            garments.take(2).toList(),
            garments.take(3).toList(),
          ]) {
            await expectLater(
              run(
                route: 0,
                images: images,
                personImage: person,
                singleGarment: true,
              ),
              throwsStateError,
            );
          }
          await expectLater(
            run(route: 0, images: [garments.first], singleGarment: true),
            throwsStateError,
          );
        },
        () => MockClient((request) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      expect(requests, 0);
    });

    test(
      '$name: legacy lookbook keeps all explicitly selected references',
      () async {
        await http.runWithClient(
          () => run(
            route: 0,
            images: garments,
            personImage: person,
            styles: ['casual'],
          ),
          () => MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(
              body['images'],
              garments.map((image) => image.toJson()).toList(),
            );
            expect(body['styles'], ['casual']);
            expect(body.containsKey('mode'), isFalse);
            return http.Response('{"looks":[]}', 200);
          }),
        );
      },
    );
  }
}
