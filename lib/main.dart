import 'dart:convert';

import 'package:fashion_tech_mvp/ai/ai_client.dart';
import 'package:fashion_tech_mvp/ai/ai_validation_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'image_upload.dart';

void main() {
  runApp(const FashionAiPocApp());
}

class FashionAiPocApp extends StatelessWidget {
  const FashionAiPocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Outfit Generator',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _teal,
          brightness: Brightness.light,
        ),
        fontFamily: 'Arial',
        scaffoldBackgroundColor: _background,
      ),
      home: const OutfitGeneratorPage(),
    );
  }
}

class OutfitGeneratorPage extends StatefulWidget {
  const OutfitGeneratorPage({super.key});

  @override
  State<OutfitGeneratorPage> createState() => _OutfitGeneratorPageState();
}

class _OutfitGeneratorPageState extends State<OutfitGeneratorPage> {
  bool _isGenerating = false;
  AiValidationResult? _result;
  String? _error;
  List<AiImageInput>? _uploadedImages;

  Future<List<AiImageInput>> _loadImages() async {
    if (_uploadedImages != null && _uploadedImages!.isNotEmpty) {
      return _uploadedImages!;
    }

    final inputs = <AiImageInput>[];
    for (final item in _demoGarments) {
      final data = await rootBundle.load(item.asset);
      inputs.add(
        AiImageInput(
          name: item.name,
          mimeType: 'image/jpeg',
          base64Data: base64Encode(data.buffer.asUint8List()),
        ),
      );
    }
    return inputs;
  }

  Future<void> _pickImages() async {
    try {
      final images = await pickGarmentImages();
      if (!mounted || images.isEmpty) return;
      setState(() {
        _uploadedImages = images;
        _result = null;
        _error = null;
      });
    } on MissingPluginException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Image picker plugin is not registered. Stop the app fully, run flutter pub get, then flutter run again.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not pick images: $error')));
    }
  }

  Future<void> _generateOutfit() async {
    if (_isGenerating) return;

    setState(() {
      _isGenerating = true;
      _result = null;
      _error = null;
    });

    try {
      final images = await _loadImages();
      final result = await runAiValidation(route: 0, images: images);
      if (!mounted) return;
      setState(() => _result = result);
    } on Object catch (error) {
      debugPrint('Outfit generation error: $error');
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedImages = _uploadedImages;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 860;
            final padding = isWide ? 28.0 : 16.0;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(padding, 22, padding, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Outfit Generator',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: _ink,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose clothes and generate one outfit photo',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _muted,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 330,
                          child: _InputPanel(
                            uploadedImages: selectedImages,
                            isGenerating: _isGenerating,
                            onPickImages: _pickImages,
                            onGenerate: _generateOutfit,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _ResultPanel(
                            isGenerating: _isGenerating,
                            result: _result,
                            error: _error,
                          ),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        _InputPanel(
                          uploadedImages: selectedImages,
                          isGenerating: _isGenerating,
                          onPickImages: _pickImages,
                          onGenerate: _generateOutfit,
                        ),
                        const SizedBox(height: 14),
                        _ResultPanel(
                          isGenerating: _isGenerating,
                          result: _result,
                          error: _error,
                        ),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InputPanel extends StatelessWidget {
  const _InputPanel({
    required this.uploadedImages,
    required this.isGenerating,
    required this.onPickImages,
    required this.onGenerate,
  });

  final List<AiImageInput>? uploadedImages;
  final bool isGenerating;
  final VoidCallback onPickImages;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final hasUploaded = uploadedImages != null && uploadedImages!.isNotEmpty;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(
            icon: Icons.checkroom_outlined,
            title: 'Selected clothes',
          ),
          const SizedBox(height: 16),
          if (hasUploaded)
            for (final image in uploadedImages!) ...[
              _UploadedImageTile(image: image),
              if (image != uploadedImages!.last) const SizedBox(height: 10),
            ]
          else
            for (final garment in _demoGarments) ...[
              _GarmentTile(item: garment),
              if (garment != _demoGarments.last) const SizedBox(height: 10),
            ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isGenerating ? null : onPickImages,
              icon: const Icon(Icons.upload_outlined),
              label: Text(hasUploaded ? 'Replace photos' : 'Upload photos'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _teal,
                side: const BorderSide(color: _teal),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isGenerating ? null : onGenerate,
              icon: Icon(
                isGenerating ? Icons.hourglass_top : Icons.auto_awesome,
              ),
              label: Text(
                isGenerating ? 'Generating outfit' : 'Generate outfit photo',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _ink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.isGenerating,
    required this.result,
    required this.error,
  });

  final bool isGenerating;
  final AiValidationResult? result;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final imageUrl = result?.generatedImageDataUrl;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(icon: Icons.image_outlined, title: 'Outfit photo'),
          const SizedBox(height: 16),
          if (isGenerating)
            const _StateBox(
              icon: Icons.auto_awesome,
              title: 'Generating your outfit',
              body: 'Combining the selected clothes into one realistic photo.',
              color: _teal,
            )
          else if (error != null)
            _StateBox(
              icon: Icons.error_outline,
              title: 'Generation error',
              body: error!,
              color: _rust,
            )
          else if (imageUrl == null)
            const _StateBox(
              icon: Icons.photo_size_select_actual_outlined,
              title: 'No outfit yet',
              body: 'Choose clothes, then tap Generate outfit photo.',
              color: _muted,
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: ColoredBox(
                  color: _cream,
                  child: Image.memory(
                    _decodeDataUrl(imageUrl),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaBadge(icon: Icons.memory_outlined, label: result!.model),
                _MetaBadge(
                  icon: Icons.timer_outlined,
                  label: '${(result!.latencyMs / 1000).toStringAsFixed(1)}s',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _GarmentTile extends StatelessWidget {
  const _GarmentTile({required this.item});

  final GarmentItem item;

  @override
  Widget build(BuildContext context) {
    return _TileShell(
      image: Image.asset(item.asset, fit: BoxFit.cover),
      title: item.name,
      subtitle: item.note,
    );
  }
}

class _UploadedImageTile extends StatelessWidget {
  const _UploadedImageTile({required this.image});

  final AiImageInput image;

  @override
  Widget build(BuildContext context) {
    return _TileShell(
      image: Image.memory(_decodeBase64(image.base64Data), fit: BoxFit.cover),
      title: image.name,
      subtitle: image.mimeType,
    );
  }
}

class _TileShell extends StatelessWidget {
  const _TileShell({
    required this.image,
    required this.title,
    required this.subtitle,
  });

  final Widget image;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(width: 76, height: 76, child: image),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: _ink,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _muted,
                    height: 1.25,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _teal.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: _teal, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _ink,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _StateBox extends StatelessWidget {
  const _StateBox({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _muted,
                    height: 1.35,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  const _MetaBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: _teal),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: _ink,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _ink.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

@immutable
class GarmentItem {
  const GarmentItem({
    required this.name,
    required this.note,
    required this.asset,
  });

  final String name;
  final String note;
  final String asset;
}

Uint8List _decodeDataUrl(String value) {
  return Uri.parse(value).data!.contentAsBytes();
}

Uint8List _decodeBase64(String value) {
  return base64Decode(value);
}

const _demoGarments = [
  GarmentItem(
    name: 'Brown knit sweater',
    note: 'warm brown knit',
    asset: 'assets/demo/input_sweater.jpg',
  ),
  GarmentItem(
    name: 'Relaxed blue denim',
    note: 'washed denim',
    asset: 'assets/demo/input_jeans.jpg',
  ),
  GarmentItem(
    name: 'Black sneakers',
    note: 'black low-top sneakers',
    asset: 'assets/demo/input_sneakers.jpg',
  ),
];

const _background = Color(0xFFF5F1EA);
const _cream = Color(0xFFFBF8F2);
const _surface = Color(0xFFFFFCF7);
const _border = Color(0xFFE0D8CD);
const _ink = Color(0xFF24221F);
const _muted = Color(0xFF6D685F);
const _teal = Color(0xFF236B72);
const _rust = Color(0xFFAF563C);
