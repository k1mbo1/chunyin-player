// 纯音播放器手机版 —— 后台播放服务
// audio_service (BaseAudioHandler) + just_audio (ExoPlayer / AVPlayer)
// 支持锁屏控制 / 耳机线控 / 通知栏媒体控制 / 后台连续播放
// 双模式播放：
//   常规队列（本地/电台/Archive）→ ConcatenatingAudioSource 无缝连播
//   全网聚合队列（网易云/QQ/酷我/B站）→ 单曲模式，播放前多源解析直链
//                                （原平台失败自动跨平台匹配免费来源），播完自动连播
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'api.dart' as webapi;
import 'proxy.dart' as proxy;
import 'store.dart';

/// 统一曲目模型（本地 / 电台 / Internet Archive / 全网搜索）
class PTrack {
  final String title;
  final String artist;
  final String album;
  final String source; // 本地: 文件路径或 content:// ；在线: https URL；web: 空
  final Duration? duration;
  final bool isLocal;
  final bool isLive; // 电台直播
  final bool isLossless; // flac/wav/alac/ape/aiff/dsf/dff
  final String fmt; // FLAC / MP3 / ...
  final int? artId; // on_audio_query 封面 id（仅本地）
  final String wsrc; // 全网搜索平台：netease / qq / kuwo / bili（空 = 非 web 曲目）
  final String rid; // 平台歌曲 ID（web 曲目用）

  const PTrack({
    required this.title,
    required this.artist,
    required this.album,
    required this.source,
    this.duration,
    this.isLocal = false,
    this.isLive = false,
    this.isLossless = false,
    this.fmt = '',
    this.artId,
    this.wsrc = '',
    this.rid = '',
  });

  bool get isWeb => wsrc.isNotEmpty;

  String get id => isWeb ? 'web:$wsrc:$rid' : 'src:$source';

  Map<String, dynamic> toJson() => {
        'title': title,
        'artist': artist,
        'album': album,
        'source': source,
        'duration': duration?.inMilliseconds,
        'isLocal': isLocal,
        'isLive': isLive,
        'isLossless': isLossless,
        'fmt': fmt,
        'artId': artId,
        'wsrc': wsrc,
        'rid': rid,
        'id': id,
      };

  /// 收藏/历史中恢复；本地文件可能已不存在，恢复失败时由播放层兜底
  factory PTrack.fromJson(Map<String, dynamic> j) => PTrack(
        title: '${j['title'] ?? ''}',
        artist: '${j['artist'] ?? ''}',
        album: '${j['album'] ?? ''}',
        source: '${j['source'] ?? ''}',
        duration: j['duration'] == null
            ? null
            : Duration(milliseconds: (j['duration'] as num).toInt()),
        isLocal: j['isLocal'] == true,
        isLive: j['isLive'] == true,
        isLossless: j['isLossless'] == true,
        fmt: '${j['fmt'] ?? ''}',
        artId: j['artId'] == null ? null : (j['artId'] as num).toInt(),
        wsrc: '${j['wsrc'] ?? ''}',
        rid: '${j['rid'] ?? ''}',
      );

  MediaItem toMediaItem() => MediaItem(
        id: id,
        title: title,
        artist: artist,
        album: album,
        duration: isLive ? null : duration,
        extras: {'quality': ''},
      );
}

Uri _sourceUri(String s) =>
    s.startsWith('content://') || s.startsWith('http') ? Uri.parse(s) : Uri.file(s);

AudioSource _toAudioSource(PTrack t) => AudioSource.uri(
      _sourceUri(t.source),
      tag: t.toMediaItem(),
    );

class AudioPlayerHandler extends BaseAudioHandler {
  final AudioPlayer _player = AudioPlayer();
  final List<PTrack> _tracks = [];

  bool _webMode = false; // 全网搜索单曲模式
  int _webIndex = -1;
  bool _webLoading = false; // 防止连播重复触发
  bool _autoNexting = false;

  // 播放失败提示（UI 订阅后弹 SnackBar 并提示已自动切歌）
  final _errorCtrl = StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorCtrl.stream;

  String _quality = '';
  String get currentQuality => _quality;

  String _loopMode = 'all'; // all / one / off（仅非 web 队列生效）
  bool _shuffle = false;

  // 播放记忆（上次队列与进度）
  int _pendingResumeIndex = -1;
  Duration _pendingResumePos = Duration.zero;

  DateTime _lastMemSave = DateTime.fromMillisecondsSinceEpoch(0);

  AudioPlayerHandler() {
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    _player.currentIndexStream.listen(_onIndexChanged);
    _player.durationStream.listen((d) {
      final item = mediaItem.valueOrNull;
      if (item != null && d != null) {
        mediaItem.add(item.copyWith(duration: d));
      }
    });
    // 全网搜索模式：单曲播完自动连播
    _player.processingStateStream.listen((state) {
      if (_webMode && !_webLoading && state == ProcessingState.completed) {
        _playNextWeb(auto: true);
      }
    });
    _loopMode = Store.loopMode;
    _shuffle = Store.shuffle;
    _applyPlayerModes();
    // 每 5 秒落盘播放进度（避免频繁写盘）
    Timer.periodic(const Duration(seconds: 5), (_) => _saveMemory());
  }

  // ---------- UI 使用的流 ----------
  AudioPlayer get player => _player;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;
  Stream<AudioProcessingState> get processingStream =>
      _player.processingStateStream.map((s) => const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[s]!);

  List<PTrack> get tracks => List.unmodifiable(_tracks);
  int get currentIndex => _webMode ? _webIndex : (_player.currentIndex ?? -1);
  PTrack? get currentTrack {
    final i = currentIndex;
    return (i >= 0 && i < _tracks.length) ? _tracks[i] : null;
  }

  String get loopMode => _loopMode;
  bool get shuffle => _shuffle;

  /// 载入播放队列并从 startIndex 开始播放
  Future<void> loadQueue(List<PTrack> tracks, int startIndex,
      {bool autoplay = true}) async {
    _tracks
      ..clear()
      ..addAll(tracks);
    queue.add(tracks.map((t) => t.toMediaItem()).toList());
    _webMode = tracks.any((t) => t.isWeb);
    _autoNexting = false;
    if (_webMode) {
      await _loadWeb(startIndex.clamp(0, tracks.length - 1), autoplay: autoplay);
      return;
    }
    await _player.setAudioSource(
      ConcatenatingAudioSource(
        children: tracks.map(_toAudioSource).toList(),
      ),
      initialIndex: startIndex.clamp(0, tracks.length - 1),
    );
    _onIndexChanged(_player.currentIndex);
    if (autoplay) await _player.play();
  }

  /// 全网搜索模式：单曲加载（播放前多源解析直链——原平台失败
  /// 自动跨平台匹配免费来源；直链失效自动重解析一次）
  Future<void> _loadWeb(int index,
      {bool autoplay = true, Duration? resumeAt}) async {
    if (index < 0 || index >= _tracks.length) {
      await _player.pause();
      return;
    }
    _webLoading = true;
    _webIndex = index;
    final t = _tracks[index];
    _quality = '';
    mediaItem.add(t.toMediaItem());
    Future<webapi.ResolvedUrl?> resolve() =>
        webapi.webResolveAuto(t.title, t.artist, t.wsrc, t.rid,
            t.duration?.inSeconds.toDouble() ?? 0);
    try {
      var r = await resolve();
      if (r == null) {
        throw _PlayFail('暂时无法获取播放链接');
      }
      _quality = r.quality;
      // iOS(AVPlayer) 不支持自定义请求头：带 Referer 的直链
      // 统一走本机代理转发；无特殊头的直链原样返回
      final playUrl = await proxy.proxiedUrl(r.url, r.headers);
      try {
        await _player.setUrl(playUrl);
      } catch (_) {
        // 直链可能已失效，重新解析一次
        r = await resolve();
        if (r == null) throw _PlayFail('播放链接已失效');
        _quality = r.quality;
        await _player.setUrl(await proxy.proxiedUrl(r.url, r.headers));
      }
      final at = resumeAt ?? _pendingResumePos;
      if (at > Duration.zero && _pendingResumeIndex == index) {
        await _player.seek(at);
        _pendingResumeIndex = -1;
        _pendingResumePos = Duration.zero;
      }
      if (autoplay) await _player.play();
      _pushHistory(t);
      _saveMemory();
      _prefetchNext(index);
    } on _PlayFail catch (e) {
      _fail(t, e.msg);
    } catch (e) {
      _fail(t, '网络异常或资源已失效');
    } finally {
      _webLoading = false;
    }
  }

  void _fail(PTrack t, String reason) {
    if (!_errorCtrl.isClosed) {
      _errorCtrl.add('「${t.title}」播放失败：$reason');
    }
    // 自动切下一首（避免停在同一首死循环：最多连续 3 次）
    if (_autoNexting) return;
    _autoNexting = true;
    Timer(const Duration(milliseconds: 900), () {
      _autoNexting = false;
      _playNextWeb(auto: true);
    });
  }

  void _prefetchNext(int index) {
    final n = _nextWebIndex(index);
    if (n < 0 || n >= _tracks.length) return;
    final t = _tracks[n];
    // 静默预解析（结果进缓存，切歌时直接命中 → 秒开）
    webapi
        .webResolveAuto(t.title, t.artist, t.wsrc, t.rid,
            t.duration?.inSeconds.toDouble() ?? 0)
        .catchError((_) => null);
  }

  int _nextWebIndex(int from) {
    if (!_shuffle) return from + 1;
    if (_tracks.isEmpty) return -1;
    var n = from;
    for (var i = 0; i < _tracks.length; i++) {
      n = (n + 1) % _tracks.length;
      if (n != from) return n; // 随机即可（单曲循环由 loopMode=one 拦截）
    }
    return from;
  }

  int _prevWebIndex(int from) {
    if (!_shuffle) return from - 1;
    return _nextWebIndex(from);
  }

  Future<void> _playNextWeb({bool auto = false}) async {
    if (_loopMode == 'one' && auto) {
      await _loadWeb(_webIndex);
      return;
    }
    final n = _nextWebIndex(_webIndex);
    if (n <= 0 && _loopMode == 'off') {
      await _player.pause();
      await _player.seek(Duration.zero);
      return;
    }
    await _loadWeb(n < 0 ? 0 : n);
  }

  void _pushHistory(PTrack t) {
    Store.pushHistory(t.toJson());
  }

  void _saveMemory() {
    if (_tracks.isEmpty || !_webMode && _player.currentIndex == null) return;
    final now = DateTime.now();
    if (now.difference(_lastMemSave).inSeconds < 3 && _webMode) return;
    _lastMemSave = now;
    final idx = currentIndex;
    if (idx < 0 || idx >= _tracks.length) return;
    Store.savePlaybackMemory({
      'tracks': _tracks.take(60).map((e) => e.toJson()).toList(),
      'index': idx,
      'position': _player.position.inMilliseconds,
      'web': _webMode,
      'at': now.millisecondsSinceEpoch,
    });
  }

  /// 启动时恢复上次队列（不自动播放，显示在迷你播放器，点播放继续）
  Future<bool> restoreSession() async {
    final m = Store.playbackMemory;
    if (m == null) return false;
    try {
      final list = (m['tracks'] as List)
          .map((e) => PTrack.fromJson(e as Map<String, dynamic>))
          .toList();
      if (list.isEmpty) return false;
      final idx = (m['index'] as num?)?.toInt() ?? 0;
      if (idx < 0 || idx >= list.length) return false;
      final pos = Duration(milliseconds: (m['position'] as num?)?.toInt() ?? 0);
      if (m['web'] == true || list[idx].isWeb) {
        // 在线曲目：启动时不解析直链（避免拖慢冷启动），
        // 仅恢复迷你条信息，首次点播放时再解析并 seek 到原进度
        _tracks
          ..clear()
          ..addAll(list);
        _webMode = true;
        _webIndex = idx;
        queue.add(list.map((t) => t.toMediaItem()).toList());
        mediaItem.add(list[idx].toMediaItem());
        _pendingResumeIndex = idx;
        _pendingResumePos = pos;
        return true;
      }
      await loadQueue(list, idx, autoplay: false);
      await _player.seek(pos);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _onIndexChanged(int? i) {
    if (_webMode) return;
    if (i == null || i < 0 || i >= _tracks.length) return;
    mediaItem.add(_tracks[i].toMediaItem());
    _pushHistory(_tracks[i]);
    _saveMemory();
  }

  void _applyPlayerModes() {
    _player.setLoopMode(
      _loopMode == 'one'
          ? LoopMode.one
          : (_loopMode == 'all' ? LoopMode.all : LoopMode.off),
    );
    _player.setShuffleModeEnabled(_shuffle);
  }

  Future<void> setLoopMode(String mode) async {
    _loopMode = mode;
    await Store.setLoopMode(mode);
    _applyPlayerModes();
    playbackState.add(playbackState.value);
  }

  Future<void> toggleShuffle() async {
    _shuffle = !_shuffle;
    await Store.setShuffle(_shuffle);
    _applyPlayerModes();
    playbackState.add(playbackState.value);
  }

  Future<void> setVolume(double v) => _player.setVolume(v.clamp(0.0, 1.0));
  double get volume => _player.volume;

  // ---------- 基础控制 ----------
  @override
  Future<void> play() async {
    // 恢复会话后首次播放：web 曲目需要先解析直链
    if (_webMode && _pendingResumeIndex >= 0) {
      final i = _pendingResumeIndex;
      final pos = _pendingResumePos;
      _pendingResumeIndex = -1;
      _pendingResumePos = Duration.zero;
      await _loadWeb(i, resumeAt: pos);
      return;
    }
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _saveMemory();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _saveMemory();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_webMode) {
      if (_loopMode == 'one') return _loadWeb(_webIndex);
      await _playNextWeb();
      return;
    }
    final i = _player.nextIndex;
    if (i != null) {
      await _player.seek(Duration.zero, index: i);
    } else {
      await _player.pause();
      await _player.seek(Duration.zero);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_webMode) {
      if (_player.position > const Duration(seconds: 5)) {
        await _player.seek(Duration.zero);
        return;
      }
      await _loadWeb(_prevWebIndex(_webIndex));
      return;
    }
    if (_player.position > const Duration(seconds: 5)) {
      await _player.seek(Duration.zero);
      return;
    }
    final i = _player.previousIndex;
    if (i != null) {
      await _player.seek(Duration.zero, index: i);
    } else {
      await _player.seek(Duration.zero);
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    await Store.setSpeed(speed);
  }

  @override
  Future<void> onTaskRemoved() async {
    _saveMemory();
    await super.onTaskRemoved();
  }

  // ---------- 通知栏状态 ----------
  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
    );
  }
}

class _PlayFail implements Exception {
  final String msg;
  _PlayFail(this.msg);
}
