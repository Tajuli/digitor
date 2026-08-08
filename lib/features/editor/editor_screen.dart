import 'dart:async';

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

  final Map<String, double> correction = <String, double>{
    'Exposure': 0,
    'Contrast': 0,
    'Saturation': 0,
    'Temperature': 0,
    'Tint': 0,
    'Highlights': 0,
    'Shadows': 0,
    'Hue': 0,
    'Color Boost': 0,
  };
  final Map<String, double> primary = <String, double>{
    'Lift': 0,
    'Gamma': 0,
    'Gain': 0,
    'Offset': 0,
  };
  final Map<String, double> log = <String, double>{
    'Shadows': 0,
    'Midtones': 0,
    'Highlights': 0,
    'Global': 0,
  };

  double curveMidpoint = 0;
  double hueLow = 0;
  double hueHigh = 1;
  DigitorNodeEffectType effectType = DigitorNodeEffectType.vignette;
  double effectAmount = 0.15;
  double effectRadius = 0.2;
  DigitorPowerWindowShape windowShape = DigitorPowerWindowShape.ellipse;
  double windowWidth = 0.75;
  double windowHeight = 0.75;
  double windowFeather = 0.15;

  @override
  void initState() {
    super.initState();
    gateway = DigitorEngineGateway()..addListener(_refresh);
    unawaited(gateway.initialize());
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
          Center(child: Text(gateway.rendererLabel)),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Import video',
            onPressed: gateway.ready ? gateway.pickMedia : null,
            icon: const Icon(Icons.video_file_outlined),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (gateway.error case final message?)
            MaterialBanner(
              content: Text(message),
              actions: const <Widget>[SizedBox.shrink()],
            ),
          Expanded(child: _PreviewPanel(gateway: gateway)),
          _TimelineStrip(gateway: gateway),
          _ToolSelector(
            selected: tool,
            onSelected: (value) => setState(() => tool = value),
          ),
          SizedBox(height: 270, child: _toolPanel()),
        ],
      ),
    );
  }

  Widget _toolPanel() {
    if (!gateway.ready) {
      return Center(
        child: gateway.initializing
            ? const CircularProgressIndicator()
            : const Text('DigitorEngine unavailable'),
      );
    }

    return switch (tool) {
      EditorTool.nodes => _NodesPanel(gateway: gateway),
      EditorTool.correction => _SliderPanel(
          title: 'Correction',
          values: correction,
          min: -1,
          max: 1,
          onChanged: (key, value) => setState(() => correction[key] = value),
          onApply: () => gateway.applyCorrection(
            exposure: correction['Exposure']!,
            contrast: correction['Contrast']!,
            saturation: correction['Saturation']!,
            temperature: correction['Temperature']!,
            tint: correction['Tint']!,
            highlights: correction['Highlights']!,
            shadows: correction['Shadows']!,
            hue: correction['Hue']!,
            colorBoost: correction['Color Boost']!,
          ),
        ),
      EditorTool.primary => _SliderPanel(
          title: 'Primary Wheels • master channels',
          values: primary,
          min: -1,
          max: 1,
          onChanged: (key, value) => setState(() => primary[key] = value),
          onApply: () => gateway.applyPrimaryWheels(
            lift: primary['Lift']!,
            gamma: primary['Gamma']!,
            gain: primary['Gain']!,
            offset: primary['Offset']!,
          ),
        ),
      EditorTool.log => _SliderPanel(
          title: 'Log Wheels • master channels',
          values: log,
          min: -1,
          max: 1,
          onChanged: (key, value) => setState(() => log[key] = value),
          onApply: () => gateway.applyLogWheels(
            shadows: log['Shadows']!,
            midtones: log['Midtones']!,
            highlights: log['Highlights']!,
            global: log['Global']!,
          ),
        ),
      EditorTool.curves => _SingleSliderPanel(
          title: 'RGB Curves • master midpoint',
          value: curveMidpoint,
          min: -0.45,
          max: 0.45,
          onChanged: (value) => setState(() => curveMidpoint = value),
          onApply: () => gateway.applyRgbCurve(curveMidpoint),
        ),
      EditorTool.qualifier => _QualifierPanel(
          low: hueLow,
          high: hueHigh,
          onLow: (value) => setState(() => hueLow = value),
          onHigh: (value) => setState(() => hueHigh = value),
          onApply: () => gateway.applyQualifier(
            hueLow: hueLow,
            hueHigh: hueHigh,
          ),
        ),
      EditorTool.lut => _ActionPanel(
          title: 'LUT',
          description:
              'LUT data is attached to the selected native DigitorEngine node.',
          label: 'Add identity LUT',
          onPressed: gateway.applyIdentityLut,
        ),
      EditorTool.effects => _EffectsPanel(
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
        ),
      EditorTool.window => _WindowPanel(
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
        ),
      EditorTool.export => const _ActionPanel(
          title: 'Export',
          description:
              'No Dart or Media3 export path exists. Production export will be bound to the exact DigitorEngine node-graph revision used by preview.',
          label: 'Engine-only export',
        ),
    };
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.gateway});
  final DigitorEngineGateway gateway;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.movie_outlined, size: 52),
              const SizedBox(height: 12),
              Text(gateway.mediaLabel, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(gateway.hostLabel),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: gateway.ready ? gateway.pickMedia : null,
                icon: const Icon(Icons.add),
                label: Text(
                  gateway.mediaPath == null ? 'Import video' : 'Replace video',
                ),
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
      height: 64,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF),
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

class _ToolSelector extends StatelessWidget {
  const _ToolSelector({required this.selected, required this.onSelected});
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
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
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
              OutlinedButton(
                onPressed: gateway.clearSelectedOperations,
                child: const Text('Clear operations'),
              ),
              OutlinedButton.icon(
                onPressed: gateway.removeSelectedNode,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Selected ${gateway.selectedNode} • graph ${gateway.graph.graphRevision} • parameters ${gateway.graph.parameterRevision}',
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(gateway.graph.json),
            ),
          ),
        ],
      ),
    );
  }
}

typedef NamedValueChanged = void Function(String key, double value);

class _SliderPanel extends StatelessWidget {
  const _SliderPanel({
    required this.title,
    required this.values,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onApply,
  });

  final String title;
  final Map<String, double> values;
  final double min;
  final double max;
  final NamedValueChanged onChanged;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return _PanelShell(
      title: title,
      onApply: onApply,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: values.entries
            .map(
              (entry) => _LabeledSlider(
                label: entry.key,
                value: entry.value,
                min: min,
                max: max,
                onChanged: (value) => onChanged(entry.key, value),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _SingleSliderPanel extends StatelessWidget {
  const _SingleSliderPanel({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onApply,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return _PanelShell(
      title: title,
      onApply: onApply,
      child: _LabeledSlider(
        label: 'Value',
        value: value,
        min: min,
        max: max,
        onChanged: onChanged,
      ),
    );
  }
}

class _QualifierPanel extends StatelessWidget {
  const _QualifierPanel({
    required this.low,
    required this.high,
    required this.onLow,
    required this.onHigh,
    required this.onApply,
  });

  final double low;
  final double high;
  final ValueChanged<double> onLow;
  final ValueChanged<double> onHigh;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return _PanelShell(
      title: 'HSL Qualifier',
      onApply: onApply,
      child: Wrap(
        children: <Widget>[
          _LabeledSlider(label: 'Hue low', value: low, onChanged: onLow),
          _LabeledSlider(label: 'Hue high', value: high, onChanged: onHigh),
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
    return _PanelShell(
      title: 'Effects',
      onApply: onApply,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          DropdownButton<DigitorNodeEffectType>(
            value: type,
            items: DigitorNodeEffectType.values
                .map(
                  (value) => DropdownMenuItem<DigitorNodeEffectType>(
                    value: value,
                    child: Text(value.name),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value != null) onType(value);
            },
          ),
          _LabeledSlider(
            label: 'Amount',
            value: amount,
            onChanged: onAmount,
          ),
          _LabeledSlider(
            label: 'Radius',
            value: radius,
            onChanged: onRadius,
          ),
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
    return _PanelShell(
      title: 'Power Window',
      onApply: onApply,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          DropdownButton<DigitorPowerWindowShape>(
            value: shape,
            items: DigitorPowerWindowShape.values
                .map(
                  (value) => DropdownMenuItem<DigitorPowerWindowShape>(
                    value: value,
                    child: Text(value.name),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value != null) onShape(value);
            },
          ),
          _LabeledSlider(label: 'Width', value: width, onChanged: onWidth),
          _LabeledSlider(label: 'Height', value: height, onChanged: onHeight),
          _LabeledSlider(
            label: 'Feather',
            value: feather,
            onChanged: onFeather,
          ),
        ],
      ),
    );
  }
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({
    required this.title,
    required this.child,
    required this.onApply,
  });

  final String title;
  final Widget child;
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
              Expanded(
                child: Text(title, style: Theme.of(context).textTheme.titleMedium),
              ),
              FilledButton(onPressed: onApply, child: const Text('Apply to node')),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: SingleChildScrollView(child: child)),
        ],
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final safeValue = value.clamp(min, max).toDouble();
    return SizedBox(
      width: 220,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('$label  ${safeValue.toStringAsFixed(2)}'),
          Slider(
            value: safeValue,
            min: min,
            max: max,
            onChanged: onChanged,
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
    required this.label,
    this.onPressed,
  });

  final String title;
  final String description;
  final String label;
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
          FilledButton(onPressed: onPressed, child: Text(label)),
        ],
      ),
    );
  }
}
