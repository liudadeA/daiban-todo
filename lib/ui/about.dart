import 'package:flutter/material.dart';

const aboutText = '''代办 是一款兼容 topydo / todo.txt 格式的安卓待办清单，思路与任务语义参考自 topydo 项目。

topydo — Copyright (C) 2014-2015 Bram Schoenmakers 及贡献者
https://github.com/topydo/topydo
topydo 以 GNU GPL-3.0 许可发布。本应用借鉴其 todo.txt 格式与排序/到期日语义，并以同样的 GNU GPL-3.0 许可发布（详见 LICENSE）。

本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证（第 3 版，或你选择的更新版本）重新分发和/或修改它。本程序的发布是希望它有用，但没有任何担保；甚至没有适销性或特定用途适用性的默示担保。详见 GNU GPL。
https://www.gnu.org/licenses/gpl-3.0.html

todo.txt 格式：
  (A) 任务描述 +项目 @情境 due:2026-11-11 t:2026-11-10
  x 2026-11-11 已完成的任务
''';

void showAbout(BuildContext context) {
  showDialog(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('关于 代办'),
      content: const SingleChildScrollView(child: Text(aboutText)),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('关闭'))],
    ),
  );
}
