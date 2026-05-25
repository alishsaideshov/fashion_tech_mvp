import 'ai_validation_models.dart';

Future<AiValidationResult> runAiValidation({
  required int route,
  required List<AiImageInput> images,
  AiImageInput? personImage,
  List<String>? styles,
  void Function(StyleLook look)? onLookReady,
}) async {
  throw UnsupportedError('No AI client available for this platform.');
}
