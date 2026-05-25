import 'dart:convert';
import 'package:fashion_tech_mvp/ai/ai_validation_models.dart';
import 'package:image_picker/image_picker.dart';

/// Открывает системный file picker на web, iOS и Android.
/// Возвращает пустой список если пользователь закрыл диалог.
Future<List<AiImageInput>> pickGarmentImages() async {
  final picker = ImagePicker();

  final picked = await picker.pickMultiImage(
    imageQuality: 60, // was 72
    limit: 5,
    maxWidth: 1280, // was 1280
    maxHeight: 1600, // was 1600
  );

  if (picked.isEmpty) return [];

  final results = <AiImageInput>[];

  for (final xFile in picked) {
    final bytes = await xFile.readAsBytes();
    final base64Data = base64Encode(bytes);

    // Определяем mimeType из расширения файла
    final ext = xFile.name.split('.').last.toLowerCase();
    final mimeType = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };

    results.add(
      AiImageInput(
        name: xFile.name,
        mimeType: mimeType,
        base64Data: base64Data,
      ),
    );
  }

  return results;
}

Future<AiImageInput?> pickSingleImage() async {
  final picker = ImagePicker();
  final picked = await picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 72,
    maxWidth: 1280,
    maxHeight: 1600,
  );

  if (picked == null) return null;

  final bytes = await picked.readAsBytes();
  final ext = picked.name.split('.').last.toLowerCase();
  final mimeType = switch (ext) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    _ => 'image/jpeg',
  };

  return AiImageInput(
    name: picked.name,
    mimeType: mimeType,
    base64Data: base64Encode(bytes),
  );
}
