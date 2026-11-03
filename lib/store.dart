// 纯音播放器手机版 —— 本地持久化（收藏 / 历史 / 搜索词 / 播放记忆 / 偏好）
// 曲目以 JSON 文本落盘，避免与播放模块循环依赖。
import 'dart:convert';

import 'prefs.dart';

class Store {
  static Future<void> init() => Prefs.init();

  // ---------- 通用 ----------
  static List<Map<String, dynamic>> _list(String key) {
    final raw = Prefs.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final d = json.decode(raw);
      return d is List ? d.cast<Map<String, dynamic>>() : [];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveList(String key, List<Map<String, dynamic>> v) =>
      Prefs.put(key, json.encode(v));

  // ---------- 收藏 ----------
  static const _kFav = 'favorites_v1';

  static List<Map<String, dynamic>> get favorites => _list(_kFav);

  static bool isFavorite(String id) => favorites.any((e) => e['id'] == id);

  /// 返回切换后的状态（true = 已收藏）
  static Future<bool> toggleFavorite(Map<String, dynamic> track) async {
    final l = favorites;
    final idx = l.indexWhere((e) => e['id'] == track['id']);
    if (idx >= 0) {
      l.removeAt(idx);
      await _saveList(_kFav, l);
      return false;
    }
    l.insert(0, track);
    await _saveList(_kFav, l.take(500).toList());
    return true;
  }

  static Future<void> removeFavorite(String id) async {
    final l = favorites..removeWhere((e) => e['id'] == id);
    await _saveList(_kFav, l);
  }

  // ---------- 最近播放 ----------
  static const _kHistory = 'history_v1';

  static List<Map<String, dynamic>> get history => _list(_kHistory);

  static Future<void> pushHistory(Map<String, dynamic> track) async {
    final l = history..removeWhere((e) => e['id'] == track['id']);
    l.insert(0, {...track, 'at': DateTime.now().millisecondsSinceEpoch});
    await _saveList(_kHistory, l.take(100).toList());
  }

  static Future<void> clearHistory() => _saveList(_kHistory, []);

  // ---------- 最近搜索 ----------
  static const _kSearch = 'recent_search_v1';

  static List<String> get recentSearches {
    final raw = Prefs.getString(_kSearch);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final d = json.decode(raw);
      return d is List ? d.map((e) => '$e').toList() : const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> pushRecentSearch(String kw) async {
    final k = kw.trim();
    if (k.isEmpty) return;
    final l = recentSearches.toList()..remove(k);
    l.insert(0, k);
    await Prefs.put(_kSearch, json.encode(l.take(10).toList()));
  }

  static Future<void> clearRecentSearches() => Prefs.remove(_kSearch);

  // ---------- 播放记忆（上次队列与进度） ----------
  static const _kMem = 'playback_memory_v1';

  static Map<String, dynamic>? get playbackMemory {
    final raw = Prefs.getString(_kMem);
    if (raw == null || raw.isEmpty) return null;
    try {
      final d = json.decode(raw);
      return d is Map<String, dynamic> ? d : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> savePlaybackMemory(Map<String, dynamic> v) =>
      Prefs.put(_kMem, json.encode(v));

  static Future<void> clearPlaybackMemory() => Prefs.remove(_kMem);

  // ---------- 偏好 ----------
  static double get speed => Prefs.getDouble('speed') ?? 1.0;
  static Future<void> setSpeed(double v) => Prefs.put('speed', v);

  static String get loopMode => Prefs.getString('loop_mode') ?? 'all';
  static Future<void> setLoopMode(String v) => Prefs.put('loop_mode', v);

  static bool get shuffle => Prefs.getBool('shuffle') ?? false;
  static Future<void> setShuffle(bool v) => Prefs.put('shuffle', v);

  static bool get onboarded => Prefs.getBool('onboarded') ?? false;
  static Future<void> setOnboarded() => Prefs.put('onboarded', true);
}
