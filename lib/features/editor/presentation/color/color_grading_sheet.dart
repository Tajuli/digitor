import 'dart:math' as math;
import 'dart:ui' show FontFeature;
import 'package:digitor/features/editor/domain/models/clip_adjustments.dart';
import 'package:digitor/features/editor/domain/models/color/color_node_graph.dart';
import 'package:flutter/material.dart';

enum ColorPanelType { correction, wheels, curves, qualifier }

class ColorGradingSheet extends StatefulWidget {
  const ColorGradingSheet({super.key, required this.graph, required this.type, required this.onDone, this.onChanged});
  final ColorNodeGraph graph;
  final ColorPanelType type;
  final ValueChanged<ColorNodeGraph> onDone;
  final ValueChanged<ColorNodeGraph>? onChanged;
  @override State<ColorGradingSheet> createState() => _ColorGradingSheetState();
}

class _ColorGradingSheetState extends State<ColorGradingSheet> {
  late ColorNodeGraph graph;
  late ColorNode node;
  bool _qualifierPickerActive = false;
  @override void initState(){super.initState(); graph=widget.graph; node=graph.selectedProcessingNode ?? graph.defaultNode;}
  void _replace(ColorNode next){setState((){node=next; graph=graph.copyWith(nodes: graph.nodes.map((n)=>n.id==next.id?next:n).toList());}); widget.onChanged?.call(graph);}
  @override Widget build(BuildContext context){
    return Material(color: const Color(0xff202126), child: SafeArea(top:false, child: Column(children:[
      SizedBox(height:46, child: Row(children:[
        IconButton(onPressed:()=>widget.onDone(graph), icon:const Icon(Icons.keyboard_arrow_down,color:Colors.white)),
        Text(_title, style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w600)),
        const Spacer(), Text(node.name,style:const TextStyle(color:Colors.white54,fontSize:12)), const SizedBox(width:14),
        IconButton(onPressed:_reset,icon:const Icon(Icons.restart_alt,color:Colors.white70)),
      ])), const Divider(height:1,color:Colors.white12),
      Expanded(child: switch (widget.type) {
        ColorPanelType.correction => _correction(),
        ColorPanelType.wheels => _wheels(),
        ColorPanelType.curves => _curves(),
        ColorPanelType.qualifier => _qualifier(),
      }),
    ])));
  }
  String get _title => switch (widget.type) {
    ColorPanelType.correction => 'Correction',
    ColorPanelType.wheels => 'Color Wheels',
    ColorPanelType.curves => 'Curves',
    ColorPanelType.qualifier => 'Qualifier · HSL',
  };
  void _reset(){
    if (widget.type == ColorPanelType.qualifier) {
      _replace(node.copyWith(qualifier: const HslQualifierSettings()));
    } else if (widget.type == ColorPanelType.curves) {
      _replace(node.copyWith(curves: const ColorCurveSettings()));
    } else if (widget.type == ColorPanelType.correction) {
      _replace(node.copyWith(grade: const ClipColorAdjustments()));
    } else {
      _replace(node.copyWith(wheels: const ColorWheelSettings()));
    }
  }

  Widget _wheels() {
    final wheels = node.wheels;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: wheels.previewEnabled ? 'Disable wheel preview' : 'Enable wheel preview',
              onPressed: () => _wheelSettings(wheels.copyWith(previewEnabled: !wheels.previewEnabled)),
              style: IconButton.styleFrom(
                backgroundColor: wheels.previewEnabled ? Colors.white12 : Colors.transparent,
              ),
              icon: Icon(
                wheels.previewEnabled ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                color: wheels.previewEnabled ? Colors.white : Colors.white38,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              wheels.previewEnabled ? 'Preview on' : 'Preview bypassed',
              style: TextStyle(
                color: wheels.previewEnabled ? Colors.white70 : Colors.white38,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _wheelSettings(const ColorWheelSettings()),
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Reset all'),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 720 ? 4 : constraints.maxWidth >= 360 ? 2 : 1;
            const gap = 10.0;
            final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                _wheelCard('Lift', wheels.lift, width, (v) => _wheelSettings(wheels.copyWith(lift: v))),
                _wheelCard('Gamma', wheels.gamma, width, (v) => _wheelSettings(wheels.copyWith(gamma: v))),
                _wheelCard('Gain', wheels.gain, width, (v) => _wheelSettings(wheels.copyWith(gain: v))),
                _wheelCard('Offset', wheels.offset, width, (v) => _wheelSettings(wheels.copyWith(offset: v))),
              ],
            );
          },
        ),
      ],
    );
  }


  Widget _correction() {
    final grade = node.grade;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        _correctionSlider('Exposure', Icons.exposure_rounded, grade.exposure, -1, 1, (v) => _grade(grade.copyWith(exposure: v))),
        _correctionSlider('Contrast', Icons.contrast_rounded, grade.contrast, -1, 1, (v) => _grade(grade.copyWith(contrast: v))),
        _correctionSlider('Saturation', Icons.water_drop_outlined, grade.saturation, -1, 1, (v) => _grade(grade.copyWith(saturation: v))),
        _correctionSlider('Temperature', Icons.thermostat_rounded, grade.temperature, -1, 1, (v) => _grade(grade.copyWith(temperature: v))),
        _correctionSlider('Tint', Icons.gradient_rounded, grade.tint, -1, 1, (v) => _grade(grade.copyWith(tint: v))),
        _correctionSlider('Highlights', Icons.wb_sunny_outlined, grade.highlights, -1, 1, (v) => _grade(grade.copyWith(highlights: v))),
        _correctionSlider('Shadows', Icons.nights_stay_outlined, grade.shadows, -1, 1, (v) => _grade(grade.copyWith(shadows: v))),
        _correctionSlider('Hue', Icons.palette_outlined, grade.hue, -1, 1, (v) => _grade(grade.copyWith(hue: v)), suffix: '${(grade.hue * 180).round()}°'),
        _correctionSlider('Color Boost', Icons.auto_awesome_rounded, grade.colorBoost, -1, 1, (v) => _grade(grade.copyWith(colorBoost: v))),
      ],
    );
  }

  Widget _correctionSlider(
    String label,
    IconData icon,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    String? suffix,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    decoration: BoxDecoration(
      color: const Color(0xff292b30),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white10),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: Colors.white54),
        const SizedBox(width: 10),
        SizedBox(width: 88, child: Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600))),
        Expanded(
          child: GestureDetector(
            onDoubleTap: () => onChanged(0),
            child: Slider(value: value.clamp(min, max).toDouble(), min: min, max: max, onChanged: onChanged),
          ),
        ),
        SizedBox(
          width: 50,
          child: InkWell(
            borderRadius: BorderRadius.circular(5),
            onTap: () => _editCorrectionValue(label, value, min, max, onChanged),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Text(
                suffix ?? _signed(value),
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Reset $label',
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(0),
          icon: const Icon(Icons.restart_alt_rounded, size: 18, color: Colors.white38),
        ),
      ],
    ),
  );

  void _wheelSettings(ColorWheelSettings value) => _replace(node.copyWith(wheels: value));
  void _grade(ClipColorAdjustments value) => _replace(node.copyWith(grade: value));

  Widget _wheelCard(
    String label,
    ColorWheelControl value,
    double width,
    ValueChanged<ColorWheelControl> onChanged,
  ) {
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xff292b30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                tooltip: 'Reset $label',
                visualDensity: VisualDensity.compact,
                onPressed: () => onChanged(const ColorWheelControl()),
                icon: const Icon(Icons.restart_alt_rounded, color: Colors.white54, size: 18),
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final size = math.min(constraints.maxWidth - 12, 132.0).clamp(88.0, 132.0).toDouble();
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanDown: (details) => _setWheelFromPosition(details.localPosition, size, value, onChanged),
                onPanUpdate: (details) => _setWheelFromPosition(details.localPosition, size, value, onChanged),
                onDoubleTap: () => onChanged(value.copyWith(chroma: Offset.zero)),
                child: CustomPaint(
                  size: Size.square(size),
                  painter: _WheelPainter(value.chroma),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.brightness_6_rounded, size: 15, color: Colors.white38),
              Expanded(
                child: Slider(
                  value: value.luminance.clamp(-1.0, 1.0).toDouble(),
                  min: -1,
                  max: 1,
                  onChanged: (v) => onChanged(value.copyWith(luminance: v)),
                ),
              ),
              SizedBox(
                width: 42,
                child: InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: () => _editWheelComponent(
                    '$label luminance',
                    value.luminance,
                    (v) => onChanged(value.copyWith(luminance: v)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Text(
                      _signed(value.luminance),
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _numeric(
                'X',
                value.chroma.dx,
                onTap: () => _editWheelComponent(
                  '$label X',
                  value.chroma.dx,
                  (v) => onChanged(value.copyWith(chroma: Offset(v, value.chroma.dy))),
                ),
              ),
              _numeric(
                'Y',
                value.chroma.dy,
                onTap: () => _editWheelComponent(
                  '$label Y',
                  value.chroma.dy,
                  (v) => onChanged(value.copyWith(chroma: Offset(value.chroma.dx, v))),
                ),
              ),
              _numeric(
                'Lum',
                value.luminance,
                onTap: () => _editWheelComponent(
                  '$label luminance',
                  value.luminance,
                  (v) => onChanged(value.copyWith(luminance: v)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _setWheelFromPosition(
    Offset position,
    double size,
    ColorWheelControl current,
    ValueChanged<ColorWheelControl> onChanged,
  ) {
    final center = Offset(size / 2, size / 2);
    var normalized = (position - center) / (size / 2);
    if (normalized.distance > 1) normalized = normalized / normalized.distance;
    onChanged(current.copyWith(chroma: Offset(normalized.dx, normalized.dy)));
  }

  Widget _numeric(String label, double value, {VoidCallback? onTap}) => InkWell(
    borderRadius: BorderRadius.circular(5),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(5)),
      child: Text(
        '$label ${_signed(value)}',
        style: const TextStyle(color: Colors.white60, fontSize: 10, fontFeatures: [FontFeature.tabularFigures()]),
      ),
    ),
  );

  Future<void> _editCorrectionValue(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) async {
    final isHue = label == 'Hue';
    final shownValue = isHue ? value * 180 : value;
    final result = await _showNumericInput(
      title: label,
      value: shownValue,
      min: isHue ? -180 : min,
      max: isHue ? 180 : max,
      suffix: isHue ? '°' : null,
    );
    if (result == null) return;
    onChanged(isHue ? result / 180 : result);
  }

  Future<void> _editWheelComponent(
    String title,
    double value,
    ValueChanged<double> onChanged,
  ) async {
    final result = await _showNumericInput(title: title, value: value, min: -1, max: 1);
    if (result != null) onChanged(result);
  }

  Future<double?> _showNumericInput({
    required String title,
    required double value,
    required double min,
    required double max,
    String? suffix,
  }) {
    return showDialog<double>(
      context: context,
      builder: (_) => _NumericInputDialog(
        title: title,
        value: value,
        min: min,
        max: max,
        suffix: suffix,
      ),
    );
  }

  String _signed(double value) => '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}';

  Widget _wide(String label,double value,double min,double max,ValueChanged<double> change)=>Row(children:[SizedBox(width:90,child:Text(label,style:const TextStyle(color:Colors.white70))),Expanded(child:Slider(value:value.clamp(min,max).toDouble(),min:min,max:max,onChanged:change)),SizedBox(width:48,child:Text(value.toStringAsFixed(2),style:const TextStyle(color:Colors.white70)))]);

  Widget _curves(){final c=node.curves; return Column(children:[
    Padding(padding:const EdgeInsets.all(10),child:Row(children:[for(final ch in CurveChannel.values) _channelButton(ch,c.channel),const Spacer(),const Text('Drag points · double tap to add',style:TextStyle(color:Colors.white38,fontSize:11))])),
    Expanded(child:Padding(padding:const EdgeInsets.fromLTRB(12,0,12,8),child:_CurveEditor(settings:c,onChanged:(v)=>_replace(node.copyWith(curves:v))))),
    Padding(padding:const EdgeInsets.symmetric(horizontal:12),child:Column(children:[_curveSlider('Low Soft',c.lowSoft,(v)=>_curve(c.copyWith(lowSoft:v))),_curveSlider('High Soft',c.highSoft,(v)=>_curve(c.copyWith(highSoft:v)))])),
  ]);}
  void _curve(ColorCurveSettings c)=>_replace(node.copyWith(curves:c));
  Widget _channelButton(CurveChannel ch,CurveChannel selected)=>Padding(padding:const EdgeInsets.only(right:6),child:ChoiceChip(label:Text(ch.name.toUpperCase()),selected:ch==selected,onSelected:(_)=>_curve(node.curves.copyWith(channel:ch)),selectedColor:_channelColor(ch),backgroundColor:const Color(0xff303238),labelStyle:TextStyle(color:ch==selected?Colors.black:Colors.white)));
  Color _channelColor(CurveChannel c)=>switch(c){CurveChannel.y=>Colors.white,CurveChannel.r=>Colors.redAccent,CurveChannel.g=>Colors.greenAccent,CurveChannel.b=>Colors.blueAccent};
  Widget _curveSlider(String t,double v,ValueChanged<double> f)=>Row(children:[SizedBox(width:80,child:Text(t,style:const TextStyle(color:Colors.white60))),Expanded(child:Slider(value:v,min:0,max:1,onChanged:f)),Text((v*100).toStringAsFixed(0),style:const TextStyle(color:Colors.white70))]);

  Widget _qualifier(){
    final q=node.qualifier;
    return ListView(padding:const EdgeInsets.all(12),children:[
      Row(children:[
        IconButton(
          tooltip:'HSL picker',
          onPressed:()=>setState(()=>_qualifierPickerActive=!_qualifierPickerActive),
          style:IconButton.styleFrom(backgroundColor:_qualifierPickerActive?Colors.white12:Colors.transparent),
          icon:Icon(Icons.colorize_rounded,color:_qualifierPickerActive?Colors.white:Colors.white54),
        ),
        const SizedBox(width:4),
        const Text('Qualifier tools',style:TextStyle(color:Colors.white70,fontWeight:FontWeight.w600)),
        const Spacer(),
        Switch(value:q.enabled,onChanged:(v)=>_qual(q.copyWith(enabled:v))),
      ]),
      if(_qualifierPickerActive)
        Container(
          margin:const EdgeInsets.only(bottom:12),
          padding:const EdgeInsets.all(10),
          decoration:BoxDecoration(color:const Color(0xff2a2c31),borderRadius:BorderRadius.circular(10),border:Border.all(color:Colors.white12)),
          child:const Row(children:[
            Icon(Icons.touch_app_rounded,color:Colors.white60,size:18),
            SizedBox(width:8),
            Expanded(child:Text('Picker active: tap the Hue strip to sample/select a colour family.',style:TextStyle(color:Colors.white60,fontSize:12))),
          ]),
        ),
      _huePickerRange(q),
      _gradientRange('Saturation',q.saturationLow,q.saturationHigh,(r)=>_qual(q.copyWith(enabled:true,saturationLow:r.start,saturationHigh:r.end)),const [Colors.grey,Colors.green]),
      _gradientRange('Luminance',q.luminanceLow,q.luminanceHigh,(r)=>_qual(q.copyWith(enabled:true,luminanceLow:r.start,luminanceHigh:r.end)),const [Colors.black,Colors.white]),
      const SizedBox(height:10),
      const Text('Matte Finesse',style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w600)),
      _qSlider('Pre-Filter',q.softness,(v)=>_qual(q.copyWith(enabled:true,softness:v))),
      _qSlider('Clean Black',q.denoise,(v)=>_qual(q.copyWith(enabled:true,denoise:v))),
      _qSlider('Blur Radius',q.blur,(v)=>_qual(q.copyWith(enabled:true,blur:v))),
      SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Invert Matte',style:TextStyle(color:Colors.white70)),value:q.inverted,onChanged:(v)=>_qual(q.copyWith(enabled:true,inverted:v))),
    ]);
  }

  Widget _huePickerRange(HslQualifierSettings q){
    final lo=(q.hueCenter-q.hueWidth/2).clamp(0.0,1.0).toDouble();
    final hi=(q.hueCenter+q.hueWidth/2).clamp(0.0,1.0).toDouble();
    const colors=[Colors.purple,Colors.red,Colors.yellow,Colors.green,Colors.cyan,Colors.blue,Color(0xFFFF00FF)];
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Hue',style:TextStyle(color:Colors.white70)),
      GestureDetector(
        behavior:HitTestBehavior.opaque,
        onTapDown:_qualifierPickerActive?(details){
          final box=context.findRenderObject();
          final width=(box is RenderBox?box.size.width:300.0)-24;
          final value=(details.localPosition.dx/width).clamp(0.0,1.0).toDouble();
          _qual(q.copyWith(enabled:true,hueCenter:value,hueWidth:math.min(q.hueWidth,.18)));
        }:null,
        child:Container(height:20,margin:const EdgeInsets.only(top:6),decoration:BoxDecoration(borderRadius:BorderRadius.circular(5),gradient:const LinearGradient(colors:colors),border:Border.all(color:_qualifierPickerActive?Colors.white70:Colors.white24))),
      ),
      RangeSlider(values:RangeValues(lo,hi),onChanged:(r)=>_qual(q.copyWith(enabled:true,hueCenter:(r.start+r.end)/2,hueWidth:math.max(.01,r.end-r.start)))),
      Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
        Text('Center ${(q.hueCenter*360).toStringAsFixed(0)}°',style:const TextStyle(color:Colors.white54)),
        Text('Width ${(q.hueWidth*100).toStringAsFixed(0)}',style:const TextStyle(color:Colors.white54)),
      ]),
      const SizedBox(height:8),
    ]);
  }
  void _qual(HslQualifierSettings q)=>_replace(node.copyWith(qualifier:q));
  Widget _gradientRange(String title,double lo,double hi,ValueChanged<RangeValues> f,List<Color> colors)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(color:Colors.white70)),Container(height:16,margin:const EdgeInsets.only(top:6),decoration:BoxDecoration(borderRadius:BorderRadius.circular(8),gradient:LinearGradient(colors:colors))),RangeSlider(values:RangeValues(lo.clamp(0,1).toDouble(),hi.clamp(0,1).toDouble()),onChanged:f),Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text((lo*100).toStringAsFixed(0),style:const TextStyle(color:Colors.white54)),Text((hi*100).toStringAsFixed(0),style:const TextStyle(color:Colors.white54))]),const SizedBox(height:8)]);
  Widget _qSlider(String t,double v,ValueChanged<double> f)=>_wide(t,v,0,1,f);
}


class _NumericInputDialog extends StatefulWidget {
  const _NumericInputDialog({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    this.suffix,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final String? suffix;

  @override
  State<_NumericInputDialog> createState() => _NumericInputDialogState();
}

class _NumericInputDialogState extends State<_NumericInputDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String? _error;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.value.toStringAsFixed(2),
    );
    _focusNode = FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  double? _parseValue() {
    final normalized = _controller.text.trim().replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  void _submit() {
    if (_submitted) return;

    final parsed = _parseValue();
    if (parsed == null || parsed < widget.min || parsed > widget.max) {
      setState(() {
        _error =
            'Enter a value between ${widget.min.toStringAsFixed(2)} and ${widget.max.toStringAsFixed(2)}';
      });
      return;
    }

    _submitted = true;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(parsed);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xff292b30),
      title: Text(
        'Set ${widget.title}',
        style: const TextStyle(color: Colors.white),
      ),
      content: TextField(
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        textInputAction: TextInputAction.done,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText:
              'Value${widget.suffix == null ? '' : ' (${widget.suffix})'}',
          labelStyle: const TextStyle(color: Colors.white54),
          errorText: _error,
          helperText:
              '${widget.min.toStringAsFixed(2)} to ${widget.max.toStringAsFixed(2)}',
          helperStyle: const TextStyle(color: Colors.white38),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white24),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white70),
          ),
          errorBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.redAccent),
          ),
          focusedErrorBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.redAccent),
          ),
        ),
        onChanged: (_) {
          if (_error == null) return;
          setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () {
            FocusScope.of(context).unfocus();
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter(this.chroma);
  final Offset chroma;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final circle = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const SweepGradient(
          colors: [
            Colors.red,
            Colors.yellow,
            Colors.green,
            Colors.cyan,
            Colors.blue,
            Color(0xFFFF00FF),
            Colors.red,
          ],
        ).createShader(circle),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Colors.white, Color(0x00FFFFFF)],
          stops: [0, 1],
        ).createShader(circle),
    );
    canvas.drawCircle(center, radius, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.white24);
    canvas.drawLine(Offset(center.dx, 3), Offset(center.dx, size.height - 3), Paint()..color = Colors.white12);
    canvas.drawLine(Offset(3, center.dy), Offset(size.width - 3, center.dy), Paint()..color = Colors.white12);

    final dot = center + Offset(chroma.dx, chroma.dy) * radius;
    canvas.drawCircle(dot, 7, Paint()..color = Colors.black87);
    canvas.drawCircle(dot, 5, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) => oldDelegate.chroma != chroma;
}

class _CurveEditor extends StatelessWidget{const _CurveEditor({required this.settings,required this.onChanged});final ColorCurveSettings settings;final ValueChanged<ColorCurveSettings> onChanged;@override Widget build(BuildContext context){return LayoutBuilder(builder:(context,b){final pts=settings.pointsFor(settings.channel);return GestureDetector(onDoubleTapDown:(d){final p=Offset((d.localPosition.dx/b.maxWidth).clamp(0,1).toDouble(),1-(d.localPosition.dy/b.maxHeight).clamp(0,1).toDouble());final n=[...pts,p]..sort((a,b)=>a.dx.compareTo(b.dx));onChanged(settings.withPoints(settings.channel,n));},onPanUpdate:(d){if(pts.length<=2)return;final pos=Offset((d.localPosition.dx/b.maxWidth).clamp(0,1).toDouble(),1-(d.localPosition.dy/b.maxHeight).clamp(0,1).toDouble());var nearest=1;var dist=double.infinity;for(var i=1;i<pts.length-1;i++){final dd=(pts[i]-pos).distance;if(dd<dist){dist=dd;nearest=i;}}final n=[...pts];n[nearest]=Offset(pos.dx.clamp(n[nearest-1].dx+.01,n[nearest+1].dx-.01).toDouble(),pos.dy);onChanged(settings.withPoints(settings.channel,n));},child:CustomPaint(size:Size.infinite,painter:_CurvePainter(pts,settings.channel)));});}}
class _CurvePainter extends CustomPainter{_CurvePainter(this.points,this.channel);final List<Offset> points;final CurveChannel channel;@override void paint(Canvas c,Size s){c.drawRect(Offset.zero&s,Paint()..color=const Color(0xff17181c));final grid=Paint()..color=Colors.white10..strokeWidth=1;for(int i=1;i<8;i++){c.drawLine(Offset(s.width*i/8,0),Offset(s.width*i/8,s.height),grid);c.drawLine(Offset(0,s.height*i/8),Offset(s.width,s.height*i/8),grid);}final path=Path();for(int i=0;i<points.length;i++){final p=Offset(points[i].dx*s.width,(1-points[i].dy)*s.height);if(i==0)path.moveTo(p.dx,p.dy);else path.lineTo(p.dx,p.dy);}final color=switch(channel){CurveChannel.y=>Colors.white,CurveChannel.r=>Colors.redAccent,CurveChannel.g=>Colors.greenAccent,CurveChannel.b=>Colors.blueAccent};c.drawPath(path,Paint()..color=color..strokeWidth=2..style=PaintingStyle.stroke);for(final v in points){final p=Offset(v.dx*s.width,(1-v.dy)*s.height);c.drawCircle(p,5,Paint()..color=const Color(0xff17181c));c.drawCircle(p,3,Paint()..color=color);}}@override bool shouldRepaint(covariant _CurvePainter old)=>old.points!=points||old.channel!=channel;}
