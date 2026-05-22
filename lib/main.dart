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
  const LookbookPage({super.key});

  @override
  State<LookbookPage> createState() => _LookbookPageState();
}

class _LookbookPageState extends State<LookbookPage> {
  final Set<String> _selectedStyles = {..._stylePresets};

  bool _isGenerating = false;
  AiValidationResult? _result;
  String? _error;
  String _status =
      'Ready. If you upload nothing, the app uses bundled demo person and clothes.';
  AiImageInput? _personImage;
  List<AiImageInput>? _garmentImages;

  Future<AiImageInput> _loadDemoPerson() async {
    final data = await rootBundle.load('assets/demo/face_generation_ref.png');
    return AiImageInput(
      name: 'Demo person reference',
      mimeType: 'image/png',
      base64Data: base64Encode(data.buffer.asUint8List()),
    );
  }

  Future<List<AiImageInput>> _loadGarments() async {
    if (_garmentImages != null && _garmentImages!.isNotEmpty) {
      return _garmentImages!;
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

  Future<void> _pickPerson() async {
    try {
      final image = await pickSingleImage();
      if (!mounted || image == null) return;
      setState(() {
        _personImage = image;
        _result = null;
        _error = null;
        _status = 'Person photo selected. Demo clothes remain available.';
      });
    } on MissingPluginException {
      _showPickerPluginMessage();
    } on Object catch (error) {
      _showSnack('Could not pick person photo: $error');
    }
  }

  Future<void> _pickGarments() async {
    try {
      final images = await pickGarmentImages();
      if (!mounted || images.isEmpty) return;
      setState(() {
        _garmentImages = images;
        _result = null;
        _error = null;
        _status = '${images.length} clothing photos selected.';
      });
    } on MissingPluginException {
      _showPickerPluginMessage();
    } on Object catch (error) {
      _showSnack('Could not pick garment photos: $error');
    }
  }

  Future<void> _generateLookbook() async {
    if (_isGenerating) return;

    setState(() {
      _isGenerating = true;
      _result = null;
      _error = null;
      _status = 'Preparing demo/user inputs...';
    });

    try {
      final person = _personImage ?? await _loadDemoPerson();
      final garments = await _loadGarments();
      final styles = _selectedStyles.toList();
      if (!mounted) return;
      setState(() {
        _status =
            'Sending ${garments.length} clothes + person reference to AI proxy. Styles: ${styles.map(_styleLabel).join(', ')}.';
      });

      final result = await runAiValidation(
        route: 0,
        images: garments,
        personImage: person,
        styles: styles,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _status =
            'Done. Generated ${result.looks.length} looks in ${(result.latencyMs / 1000).toStringAsFixed(1)}s.';
      });
    } on Object catch (error) {
      debugPrint('Lookbook generation error: $error');
      if (!mounted) return;
      final message = _formatError(error);
      setState(() {
        _error = message;
        _status = 'Generation failed. See error below.';
      });
      _showSnack(message);
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  String _formatError(Object error) {
    final message = error.toString().replaceFirst('Bad state: ', '');
    if (message.length <= 1400) return message;
    return '${message.substring(0, 1400)}...';
  }

  void _toggleStyle(String style) {
    if (_isGenerating) return;
    setState(() {
      if (_selectedStyles.contains(style)) {
        if (_selectedStyles.length > 1) _selectedStyles.remove(style);
      } else if (_selectedStyles.length < 5) {
        _selectedStyles.add(style);
      }
      _result = null;
      _error = null;
    });
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
                    'Upload a face/person photo and clothes to generate 3-5 styled outfit variations.',
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
                            selectedStyles: _selectedStyles,
                            isGenerating: _isGenerating,
                            isUsingDemoPerson: isUsingDemoPerson,
                            isUsingDemoGarments: isUsingDemoGarments,
                            status: _status,
                            error: _error,
                            onPickPerson: _pickPerson,
                            onPickGarments: _pickGarments,
                            onToggleStyle: _toggleStyle,
                            onGenerate: _generateLookbook,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _LookbookPanel(
                            isGenerating: _isGenerating,
                            result: _result,
                            error: _error,
                            selectedStyles: _selectedStyles,
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
                          selectedStyles: _selectedStyles,
                          isGenerating: _isGenerating,
                          isUsingDemoPerson: isUsingDemoPerson,
                          isUsingDemoGarments: isUsingDemoGarments,
                          status: _status,
                          error: _error,
                          onPickPerson: _pickPerson,
                          onPickGarments: _pickGarments,
                          onToggleStyle: _toggleStyle,
                          onGenerate: _generateLookbook,
                        ),
                        const SizedBox(height: 14),
                        _LookbookPanel(
                          isGenerating: _isGenerating,
                          result: _result,
                          error: _error,
                          selectedStyles: _selectedStyles,
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
    required this.selectedStyles,
    required this.isGenerating,
    required this.isUsingDemoPerson,
    required this.isUsingDemoGarments,
    required this.status,
    required this.error,
    required this.onPickPerson,
    required this.onPickGarments,
    required this.onToggleStyle,
    required this.onGenerate,
  });

  final AiImageInput? personImage;
  final List<AiImageInput>? garmentImages;
  final Set<String> selectedStyles;
  final bool isGenerating;
  final bool isUsingDemoPerson;
  final bool isUsingDemoGarments;
  final String status;
  final String? error;
  final VoidCallback onPickPerson;
  final VoidCallback onPickGarments;
  final ValueChanged<String> onToggleStyle;
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
            const _DemoPersonTile()
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
          const SizedBox(height: 12),
          if (hasGarments)
            for (final image in garmentImages!) ...[
              _ImageTile(image: image),
              if (image != garmentImages!.last) const SizedBox(height: 10),
            ]
          else
            for (final garment in _demoGarments) ...[
              _GarmentTile(item: garment),
              if (garment != _demoGarments.last) const SizedBox(height: 10),
            ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isGenerating ? null : onPickGarments,
              icon: const Icon(Icons.upload_outlined),
              label: Text(
                isUsingDemoGarments ? 'Upload clothes' : 'Replace clothes',
              ),
              style: _outlineButtonStyle(),
            ),
          ),
          const SizedBox(height: 18),
          const _PanelTitle(
            icon: Icons.style_outlined,
            title: 'Style variations',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final style in _stylePresets)
                FilterChip(
                  selected: selectedStyles.contains(style),
                  label: Text(_styleLabel(style)),
                  onSelected: isGenerating ? null : (_) => onToggleStyle(style),
                  selectedColor: _teal.withValues(alpha: 0.16),
                  checkmarkColor: _teal,
                  side: BorderSide(
                    color: selectedStyles.contains(style) ? _teal : _border,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
            ],
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

class _LookbookPanel extends StatelessWidget {
  const _LookbookPanel({
    required this.isGenerating,
    required this.result,
    required this.error,
    required this.selectedStyles,
  });

  final bool isGenerating;
  final AiValidationResult? result;
  final String? error;
  final Set<String> selectedStyles;

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
          if (isGenerating)
            _GeneratingGrid(styles: selectedStyles.toList())
          else if (error != null)
            _StateBox(
              icon: Icons.error_outline,
              title: 'Generation error',
              body: error!,
              color: _rust,
            )
          else if (looks.isEmpty)
            const _StateBox(
              icon: Icons.auto_awesome_outlined,
              title: 'No lookbook yet',
              body:
                  'Upload a person photo and wardrobe items, then generate styled variations.',
              color: _muted,
            )
          else
            _LookGrid(looks: looks),
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

class _LookGrid extends StatelessWidget {
  const _LookGrid({required this.looks});

  final List<StyleLook> looks;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 4
            : constraints.maxWidth >= 660
            ? 3
            : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: looks.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.66,
          ),
          itemBuilder: (context, index) {
            return _LookCard(look: looks[index]);
          },
        );
      },
    );
  }
}

class _LookCard extends StatelessWidget {
  const _LookCard({required this.look});

  final StyleLook look;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
              child: SizedBox.expand(
                child: Image.memory(
                  _decodeDataUrl(look.imageDataUrl),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _styleLabel(look.style),
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

class _DemoPersonTile extends StatelessWidget {
  const _DemoPersonTile();

  @override
  Widget build(BuildContext context) {
    return _TileShell(
      image: Image.asset(
        'assets/demo/face_generation_ref.png',
        fit: BoxFit.cover,
      ),
      title: 'Demo person reference',
      subtitle: 'upload your photo for stronger client demo',
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

class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.image});

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
      isUsingDemoGarments ? 'demo clothes' : 'uploaded clothes',
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

Uint8List _decodeDataUrl(String value) {
  return Uri.parse(value).data!.contentAsBytes();
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
