import 'package:flutter/material.dart';

import '../data/store.dart';

/// 类别输入框 + 已有类别快捷选择（点击 chip 即填入）。
class CategoryField extends StatelessWidget {
  final TextEditingController controller;
  final List<String> categories;
  final String label;
  final String? helper;
  const CategoryField({
    super.key,
    required this.controller,
    required this.categories,
    this.label = '类别',
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper ?? '任务的第一个 +标签，例如 408、数学；留空 = 未分类',
          border: const OutlineInputBorder(),
          prefixText: '+',
        ),
      ),
      if (categories.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, v, _) => Wrap(spacing: 6, runSpacing: 0, children: [
              for (final c in categories)
                ChoiceChip(
                  label: Text(c),
                  selected: v.text.trim() == c,
                  onSelected: (_) => controller.text = c,
                ),
            ]),
          ),
        ),
    ]);
  }
}

class ImportChoice {
  final bool replace;
  final String? category;
  final bool keepOtherTags;
  ImportChoice(this.replace, this.category, this.keepOtherTags);
}

/// 导入确认对话框：设置类别、选择追加 / 覆盖。
Future<ImportChoice?> showImportDialog(BuildContext context, TodoStore store, ImportPreview p) {
  final cat = TextEditingController(text: p.defaultCategory ?? store.primaryCategory ?? '');
  var keep = true;
  return showDialog<ImportChoice>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('导入任务'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p.fromIcs ? '识别为日历（.ics），已按学习条目拆分。\n' : ''}'
                '识别到 ${p.todo.length} 条待办、${p.done.length} 条已完成。'),
            const SizedBox(height: 12),
            CategoryField(
              controller: cat,
              categories: {...store.categories, if (p.defaultCategory != null) p.defaultCategory!}.toList()..sort(),
              label: '导入后的类别',
              helper: '类别会成为每条任务的第一个 +标签；同一类别的任务会一起提前 / 顺延。',
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              value: keep,
              onChanged: (v) => setState(() => keep = v ?? true),
              title: const Text('保留任务原有的其它 +标签'),
              subtitle: const Text('取消勾选则清除原有 +标签，只保留上面的类别'),
            ),
            const Text('「追加」保留现有任务（完全相同的任务自动跳过）；「覆盖」会先清空现有待办和已完成。',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ImportChoice(true, cat.text, keep)), child: const Text('覆盖')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ImportChoice(false, cat.text, keep)), child: const Text('追加')),
        ],
      ),
    ),
  );
}

/// 选择类别的对话框（批量更改类别、重命名）。返回 null 表示取消；空字符串表示“未分类”。
Future<String?> showCategoryDialog(BuildContext context, TodoStore store,
    {required String title, String initial = '', String? helper}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
          child: CategoryField(controller: c, categories: store.categories, helper: helper)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('确定')),
      ],
    ),
  );
}
