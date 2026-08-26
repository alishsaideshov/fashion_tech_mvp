import 'dart:convert';

import 'package:fashion_tech_mvp/ai/ai_client_io.dart';
import 'package:fashion_tech_mvp/ai/ai_validation_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'native client sends selfie and all five photos for every variation',
    () async {
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
      var requests = 0;
      for (var variation = 1; variation <= 3; variation++) {
        final client = MockClient((request) async {
          requests++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['personImage'], person.toJson());
          expect(
            body['images'],
            garments.map((image) => image.toJson()).toList(),
          );
          expect(body['variation'], variation);
          return http.Response(
            jsonEncode({
              'looks': [
                {
                  'style': 'casual',
                  'variation': variation,
                  'imageDataUrl': 'generated',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });
        await http.runWithClient(
          () => runAiValidation(
            route: 0,
            images: garments,
            personImage: person,
            styles: ['casual'],
            variation: variation,
          ),
          () => client,
        );
      }
      expect(requests, 3);
    },
  );
}
