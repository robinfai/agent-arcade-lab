import 'dart:convert';
import 'dart:io';
import 'package:agent_arcade_lab/snake_game.dart';
import 'package:agent_arcade_lab/jev_client.dart';
Future<void> main() async {
 final g=SnakeArena(20260921,names:const ['Laya']);
 final api=JevClient('http://127.0.0.1:8769',endpoint:'/v1/snake-decision');
 final rows=<Map<String,dynamic>>[];
 try {
  for(var i=0;i<12&&!g.over;i++) {
   final req=g.request(0),r=await api.decide(g.request(0));
   rows.add({'frame':g.frame,'body':g.snakes[0].body.toString(),'heading':g.snakes[0].direction,'food':g.food.toString(),'request':req,'response':r});
   if(r['error']!=null) {break;}
   g.advance([r['choice'] as String]);
  }
 }finally{api.close();}
 File('reports/snake-multilingual/solo-loop-probe.json').writeAsStringSync(jsonEncode(rows));
 for(final r in rows){stdout.writeln(jsonEncode({'frame':r['frame'],'body':r['body'],'heading':r['heading'],'food':r['food'],'choice':r['response']['choice'],'criteria':r['request']['questions']['move']['criteria']}));}
}
