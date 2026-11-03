// 极轻量键值存储：走原生通道（Android SharedPreferences / iOS UserDefaults）
// 不使用第三方插件，规避新版插件在 AGP 9 下的 Gradle 构建不兼容问题。
import 'package:flutter/services.dart';

class Prefs {
  static const _ch = MethodChannel('chunyin/kv');
  static final Map<String, dynamic> _mem = {};

  static String _k(String k) => 'cy_$k';

  /// 启动时一次性载入（之后全部同步读取，UI 可直接用）
  static Future<void> init() async {
    try {
      final all = await _ch.invokeMapMethod<String, dynamic>('getAll');
      _mem.clear();
      all?.forEach((k, v) {
        if (k.startsWith('cy_')) _mem[k.substring(3)] = v;
      });
    } catch (_) {
      // 通道不可用（例如单元测试环境）时降级为纯内存
    }
  }

  static dynamic raw(String key) => _mem[key];

  static String? getString(String key) {
    final v = _mem[key];
    return v is String ? v : null;
  }

  static bool? getBool(String key) {
    final v = _mem[key];
    return v is bool ? v : null;
  }

  static double? getDouble(String key) {
    final v = _mem[key];
    return v is num ? v.toDouble() : null;
  }

  static Future<void> put(String key, Object value) async {
    _mem[key] = value;
    try {
      await _ch.invokeMethod('put', {'key': _k(key), 'value': value});
    } catch (_) {}
  }

  static Future<void> remove(String key) async {
    _mem.remove(key);
    try {
      await _ch.invokeMethod('remove', {'key': _k(key)});
    } catch (_) {}
  }
}
