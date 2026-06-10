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
  final client = http.Client();
  final requestImages = images.isNotEmpty
      ? images
      : [if (personImage != null) personImage];

  try {
    final request = http.Request('POST', Uri.parse(aiProxyUrl))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'route': route == 1 ? 'ghost_fit' : 'human_fit',
        'images': requestImages.map((image) => image.toJson()).toList(),
        if (personImage != null) 'personImage': personImage.toJson(),
        if (styles != null) 'styles': styles,
      });

    final response = await client
        .send(request)
        .timeout(const Duration(minutes: 20));

    final body = StringBuffer();
    final looks = <StyleLook>[];
    final limitations = <String>[];

    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      throw StateError('AI proxy returned ${response.statusCode}: $errorBody');
    }

    final contentType = response.headers['content-type'] ?? '';
    if (contentType.contains('text/event-stream')) {
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .timeout(
                const Duration(seconds: 90), // per-chunk timeout
                onTimeout: (sink) =>
                    sink.close(), // close stream instead of throwing
              )) {
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

    await for (final chunk in response.stream.transform(utf8.decoder)) {
      body.write(chunk);
    }

    final decoded = jsonDecode(body.toString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('AI proxy returned an unexpected payload.');
    }
    final result = AiValidationResult.fromJson({
      ...decoded,
      'latencyMs':
          decoded['latencyMs'] as int? ?? stopwatch.elapsedMilliseconds,
    });
    for (final look in result.looks) {
      onLookReady?.call(look);
    }
    return result;
  } on Exception catch (error) {
    final localhostHint = aiProxyUrl.contains('127.0.0.1')
        ? ' On a physical phone, 127.0.0.1 points to the phone itself. Re-run with your Mac LAN IP, for example --dart-define=AI_PROXY_URL=http://192.168.x.x:8787/api/analyze-outfit.'
        : '';
    throw StateError(
      'Cannot reach AI proxy at $aiProxyUrl. '
      'Check proxy host, phone network, and GEMINI_API_KEY.$localhostHint '
      'Details: $error',
    );
  } finally {
    client.close();
    stopwatch.stop();
  }
}
