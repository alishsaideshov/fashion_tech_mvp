import 'dart:convert';
import 'package:http/http.dart' as http;
import 'ai_client_config.dart';
import 'ai_validation_models.dart';

Future<AiValidationResult> runAiValidation({
  required int route,
  required List<AiImageInput> images,
  AiImageInput? personImage,
  List<String>? styles,
}) async {
  final stopwatch = Stopwatch()..start();

  late final http.Response response;

  try {
    response = await http
        .post(
          Uri.parse(aiProxyUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'route': route == 1 ? 'ghost_fit' : 'human_fit',
            'images': images.map((image) => image.toJson()).toList(),
            if (personImage != null) 'personImage': personImage.toJson(),
            if (styles != null) 'styles': styles,
          }),
        )
        .timeout(const Duration(minutes: 3));
  } on Exception catch (error) {
    throw StateError(
      'Cannot reach AI proxy at $aiProxyUrl. '
      'Check proxy host, phone network, and GEMINI_API_KEY. '
      'Details: $error',
    );
  }

  stopwatch.stop();

  if (response.statusCode != 200) {
    throw StateError(
      'AI proxy returned ${response.statusCode}: ${response.body}',
    );
  }

  final decoded = jsonDecode(response.body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('AI proxy returned an unexpected payload.');
  }

  return AiValidationResult.fromJson({
    ...decoded,
    'latencyMs': decoded['latencyMs'] as int? ?? stopwatch.elapsedMilliseconds,
  });
}
