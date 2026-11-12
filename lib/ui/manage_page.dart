import 'package:flutter/material.dart';

import '../data/focus_store.dart';
import '../data/store.dart';
import '../logic/estimator.dart';
import 'category_widgets.dart';
import 'timer_page.dart';

/// 批量管理：删除全部、清空已完成、按类别删除 / 重命名。
class ManagePage extends StatelessWidget {
  final TodoStore store;
  final FocusStore? focus;
  const ManagePage({super.key, required this.store, this.focus});

  Future<bool> _confirm(BuildContext context, String title, String body) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('确认删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    return r == true;
  }

  void _toast(BuildContext context, String msg) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(label: '撤销', onPressed: () => store.undo())));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store, if (focus != null) focus!]),
      builder: (context, _) {
        final cats = <String?>[...store.categories, if (store.hasUncategorized) null];
        int todoN(String? c) => store.todo.where((t) => t.category == c).length;
        int doneN(String? c) => store.done.where((t) => t.category == c).length;
        return Scaffold(
          appBar: AppBar(title: const Text('批量管理')),
          body: ListView(children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('提示：在任务列表里长按任务可进入多选，支持批量完成 / 删除 / 更改类别 / 平移日期。',
                  style: TextStyle(color: Colors.black54)),
            ),
            const _Section('全部'),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('删除全部任务', style: TextStyle(color: Colors.red)),
              subtitle: Text('待办 ${store.todo.length} 项 + 已完成 ${store.done.length} 项'),
              enabled: store.todo.isNotEmpty || store.done.isNotEmpty,
              onTap: () async {
                if (await _confirm(context, '删除全部任务？',
                    '将删除全部 ${store.todo.length} 项待办和 ${store.done.length} 项已完成，此操作可立即撤销。')) {
                  await store.deleteAll();
                  if (context.mounted) _toast(context, '已删除全部任务');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('清空已完成'),
              subtitle: Text('${store.done.length} 项'),
              enabled: store.done.isNotEmpty,
              onTap: () async {
                if (await _confirm(context, '清空已完成？', '将删除 done.txt 中的全部 ${store.done.length} 条记录。')) {
                  await store.clearDone();
                  if (context.mounted) _toast(context, '已清空已完成');
                }
              },
            ),
            const _Section('按类别'),
            if (cats.isEmpty) const ListTile(title: Text('还没有任务')),
            for (final c in cats)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(store.categoryLabel(c)),
                isThreeLine: true,
                subtitle: Text(Estimator.detail(Estimator.forCategory(store.todo, store.done, store.today, c), store.today).join('\n')),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (focus != null)
                    TextButton(
                      key: Key('manage_timer_${c ?? ''}'),
                      onPressed: () async {
                        final f = focus!;
                        if (f.isRunning && f.runningCategory != c) {
                          _toast(context, '正在计时「${store.categoryLabel(f.runningCategory)}」，请先结束或退出');
                          return;
                        }
                        if (!f.isRunning) await f.start(c);
                        if (!context.mounted) return;
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => TimerPage(store: store, focus: f), fullscreenDialog: true));
                      },
                      child: Text(focus!.isRunning && focus!.runningCategory == c ? '继续' : '开始'),
                    ),
                  IconButton(
                    icon: const Icon(Icons.drive_file_rename_outline),
                    tooltip: '重命名 / 合并到其它类别',
                    onPressed: () async {
                      final to = await showCategoryDialog(context, store,
                          title: '重命名「${store.categoryLabel(c)}」',
                          initial: c ?? '',
                          helper: '填写已有类别名即合并到该类别');
                      if (to == null || to == (c ?? '')) return;
                      final n = await store.renameCategory(c, to);
                      if (context.mounted) _toast(context, '已更改 $n 项任务的类别');
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: '删除该类别的全部任务',
                    onPressed: () async {
                      if (await _confirm(context, '删除「${store.categoryLabel(c)}」的全部任务？',
                          '将删除该类别的 ${todoN(c)} 项待办和 ${doneN(c)} 项已完成，此操作可立即撤销。')) {
                        final n = await store.deleteCategory(c);
                        if (context.mounted) _toast(context, '已删除 $n 项任务');
                      }
                    },
                  ),
                ]),
              ),
          ]),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  final String text;
  const _Section(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text,
            style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
      );
}
