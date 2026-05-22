import 'ai_validation_models.dart';

Future<AiValidationResult> runAiValidation({
  required int route,
  required List<AiImageInput> images,
  AiImageInput? personImage,
  List<String>? styles,
}) {
  throw UnsupportedError(
    'Real AI validation is available in Flutter web via the local dev proxy.',
  );
}
