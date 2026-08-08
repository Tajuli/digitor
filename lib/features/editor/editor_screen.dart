import 'dart:async';

import 'package:digitor_engine_ffi/digitor_engine_ffi.dart';
import 'package:flutter/material.dart';

import '../../engine/digitor_engine_gateway.dart';

enum EditorTool {
  nodes('Nodes'), correction('Correction'), primary('Primary'), log('Log'),
  curves('Curves'), qualifier('Qualifier'), lut('LUT'), effects('Effects'),
  window('Window'), export('Export');
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
  final correction = <String, double>{
    'Exposure': 0, 'Contrast': 0, 'Saturation': 0, 'Temperature': 0,
    'Tint': 0, 'Highlights': 0, 'Shadows': 0, 'Hue': 0, 'Color Boost': 0,
  };
  final primary = <String, double>{'Lift': 0, 'Gamma': 0, 'Gain': 0, 'Offset': 0};
  final log = <String, double>{'Shadows': 0, 'Midtones': 0, 'Highlights': 0, 'Global': 0};
  double curveMidpoint = 0, hueLow = 0, hueHigh = 1;
  DigitorNodeEffectType effectType = DigitorNodeEffectType.vignette;
  double effectAmount = .15, effectRadius = .2;
  DigitorPowerWindowShape windowShape = DigitorPowerWindowShape.ellipse;
  double windowWidth = .75, windowHeight = .75, windowFeather = .15;

  @override
  void initState() {
    super.initState();
    gateway = DigitorEngineGateway()..addListener(_refresh);
    unawaited(gateway.initialize());
  }

  void _refresh() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    gateway.removeListener(_refresh);
    gateway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Digitor'),
      actions: [
        Center(child: Text(gateway.rendererLabel)),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Import video',
          onPressed: gateway.ready ? gateway.pickMedia : null,
          icon: const Icon(Icons.video_file_outlined),
        ),
      ],
    ),
    body: Column(children: [
      if (gateway.error case final message?)
        MaterialBanner(content: Text(message), actions: const [SizedBox.shrink()]),
      Expanded(child: _PreviewPanel(gateway: gateway)),
      _TimelineStrip(gateway: gateway),
      _ToolSelector(selected: tool, onSelected: (v) => setState(() => tool = v)),
      SizedBox(height: 270, child: _toolPanel()),
    ]),
  );

  Widget _toolPanel() {
    if (!gateway.ready) {
      return Center(child: gateway.initializing
          ? const CircularProgressIndicator()
          : const Text('DigitorEngine unavailable'));
    }
    return switch (tool) {
      EditorTool.nodes => _NodesPanel(gateway: gateway),
      EditorTool.correction => _SliderPanel(
        title: 'Correction', values: correction, min: -1, max: 1,
        onChanged: (k, v) => setState(() => correction[k] = v),
        onApply: () => gateway.applyCorrection(
          exposure: correction['Exposure']!, contrast: correction['Contrast']!,
          saturation: correction['Saturation']!, temperature: correction['Temperature']!,
          tint: correction['Tint']!, highlights: correction['Highlights']!,
          shadows: correction['Shadows']!, hue: correction['Hue']!,
          colorBoost: correction['Color Boost']!),
      ),
      EditorTool.primary => _SliderPanel(
        title: 'Primary Wheels • master channels', values: primary, min: -1, max: 1,
        onChanged: (k, v) => setState(() => primary[k] = v),
        onApply: () => gateway.applyPrimaryWheels(
          lift: primary['Lift']!, gamma: primary['Gamma']!,
          gain: primary['Gain']!, offset: primary['Offset']!),
      ),
      EditorTool.log => _SliderPanel(
        title: 'Log Wheels • master channels', values: log, min: -1, max: 1,
        onChanged: (k, v) => setState(() => log[k] = v),
        onApply: () => gateway.applyLogWheels(
          shadows: log['Shadows']!, midtones: log['Midtones']!,
          highlights: log['Highlights']!, global: log['Global']!),
      ),
      EditorTool.curves => _SingleSliderPanel(
        title: 'RGB Curves • master midpoint', value: curveMidpoint, min: -.45, max: .45,
        onChanged: (v) => setState(() => curveMidpoint = v),
        onApply: () => gateway.applyRgbCurve(curveMidpoint),
      ),
      EditorTool.qualifier => _QualifierPanel(
        low: hueLow, high: hueHigh,
        onLow: (v) => setState(() => hueLow = v),
        onHigh: (v) => setState(() => hueHigh = v),
        onApply: () => gateway.applyQualifier(hueLow: hueLow, hueHigh: hueHigh),
      ),
      EditorTool.lut => _ActionPanel(
        title: 'LUT',
        description: 'LUT data is attached to the selected DigitorEngine node.',
        label: 'Add identity LUT', onPressed: gateway.applyIdentityLut,
      ),
      EditorTool.effects => _EffectsPanel(
        type: effectType, amount: effectAmount, radius: effectRadius,
        onType: (v) => setState(() => effectType = v),
        onAmount: (v) => setState(() => effectAmount = v),
        onRadius: (v) => setState(() => effectRadius = v),
        onApply: () => gateway.applyEffect(type: effectType, amount: effectAmount, radius: effectRadius),
      ),
      EditorTool.window => _WindowPanel(
        shape: windowShape, width: windowWidth, height: windowHeight, feather: windowFeather,
        onShape: (v) => setState(() => windowShape = v),
        onWidth: (v) => setState(() => windowWidth = v),
        onHeight: (v) => setState(() => windowHeight = v),
        onFeather: (v) => setState(() => windowFeather = v),
        onApply: () => gateway.applyPowerWindow(
          shape: windowShape, width: windowWidth, height: windowHeight, feather: windowFeather),
      ),
      EditorTool.export => const _ActionPanel(
        title: 'Export',
        description: 'Preview and export are delegated to DigitorEngine.',
        label: 'Engine export',
      ),
    };
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({required this.gateway});
  final DigitorEngineGateway gateway;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.movie_outlined, size: 52),
        const SizedBox(height: 12), Text(gateway.mediaLabel, textAlign: TextAlign.center),
        const SizedBox(height: 6), Text(gateway.hostLabel),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: gateway.ready ? gateway.pickMedia : null,
          icon: const Icon(Icons.add),
          label: Text(gateway.mediaPath == null ? 'Import video' : 'Replace video'),
        ),
      ])),
    ),
  );
}

class _TimelineStrip extends StatefulWidget {
  const _TimelineStrip({required this.gateway});
  final DigitorEngineGateway gateway;
  @override
  State<_TimelineStrip> createState() => _TimelineStripState();
}

class _TimelineStripState extends State<_TimelineStrip> {
  Timer? _poller;
  DigitorTimelineStatus? _status;
  DigitorTimelineTelemetry? _telemetry;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
    _poller = Timer.periodic(const Duration(milliseconds: 200), (_) => _refreshStatus());
  }

  void _refreshStatus() {
    if (!mounted || !widget.gateway.ready) return;
    final status = widget.gateway.timelineStatus();
    final telemetry = widget.gateway.timelineTelemetry();
    if (!mounted) return;
    setState(() { _status = status; _telemetry = telemetry; });
  }

  void _playPause() {
    if (_status?.playbackState == DigitorPlaybackState.playing) {
      widget.gateway.pause();
    } else {
      widget.gateway.play();
    }
    _refreshStatus();
  }

  void _stop() { widget.gateway.stop(); _refreshStatus(); }
  void _seek(double fraction) {
    final duration = _status?.durationUs ?? 0;
    if (duration <= 0) return;
    widget.gateway.seek((duration * fraction.clamp(0.0, 1.0)).round());
    _refreshStatus();
  }

  @override
  void dispose() { _poller?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final duration = _status?.durationUs ?? 0;
    final position = _status?.positionUs ?? 0;
    final progress = duration <= 0 ? 0.0 : (position / duration).clamp(0.0, 1.0).toDouble();
    final playing = _status?.playbackState == DigitorPlaybackState.playing;
    final hasMedia = widget.gateway.mediaPath != null;
    return Container(
      height: 96, margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: const Color(0x0AFFFFFF), borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        Row(children: [
          IconButton(tooltip: playing ? 'Pause' : 'Play', onPressed: hasMedia ? _playPause : null,
            icon: Icon(playing ? Icons.pause : Icons.play_arrow)),
          IconButton(tooltip: 'Stop', onPressed: hasMedia ? _stop : null, icon: const Icon(Icons.stop)),
          Expanded(child: Slider(value: progress, onChanged: hasMedia && duration > 0 ? _seek : null)),
          const SizedBox(width: 8), Text(_timecode(position)), const Text(' / '),
          Text(duration > 0 ? _timecode(duration) : '--:--:--.---'),
        ]),
        Expanded(child: Row(children: [
          const SizedBox(width: 56, child: Text('V1 / A1', style: TextStyle(fontSize: 11))),
          Expanded(child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color: hasMedia ? Theme.of(context).colorScheme.primaryContainer : Colors.white10),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(alignment: Alignment.centerLeft,
                child: Text(hasMedia
                  ? '${_basename(widget.gateway.mediaPath!)} • Engine timeline r${_status?.revision ?? 0}'
                  : 'Import media to publish the Engine timeline',
                  overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)))),
          )),
          const SizedBox(width: 8),
          Text('pub ${_telemetry?.publications ?? 0} • seek ${_telemetry?.seekCommands ?? 0}',
            style: Theme.of(context).textTheme.labelSmall),
        ])),
      ]),
    );
  }

  static String _basename(String path) => path.replaceAll('\\', '/').split('/').last;
  static String _timecode(int us) {
    final d = Duration(microseconds: us < 0 ? 0 : us);
    return '${d.inHours.toString().padLeft(2, '0')}:'
      '${(d.inMinutes % 60).toString().padLeft(2, '0')}:'
      '${(d.inSeconds % 60).toString().padLeft(2, '0')}.'
      '${(d.inMilliseconds % 1000).toString().padLeft(3, '0')}';
  }
}

class _ToolSelector extends StatelessWidget {
  const _ToolSelector({required this.selected, required this.onSelected});
  final EditorTool selected;
  final ValueChanged<EditorTool> onSelected;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 58,
    child: ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      scrollDirection: Axis.horizontal,
      itemCount: EditorTool.values.length,
      separatorBuilder: (_, __) => const SizedBox(width: 6),
      itemBuilder: (_, i) { final v = EditorTool.values[i]; return ChoiceChip(
        label: Text(v.label), selected: v == selected, onSelected: (_) => onSelected(v)); },
    ),
  );
}

class _NodesPanel extends StatelessWidget {
  const _NodesPanel({required this.gateway});
  final DigitorEngineGateway gateway;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(onPressed: gateway.addSerialNode, icon: const Icon(Icons.add), label: const Text('Serial')),
        FilledButton.tonalIcon(onPressed: gateway.addParallelNodes, icon: const Icon(Icons.call_split), label: const Text('Parallel')),
        OutlinedButton(onPressed: gateway.clearSelectedOperations, child: const Text('Clear operations')),
        OutlinedButton.icon(onPressed: gateway.removeSelectedNode, icon: const Icon(Icons.delete_outline), label: const Text('Delete')),
      ]),
      const SizedBox(height: 10),
      Text('Selected ${gateway.selectedNode} • graph ${gateway.graphRevision} • parameters ${gateway.parameterRevision}'),
      const SizedBox(height: 8),
      SelectableText('Recipe identity: ${gateway.recipeIdentity}'),
    ]),
  );
}

typedef NamedValueChanged = void Function(String key, double value);

class _SliderPanel extends StatelessWidget {
  const _SliderPanel({required this.title, required this.values, required this.min,
    required this.max, required this.onChanged, required this.onApply});
  final String title; final Map<String, double> values; final double min, max;
  final NamedValueChanged onChanged; final VoidCallback onApply;
  @override
  Widget build(BuildContext context) => _PanelShell(title: title, onApply: onApply,
    child: Wrap(spacing: 8, runSpacing: 4, children: values.entries.map((e) =>
      _LabeledSlider(label: e.key, value: e.value, min: min, max: max,
        onChanged: (v) => onChanged(e.key, v))).toList()));
}

class _SingleSliderPanel extends StatelessWidget {
  const _SingleSliderPanel({required this.title, required this.value, required this.min,
    required this.max, required this.onChanged, required this.onApply});
  final String title; final double value, min, max; final ValueChanged<double> onChanged;
  final VoidCallback onApply;
  @override
  Widget build(BuildContext context) => _PanelShell(title: title, onApply: onApply,
    child: _LabeledSlider(label: 'Value', value: value, min: min, max: max, onChanged: onChanged));
}

class _QualifierPanel extends StatelessWidget {
  const _QualifierPanel({required this.low, required this.high, required this.onLow,
    required this.onHigh, required this.onApply});
  final double low, high; final ValueChanged<double> onLow, onHigh; final VoidCallback onApply;
  @override
  Widget build(BuildContext context) => _PanelShell(title: 'HSL Qualifier', onApply: onApply,
    child: Wrap(children: [
      _LabeledSlider(label: 'Hue low', value: low, onChanged: onLow),
      _LabeledSlider(label: 'Hue high', value: high, onChanged: onHigh),
    ]));
}

class _EffectsPanel extends StatelessWidget {
  const _EffectsPanel({required this.type, required this.amount, required this.radius,
    required this.onType, required this.onAmount, required this.onRadius, required this.onApply});
  final DigitorNodeEffectType type; final double amount, radius;
  final ValueChanged<DigitorNodeEffectType> onType; final ValueChanged<double> onAmount, onRadius;
  final VoidCallback onApply;
  @override
  Widget build(BuildContext context) => _PanelShell(title: 'Effects', onApply: onApply,
    child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
      DropdownButton<DigitorNodeEffectType>(value: type,
        items: DigitorNodeEffectType.values.map((v) => DropdownMenuItem(value: v, child: Text(v.name))).toList(),
        onChanged: (v) { if (v != null) onType(v); }),
      _LabeledSlider(label: 'Amount', value: amount, onChanged: onAmount),
      _LabeledSlider(label: 'Radius', value: radius, onChanged: onRadius),
    ]));
}

class _WindowPanel extends StatelessWidget {
  const _WindowPanel({required this.shape, required this.width, required this.height,
    required this.feather, required this.onShape, required this.onWidth, required this.onHeight,
    required this.onFeather, required this.onApply});
  final DigitorPowerWindowShape shape; final double width, height, feather;
  final ValueChanged<DigitorPowerWindowShape> onShape; final ValueChanged<double> onWidth, onHeight, onFeather;
  final VoidCallback onApply;
  @override
  Widget build(BuildContext context) => _PanelShell(title: 'Power Window', onApply: onApply,
    child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
      DropdownButton<DigitorPowerWindowShape>(value: shape,
        items: DigitorPowerWindowShape.values.map((v) => DropdownMenuItem(value: v, child: Text(v.name))).toList(),
        onChanged: (v) { if (v != null) onShape(v); }),
      _LabeledSlider(label: 'Width', value: width, onChanged: onWidth),
      _LabeledSlider(label: 'Height', value: height, onChanged: onHeight),
      _LabeledSlider(label: 'Feather', value: feather, onChanged: onFeather),
    ]));
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({required this.title, required this.child, required this.onApply});
  final String title; final Widget child; final VoidCallback onApply;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        FilledButton(onPressed: onApply, child: const Text('Apply to node'))]),
      const SizedBox(height: 8), Expanded(child: SingleChildScrollView(child: child)),
    ]));
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({required this.label, required this.value, required this.onChanged,
    this.min = 0, this.max = 1});
  final String label; final double value, min, max; final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) {
    final safe = value.clamp(min, max).toDouble();
    return SizedBox(width: 220, child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('$label  ${safe.toStringAsFixed(2)}'),
      Slider(value: safe, min: min, max: max, onChanged: onChanged),
    ]));
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({required this.title, required this.description, required this.label, this.onPressed});
  final String title, description, label; final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 12),
      Text(description), const SizedBox(height: 18), FilledButton(onPressed: onPressed, child: Text(label)),
    ]));
}
