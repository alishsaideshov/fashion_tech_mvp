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
  });

  factory AiValidationResult.fromJson(Map<String, Object?> json) {
    return AiValidationResult(
      summary: json['summary'] as String? ?? 'No summary returned.',
      prompt: json['prompt'] as String? ?? 'No prompt returned.',
      qualityScore: json['qualityScore'] as String? ?? 'n/a',
      latencyMs: json['latencyMs'] as int? ?? 0,
      limitations: (json['limitations'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      generatedImageDataUrl: json['generatedImageDataUrl'] as String?,
      model: json['model'] as String? ?? 'unknown',
    );
  }

  final String summary;
  final String prompt;
  final String qualityScore;
  final int latencyMs;
  final List<String> limitations;
  final String? generatedImageDataUrl;
  final String model;
}
