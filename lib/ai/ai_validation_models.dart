import 'package:flutter/foundation.dart';

@immutable
class AiImageInput {
  const AiImageInput({
    required this.name,
    required this.mimeType,
    required this.base64Data,
  });

  final String name;
  final String mimeType;
  final String base64Data;

  Map<String, Object> toJson() {
    return {'name': name, 'mimeType': mimeType, 'base64Data': base64Data};
  }
}

@immutable
class AiValidationResult {
  const AiValidationResult({
    required this.summary,
    required this.prompt,
    required this.qualityScore,
    required this.latencyMs,
    required this.limitations,
    required this.generatedImageDataUrl,
    required this.model,
    required this.looks,
  });

  factory AiValidationResult.fromJson(Map<String, Object?> json) {
    final generatedImageDataUrl = json['generatedImageDataUrl'] as String?;
    final looks = (json['looks'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(StyleLook.fromJson)
        .toList();
    if (looks.isEmpty &&
        generatedImageDataUrl != null &&
        generatedImageDataUrl.isNotEmpty) {
      looks.add(
        StyleLook(
          style: json['style'] as String? ?? 'Generated look',
          variation: json['variation'] as int? ?? 1,
          imageDataUrl: generatedImageDataUrl,
          prompt: json['prompt'] as String? ?? '',
          model: json['model'] as String? ?? 'unknown',
          latencyMs: json['latencyMs'] as int? ?? 0,
        ),
      );
    }

    return AiValidationResult(
      summary: json['summary'] as String? ?? 'No summary returned.',
      prompt: json['prompt'] as String? ?? 'No prompt returned.',
      qualityScore: json['qualityScore'] as String? ?? 'n/a',
      latencyMs: json['latencyMs'] as int? ?? 0,
      limitations: (json['limitations'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      generatedImageDataUrl: generatedImageDataUrl,
      model: json['model'] as String? ?? 'unknown',
      looks: looks,
    );
  }

  final String summary;
  final String prompt;
  final String qualityScore;
  final int latencyMs;
  final List<String> limitations;
  final String? generatedImageDataUrl;
  final String model;
  final List<StyleLook> looks;
}

@immutable
class StyleLook {
  const StyleLook({
    required this.style,
    required this.variation,
    required this.imageDataUrl,
    required this.prompt,
    required this.model,
    required this.latencyMs,
  });

  factory StyleLook.fromJson(Map<String, Object?> json) {
    return StyleLook(
      style: json['style'] as String? ?? 'Look',
      variation: json['variation'] as int? ?? 1,
      imageDataUrl: json['imageDataUrl'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      model: json['model'] as String? ?? 'unknown',
      latencyMs: json['latencyMs'] as int? ?? 0,
    );
  }

  final String style;
  final int variation;
  final String imageDataUrl;
  final String prompt;
  final String model;
  final int latencyMs;
}
