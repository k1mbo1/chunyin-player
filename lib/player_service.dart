// 纯音播放器手机版 —— 后台播放服务
// audio_service (BaseAudioHandler) + just_audio (ExoPlayer)
// 支持锁屏控制 / 耳机线控 / 通知栏媒体控制 / 后台连续播放
// 双模式播放：
//   常规队列（本地/电台/Archive）→ ConcatenatingAudioSource 无缝连播
//   全网聚合队列（网易云/QQ）    → 单曲模式，播放前多源解析直链（原平台
//                                失败自动跨平台匹配免费来源），播完自动连播
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'api.dart' as webapi;

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
  final String wsrc; // 全网搜索平台：kuwo / netease（空 = 非 web 曲目）
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

  MediaItem toMediaItem() => MediaItem(
        id: isWeb ? 'web:$wsrc:$rid' : source,
        title: title,
        artist: artist,
        album: album,
        duration: isLive ? null : duration,
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
        _loadWeb(_webIndex + 1);
      }
    });
  }

  // ---------- UI 使用的流 ----------
  AudioPlayer get player => _player;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<bool> get playingStream => _player.playingStream;

  List<PTrack> get tracks => List.unmodifiable(_tracks);
  int get currentIndex => _webMode ? _webIndex : (_player.currentIndex ?? -1);
  PTrack? get currentTrack {
    final i = currentIndex;
    return (i >= 0 && i < _tracks.length) ? _tracks[i] : null;
  }

  /// 载入播放队列并从 startIndex 开始播放
  Future<void> loadQueue(List<PTrack> tracks, int startIndex) async {
    _tracks
      ..clear()
      ..addAll(tracks);
    queue.add(tracks.map((t) => t.toMediaItem()).toList());
    _webMode = tracks.any((t) => t.isWeb);
    if (_webMode) {
      await _loadWeb(startIndex.clamp(0, tracks.length - 1));
      return;
    }
    await _player.setAudioSource(
      ConcatenatingAudioSource(
        children: tracks.map(_toAudioSource).toList(),
      ),
      initialIndex: startIndex.clamp(0, tracks.length - 1),
    );
    _onIndexChanged(_player.currentIndex);
    await _player.play();
  }

  /// 全网搜索模式：单曲加载（播放前多源解析直链——原平台失败
  /// 自动跨平台匹配免费来源；直链失效自动重解析一次）
  Future<void> _loadWeb(int index) async {
    if (index < 0 || index >= _tracks.length) {
      await _player.pause();
      return;
    }
    _webLoading = true;
    _webIndex = index;
    final t = _tracks[index];
    mediaItem.add(t.toMediaItem());
    Future<webapi.ResolvedUrl?> resolve() =>
        webapi.webResolveAuto(t.title, t.artist, t.wsrc, t.rid,
            t.duration?.inSeconds.toDouble() ?? 0);
    try {
      var r = await resolve();
      if (r == null) {
        throw Exception('暂时无法获取播放链接：${t.title}');
      }
      try {
        await _player.setUrl(r.url, headers: r.headers);
      } catch (_) {
        // 直链可能已失效，重新解析一次
        r = await resolve();
        if (r == null) {
          throw Exception('播放链接已失效：${t.title}');
        }
        await _player.setUrl(r.url, headers: r.headers);
      }
      await _player.play();
    } finally {
      _webLoading = false;
    }
  }

  void _onIndexChanged(int? i) {
    if (_webMode) return;
    if (i == null || i < 0 || i >= _tracks.length) return;
    mediaItem.add(_tracks[i].toMediaItem());
  }

  // ---------- 基础控制 ----------
  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_webMode) {
      await _loadWeb(_webIndex + 1);
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
      await _loadWeb(_webIndex - 1);
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
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

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
