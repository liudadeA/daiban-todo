import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/store.dart';
import '../logic/dates.dart';
import '../logic/planner.dart';
import '../logic/todo_item.dart';
import 'about.dart';
import 'category_widgets.dart';
import 'edit_page.dart';
import 'manage_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  final TodoStore store;
  const HomePage({super.key, required this.store});

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  int _tab = 0;
  TodoStore get store => widget.store;

  // ---- 多选模式
  bool _selMode = false;
  final Set<int> _sel = {};

  void _exitSelection() => setState(() {
        _selMode = false;
        _sel.clear();
      });

  void _toggleSel(TodoItem t) => setState(() {
        _selMode = true;
        if (!_sel.remove(t.id)) _sel.add(t.id);
      });

  List<TodoItem> get _selected => [...store.todo, ...store.done].where((t) => _sel.contains(t.id)).toList();

  List<TodoItem> _tabItems() {
    final today = store.today;
    switch (_tab) {
      case 0:
        return store.todo.where((t) => Planner.inToday(t, today) || Planner.undatedVisible(t, today)).toList();
      case 1:
        return [...store.todo];
      default:
        return [...store.done];
    }
  }

  Future<bool> _confirm(String title, String body, {String ok = '删除'}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _batchDelete() async {
    final items = _selected;
    if (items.isEmpty) return;
    if (!await _confirm('删除 ${items.length} 项任务？', '可在提示条上点“撤销”恢复。')) return;
    await store.deleteMany(items);
    _exitSelection();
    _toast('已删除 ${items.length} 项', undo: true);
  }

  Future<void> _batchComplete() async {
    final items = _selected.where((t) => !t.done).toList();
    if (items.isEmpty) return;
    final msg = await store.completeMany(items);
    _exitSelection();
    _toast(msg ?? '已完成 ${items.length} 项，已归档', undo: true, seconds: 5);
  }

  Future<void> _batchReopen() async {
    final items = _selected.where((t) => t.done).toList();
    if (items.isEmpty) return;
    await store.reopenMany(items);
    _exitSelection();
    _toast('已恢复 ${items.length} 项到待办', undo: true);
  }

  Future<void> _batchCategory() async {
    final items = _selected;
    if (items.isEmpty) return;
    final c = await showCategoryDialog(context, store,
        title: '更改类别（${items.length} 项）', helper: '原来的第一个 +标签会被换成新类别；留空 = 改为未分类（清除全部 +标签）');
    if (c == null) return;
    await store.setCategoryMany(items, c);
    _exitSelection();
    _toast('已更改 ${items.length} 项的类别', undo: true);
  }

  Future<void> _batchShift() async {
    final items = _selected.where((t) => !t.done && t.date != null).toList();
    if (items.isEmpty) {
      _toast('所选任务没有日期，无法平移');
      return;
    }
    final c = TextEditingController(text: '1');
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('平移日期（${items.length} 项）'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            decoration: const InputDecoration(
                labelText: '天数', helperText: '正数 = 推迟，负数 = 提前；截止日期和开始日期一起移动', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, children: [
            for (final v in [-7, -1, 1, 7])
              ActionChip(label: Text(v > 0 ? '+$v' : '$v'), onPressed: () => c.text = '$v'),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text.trim())), child: const Text('确定')),
        ],
      ),
    );
    if (n == null || n == 0) return;
    final moved = await store.shiftMany(items, n);
    _exitSelection();
    _toast('已把 $moved 项任务${n > 0 ? '推迟' : '提前'} ${n.abs()} 天', undo: true);
  }

  void _toast(String msg, {bool undo = false, int seconds = 4}) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(
      content: Text(msg),
      duration: Duration(seconds: seconds),
      action: undo ? SnackBarAction(label: '撤销', onPressed: () => store.undo()) : null,
    ));
  }

  Future<void> _complete(TodoItem item) async {
    final msg = await store.complete(item);
    if (!mounted) return;
    if (msg != null) {
      _toast(msg, undo: true, seconds: 5);
    } else {
      _toast('已完成，已归档', undo: true, seconds: 3);
    }
  }

  Future<void> _edit([TodoItem? item]) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => EditPage(
                store: store, item: item, defaultDue: item == null ? store.today : null)));
  }

  // ------------------------------------------------------------ 导入 / 导出

  Future<void> _pickFile() async {
    try {
      final r = await FilePicker.pickFiles(type: FileType.any, withData: true);
      final f = r?.files.single;
      if (f == null) return;
      final bytes = f.bytes;
      if (bytes == null) {
        _toast('读取文件失败');
        return;
      }
      await importText(utf8.decode(bytes, allowMalformed: true));
    } catch (e) {
      _toast('导入失败：$e');
    }
  }

  Future<void> _pasteDialog() async {
    final c = TextEditingController();
    final clip = await Clipboard.getData('text/plain');
    if (clip?.text != null) c.text = clip!.text!;
    if (!mounted) return;
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('粘贴 todo.txt 文本'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: c,
            maxLines: 12,
            minLines: 6,
            decoration: const InputDecoration(
              hintText: '每行一条，例如：\n(A) 做数学试卷 due:2026-11-12 t:2026-11-12 +考研 @家里\nx 2026-11-10 背单词',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('下一步')),
        ],
      ),
    );
    if (text != null && text.trim().isNotEmpty) await importText(text);
  }

  /// 解析文本并让用户选择“追加 / 覆盖”。也被分享 / 打开文件的 intent 调用。
  Future<void> importText(String text) async {
    final p = store.preview(text);
    if (p.total == 0) {
      _toast('没有识别到任何任务');
      return;
    }
    final choice = await showImportDialog(context, store, p);
    if (choice == null) return;
    // 类别成为第一个 +标签（留空且保留旧标签 = 不改动）
    p.applyCategory(choice.category, keepOtherTags: choice.keepOtherTags);
    final skipped = await store.applyImport(p, replace: choice.replace);
    if (mounted) {
      _toast(skipped > 0 ? '已导入 ${p.total - skipped} 条，跳过重复 $skipped 条' : '已导入 ${p.total} 条', undo: true);
    }
  }

  Future<void> _export() async {
    final which = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('导出为 todo.txt')),
          ListTile(
              leading: const Icon(Icons.checklist),
              title: const Text('待办（todo.txt）'),
              onTap: () => Navigator.pop(ctx, 'todo')),
          ListTile(
              leading: const Icon(Icons.done_all),
              title: const Text('已完成（done.txt）'),
              onTap: () => Navigator.pop(ctx, 'done')),
          ListTile(
              leading: const Icon(Icons.all_inbox),
              title: const Text('全部（待办 + 已完成）'),
              onTap: () => Navigator.pop(ctx, 'all')),
          ListTile(
              leading: const Icon(Icons.event),
              title: const Text('日历文件（.ics，仅有日期的待办）'),
              onTap: () => Navigator.pop(ctx, 'ics')),
        ]),
      ),
    );
    if (which == null || !mounted) return;
    final text = which == 'todo'
        ? store.exportTodo()
        : which == 'done'
            ? store.exportDone()
            : which == 'ics'
                ? store.exportIcs()
                : store.exportAll();
    final name = which == 'done' ? 'done.txt' : (which == 'ics' ? 'daiban.ics' : 'todo.txt');
    final how = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出方式'),
        content: Text(which == 'ics'
            ? '共 ${RegExp('BEGIN:VEVENT').allMatches(text).length} 个日历事件'
            : '共 ${text.isEmpty ? 0 : text.trim().split('\n').length} 行'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'copy'), child: const Text('复制到剪贴板')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('保存为文件')),
        ],
      ),
    );
    if (how == 'copy') {
      await Clipboard.setData(ClipboardData(text: text));
      _toast('已复制到剪贴板');
    } else if (how == 'save') {
      try {
        final path = await FilePicker.saveFile(
          dialogTitle: '保存 $name',
          fileName: name,
          bytes: Uint8List.fromList(utf8.encode(text)),
        );
        if (path != null) _toast('已保存');
      } catch (e) {
        _toast('保存失败：$e');
      }
    }
  }

  // ------------------------------------------------------------ 列表构建

  static int _cmp(TodoItem a, TodoItem b) {
    final da = a.date, db = b.date;
    if (da != null && db != null && da != db) return da.compareTo(db);
    final pa = a.priority ?? '[', pb = b.priority ?? '[';
    return pa.compareTo(pb);
  }

  String _dateLabel(DateTime d) {
    final diff = Ymd.diff(d, store.today);
    final base = '${d.month}月${d.day}日 ${Ymd.weekday(d)}';
    if (diff == 0) return '今天 · $base';
    if (diff == 1) return '明天 · $base';
    if (diff == 2) return '后天 · $base';
    if (diff < 0) return '逾期 $base（${-diff}天前）';
    return base;
  }

  Widget _header(String text, {Color? color}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text,
            style: TextStyle(fontWeight: FontWeight.bold, color: color ?? Theme.of(context).colorScheme.primary)),
      );

  Widget _tile(TodoItem t, {bool doneTile = false}) {
    final today = store.today;
    final d = t.date;
    final overdue = !doneTile && d != null && d.isBefore(today);
    final chips = <Widget>[];
    Widget chip(String s, {Color? c}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
              color: (c ?? Colors.blueGrey).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
          child: Text(s, style: TextStyle(fontSize: 12, color: c ?? Colors.blueGrey.shade700)),
        );
    if (t.due != null) chips.add(chip('截止 ${Ymd.fmt(t.due!)}', c: overdue ? Colors.red : null));
    if (t.start != null) chips.add(chip('开始 ${Ymd.fmt(t.start!)}', c: Colors.teal));
    if (doneTile && t.completionDate != null) {
      chips.add(chip('完成于 ${Ymd.fmt(t.completionDate!)}', c: Colors.green));
    }
    for (final p in t.projects) {
      chips.add(chip('+$p', c: Colors.indigo));
    }
    for (final c in t.contexts) {
      chips.add(chip('@$c', c: Colors.orange.shade800));
    }
    String? pri = t.priority;
    if (doneTile) {
      final tag = t.tokens.where((e) => RegExp(r'^pri:[A-Z]$').hasMatch(e));
      pri = tag.isEmpty ? null : tag.first.substring(4);
    }
    final selected = _sel.contains(t.id);
    final tileCore = ListTile(
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
      leading: _selMode
          ? Checkbox(value: selected, onChanged: (_) => _toggleSel(t))
          : Checkbox(
              value: doneTile,
              onChanged: (_) => doneTile ? store.reopen(t) : _complete(t),
            ),
      title: Text.rich(TextSpan(children: [
        if (pri != null)
          TextSpan(
              text: '($pri) ',
              style: TextStyle(color: pri == 'A' ? Colors.red : Colors.deepOrange, fontWeight: FontWeight.bold)),
        TextSpan(
            text: t.text,
            style: doneTile ? const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey) : null),
      ])),
      subtitle: chips.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(spacing: 6, runSpacing: 4, children: chips),
            ),
      onTap: _selMode ? () => _toggleSel(t) : (doneTile ? null : () => _edit(t)),
      onLongPress: () => _toggleSel(t),
    );
    if (_selMode) return tileCore;
    return Dismissible(
      key: ValueKey('t${t.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) {
        store.delete(t);
        _toast('已删除', undo: true);
      },
      child: tileCore,
    );
  }

  Widget _empty(String text) => Center(
      child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black45, fontSize: 16))));

  Widget _todayView() {
    final today = store.today;
    final groups = Planner.groupByCategory(store.todo);
    final doneToday = store.done.where((t) => t.completionDate == today).length;
    final rows = <_CatGroup>[];
    groups.forEach((cat, items) {
      final tset = items.where((t) => Planner.inToday(t, today)).toList()..sort(_cmp);
      final undated = items.where((t) => Planner.undatedVisible(t, today)).toList()..sort(_cmp);
      final hasLater = items.any((t) => !t.done && t.date != null && t.date!.isAfter(today));
      if (tset.isEmpty && undated.isEmpty && !hasLater) return;
      rows.add(_CatGroup(cat, tset, undated, hasLater));
    });
    rows.sort((a, b) {
      if (a.today.isEmpty != b.today.isEmpty) return a.today.isEmpty ? 1 : -1;
      if (a.cat == null || b.cat == null) return a.cat == null ? 1 : -1;
      return a.cat!.compareTo(b.cat!);
    });
    final total = rows.fold<int>(0, (n, g) => n + g.today.length);
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text('${today.month}月${today.day}日 ${Ymd.weekday(today)}　今日剩余 $total 项 · 今日已完成 $doneToday 项',
            style: const TextStyle(color: Colors.black54)),
      ),
    ];
    for (final g in rows) {
      final cleared = g.today.isEmpty;
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
        child: Row(children: [
          Expanded(
            child: Text(
              '${store.categoryLabel(g.cat)} · ${cleared ? '今日已清空' : '今日剩余 ${g.today.length} 项'}',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: g.today.any((t) => t.date!.isBefore(today)) ? Colors.red : Theme.of(context).colorScheme.primary),
            ),
          ),
          if (g.hasLater)
            (cleared ? FilledButton.tonalIcon : TextButton.icon)(
              onPressed: () async {
                final msg = await store.pullNextBatch(g.cat);
                if (mounted) _toast(msg, undo: true);
              },
              icon: const Icon(Icons.fast_forward, size: 18),
              label: const Text('提前下一批'),
            ),
        ]),
      ));
      children.addAll(g.today.map((t) => _tile(t)));
      children.addAll(g.undated.map((t) => _tile(t)));
    }
    if (rows.isEmpty) {
      children.add(SizedBox(
          height: 240,
          child: _empty(store.todo.isEmpty ? '还没有任务\n点右下角 + 新建，或从右上角菜单导入 todo.txt / .ics' : '今天没有任务 🎉')));
    }
    children.add(const SizedBox(height: 80));
    return ListView(children: children);
  }

  Widget _allView() {
    final items = [...store.todo]..sort(_cmp);
    if (items.isEmpty) return _empty('没有待办任务');
    final children = <Widget>[];
    var first = true;
    String? lastHeader;
    for (final t in items) {
      final d = t.date;
      final h = d == null ? '无日期' : _dateLabel(d);
      if (first || h != lastHeader) {
        children.add(_header(h, color: d != null && d.isBefore(store.today) ? Colors.red : null));
        lastHeader = h;
        first = false;
      }
      children.add(_tile(t));
    }
    children.add(const SizedBox(height: 80));
    return ListView(children: children);
  }

  Widget _doneView() {
    if (store.done.isEmpty) return _empty('还没有已完成的任务');
    return ListView(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
        child: Row(children: [
          Text('共 ${store.done.length} 项（done.txt）', style: const TextStyle(color: Colors.black54)),
          const Spacer(),
          TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('清空已完成？'),
                    content: const Text('将删除 done.txt 中的全部记录（可立即撤销）。'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                      TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('清空')),
                    ],
                  ),
                );
                if (ok == true) {
                  await store.clearDone();
                  _toast('已清空', undo: true);
                }
              },
              child: const Text('清空')),
        ]),
      ),
      ...store.done.map((t) => _tile(t, doneTile: true)),
      const SizedBox(height: 40),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final titles = ['今日', '全部任务', '已完成'];
        return PopScope(
          canPop: !_selMode,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _exitSelection();
          },
          child: Scaffold(
          appBar: _selMode ? _selectionBar() : AppBar(
            title: Text('待办 · ${titles[_tab]}'),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'file':
                      _pickFile();
                    case 'paste':
                      _pasteDialog();
                    case 'export':
                      _export();
                    case 'select':
                      setState(() => _selMode = true);
                    case 'manage':
                      Navigator.push(context, MaterialPageRoute(builder: (_) => ManagePage(store: store)));
                    case 'settings':
                      Navigator.push(
                          context, MaterialPageRoute(builder: (_) => SettingsPage(store: store)));
                    case 'about':
                      showAbout(context);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'file', child: Text('从文件导入（txt / ics）')),
                  PopupMenuItem(value: 'paste', child: Text('粘贴文本导入')),
                  PopupMenuItem(value: 'export', child: Text('导出')),
                  PopupMenuItem(value: 'select', child: Text('多选')),
                  PopupMenuItem(value: 'manage', child: Text('批量管理 / 类别')),
                  PopupMenuItem(value: 'settings', child: Text('设置')),
                  PopupMenuItem(value: 'about', child: Text('关于')),
                ],
              ),
            ],
          ),
          body: [_todayView, _allView, _doneView][_tab](),
          floatingActionButton: (_tab == 2 || _selMode)
              ? null
              : FloatingActionButton(onPressed: () => _edit(), tooltip: '新建任务', child: const Icon(Icons.add)),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() {
              _tab = i;
              _selMode = false;
              _sel.clear();
            }),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.today), label: '今日'),
              NavigationDestination(icon: Icon(Icons.calendar_month), label: '全部'),
              NavigationDestination(icon: Icon(Icons.done_all), label: '已完成'),
            ],
          ),
        ));
      },
    );
  }

  PreferredSizeWidget _selectionBar() {
    final inDone = _tab == 2;
    return AppBar(
      leading: IconButton(icon: const Icon(Icons.close), tooltip: '退出多选', onPressed: _exitSelection),
      title: Text('已选 ${_sel.length} 项'),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all),
          tooltip: '全选 / 取消全选',
          onPressed: () => setState(() {
            final ids = _tabItems().map((e) => e.id).toSet();
            if (ids.isNotEmpty && ids.every(_sel.contains)) {
              _sel.removeAll(ids);
            } else {
              _sel.addAll(ids);
            }
          }),
        ),
        IconButton(
          icon: Icon(inDone ? Icons.undo : Icons.done_all),
          tooltip: inDone ? '取消完成' : '批量完成',
          onPressed: _sel.isEmpty ? null : (inDone ? _batchReopen : _batchComplete),
        ),
        IconButton(icon: const Icon(Icons.delete_outline), tooltip: '批量删除', onPressed: _sel.isEmpty ? null : _batchDelete),
        PopupMenuButton<String>(
          enabled: _sel.isNotEmpty,
          onSelected: (v) => v == 'cat' ? _batchCategory() : _batchShift(),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'cat', child: Text('更改类别')),
            if (!inDone) const PopupMenuItem(value: 'shift', child: Text('平移日期')),
          ],
        ),
      ],
    );
  }
}

class _CatGroup {
  final String? cat;
  final List<TodoItem> today;
  final List<TodoItem> undated;
  final bool hasLater;
  _CatGroup(this.cat, this.today, this.undated, this.hasLater);
}
