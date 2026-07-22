import 'package:digitor/features/editor/application/color/color_node_controller.dart';
import 'package:digitor/features/editor/domain/models/clip_adjustments.dart';
import 'package:digitor/features/editor/domain/models/color/color_node_graph.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<ColorNodeGraph?> showColorNodeSheet(BuildContext context, ColorNodeGraph graph) {
  return showModalBottomSheet<ColorNodeGraph>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xff111318),
    builder: (_) => FractionallySizedBox(heightFactor: .9, child: ColorNodeSheet(graph: graph)),
  );
}

class ColorNodeSheet extends StatefulWidget {
  const ColorNodeSheet({super.key, required this.graph});
  final ColorNodeGraph graph;
  @override State<ColorNodeSheet> createState() => _ColorNodeSheetState();
}

class _ColorNodeSheetState extends State<ColorNodeSheet> {
  late final ColorNodeController controller;
  @override void initState() { super.initState(); controller = ColorNodeController(widget.graph); }
  @override void dispose() { controller.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, __) {
      final target = controller.graph.qualifierTarget;
      return SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(12,8,8,6), child: Row(children:[
          const Expanded(child: Text('Color Nodes', style: TextStyle(color: Colors.white,fontSize:18,fontWeight:FontWeight.w700))),
          Text('HSL → ${target.name}', style: const TextStyle(color: Colors.white60,fontSize:12)),
          IconButton(onPressed:()=>Navigator.pop(context, controller.graph), icon: const Icon(Icons.check,color:Colors.white)),
        ])),
        const Divider(height:1,color:Colors.white12),
        Expanded(flex: 5, child: _GraphCanvas(controller: controller)),
        const Divider(height:1,color:Colors.white12),
        Expanded(flex: 4, child: _Controls(controller: controller)),
      ]));
    },
  );
}

class _GraphCanvas extends StatelessWidget {
  const _GraphCanvas({required this.controller}); final ColorNodeController controller;
  @override Widget build(BuildContext context) => InteractiveViewer(
    minScale:.5,maxScale:2.2,boundaryMargin:const EdgeInsets.all(400),
    child:SizedBox(width:760,height:300,child:Stack(children:[
      CustomPaint(size: const Size(760,300), painter:_ConnectionPainter(controller.graph)),
      ...controller.graph.nodes.map((node)=>Positioned(left:node.position.dx,top:node.position.dy,child:_NodeCard(node:node,controller:controller))),
    ])),
  );
}

class _NodeCard extends StatelessWidget {
  const _NodeCard({required this.node,required this.controller}); final ColorNode node; final ColorNodeController controller;
  @override Widget build(BuildContext context) {
    final selected=controller.graph.selectedNodeId==node.id;
    return GestureDetector(
      onTap:()=>controller.select(node.id),
      onLongPress: node.type==ColorNodeType.output ? null : () async {
        HapticFeedback.mediumImpact();
        final action=await showMenu<String>(context:context,position:const RelativeRect.fromLTRB(120,250,40,0),items:[
          if(node.type!=ColorNodeType.output) const PopupMenuItem(value:'serial',child:Text('Add Serial Node')),
          if(node.supportsProcessing) const PopupMenuItem(value:'parallel',child:Text('Add Parallel Node')),
        ]);
        if(action=='serial') controller.addSerialAfter(node.id);
        if(action=='parallel') controller.addParallelFrom(node.id);
      },
      child:Container(width:118,height:72,padding:const EdgeInsets.all(8),decoration:BoxDecoration(
        color:selected?const Color(0xff315f8f):const Color(0xff252a32),borderRadius:BorderRadius.circular(10),
        border:Border.all(color:selected?Colors.lightBlueAccent:Colors.white24,width:selected?2:1)),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[Expanded(child:Text(node.name,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w600,fontSize:12))),
          if(node.supportsProcessing) GestureDetector(onTap:()=>controller.toggle(node.id),child:Icon(node.enabled?Icons.visibility:Icons.visibility_off,size:15,color:Colors.white70))]),
          const Spacer(),Text(node.type.name,style:const TextStyle(color:Colors.white54,fontSize:10)),
          if(node.qualifier.enabled) const Text('HSL',style:TextStyle(color:Colors.amber,fontSize:10,fontWeight:FontWeight.bold)),
        ]),
      ),
    );
  }
}

class _ConnectionPainter extends CustomPainter {
  _ConnectionPainter(this.graph); final ColorNodeGraph graph;
  @override void paint(Canvas canvas,Size size){
    final p=Paint()..color=Colors.white38..strokeWidth=2..style=PaintingStyle.stroke;
    for(final c in graph.connections){final a=graph.nodeById(c.from),b=graph.nodeById(c.to);if(a==null||b==null)continue;
      final s=a.position+const Offset(118,36),e=b.position+const Offset(0,36),path=Path()..moveTo(s.dx,s.dy)..cubicTo((s.dx+e.dx)/2,s.dy,(s.dx+e.dx)/2,e.dy,e.dx,e.dy);canvas.drawPath(path,p);}
  }
  @override bool shouldRepaint(covariant _ConnectionPainter old)=>old.graph!=graph;
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller}); final ColorNodeController controller;
  @override Widget build(BuildContext context){final node=controller.graph.qualifierTarget,q=node.qualifier,g=node.grade;
    return ListView(padding:const EdgeInsets.all(12),children:[
      Row(children:[const Text('Selected node grading',style:TextStyle(color:Colors.white,fontWeight:FontWeight.w700)),const Spacer(),Text(node.name,style:const TextStyle(color:Colors.lightBlueAccent))]),
      _slider('Exposure',g.exposure,-1,1,(v)=>controller.updateGrade(node.id,g.copyWith(exposure:v))),
      _slider('Contrast',g.contrast,-1,1,(v)=>controller.updateGrade(node.id,g.copyWith(contrast:v))),
      _slider('Saturation',g.saturation,-1,1,(v)=>controller.updateGrade(node.id,g.copyWith(saturation:v))),
      SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('HSL Qualifier',style:TextStyle(color:Colors.white)),subtitle:Text('Applied to ${node.name}',style:const TextStyle(color:Colors.white54)),value:q.enabled,onChanged:(v)=>controller.updateQualifier(q.copyWith(enabled:v))),
      _slider('Hue',q.hueCenter,0,1,(v)=>controller.updateQualifier(q.copyWith(hueCenter:v,enabled:true))),
      _slider('Hue width',q.hueWidth,0,1,(v)=>controller.updateQualifier(q.copyWith(hueWidth:v,enabled:true))),
      _slider('Saturation low',q.saturationLow,0,1,(v)=>controller.updateQualifier(q.copyWith(saturationLow:v,enabled:true))),
      _slider('Saturation high',q.saturationHigh,0,1,(v)=>controller.updateQualifier(q.copyWith(saturationHigh:v,enabled:true))),
      _slider('Luminance low',q.luminanceLow,0,1,(v)=>controller.updateQualifier(q.copyWith(luminanceLow:v,enabled:true))),
      _slider('Luminance high',q.luminanceHigh,0,1,(v)=>controller.updateQualifier(q.copyWith(luminanceHigh:v,enabled:true))),
      _slider('Softness',q.softness,0,1,(v)=>controller.updateQualifier(q.copyWith(softness:v,enabled:true))),
    ]);
  }
  Widget _slider(String label,double value,double min,double max,ValueChanged<double> change)=>Row(children:[SizedBox(width:112,child:Text(label,style:const TextStyle(color:Colors.white70,fontSize:12))),Expanded(child:Slider(value:value.clamp(min,max),min:min,max:max,onChanged:change)),SizedBox(width:42,child:Text(value.toStringAsFixed(2),style:const TextStyle(color:Colors.white54,fontSize:11))) ]);
}
