// 用法：dart run tool/ics_to_todo.dart 输入.ics 输出.txt
// 与 App 内“导入 .ics”使用同一套解析 / 拆分逻辑。
import 'dart:convert';
import 'dart:io';

import 'package:daiban/logic/ics.dart';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('用法: dart run tool/ics_to_todo.dart in.ics out.txt');
    exit(64);
  }
  final text = utf8.decode(File(args[0]).readAsBytesSync(), allowMalformed: true);
  final lines = Ics.toTodoLines(text);
  File(args[1]).writeAsStringSync('${lines.join('\n')}\n', encoding: utf8);
  stdout.writeln('wrote ${lines.length} tasks to ${args[1]}');
}
