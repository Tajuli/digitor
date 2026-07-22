import 'dart:math' as math;
import 'package:digitor/features/editor/domain/models/clip_adjustments.dart';
import 'package:digitor/features/editor/domain/models/color/color_node_graph.dart';
import 'package:flutter/material.dart';

enum ColorPanelType { wheels, curves, qualifier }

class ColorGradingSheet extends StatefulWidget {
  const ColorGradingSheet({super.key, required this.graph, required this.type, required this.onDone});
  final ColorNodeGraph graph;
  final ColorPanelType type;
  final ValueChanged<ColorNodeGraph> onDone;
  @override State<ColorGradingSheet> createState() => _ColorGradingSheetState();
}

class _ColorGradingSheetState extends State<ColorGradingSheet> {
  late ColorNodeGraph graph;
  late ColorNode node;
  @override void initState(){super.initState(); graph=widget.graph; node=graph.selectedProcessingNode ?? graph.defaultNode;}
  void _replace(ColorNode next){setState((){node=next; graph=graph.copyWith(nodes: graph.nodes.map((n)=>n.id==next.id?next:n).toList());});}
  @override Widget build(BuildContext context){
    return Material(color: const Color(0xff202126), child: SafeArea(top:false, child: Column(children:[
      SizedBox(height:46, child: Row(children:[
        IconButton(onPressed:()=>widget.onDone(graph), icon:const Icon(Icons.keyboard_arrow_down,color:Colors.white)),
        Text(_title, style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w600)),
        const Spacer(), Text(node.name,style:const TextStyle(color:Colors.white54,fontSize:12)), const SizedBox(width:14),
        IconButton(onPressed:_reset,icon:const Icon(Icons.restart_alt,color:Colors.white70)),
      ])), const Divider(height:1,color:Colors.white12),
      Expanded(child: widget.type==ColorPanelType.wheels?_wheels():widget.type==ColorPanelType.curves?_curves():_qualifier()),
    ])));
  }
  String get _title=>switch(widget.type){ColorPanelType.wheels=>'Color Wheels',ColorPanelType.curves=>'Curves',ColorPanelType.qualifier=>'Qualifier · HSL'};
  void _reset(){
    if(widget.type==ColorPanelType.qualifier){_replace(node.copyWith(qualifier:const HslQualifierSettings()));}
    else if(widget.type==ColorPanelType.curves){_replace(node.copyWith(curves:const ColorCurveSettings()));}
    else {_replace(node.copyWith(grade:const ClipColorAdjustments()));}
  }

  Widget _wheels(){ final g=node.grade; return ListView(padding:const EdgeInsets.all(12),children:[
    Wrap(spacing:12,runSpacing:12,children:[
      _wheel('Lift',g.shadows,(v)=>_grade(g.copyWith(shadows:v))),
      _wheel('Gamma',g.exposure,(v)=>_grade(g.copyWith(exposure:v))),
      _wheel('Gain',g.highlights,(v)=>_grade(g.copyWith(highlights:v))),
      _wheel('Offset',g.temperature,(v)=>_grade(g.copyWith(temperature:v))),
    ]), const SizedBox(height:14),
    _wide('Contrast',g.contrast,-1,1,(v)=>_grade(g.copyWith(contrast:v))),
    _wide('Saturation',g.saturation,-1,1,(v)=>_grade(g.copyWith(saturation:v))),
    _wide('Tint',g.tint,-1,1,(v)=>_grade(g.copyWith(tint:v))),
  ]);}
  void _grade(ClipColorAdjustments g)=>_replace(node.copyWith(grade:g));
  Widget _wheel(String label,double value,ValueChanged<double> onChanged){return SizedBox(width:150,child:Column(children:[Text(label,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w600)),const SizedBox(height:8),
    GestureDetector(onPanUpdate:(d)=>onChanged((value-d.delta.dy/100).clamp(-1.0,1.0)),child:CustomPaint(size:const Size(104,104),painter:_WheelPainter(value))),
    Slider(value:value,min:-1,max:1,onChanged:onChanged),Text(value.toStringAsFixed(2),style:const TextStyle(color:Colors.white70,fontSize:12))]));}
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

  Widget _qualifier(){final q=node.qualifier; return ListView(padding:const EdgeInsets.all(12),children:[
    SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Enable HSL Qualifier',style:TextStyle(color:Colors.white)),value:q.enabled,onChanged:(v)=>_qual(q.copyWith(enabled:v))),
    _gradientRange('Hue',q.hueCenter-q.hueWidth/2,q.hueCenter+q.hueWidth/2,(r)=>_qual(q.copyWith(hueCenter:(r.start+r.end)/2,hueWidth:r.end-r.start)),const [Colors.purple,Colors.red,Colors.yellow,Colors.green,Colors.cyan,Colors.blue,Colors.purple]),
    _gradientRange('Saturation',q.saturationLow,q.saturationHigh,(r)=>_qual(q.copyWith(saturationLow:r.start,saturationHigh:r.end)),const [Colors.grey,Colors.green]),
    _gradientRange('Luminance',q.luminanceLow,q.luminanceHigh,(r)=>_qual(q.copyWith(luminanceLow:r.start,luminanceHigh:r.end)),const [Colors.black,Colors.white]),
    const SizedBox(height:10),const Text('Matte Finesse',style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w600)),
    _qSlider('Softness',q.softness,(v)=>_qual(q.copyWith(softness:v))),_qSlider('Denoise',q.denoise,(v)=>_qual(q.copyWith(denoise:v))),_qSlider('Blur Radius',q.blur,(v)=>_qual(q.copyWith(blur:v))),
    SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Invert Matte',style:TextStyle(color:Colors.white70)),value:q.inverted,onChanged:(v)=>_qual(q.copyWith(inverted:v))),
  ]);}
  void _qual(HslQualifierSettings q)=>_replace(node.copyWith(qualifier:q));
  Widget _gradientRange(String title,double lo,double hi,ValueChanged<RangeValues> f,List<Color> colors)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(color:Colors.white70)),Container(height:16,margin:const EdgeInsets.only(top:6),decoration:BoxDecoration(borderRadius:BorderRadius.circular(8),gradient:LinearGradient(colors:colors))),RangeSlider(values:RangeValues(lo.clamp(0,1).toDouble(),hi.clamp(0,1).toDouble()),onChanged:f),Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text((lo*100).toStringAsFixed(0),style:const TextStyle(color:Colors.white54)),Text((hi*100).toStringAsFixed(0),style:const TextStyle(color:Colors.white54))]),const SizedBox(height:8)]);
  Widget _qSlider(String t,double v,ValueChanged<double> f)=>_wide(t,v,0,1,f);
}

class _WheelPainter extends CustomPainter{_WheelPainter(this.value);final double value;@override void paint(Canvas c,Size s){final center=s.center(Offset.zero),r=s.shortestSide/2;final p=Paint()..shader=SweepGradient(colors:const [Colors.red,Colors.yellow,Colors.green,Colors.cyan,Colors.blue,Colors.magenta,Colors.red]).createShader(Rect.fromCircle(center:center,radius:r));c.drawCircle(center,r,p);c.drawCircle(center,r,Paint()..shader=RadialGradient(colors:[Colors.white.withOpacity(.9),Colors.transparent]).createShader(Rect.fromCircle(center:center,radius:r)));final a=-math.pi/2+value*math.pi;final dot=center+Offset(math.cos(a),math.sin(a))*r*.55;c.drawCircle(dot,6,Paint()..color=Colors.black);c.drawCircle(dot,4,Paint()..color=Colors.white);}@override bool shouldRepaint(covariant _WheelPainter old)=>old.value!=value;}

class _CurveEditor extends StatelessWidget{const _CurveEditor({required this.settings,required this.onChanged});final ColorCurveSettings settings;final ValueChanged<ColorCurveSettings> onChanged;@override Widget build(BuildContext context){return LayoutBuilder(builder:(context,b){final pts=settings.pointsFor(settings.channel);return GestureDetector(onDoubleTapDown:(d){final p=Offset((d.localPosition.dx/b.maxWidth).clamp(0,1).toDouble(),1-(d.localPosition.dy/b.maxHeight).clamp(0,1).toDouble());final n=[...pts,p]..sort((a,b)=>a.dx.compareTo(b.dx));onChanged(settings.withPoints(settings.channel,n));},onPanUpdate:(d){if(pts.length<=2)return;final pos=Offset((d.localPosition.dx/b.maxWidth).clamp(0,1).toDouble(),1-(d.localPosition.dy/b.maxHeight).clamp(0,1).toDouble());var nearest=1;var dist=double.infinity;for(var i=1;i<pts.length-1;i++){final dd=(pts[i]-pos).distance;if(dd<dist){dist=dd;nearest=i;}}final n=[...pts];n[nearest]=Offset(pos.dx.clamp(n[nearest-1].dx+.01,n[nearest+1].dx-.01).toDouble(),pos.dy);onChanged(settings.withPoints(settings.channel,n));},child:CustomPaint(size:Size.infinite,painter:_CurvePainter(pts,settings.channel)));});}}
class _CurvePainter extends CustomPainter{_CurvePainter(this.points,this.channel);final List<Offset> points;final CurveChannel channel;@override void paint(Canvas c,Size s){c.drawRect(Offset.zero&s,Paint()..color=const Color(0xff17181c));final grid=Paint()..color=Colors.white10..strokeWidth=1;for(int i=1;i<8;i++){c.drawLine(Offset(s.width*i/8,0),Offset(s.width*i/8,s.height),grid);c.drawLine(Offset(0,s.height*i/8),Offset(s.width,s.height*i/8),grid);}final path=Path();for(int i=0;i<points.length;i++){final p=Offset(points[i].dx*s.width,(1-points[i].dy)*s.height);if(i==0)path.moveTo(p.dx,p.dy);else path.lineTo(p.dx,p.dy);}final color=switch(channel){CurveChannel.y=>Colors.white,CurveChannel.r=>Colors.redAccent,CurveChannel.g=>Colors.greenAccent,CurveChannel.b=>Colors.blueAccent};c.drawPath(path,Paint()..color=color..strokeWidth=2..style=PaintingStyle.stroke);for(final v in points){final p=Offset(v.dx*s.width,(1-v.dy)*s.height);c.drawCircle(p,5,Paint()..color=const Color(0xff17181c));c.drawCircle(p,3,Paint()..color=color);}}@override bool shouldRepaint(covariant _CurvePainter old)=>old.points!=points||old.channel!=channel;}
