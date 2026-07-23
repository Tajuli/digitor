import 'package:digitor/features/editor/domain/models/clip_adjustments.dart';
import 'package:flutter/material.dart';

enum ColorNodeType { input, serial, parallel, parallelMixer, output }

enum CurveChannel { y, r, g, b }

class ColorCurveSettings {
  const ColorCurveSettings({
    this.channel = CurveChannel.y,
    this.y = const [Offset(0, 0), Offset(1, 1)],
    this.r = const [Offset(0, 0), Offset(1, 1)],
    this.g = const [Offset(0, 0), Offset(1, 1)],
    this.b = const [Offset(0, 0), Offset(1, 1)],
    this.lowSoft = 0,
    this.highSoft = 0,
  });
  final CurveChannel channel;
  final List<Offset> y, r, g, b;
  final double lowSoft, highSoft;
  List<Offset> pointsFor(CurveChannel c) => switch(c){CurveChannel.y=>y,CurveChannel.r=>r,CurveChannel.g=>g,CurveChannel.b=>b};
  ColorCurveSettings withPoints(CurveChannel c,List<Offset> points)=>copyWith(y:c==CurveChannel.y?points:null,r:c==CurveChannel.r?points:null,g:c==CurveChannel.g?points:null,b:c==CurveChannel.b?points:null);
  ColorCurveSettings copyWith({CurveChannel? channel,List<Offset>? y,List<Offset>? r,List<Offset>? g,List<Offset>? b,double? lowSoft,double? highSoft})=>ColorCurveSettings(channel:channel??this.channel,y:y??this.y,r:r??this.r,g:g??this.g,b:b??this.b,lowSoft:lowSoft??this.lowSoft,highSoft:highSoft??this.highSoft);
  Map<String,dynamic> toJson()=>{'channel':channel.name,'y':_encode(y),'r':_encode(r),'g':_encode(g),'b':_encode(b),'lowSoft':lowSoft,'highSoft':highSoft};
  static List<List<double>> _encode(List<Offset> p)=>p.map((e)=>[e.dx,e.dy]).toList();
  static List<Offset> _decode(dynamic v){final list=(v as List?)??const [];final out=list.whereType<List>().where((e)=>e.length>=2).map((e)=>Offset((e[0] as num).toDouble(),(e[1] as num).toDouble())).toList();return out.length>=2?out:const [Offset(0,0),Offset(1,1)];}
  factory ColorCurveSettings.fromJson(Map<String,dynamic> j)=>ColorCurveSettings(channel:CurveChannel.values.firstWhere((e)=>e.name==(j['channel']??'y'),orElse:()=>CurveChannel.y),y:_decode(j['y']),r:_decode(j['r']),g:_decode(j['g']),b:_decode(j['b']),lowSoft:(j['lowSoft'] as num?)?.toDouble()??0,highSoft:(j['highSoft'] as num?)?.toDouble()??0);
}

class HslQualifierSettings {
  const HslQualifierSettings({
    this.enabled = false,
    this.hueCenter = 0.5,
    this.hueWidth = 1,
    this.saturationLow = 0,
    this.saturationHigh = 1,
    this.luminanceLow = 0,
    this.luminanceHigh = 1,
    this.softness = 0.1,
    this.denoise = 0,
    this.blur = 0,
    this.inverted = false,
  });

  final bool enabled;
  final double hueCenter;
  final double hueWidth;
  final double saturationLow;
  final double saturationHigh;
  final double luminanceLow;
  final double luminanceHigh;
  final double softness;
  final double denoise;
  final double blur;
  final bool inverted;

  HslQualifierSettings copyWith({
    bool? enabled,
    double? hueCenter,
    double? hueWidth,
    double? saturationLow,
    double? saturationHigh,
    double? luminanceLow,
    double? luminanceHigh,
    double? softness,
    double? denoise,
    double? blur,
    bool? inverted,
  }) => HslQualifierSettings(
    enabled: enabled ?? this.enabled,
    hueCenter: hueCenter ?? this.hueCenter,
    hueWidth: hueWidth ?? this.hueWidth,
    saturationLow: saturationLow ?? this.saturationLow,
    saturationHigh: saturationHigh ?? this.saturationHigh,
    luminanceLow: luminanceLow ?? this.luminanceLow,
    luminanceHigh: luminanceHigh ?? this.luminanceHigh,
    softness: softness ?? this.softness,
    denoise: denoise ?? this.denoise,
    blur: blur ?? this.blur,
    inverted: inverted ?? this.inverted,
  );

  Map<String, dynamic> toJson() => {
    'enabled': enabled, 'hueCenter': hueCenter, 'hueWidth': hueWidth,
    'saturationLow': saturationLow, 'saturationHigh': saturationHigh,
    'luminanceLow': luminanceLow, 'luminanceHigh': luminanceHigh,
    'softness': softness, 'denoise': denoise, 'blur': blur, 'inverted': inverted,
  };

  factory HslQualifierSettings.fromJson(Map<String, dynamic> json) => HslQualifierSettings(
    enabled: json['enabled'] as bool? ?? false,
    hueCenter: (json['hueCenter'] as num?)?.toDouble() ?? .5,
    hueWidth: (json['hueWidth'] as num?)?.toDouble() ?? 1,
    saturationLow: (json['saturationLow'] as num?)?.toDouble() ?? 0,
    saturationHigh: (json['saturationHigh'] as num?)?.toDouble() ?? 1,
    luminanceLow: (json['luminanceLow'] as num?)?.toDouble() ?? 0,
    luminanceHigh: (json['luminanceHigh'] as num?)?.toDouble() ?? 1,
    softness: (json['softness'] as num?)?.toDouble() ?? .1,
    denoise: (json['denoise'] as num?)?.toDouble() ?? 0,
    blur: (json['blur'] as num?)?.toDouble() ?? 0,
    inverted: json['inverted'] as bool? ?? false,
  );
}

class ColorNode {
  const ColorNode({
    required this.id,
    required this.type,
    required this.name,
    required this.position,
    this.enabled = true,
    this.grade = const ClipColorAdjustments(),
    this.qualifier = const HslQualifierSettings(),
    this.curves = const ColorCurveSettings(),
  });

  final String id;
  final ColorNodeType type;
  final String name;
  final Offset position;
  final bool enabled;
  final ClipColorAdjustments grade;
  final HslQualifierSettings qualifier;
  final ColorCurveSettings curves;

  bool get supportsProcessing => type == ColorNodeType.serial || type == ColorNodeType.parallel;

  ColorNode copyWith({
    ColorNodeType? type,
    String? name,
    Offset? position,
    bool? enabled,
    ClipColorAdjustments? grade,
    HslQualifierSettings? qualifier,
    ColorCurveSettings? curves,
  }) => ColorNode(
    id: id,
    type: type ?? this.type,
    name: name ?? this.name,
    position: position ?? this.position,
    enabled: enabled ?? this.enabled,
    grade: grade ?? this.grade,
    qualifier: qualifier ?? this.qualifier,
    curves: curves ?? this.curves,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'type': type.name, 'name': name, 'x': position.dx, 'y': position.dy,
    'enabled': enabled,
    'grade': {
      'exposure': grade.exposure, 'contrast': grade.contrast, 'saturation': grade.saturation,
      'temperature': grade.temperature, 'tint': grade.tint, 'highlights': grade.highlights, 'shadows': grade.shadows,
    },
    'qualifier': qualifier.toJson(),
    'curves': curves.toJson(),
  };

  factory ColorNode.fromJson(Map<String, dynamic> json) {
    final grade = Map<String, dynamic>.from((json['grade'] as Map?) ?? const {});
    return ColorNode(
      id: json['id'] as String,
      type: ColorNodeType.values.byName(json['type'] as String),
      name: json['name'] as String? ?? 'Node',
      position: Offset((json['x'] as num?)?.toDouble() ?? 0, (json['y'] as num?)?.toDouble() ?? 0),
      enabled: json['enabled'] as bool? ?? true,
      grade: ClipColorAdjustments(
        exposure: (grade['exposure'] as num?)?.toDouble() ?? 0,
        contrast: (grade['contrast'] as num?)?.toDouble() ?? 0,
        saturation: (grade['saturation'] as num?)?.toDouble() ?? 0,
        temperature: (grade['temperature'] as num?)?.toDouble() ?? 0,
        tint: (grade['tint'] as num?)?.toDouble() ?? 0,
        highlights: (grade['highlights'] as num?)?.toDouble() ?? 0,
        shadows: (grade['shadows'] as num?)?.toDouble() ?? 0,
      ),
      qualifier: HslQualifierSettings.fromJson(Map<String, dynamic>.from((json['qualifier'] as Map?) ?? const {})),
      curves: ColorCurveSettings.fromJson(Map<String, dynamic>.from((json['curves'] as Map?) ?? const {})),
    );
  }
}

class NodeConnection {
  const NodeConnection(this.from, this.to);
  final String from;
  final String to;
  Map<String, dynamic> toJson() => {'from': from, 'to': to};
  factory NodeConnection.fromJson(Map<String, dynamic> json) => NodeConnection(json['from'] as String, json['to'] as String);
}

class ColorNodeGraph {
  const ColorNodeGraph({required this.nodes, required this.connections, this.selectedNodeId, required this.defaultNodeId});
  final List<ColorNode> nodes;
  final List<NodeConnection> connections;
  final String? selectedNodeId;
  final String defaultNodeId;

  factory ColorNodeGraph.defaultGraph({ClipColorAdjustments initialGrade = const ClipColorAdjustments()}) => ColorNodeGraph(
    defaultNodeId: 'node-1', selectedNodeId: 'node-1',
    nodes: [
      const ColorNode(id: 'input', type: ColorNodeType.input, name: 'Input', position: Offset(20, 90)),
      ColorNode(id: 'node-1', type: ColorNodeType.serial, name: 'Node 01', position: const Offset(170, 90), grade: initialGrade),
      const ColorNode(id: 'output', type: ColorNodeType.output, name: 'Output', position: Offset(340, 90)),
    ],
    connections: const [NodeConnection('input', 'node-1'), NodeConnection('node-1', 'output')],
  );

  ColorNode? nodeById(String? id) => id == null ? null : nodes.where((n) => n.id == id).firstOrNull;
  ColorNode get defaultNode => nodeById(defaultNodeId)!;
  ColorNode? get selectedProcessingNode {
    final selected = nodeById(selectedNodeId);
    return selected != null && selected.supportsProcessing ? selected : null;
  }

  ColorNode get qualifierTarget => selectedProcessingNode ?? defaultNode;

  ClipColorAdjustments get combinedGrade {
    final active = nodes.where((node) => node.supportsProcessing && node.enabled);
    double exposure = 0;
    double contrast = 0;
    double saturation = 0;
    double temperature = 0;
    double tint = 0;
    double highlights = 0;
    double shadows = 0;
    for (final node in active) {
      exposure += node.grade.exposure;
      contrast += node.grade.contrast;
      saturation += node.grade.saturation;
      temperature += node.grade.temperature;
      tint += node.grade.tint;
      highlights += node.grade.highlights;
      shadows += node.grade.shadows;
    }
    return ClipColorAdjustments(
      exposure: exposure.clamp(-1.0, 1.0).toDouble(),
      contrast: contrast.clamp(-1.0, 1.0).toDouble(),
      saturation: saturation.clamp(-1.0, 1.0).toDouble(),
      temperature: temperature.clamp(-1.0, 1.0).toDouble(),
      tint: tint.clamp(-1.0, 1.0).toDouble(),
      highlights: highlights.clamp(-1.0, 1.0).toDouble(),
      shadows: shadows.clamp(-1.0, 1.0).toDouble(),
    );
  }

  ColorNodeGraph copyWith({List<ColorNode>? nodes, List<NodeConnection>? connections, String? selectedNodeId, bool clearSelection = false}) => ColorNodeGraph(
    nodes: nodes ?? this.nodes, connections: connections ?? this.connections,
    selectedNodeId: clearSelection ? null : selectedNodeId ?? this.selectedNodeId,
    defaultNodeId: defaultNodeId,
  );

  Map<String, dynamic> toJson() => {'nodes': nodes.map((n) => n.toJson()).toList(), 'connections': connections.map((c) => c.toJson()).toList(), 'selectedNodeId': selectedNodeId, 'defaultNodeId': defaultNodeId};
  factory ColorNodeGraph.fromJson(Map<String, dynamic> json) => ColorNodeGraph(
    nodes: ((json['nodes'] as List?) ?? const []).whereType<Map>().map((e) => ColorNode.fromJson(Map<String, dynamic>.from(e))).toList(),
    connections: ((json['connections'] as List?) ?? const []).whereType<Map>().map((e) => NodeConnection.fromJson(Map<String, dynamic>.from(e))).toList(),
    selectedNodeId: json['selectedNodeId'] as String?,
    defaultNodeId: json['defaultNodeId'] as String? ?? 'node-1',
  );
}
