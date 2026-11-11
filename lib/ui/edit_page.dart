import 'package:flutter/material.dart';

import 'category_widgets.dart';

import '../data/store.dart';
import '../logic/dates.dart';
import '../logic/todo_item.dart';

/// 新增 / 编辑任务页面。[item] 为空表示新增。
class EditPage extends StatefulWidget {
  final TodoStore store;
  final TodoItem? item;
  final DateTime? defaultDue;
  const EditPage({super.key, required this.store, this.item, this.defaultDue});

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  late final TextEditingController _text;
  late final TextEditingController _cat;
  String? _priority;
  DateTime? _due, _start;

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    _text = TextEditingController(text: it?.editableTextNoCategory ?? '');
    _cat = TextEditingController(text: it != null ? (it.category ?? '') : (widget.store.primaryCategory ?? ''));
    _priority = it?.priority;
    _due = it != null ? it.due : widget.defaultDue;
    _start = it?.start;
  }

  @override
  void dispose() {
    _text.dispose();
    _cat.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? initial) {
    final today = widget.store.today;
    return showDatePicker(
      context: context,
      initialDate: initial ?? today,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选择日期',
      cancelText: '取消',
      confirmText: '确定',
    ).then((v) => v == null ? null : Ymd.fromDateTime(v));
  }

  Future<void> _save() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入任务内容')));
      return;
    }
    if (widget.item == null) {
      await widget.store.add(text, priority: _priority, due: _due, start: _start, category: _cat.text);
    } else {
      await widget.store.update(widget.item!, text, priority: _priority, due: _due, start: _start, category: _cat.text);
    }
    if (mounted) Navigator.pop(context, true);
  }

  Widget _dateRow(String label, DateTime? v, ValueChanged<DateTime?> onChanged, String hint) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event),
      title: Text(label),
      subtitle: Text(v == null ? hint : '${Ymd.fmt(v)}  ${Ymd.weekday(v)}'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (v != null)
          IconButton(icon: const Icon(Icons.clear), tooltip: '清除', onPressed: () => onChanged(null)),
        TextButton(
            onPressed: () async {
              final d = await _pick(v);
              if (d != null) onChanged(d);
            },
            child: const Text('选择')),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.item != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? '编辑任务' : '新建任务'),
        actions: [
          if (editing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('删除任务？'),
                    content: Text(widget.item!.text),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
                    ],
                  ),
                );
                if (ok == true) {
                  await widget.store.delete(widget.item!);
                  if (context.mounted) Navigator.pop(context, true);
                }
              },
            ),
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _text,
            autofocus: !editing,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: '任务内容',
              helperText: '可直接写 +项目 @情境，例如：做数学试卷 @家里',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          CategoryField(controller: _cat, categories: widget.store.categories),
          const SizedBox(height: 16),
          Row(children: [
            const Icon(Icons.flag_outlined),
            const SizedBox(width: 16),
            const Text('优先级'),
            const Spacer(),
            DropdownButton<String?>(
              value: _priority,
              items: [
                const DropdownMenuItem(value: null, child: Text('无')),
                for (final p in ['A', 'B', 'C', 'D', 'E'])
                  DropdownMenuItem(value: p, child: Text('($p)')),
                if (_priority != null && !'ABCDE'.contains(_priority!))
                  DropdownMenuItem(value: _priority, child: Text('($_priority)')),
              ],
              onChanged: (v) => setState(() => _priority = v),
            ),
          ]),
          _dateRow('截止日期 due:', _due, (v) => setState(() => _due = v), '未设置（无日期任务）'),
          _dateRow('开始日期 t:', _start, (v) => setState(() => _start = v), '未设置（立即可见）'),
          const SizedBox(height: 8),
          const Text('提示：未到开始日期的任务不会出现在「今日」里。',
              style: TextStyle(color: Colors.black54, fontSize: 12)),
        ],
      ),
    );
  }
}
