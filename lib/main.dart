import 'dart:convert';

import 'package:fashion_tech_mvp/ai/ai_client.dart';
import 'package:fashion_tech_mvp/ai/ai_client_config.dart';
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
      title: 'AI Stylist Lookbook',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _teal,
          brightness: Brightness.light,
        ),
        fontFamily: 'Arial',
        scaffoldBackgroundColor: _background,
      ),
      home: const LookbookPage(),
    );
  }
}

class LookbookPage extends StatefulWidget {
  const LookbookPage({
    super.key,
    this.personPicker = pickSingleImage,
    this.garmentPicker = pickGarmentImages,
  });

  final Future<AiImageInput?> Function() personPicker;
  final Future<List<AiImageInput>> Function() garmentPicker;

  @override
  State<LookbookPage> createState() => _LookbookPageState();
}

class _LookbookPageState extends State<LookbookPage> {
  bool _isGenerating = false;
  AiValidationResult? _result;
  String? _error;
  String _status = 'Upload a person photo and clothes to get started.';
  AiImageInput? _personImage;
  List<AiImageInput>? _garmentImages;

  Future<void> _pickPerson() async {
    try {
      final image = await widget.personPicker();
      if (!mounted || image == null) return;
      setState(() {
        _personImage = image;
        _result = null;
        _error = null;
        _status = 'Person photo selected. Add wardrobe items next.';
      });
    } on MissingPluginException {
      _showPickerPluginMessage();
    } on Object catch (error) {
      _showSnack('Could not pick person photo: $error');
    }
  }

  Future<void> _pickGarments() async {
    try {
      final images = await widget.garmentPicker();
      if (!mounted || images.isEmpty) return;
      final merged = mergeWardrobeImages(_garmentImages ?? const [], images);
      setState(() {
        _garmentImages = merged;
        _result = null;
        _error = null;
        _status = '${merged.length} clothing photos selected.';
      });
    } on MissingPluginException {
      _showPickerPluginMessage();
    } on Object catch (error) {
      _showSnack('Could not pick garment photos: $error');
    }
  }

  void _removeGarment(AiImageInput image) {
    if (_isGenerating) return;
    setState(() {
      _garmentImages = _garmentImages!
          .where((item) => item.base64Data != image.base64Data)
          .toList();
      _result = null;
      _error = null;
      _status = '${_garmentImages!.length} clothing photos selected.';
    });
  }

  Future<void> _generateLookbook() async {
    if (_isGenerating) return;

    if (_personImage == null) {
      setState(() {
        _error = 'Please upload a person photo first.';
        _status = 'No person photo uploaded.';
      });
      return;
    }

    final garments = _garmentImages ?? const <AiImageInput>[];
    if (garments.isEmpty) {
      setState(() {
        _error = 'Please upload at least one wardrobe item first.';
        _status = 'No wardrobe items uploaded.';
      });
      return;
    }

    setState(() {
      _isGenerating = true;
      _result = null;
      _error = null;
      _status = 'Preparing inputs...';
    });

    final styles = List<String>.unmodifiable(_stylePresets);
    final looks = _pendingLooksForStyles(styles);
    final totalLooks = styles.length * _looksPerStyle;
    var generatedCount = 0;

    try {
      final person = _personImage!;
      final failures = <String>[];
      var elapsedMs = 0;
      var model = 'pending';

      setState(() {
        _result = AiValidationResult(
          looks: List.unmodifiable(looks),
          latencyMs: 0,
          summary: 'Waiting for AI generated looks.',
          prompt: '',
          qualityScore: '',
          limitations: const [],
          generatedImageDataUrl: null,
          model: 'pending',
        );
        _status = 'Generating $totalLooks wardrobe-based looks...';
      });

      for (var styleIndex = 0; styleIndex < styles.length; styleIndex += 1) {
        final style = styles[styleIndex];
        for (var variation = 1; variation <= _looksPerStyle; variation += 1) {
          var lookGenerated = false;
          final sequence = styleIndex * _looksPerStyle + variation;

          if (!mounted) return;
          setState(() {
            _status =
                'Generating ${_styleLabel(style)} $variation/$_looksPerStyle ($sequence/$totalLooks)...';
          });

          try {
            final result = await runAiValidation(
              route: 0,
              images: garments,
              personImage: person,
              styles: [style],
              variation: variation,
              onLookReady: (look) {
                if (!mounted) return;
                if (!lookGenerated) {
                  generatedCount += 1;
                  lookGenerated = true;
                }
                _mergeLook(
                  looks: looks,
                  style: style,
                  variation: variation,
                  look: look,
                );
                setState(() {
                  _result = AiValidationResult(
                    looks: List.unmodifiable(List<StyleLook>.of(looks)),
                    latencyMs: elapsedMs,
                    summary: '',
                    prompt: '',
                    qualityScore: '',
                    limitations: failures,
                    generatedImageDataUrl: look.imageDataUrl,
                    model: look.model,
                  );
                  _status = 'Generated $generatedCount of $totalLooks looks...';
                });
              },
            );

            elapsedMs += result.latencyMs;
            model = result.model;
            for (final look in result.looks) {
              if (!lookGenerated) {
                generatedCount += 1;
                lookGenerated = true;
              }
              _mergeLook(
                looks: looks,
                style: style,
                variation: variation,
                look: look,
              );
            }
          } on Object catch (error) {
            if (!lookGenerated) {
              failures.add(
                '${_styleLabel(style)} $variation: ${_formatError(error)}',
              );
            }
          }

          if (!mounted) return;
          setState(() {
            _result = AiValidationResult(
              looks: List.unmodifiable(List<StyleLook>.of(looks)),
              latencyMs: elapsedMs,
              summary: '',
              prompt: '',
              qualityScore: '',
              limitations: failures,
              generatedImageDataUrl: null,
              model: model,
            );
            _error = failures.isEmpty ? null : failures.join('\n');
            _status =
                'Generated $generatedCount of $totalLooks. Failed ${failures.length}.';
          });
        }
      }

      if (!mounted) return;
      setState(() {
        _status = failures.isEmpty
            ? 'Done. Generated all $totalLooks looks.'
            : 'Done. Generated $generatedCount of $totalLooks.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _formatError(error);
        _status = 'Generation failed.';
      });
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  List<StyleLook> _pendingLooksForStyles(List<String> styles) {
    return [
      for (final style in styles)
        for (var variation = 1; variation <= _looksPerStyle; variation += 1)
          StyleLook(
            style: style,
            variation: variation,
            imageDataUrl: '',
            prompt: 'Waiting for AI generation.',
            model: 'pending',
            latencyMs: 0,
          ),
    ];
  }

  void _mergeLook({
    required List<StyleLook> looks,
    required String style,
    required int variation,
    required StyleLook look,
  }) {
    final normalizedLook = StyleLook(
      style: style,
      variation: variation,
      imageDataUrl: look.imageDataUrl,
      prompt: look.prompt,
      model: look.model,
      latencyMs: look.latencyMs,
    );
    final index = looks.indexWhere(
      (candidate) =>
          _styleKey(candidate.style) == _styleKey(style) &&
          candidate.variation == variation,
    );
    if (index == -1) {
      looks.add(normalizedLook);
    } else {
      looks[index] = normalizedLook;
    }
  }

  String _formatError(Object error) {
    final message = error.toString().replaceFirst('Bad state: ', '');
    if (message.length <= 1400) return message;
    return '${message.substring(0, 1400)}...';
  }

  void _showPickerPluginMessage() {
    if (!mounted) return;
    _showSnack(
      'Image picker plugin is not registered. Stop the app fully, run flutter pub get, then flutter run again.',
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isUsingDemoPerson = _personImage == null;
    final isUsingDemoGarments =
        _garmentImages == null || _garmentImages!.isEmpty;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 940;
            final padding = isWide ? 28.0 : 16.0;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(padding, 22, padding, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Stylist Lookbook',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: _ink,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose your photo and wardrobe. AI builds three looks for every style automatically.',
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
                          width: 360,
                          child: _ControlPanel(
                            personImage: _personImage,
                            garmentImages: _garmentImages,
                            isGenerating: _isGenerating,
                            isUsingDemoPerson: isUsingDemoPerson,
                            isUsingDemoGarments: isUsingDemoGarments,
                            status: _status,
                            error: _error,
                            onPickPerson: _pickPerson,
                            onPickGarments: _pickGarments,
                            onRemoveGarment: _removeGarment,
                            onGenerate: _generateLookbook,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _LookbookPanel(
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
                        _ControlPanel(
                          personImage: _personImage,
                          garmentImages: _garmentImages,
                          isGenerating: _isGenerating,
                          isUsingDemoPerson: isUsingDemoPerson,
                          isUsingDemoGarments: isUsingDemoGarments,
                          status: _status,
                          error: _error,
                          onPickPerson: _pickPerson,
                          onPickGarments: _pickGarments,
                          onRemoveGarment: _removeGarment,
                          onGenerate: _generateLookbook,
                        ),
                        const SizedBox(height: 14),
                        _LookbookPanel(
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

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.personImage,
    required this.garmentImages,
    required this.isGenerating,
    required this.isUsingDemoPerson,
    required this.isUsingDemoGarments,
    required this.status,
    required this.error,
    required this.onPickPerson,
    required this.onPickGarments,
    required this.onRemoveGarment,
    required this.onGenerate,
  });

  final AiImageInput? personImage;
  final List<AiImageInput>? garmentImages;
  final bool isGenerating;
  final bool isUsingDemoPerson;
  final bool isUsingDemoGarments;
  final String status;
  final String? error;
  final VoidCallback onPickPerson;
  final VoidCallback onPickGarments;
  final ValueChanged<AiImageInput> onRemoveGarment;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final hasGarments = garmentImages != null && garmentImages!.isNotEmpty;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(icon: Icons.face_outlined, title: 'Person'),
          const SizedBox(height: 12),
          if (personImage == null)
            const _EmptyUploadHint(text: 'No photo uploaded yet')
          else
            _ImageTile(image: personImage!),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isGenerating ? null : onPickPerson,
              icon: const Icon(Icons.account_circle_outlined),
              label: Text(
                isUsingDemoPerson ? 'Upload your photo' : 'Replace photo',
              ),
              style: _outlineButtonStyle(),
            ),
          ),
          const SizedBox(height: 18),
          const _PanelTitle(icon: Icons.checkroom_outlined, title: 'Wardrobe'),
          const SizedBox(height: 6),
          Text(
            '${garmentImages?.length ?? 0}/$maxWardrobeImages photos selected',
          ),
          const SizedBox(height: 12),
          if (hasGarments)
            for (final image in garmentImages!) ...[
              _ImageTile(
                image: image,
                onRemove: isGenerating ? null : () => onRemoveGarment(image),
              ),
              if (image != garmentImages!.last) const SizedBox(height: 10),
            ]
          else
            const _EmptyUploadHint(text: 'No clothes uploaded yet'),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed:
                  isGenerating ||
                      (garmentImages?.length ?? 0) >= maxWardrobeImages
                  ? null
                  : onPickGarments,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(hasGarments ? 'Add clothes' : 'Upload clothes'),
              style: _outlineButtonStyle(),
            ),
          ),
          const SizedBox(height: 18),
          const _PanelTitle(
            icon: Icons.auto_awesome_outlined,
            title: 'Automatic styles',
          ),
          const SizedBox(height: 12),
          const _AutomaticStyleSummary(
            styleCount: 5,
            looksPerStyle: _looksPerStyle,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isGenerating ? null : onGenerate,
              icon: Icon(
                isGenerating ? Icons.hourglass_top : Icons.auto_awesome,
              ),
              label: Text(
                isGenerating ? 'Generating lookbook' : 'Generate lookbook',
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
          const SizedBox(height: 12),
          _DebugStatusBox(
            status: status,
            error: error,
            isUsingDemoPerson: isUsingDemoPerson,
            isUsingDemoGarments: isUsingDemoGarments,
          ),
        ],
      ),
    );
  }
}

class _AutomaticStyleSummary extends StatelessWidget {
  const _AutomaticStyleSummary({
    required this.styleCount,
    required this.looksPerStyle,
  });

  final int styleCount;
  final int looksPerStyle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _teal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _teal.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: _teal, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '$styleCount styles, up to $looksPerStyle looks each',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _ink,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LookbookPanel extends StatelessWidget {
  const _LookbookPanel({
    required this.isGenerating,
    required this.result,
    required this.error,
  });

  final bool isGenerating;
  final AiValidationResult? result;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final looks = result?.looks ?? const <StyleLook>[];

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(
            icon: Icons.photo_library_outlined,
            title: 'Generated lookbook',
          ),
          const SizedBox(height: 16),
          if (looks.isNotEmpty) ...[
            LookList(looks: looks),
            if (isGenerating) ...[
              const SizedBox(height: 12),
              _StateBox(
                icon: Icons.hourglass_top,
                title: 'Real AI still running',
                body:
                    'Preview images are visible now. They will be replaced if the AI returns generated looks.',
                color: _teal,
              ),
            ],
          ] else if (isGenerating) ...[
            const _GeneratingGrid(styles: _stylePresets),
          ] else ...[
            if (error != null) ...[
              _StateBox(
                icon: Icons.error_outline,
                title: looks.isEmpty
                    ? 'Generation error'
                    : 'AI error, demo fallback shown',
                body: error!,
                color: _rust,
              ),
              if (looks.isNotEmpty) const SizedBox(height: 12),
            ],
            const _StateBox(
              icon: Icons.auto_awesome_outlined,
              title: 'No lookbook yet',
              body:
                  'Upload a person photo and wardrobe items, then generate the automatic lookbook.',
              color: _muted,
            ),
          ],
        ],
      ),
    );
  }
}

class _GeneratingGrid extends StatelessWidget {
  const _GeneratingGrid({required this.styles});

  final List<String> styles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: styles.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.72,
          ),
          itemBuilder: (context, index) {
            return _GeneratingCard(style: styles[index]);
          },
        );
      },
    );
  }
}

class _GeneratingCard extends StatelessWidget {
  const _GeneratingCard({required this.style});

  final String style;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _cream,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(height: 12),
            Text(
              _styleLabel(style),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: _ink,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LookList extends StatelessWidget {
  const LookList({super.key, required this.looks});

  final List<StyleLook> looks;

  @override
  Widget build(BuildContext context) {
    final styleGroups = [
      for (final style in _stylePresets)
        (
          style: style,
          looks:
              looks
                  .where((look) => _styleKey(look.style) == _styleKey(style))
                  .toList()
                ..sort((a, b) => a.variation.compareTo(b.variation)),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (
          var groupIndex = 0;
          groupIndex < styleGroups.length;
          groupIndex += 1
        ) ...[
          if (groupIndex > 0) const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  _styleLabel(styleGroups[groupIndex].style),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
              Text(
                '${styleGroups[groupIndex].looks.where((look) => look.imageDataUrl.isNotEmpty).length}/$_looksPerStyle',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: _muted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760
                  ? 3
                  : constraints.maxWidth >= 480
                  ? 2
                  : 1;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: styleGroups[groupIndex].looks.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.62,
                ),
                itemBuilder: (context, index) =>
                    _LookCard(look: styleGroups[groupIndex].looks[index]),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _LookCard extends StatelessWidget {
  const _LookCard({required this.look});

  final StyleLook look;

  @override
  Widget build(BuildContext context) {
    final imageBytes = _tryDecodeDataUrl(look.imageDataUrl);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: 3 / 4,
                  child: imageBytes == null
                      ? _ImageEmptyState(isPending: look.model == 'pending')
                      : ColoredBox(
                          color: _cream,
                          child: Image.memory(imageBytes, fit: BoxFit.contain),
                        ),
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: _StylePhotoTile(label: 'Look ${look.variation}'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_styleLabel(look.style)} - Look ${look.variation}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 6),
                _MetaBadge(
                  icon: Icons.timer_outlined,
                  label: '${(look.latencyMs / 1000).toStringAsFixed(1)}s',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyUploadHint extends StatelessWidget {
  const _EmptyUploadHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cream,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: _muted, letterSpacing: 0),
      ),
    );
  }
}

class _StylePhotoTile extends StatelessWidget {
  const _StylePhotoTile({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _ImageEmptyState extends StatelessWidget {
  const _ImageEmptyState({required this.isPending});

  final bool isPending;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: _cream),
      child: Center(
        child: isPending
            ? const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.broken_image_outlined, color: _rust, size: 34),
      ),
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.image, this.onRemove});

  final AiImageInput image;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return _TileShell(
      image: Image.memory(_decodeBase64(image.base64Data), fit: BoxFit.cover),
      title: image.name,
      subtitle: image.mimeType,
      trailing: onRemove == null
          ? null
          : IconButton(
              tooltip: 'Remove ${image.name}',
              onPressed: onRemove,
              icon: const Icon(Icons.close),
            ),
    );
  }
}

class _TileShell extends StatelessWidget {
  const _TileShell({
    required this.image,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final Widget image;
  final String title;
  final String subtitle;
  final Widget? trailing;

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
            child: SizedBox(width: 110, height: 110, child: image),
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
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _DebugStatusBox extends StatelessWidget {
  const _DebugStatusBox({
    required this.status,
    required this.error,
    required this.isUsingDemoPerson,
    required this.isUsingDemoGarments,
  });

  final String status;
  final String? error;
  final bool isUsingDemoPerson;
  final bool isUsingDemoGarments;

  @override
  Widget build(BuildContext context) {
    final inputLabel = [
      isUsingDemoPerson ? 'demo person' : 'uploaded person',
      isUsingDemoGarments ? 'no clothes' : 'uploaded clothes',
    ].join(' + ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DebugLine(label: 'Input', value: inputLabel),
          const SizedBox(height: 8),
          _DebugLine(label: 'Proxy', value: aiProxyUrl),
          const SizedBox(height: 8),
          _DebugLine(label: 'Status', value: status),
          if (error != null) ...[
            const SizedBox(height: 8),
            _DebugLine(label: 'Error', value: error!, color: _rust),
          ],
        ],
      ),
    );
  }
}

class _DebugLine extends StatelessWidget {
  const _DebugLine({
    required this.label,
    required this.value,
    this.color = _muted,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: _ink,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            height: 1.3,
            letterSpacing: 0,
          ),
        ),
      ],
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

ButtonStyle _outlineButtonStyle() {
  return OutlinedButton.styleFrom(
    foregroundColor: _teal,
    side: const BorderSide(color: _teal),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    padding: const EdgeInsets.symmetric(vertical: 12),
  );
}

String _styleLabel(String style) {
  return style
      .split(' ')
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1)}',
      )
      .join(' ');
}

String _styleKey(String style) => style.trim().toLowerCase();

Uint8List? _tryDecodeDataUrl(String value) {
  try {
    return Uri.parse(value).data?.contentAsBytes();
  } on Object {
    return null;
  }
}

Uint8List _decodeBase64(String value) {
  return base64Decode(value);
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

const _stylePresets = [
  'casual',
  'smart casual',
  'old money',
  'monochrome',
  'minimal fashion',
];

const _looksPerStyle = 3;

const _background = Color(0xFFF5F1EA);
const _cream = Color(0xFFFBF8F2);
const _surface = Color(0xFFFFFCF7);
const _border = Color(0xFFE0D8CD);
const _ink = Color(0xFF24221F);
const _muted = Color(0xFF6D685F);
const _teal = Color(0xFF236B72);
const _rust = Color(0xFFAF563C);
