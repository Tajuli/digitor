import 'package:digitor_engine_ffi/digitor_engine_ffi.dart';
import 'package:flutter/material.dart';

import '../../engine/digitor_engine_gateway.dart';

enum EditorTool {
  nodes('Nodes'),
  correction('Correction'),
  primary('Primary'),
  log('Log'),
  curves('Curves'),
  qualifier('Qualifier'),
  lut('LUT'),
  effects('Effects'),
  window('Window'),
  export('Export');

  const EditorTool(this.label);
  final String label;
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final DigitorEngineGateway gateway;
  EditorTool tool = EditorTool.nodes;

  double exposure = 0;
  double contrast = 0;
  double saturation = 0;
  double temperature = 0;
  double tint = 0;
  double highlights = 0;
  double shadows = 0;
  double hue = 0;
  double colorBoost = 0;

  double lift = 0;
  double gamma = 0;
  double gain = 0;
  double offset = 0;

  double logShadows = 0;
  double logMidtones = 0;
  double logHighlights = 0;
  double logGlobal = 0;

  double curveMid = 0;
  double hueLow = 0;
  double hueHigh = 1;
  double effectAmount = 0.15;
  double effectRadius = 0.2;
  DigitorNodeEffectType effectType = DigitorNodeEffectType.vignette;
  DigitorPowerWindowShape windowShape = DigitorPowerWindowShape.ellipse;
  double windowWidth = 0.75;
  double windowHeight = 0.75;
  double windowFeather = 0.15;

  @override
  void initState() {
    super.initState();
    gateway = DigitorEngineGateway()..addListener(_refresh);
    gateway.initialize();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    gateway.removeListener(_refresh);
    gateway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Digitor'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(child: Text(gateway.rendererLabel)),
          ),
          IconButton(
            tooltip: 'Open media',
            onPressed: gateway.ready ? gateway.pickMedia : null,
            icon: const Icon(Icons.video_file_outlined),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (gateway.error != null)
            MaterialBanner(
              content: Text(gateway.error!),
              actions: <Widget>[
                TextButton(
                  onPressed: () {},
                  child: const Text('Engine status'),
                ),
              ],
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: _PreviewPanel(gateway: gateway),
            ),
          ),
          _TimelineStrip(gateway: gateway),
          _ToolBar(
            selected: tool,
            onSelected: (value) => setState(() => tool = value),
          ),
          SizedBox(height: 270, child: _buildToolPanel()),
        ],
      ),
    );
  }

  Widget _buildToolPanel() {
    if (!gateway.ready) {
      return Center(
        child: gateway.initializing
            ? const CircularProgressIndicator()
            : const Text('DigitorEngine unavailable'),
      );
    }
    switch (tool) {
      case EditorTool.nodes:
        return _NodesPanel(gateway: gateway);
      case EditorTool.correction:
        return _ControlPanel(
          title: 'Correction',
          controls: <Widget>[
            _slider('Exposure', exposure, -1, 1, (v) => exposure = v),
            _slider('Contrast', contrast, -1, 1, (v) => contrast = v),
            _slider('Saturation', saturation, -1, 1, (v) => saturation = v),
            _slider('Temperature', temperature, -1, 1, (v) => temperature = v),
            _slider('Tint', tint, -1, 1, (v) => tint = v),
            _slider('Highlights', highlights, -1, 1, (v) => highlights = v),
            _slider('Shadows', shadows, -1, 1, (v) => shadows = v),
            _slider('Hue', hue, -1, 1, (v) => hue = v),
            _slider('Color Boost', colorBoost, -1, 1, (v) => colorBoost = v),
          ],
          onApply: () => gateway.applyCorrection(
            exposure: exposure,
            contrast: contrast,
            saturation: saturation,
            temperature: temperature,
            tint: tint,
            highlights: highlights,
            shadows: shadows,
            hue: hue,
            colorBoost: colorBoost,
          ),
        );
      case EditorTool.primary:
        return _ControlPanel(
          title: 'Primary Wheels • master channels',
          controls: <Widget>[
            _slider('Lift', lift, -1, 1, (v) => lift = v),
            _slider('Gamma', gamma, -1, 1, (v) => gamma = v),
            _slider('Gain', gain, -1, 1, (v) => gain = v),
            _slider('Offset', offset, -1, 1, (v) => offset = v),
          ],
          onApply: () => gateway.applyPrimaryWheels(
            lift: lift,
            gamma: gamma,
            gain: gain,
            offset: offset,
          ),
        );
      case EditorTool.log:
        return _ControlPanel(
          title: 'Log Wheels • master channels',
          controls: <Widget>[
            _slider('Shadows', logShadows, -1, 1, (v) => logShadows = v),
            _slider('Midtones', logMidtones, -1, 1, (v) => logMidtones = v),
            _slider('Highlights', logHighlights, -1, 1, (v) => logHighlights = v),
            _slider('Global', logGlobal, -1, 1, (v) => logGlobal = v),
          ],
          onApply: () => gateway.applyLogWheels(
            shadows: logShadows,
            midtones: logMidtones,
            highlights: logHighlights,
            global: logGlobal,
          ),
        );
      case EditorTool.curves:
        return _ControlPanel(
          title: 'RGB Curves',
          controls: <Widget>[
            _slider('Master midpoint', curveMid, -0.45, 0.45, (v) => curveMid = v),
          ],
          onApply: () => gateway.applyRgbCurve(curveMid),
        );
      case EditorTool.qualifier:
        return _ControlPanel(
          title: 'HSL Qualifier',
          controls: <Widget>[
            _slider('Hue low', hueLow, 0, 1, (v) => hueLow = v),
            _slider('Hue high', hueHigh, 0, 1, (v) => hueHigh = v),
          ],
          onApply: () => gateway.applyQualifier(hueLow: hueLow, hueHigh: hueHigh),
        );
      case EditorTool.lut:
        return _ActionPanel(
          title: 'LUT',
          description: 'LUT operations are stored in the selected DigitorEngine node.',
          button: 'Add identity 1D LUT',
          onPressed: gateway.applyIdentityLut,
        );
      case EditorTool.effects:
        return _EffectsPanel(
          type: effectType,
          amount: effectAmount,
          radius: effectRadius,
          onType: (value) => setState(() => effectType = value),
          onAmount: (value) => setState(() => effectAmount = value),
          onRadius: (value) => setState(() => effectRadius = value),
          onApply: () => gateway.applyEffect(
            type: effectType,
            amount: effectAmount,
            radius: effectRadius,
          ),
        );
      case EditorTool.window:
        return _WindowPanel(
          shape: windowShape,
          width: windowWidth,
          height: windowHeight,
          feather: windowFeather,
          onShape: (value) => setState(() => windowShape = value),
          onWidth: (value) => setState(() => windowWidth = value),
          onHeight: (value) => setState(() => windowHeight = value),
          onFeather: (value) => setState(() => windowFeather = value),
          onApply: () => gateway.applyPowerWindow(
            shape: windowShape,
            width: windowWidth,
            height: windowHeight,
            feather: windowFeather,
          ),
        );
      case EditorTool.export:
        return const _ActionPanel(
          title: 'Export',
          description:
              'Export is intentionally not implemented in Dart or Media3. The next integration step binds DigitorEngine production export to the same node-graph revision used by preview.',
          button: 'Engine-only export',
        );
    }
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return SizedBox(
      width: 210,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('$label  ${value.toStringAsFixed(2)}'),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: (next) => setState(() => onChanged(next)),
          ),
        ],
      ),
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.gateway});
  final DigitorEngineGateway gateway;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                gateway.mediaPath == null ? Icons.movie_outlined : Icons.movie,
                size: 52,
                color: Colors.white70,
              ),
              const SizedBox(height: 12),
              Text(gateway.mediaLabel, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(gateway.hostLabel, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: gateway.ready ? gateway.pickMedia : null,
                icon: const Icon(Icons.add),
                label: Text(gateway.mediaPath == null ? 'Import video' : 'Replace video'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineStrip extends StatelessWidget {
  const _TimelineStrip({required this.gateway});
  final DigitorEngineGateway gateway;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.play_arrow),
          const SizedBox(width: 8),
          Expanded(
            child: LinearProgressIndicator(
              value: gateway.mediaPath == null ? 0 : 0.01,
              minHeight: 4,
            ),
          ),
          const SizedBox(width: 12),
          Text('Node ${gateway.selectedNode ?? '-'}'),
        ],
      ),
    );
  }
}

class _ToolBar extends StatelessWidget {
  const _ToolBar({required this.selected, required this.onSelected});
  final EditorTool selected;
  final ValueChanged<EditorTool> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: EditorTool.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final value = EditorTool.values[index];
          return ChoiceChip(
            label: Text(value.label),
            selected: value == selected,
            onSelected: (_) => onSelected(value),
          );
        },
      ),
    );
  }
}

class _NodesPanel extends StatelessWidget {
  const _NodesPanel({required this.gateway});
  final DigitorEngineGateway gateway;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Engine Node Graph',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.icon(
                onPressed: gateway.addSerialNode,
                icon: const Icon(Icons.add),
                label: const Text('Serial'),
              ),
              FilledButton.tonalIcon(
                onPressed: gateway.addParallelNodes,
                icon: const Icon(Icons.call_split),
                label: const Text('Parallel'),
              ),
              OutlinedButton.icon(
                onPressed: gateway.clearSelectedOperations,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Clear operations'),
              ),
              OutlinedButton.icon(
                onPressed: gateway.removeSelectedNode,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete node'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Selected: ${gateway.selectedNode}   Graph revision: ${gateway.graph.graphRevision}   Parameter revision: ${gateway.graph.parameterRevision}',
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                gateway.graph.json,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.title,
    required this.controls,
    required this.onApply,
  });
  final String title;
  final List<Widget> controls;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
              FilledButton(onPressed: onApply, child: const Text('Apply to node')),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(spacing: 8, runSpacing: 8, children: controls),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.title,
    required this.description,
    required this.button,
    this.onPressed,
  });
  final String title;
  final String description;
  final String button;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text(description),
          const SizedBox(height: 18),
          FilledButton(onPressed: onPressed, child: Text(button)),
        ],
      ),
    );
  }
}

class _EffectsPanel extends StatelessWidget {
  const _EffectsPanel({
    required this.type,
    required this.amount,
    required this.radius,
    required this.onType,
    required this.onAmount,
    required this.onRadius,
    required this.onApply,
  });
  final DigitorNodeEffectType type;
  final double amount;
  final double radius;
  final ValueChanged<DigitorNodeEffectType> onType;
  final ValueChanged<double> onAmount;
  final ValueChanged<double> onRadius;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              DropdownButton<DigitorNodeEffectType>(
                value: type,
                items: DigitorNodeEffectType.values
                    .map((value) => DropdownMenuItem(value: value, child: Text(value.name)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) onType(value);
                },
              ),
              Expanded(
                child: Slider(value: amount, min: 0, max: 1, onChanged: onAmount),
              ),
              Text('Amount ${amount.toStringAsFixed(2)}'),
              Expanded(
                child: Slider(value: radius, min: 0, max: 1, onChanged: onRadius),
              ),
              Text('Radius ${radius.toStringAsFixed(2)}'),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: onApply, child: const Text('Apply effect to node')),
        ],
      ),
    );
  }
}

class _WindowPanel extends StatelessWidget {
  const _WindowPanel({
    required this.shape,
    required this.width,
    required this.height,
    required this.feather,
    required this.onShape,
    required this.onWidth,
    required this.onHeight,
    required this.onFeather,
    required this.onApply,
  });
  final DigitorPowerWindowShape shape;
  final double width;
  final double height;
  final double feather;
  final ValueChanged<DigitorPowerWindowShape> onShape;
  final ValueChanged<double> onWidth;
  final ValueChanged<double> onHeight;
  final ValueChanged<double> onFeather;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: <Widget>[
          DropdownButton<DigitorPowerWindowShape>(
            value: shape,
            items: DigitorPowerWindowShape.values
                .map((value) => DropdownMenuItem(value: value, child: Text(value.name)))
                .toList(),
            onChanged: (value) {
              if (value != null) onShape(value);
            },
          ),
          _InlineSlider(label: 'Width', value: width, onChanged: onWidth),
          _InlineSlider(label: 'Height', value: height, onChanged: onHeight),
          _InlineSlider(label: 'Feather', value: feather, onChanged: onFeather),
          FilledButton(onPressed: onApply, child: const Text('Apply window to node')),
        ],
      ),
    );
  }
}

class _InlineSlider extends StatelessWidget {
  const _InlineSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(width: 70, child: Text(label)),
        Expanded(child: Slider(value: value, min: 0, max: 1, onChanged: onChanged)),
        SizedBox(width: 45, child: Text(value.toStringAsFixed(2))),
      ],
    );
  }
}
