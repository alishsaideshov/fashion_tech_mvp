import 'dart:convert';
import 'package:http/http.dart' as http;
import 'ai_client_config.dart';
import 'ai_validation_models.dart';

Future<AiValidationResult> runAiValidation({
  required int route,
  required List<AiImageInput> images,
  AiImageInput? personImage,
  List<String>? styles,
  void Function(StyleLook look)? onLookReady,
}) async {
  final stopwatch = Stopwatch()..start();
  final response = await http
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
      .timeout(const Duration(minutes: 20));
  stopwatch.stop();

  if (response.statusCode != 200) {
    throw StateError(
      'AI proxy returned ${response.statusCode}: ${response.body}',
    );
  }

  final contentType = response.headers['content-type'] ?? '';
  if (contentType.contains('text/event-stream') ||
      response.body.trimLeft().startsWith('data: ')) {
    final looks = <StyleLook>[];
    final limitations = <String>[];

    for (final line in const LineSplitter().convert(response.body)) {
      if (!line.startsWith('data: ')) continue;
      final decoded = jsonDecode(line.substring(6));
      if (decoded is! Map<String, dynamic>) continue;

      if (decoded['type'] == 'look') {
        final rawLook = decoded['look'];
        if (rawLook is Map<String, dynamic>) {
          final look = StyleLook.fromJson(rawLook);
          looks.add(look);
          onLookReady?.call(look);
        }
      } else if (decoded['type'] == 'error') {
        limitations.add(
          decoded['message'] as String? ?? 'AI stream returned an error.',
        );
      }
    }

    if (looks.isEmpty) {
      throw StateError(
        limitations.isEmpty
            ? 'AI proxy stream ended with no image looks.'
            : limitations.join('\n'),
      );
    }

    return AiValidationResult(
      summary: 'Generated ${looks.length} look(s).',
      prompt: 'AI stylist lookbook stream.',
      qualityScore: 'lookbook',
      latencyMs: stopwatch.elapsedMilliseconds,
      limitations: limitations,
      generatedImageDataUrl: looks.first.imageDataUrl,
      model: looks.first.model,
      looks: looks,
    );
  }

  final decoded = jsonDecode(response.body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('AI proxy returned an unexpected payload.');
  }

  final result = AiValidationResult.fromJson({
    ...decoded,
    'latencyMs': decoded['latencyMs'] as int? ?? stopwatch.elapsedMilliseconds,
  });
  for (final look in result.looks) {
    onLookReady?.call(look);
  }
  return result;
}
