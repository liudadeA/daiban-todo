import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/store.dart';
import 'ui/home_page.dart';
import 'widget_sync.dart';
import 'package:home_widget/home_widget.dart';

final messengerKey = GlobalKey<ScaffoldMessengerState>();
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final dir = await getApplicationDocumentsDirectory();
  final store = TodoStore(dir: dir, prefs: prefs);
  store.onPersisted = () => syncTodayWidget(store);
  await HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);
  await store.load();
  runApp(DaibanApp(store: store));
}

class DaibanApp extends StatefulWidget {
  final TodoStore store;
  const DaibanApp({super.key, required this.store});

  @override
  State<DaibanApp> createState() => _DaibanAppState();
}

class _DaibanAppState extends State<DaibanApp> with WidgetsBindingObserver {
  static const _channel = MethodChannel('daiban/intent');
  final _homeKey = GlobalKey<HomePageState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onText') {
        _homeKey.currentState?.importText(call.arguments as String);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _dayCheck();
      try {
        final t = await _channel.invokeMethod<String>('getInitialText');
        if (t != null && t.trim().isNotEmpty) _homeKey.currentState?.importText(t);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResume();
  }

  /// 回到前台时先从磁盘重新读取（桌面组件可能已勾选完成），再检查是否跨天。
  Future<void> _onResume() async {
    // 组件的后台 isolate 可能已经改过设置（上次处理日期等），先重读再做跨日检查。
    await widget.store.prefs.reload();
    await widget.store.load();
    await _dayCheck();
  }

  /// 打开 / 回到前台时检查是否跨天，并按设置整体顺延。
  Future<void> _dayCheck() async {
    final msg = await widget.store.checkDayChange();
    if (msg != null) {
      messengerKey.currentState?.showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: '撤销', onPressed: () => widget.store.undo()),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '待办',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: messengerKey,
      navigatorKey: navigatorKey,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D6B)),
        useMaterial3: true,
      ),
      home: HomePage(key: _homeKey, store: widget.store),
    );
  }
}
