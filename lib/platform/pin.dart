import 'package:flutter/services.dart';

/// 屏幕固定 / 保持亮屏 / 系统分享。真实设备走 Android MethodChannel；测试里可注入。
class ScreenPin {
  static const channelName = 'daiban/pin';
  static MethodChannel channel = const MethodChannel(channelName);

  static Future<bool> start() async {
    try {
      return await channel.invokeMethod<bool>('startPin') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      await channel.invokeMethod('stopPin');
    } catch (_) {}
  }

  static Future<bool> isPinned() async {
    try {
      return await channel.invokeMethod<bool>('isPinned') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setKeepScreenOn(bool on) async {
    try {
      await channel.invokeMethod('setKeepScreenOn', on);
    } catch (_) {}
  }

  static Future<void> share(String text) async {
    try {
      await channel.invokeMethod('share', {'text': text});
    } catch (_) {}
  }

  /// 系统解除屏幕固定时回调。返回取消订阅的函数。
  static VoidCallback listen(void Function(bool pinned) onChange) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onPinState') onChange(call.arguments == true);
    });
    return () => channel.setMethodCallHandler(null);
  }
}
