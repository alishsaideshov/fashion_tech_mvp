import 'dart:async';

import 'package:flutter/material.dart';

void main() {
  runApp(const FashionAiPocApp());
}

class FashionAiPocApp extends StatelessWidget {
  const FashionAiPocApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Visual AI POC',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _teal,
          brightness: Brightness.light,
        ),
        fontFamily: 'Arial',
        scaffoldBackgroundColor: _background,
      ),
      home: const ValidationConsole(),
    );
  }
}

class ValidationConsole extends StatefulWidget {
  const ValidationConsole({super.key});

  @override
  State<ValidationConsole> createState() => _ValidationConsoleState();
}

class _ValidationConsoleState extends State<ValidationConsole> {
  int _selectedRoute = 0;
  int _activeStep = -1;
  bool _isRunning = false;
  bool _hasRun = false;

  Future<void> _runValidation() async {
    if (_isRunning) return;

    setState(() {
      _isRunning = true;
      _hasRun = false;
      _activeStep = 0;
    });

    for (var i = 0; i < _pipelineSteps.length; i++) {
      setState(() => _activeStep = i);
      await Future<void>.delayed(_pipelineSteps[i].demoDelay);
    }

    if (!mounted) return;
    setState(() {
      _isRunning = false;
      _hasRun = true;
      _activeStep = -1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1120;
            final horizontalPadding = isWide ? 28.0 : 16.0;

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      22,
                      horizontalPadding,
                      12,
                    ),
                    child: const _Header(),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    0,
                    horizontalPadding,
                    28,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(width: 310, child: _InputPanel()),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _ValidationPanel(
                                  selectedRoute: _selectedRoute,
                                  activeStep: _activeStep,
                                  isRunning: _isRunning,
                                  hasRun: _hasRun,
                                  onRouteChanged: (value) {
                                    setState(() => _selectedRoute = value);
                                  },
                                  onRun: _runValidation,
                                ),
                              ),
                              const SizedBox(width: 16),
                              const SizedBox(
                                width: 390,
                                child: _OutputsPanel(),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              const _InputPanel(),
                              const SizedBox(height: 14),
                              _ValidationPanel(
                                selectedRoute: _selectedRoute,
                                activeStep: _activeStep,
                                isRunning: _isRunning,
                                hasRun: _hasRun,
                                onRouteChanged: (value) {
                                  setState(() => _selectedRoute = value);
                                },
                                onRun: _runValidation,
                              ),
                              const SizedBox(height: 14),
                              const _OutputsPanel(),
                            ],
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 14,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Visual AI POC',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: _ink,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Outfit generation validation - no auth, no backend, no MVP shell',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: _muted, letterSpacing: 0),
            ),
          ],
        ),
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatusPill(icon: Icons.science_outlined, label: 'Tech check'),
            _StatusPill(icon: Icons.timer_outlined, label: 'Latency'),
            _StatusPill(icon: Icons.image_search_outlined, label: 'Outputs'),
          ],
        ),
      ],
    );
  }
}

class _InputPanel extends StatelessWidget {
  const _InputPanel();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(
            icon: Icons.checkroom_outlined,
            title: 'Input set',
            subtitle: 'Real-world garment photos',
          ),
          const SizedBox(height: 16),
          for (final item in _garments) ...[
            _GarmentTile(item: item),
            if (item != _garments.last) const SizedBox(height: 10),
          ],
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 16 / 7.4,
              child: Image.asset(
                'assets/demo/pipeline_board.jpg',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ValidationPanel extends StatelessWidget {
  const _ValidationPanel({
    required this.selectedRoute,
    required this.activeStep,
    required this.isRunning,
    required this.hasRun,
    required this.onRouteChanged,
    required this.onRun,
  });

  final int selectedRoute;
  final int activeStep;
  final bool isRunning;
  final bool hasRun;
  final ValueChanged<int> onRouteChanged;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(
            icon: Icons.auto_awesome_outlined,
            title: 'Validation run',
            subtitle: 'Prompt route, latency, and failure modes',
          ),
          const SizedBox(height: 16),
          SegmentedButton<int>(
            showSelectedIcon: false,
            selected: {selectedRoute},
            onSelectionChanged: isRunning
                ? null
                : (selection) => onRouteChanged(selection.first),
            segments: const [
              ButtonSegment<int>(
                value: 0,
                icon: Icon(Icons.person_outline),
                label: Text('Human fit'),
              ),
              ButtonSegment<int>(
                value: 1,
                icon: Icon(Icons.accessibility_new_outlined),
                label: Text('Ghost fit'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PromptRecipe(route: selectedRoute),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: isRunning ? null : onRun,
            icon: Icon(isRunning ? Icons.hourglass_top : Icons.play_arrow),
            label: Text(
              isRunning ? 'Running validation' : 'Generate validation run',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              backgroundColor: _ink,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 18),
          _PipelineSteps(activeStep: activeStep, hasRun: hasRun),
          const SizedBox(height: 18),
          _LatencySummary(isRunning: isRunning, hasRun: hasRun),
          const SizedBox(height: 18),
          const _QualityGateGrid(),
          const SizedBox(height: 18),
          const _LimitationsPanel(),
        ],
      ),
    );
  }
}

class _OutputsPanel extends StatelessWidget {
  const _OutputsPanel();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelTitle(
            icon: Icons.photo_library_outlined,
            title: 'Output examples',
            subtitle: '1-3 images for direction review',
          ),
          const SizedBox(height: 16),
          for (final example in _examples) ...[
            _OutputCard(example: example),
            if (example != _examples.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _PromptRecipe extends StatelessWidget {
  const _PromptRecipe({required this.route});

  final int route;

  @override
  Widget build(BuildContext context) {
    final isGhost = route == 1;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _cream,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isGhost ? 'Ghost mannequin recipe' : 'Human model recipe',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _ink,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isGhost
                  ? 'single outfit, body volume, no visible face/hands/skin, studio wall, preserve garment texture and color'
                  : 'full-body outfit on model, same studio light, natural fit, preserve source garments, no extra accessories',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _muted,
                height: 1.4,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PipelineSteps extends StatelessWidget {
  const _PipelineSteps({required this.activeStep, required this.hasRun});

  final int activeStep;
  final bool hasRun;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pipeline',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: _ink,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < _pipelineSteps.length; i++) ...[
          _PipelineStepRow(
            step: _pipelineSteps[i],
            isActive: activeStep == i,
            isComplete: hasRun || (activeStep > i && activeStep != -1),
          ),
          if (i != _pipelineSteps.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _PipelineStepRow extends StatelessWidget {
  const _PipelineStepRow({
    required this.step,
    required this.isActive,
    required this.isComplete,
  });

  final PipelineStep step;
  final bool isActive;
  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    final tone = isComplete ? _olive : (isActive ? _teal : _muted);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? _teal.withValues(alpha: 0.08) : Colors.white,
        border: Border.all(color: isActive ? _teal : _border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            isComplete ? Icons.check_circle : step.icon,
            color: tone,
            size: 21,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  step.note,
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
          const SizedBox(width: 10),
          Text(
            step.latency,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: tone,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _LatencySummary extends StatelessWidget {
  const _LatencySummary({required this.isRunning, required this.hasRun});

  final bool isRunning;
  final bool hasRun;

  @override
  Widget build(BuildContext context) {
    final lastRun = isRunning
        ? 'measuring'
        : (hasRun ? '18.4s mock' : 'not run');
    return Row(
      children: [
        Expanded(
          child: _MetricTile(
            label: 'Target',
            value: '<25s',
            icon: Icons.speed_outlined,
            color: _olive,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricTile(
            label: 'Last run',
            value: lastRun,
            icon: Icons.timer_outlined,
            color: _teal,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricTile(
            label: 'Risk',
            value: 'fidelity',
            icon: Icons.warning_amber_outlined,
            color: _rust,
          ),
        ),
      ],
    );
  }
}

class _QualityGateGrid extends StatelessWidget {
  const _QualityGateGrid();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quality gates',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: _ink,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            _QualityPill(label: 'color match', state: 'pass', color: _olive),
            _QualityPill(label: 'body volume', state: 'watch', color: _gold),
            _QualityPill(label: 'texture', state: 'pass', color: _olive),
            _QualityPill(label: 'hands/face', state: 'risk', color: _rust),
            _QualityPill(label: 'shoe angle', state: 'watch', color: _gold),
          ],
        ),
      ],
    );
  }
}

class _LimitationsPanel extends StatelessWidget {
  const _LimitationsPanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Known limitations',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: _ink,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
        for (final item in _limitations) ...[
          _LimitationRow(item: item),
          if (item != _limitations.last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _LimitationRow extends StatelessWidget {
  const _LimitationRow({required this.item});

  final Limitation item;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(item.icon, size: 18, color: item.color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.note,
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
    );
  }
}

class _GarmentTile extends StatelessWidget {
  const _GarmentTile({required this.item});

  final GarmentItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 76,
              height: 76,
              child: Image.asset(item.asset, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
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
                  item.note,
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

class _OutputCard extends StatelessWidget {
  const _OutputCard({required this.example});

  final OutputExample example;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: AspectRatio(
              aspectRatio: 0.78,
              child: ColoredBox(
                color: _cream,
                child: Image.asset(
                  example.asset,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        example.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: _ink,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    _ScoreBadge(score: example.score),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  example.note,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _muted,
                    height: 1.35,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SmallBadge(
                      icon: Icons.timer_outlined,
                      label: example.latency,
                    ),
                    _SmallBadge(
                      icon: Icons.check_circle_outline,
                      label: example.verdict,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: _muted, letterSpacing: 0),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: _ink,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QualityPill extends StatelessWidget {
  const _QualityPill({
    required this.label,
    required this.state,
    required this.color,
  });

  final String label;
  final String state;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 8),
          Text(
            '$label: $state',
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

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _ink,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _muted,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ],
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: _teal),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
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

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});

  final String score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: _olive.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        score,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: _olive,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.icon, required this.label});

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

@immutable
class OutputExample {
  const OutputExample({
    required this.title,
    required this.note,
    required this.asset,
    required this.score,
    required this.latency,
    required this.verdict,
  });

  final String title;
  final String note;
  final String asset;
  final String score;
  final String latency;
  final String verdict;
}

@immutable
class PipelineStep {
  const PipelineStep({
    required this.title,
    required this.note,
    required this.latency,
    required this.icon,
    required this.demoDelay,
  });

  final String title;
  final String note;
  final String latency;
  final IconData icon;
  final Duration demoDelay;
}

@immutable
class Limitation {
  const Limitation({
    required this.title,
    required this.note,
    required this.icon,
    required this.color,
  });

  final String title;
  final String note;
  final IconData icon;
  final Color color;
}

const _garments = [
  GarmentItem(
    name: 'Brown knit sweater',
    note: 'patterned floor, warm light, soft silhouette',
    asset: 'assets/demo/input_sweater.jpg',
  ),
  GarmentItem(
    name: 'Relaxed blue denim',
    note: 'flat lay, worn texture, knee distressing',
    asset: 'assets/demo/input_jeans.jpg',
  ),
  GarmentItem(
    name: 'Black sneakers',
    note: 'POV angle, laces visible, low contrast',
    asset: 'assets/demo/input_sneakers.jpg',
  ),
];

const _examples = [
  OutputExample(
    title: 'Look 01 - strongest',
    note:
        'Best read on fit and garment harmony. Denim wash and sweater volume remain convincing.',
    asset: 'assets/demo/output_brown_look.jpg',
    score: '8.4/10',
    latency: '17.8s',
    verdict: 'ship to review',
  ),
  OutputExample(
    title: 'Look 02 - clean alt',
    note:
        'Good studio consistency. Main risk is preserving exact shoe shape and cargo pocket scale.',
    asset: 'assets/demo/output_green_look.jpg',
    score: '7.6/10',
    latency: '19.2s',
    verdict: 'usable',
  ),
  OutputExample(
    title: 'Prompt ref - chat run',
    note:
        'Useful as a quick stakeholder reference, but lower fidelity than isolated output crops.',
    asset: 'assets/demo/chat_result.jpg',
    score: '7.1/10',
    latency: 'n/a',
    verdict: 'reference',
  ),
];

const _pipelineSteps = [
  PipelineStep(
    title: 'Normalize source photos',
    note: 'crop garments, classify category, remove noisy background',
    latency: '2.1s',
    icon: Icons.crop_outlined,
    demoDelay: Duration(milliseconds: 420),
  ),
  PipelineStep(
    title: 'Extract garment intent',
    note: 'color, texture, silhouette, priority details',
    latency: '3.4s',
    icon: Icons.manage_search_outlined,
    demoDelay: Duration(milliseconds: 520),
  ),
  PipelineStep(
    title: 'Generate outfit render',
    note: 'compose full look with locked camera and lighting',
    latency: '10.7s',
    icon: Icons.auto_awesome_outlined,
    demoDelay: Duration(milliseconds: 860),
  ),
  PipelineStep(
    title: 'Quality pass',
    note: 'flag drift, body artifacts, and inconsistent item geometry',
    latency: '2.2s',
    icon: Icons.fact_check_outlined,
    demoDelay: Duration(milliseconds: 460),
  ),
];

const _limitations = [
  Limitation(
    title: 'Multi-image fidelity',
    note:
        'Exact fabric, logo, and seams can drift without masking or reference weighting.',
    icon: Icons.layers_outlined,
    color: _rust,
  ),
  Limitation(
    title: 'Ghost fit body gaps',
    note:
        'No face/hands/skin needs stricter negative prompts and likely inpaint masks.',
    icon: Icons.accessibility_new_outlined,
    color: _gold,
  ),
  Limitation(
    title: 'Perspective mismatch',
    note:
        'Shoes from POV photos are the first item likely to lose angle accuracy.',
    icon: Icons.straighten_outlined,
    color: _gold,
  ),
  Limitation(
    title: 'Latency variance',
    note:
        'Batching 3-5 garments is feasible; retry loops can push total time above target.',
    icon: Icons.timer_off_outlined,
    color: _teal,
  ),
];

const _background = Color(0xFFF5F1EA);
const _cream = Color(0xFFFBF8F2);
const _surface = Color(0xFFFFFCF7);
const _border = Color(0xFFE0D8CD);
const _ink = Color(0xFF24221F);
const _muted = Color(0xFF6D685F);
const _teal = Color(0xFF236B72);
const _olive = Color(0xFF5F7148);
const _rust = Color(0xFFAF563C);
const _gold = Color(0xFF9C7A2E);
