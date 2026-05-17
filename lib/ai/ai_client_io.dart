import 'dart:convert';
import 'package:http/http.dart' as http;
import 'ai_client_config.dart';
import 'ai_validation_models.dart';

Future<AiValidationResult> runAiValidation({
  required int route,
  required List<AiImageInput> images,
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
          }),
        )
        .timeout(const Duration(seconds: 60));
  } on Exception catch (error) {
    final localhostHint = aiProxyUrl.contains('127.0.0.1')
        ? ' On a physical phone, 127.0.0.1 points to the phone itself. Re-run with your Mac LAN IP, for example --dart-define=AI_PROXY_URL=http://192.168.x.x:8787/api/analyze-outfit.'
        : '';
    throw StateError(
      'Cannot reach AI proxy at $aiProxyUrl. '
      'Check proxy host, phone network, and GEMINI_API_KEY.$localhostHint '
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
