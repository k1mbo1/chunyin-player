// 纯音播放器手机版 —— 主界面
// 四大音源：本地音乐（全格式无损）/ 全球电台 / 全网聚合搜索（网易云+QQ）/ Internet Archive
// 深色 HiFi 风格，与 PC 版一致（#10141c 底 + #37e2c4 青色点缀）
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api.dart';
import 'player_service.dart';

late AudioPlayerHandler gHandler;

// ---------------- 配色 ----------------
const cBg = Color(0xFF10141c);
const cPanel = Color(0xFF0b0f16);
const cCard = Color(0xFF161d29);
const cCardHover = Color(0xFF1c2534);
const cAccent = Color(0xFF37e2c4);
const cText = Color(0xFFdde3ee);
const cDim = Color(0xFF7d8aa2);
const cGreen = Color(0xFF3ddc84);
const cGold = Color(0xFFffc94d);
const cPink = Color(0xFFff7a90);

const losslessExts = {'flac', 'wav', 'alac', 'ape', 'aiff', 'aif', 'dsf', 'dff', 'wv'};

String two(int n) => n.toString().padLeft(2, '0');

String fmtTime(Duration d) {
  d = d.abs();
  final h = d.inHours;
  if (h > 0) return '$h:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  return '${d.inMinutes}:${two(d.inSeconds % 60)}';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: cPanel,
  ));
  gHandler = await AudioService.init(
    builder: () => AudioPlayerHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.chunyin.chunyin_mobile.audio',
      androidNotificationChannelName: '纯音播放器',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  runApp(const ChunyinApp());
}

class ChunyinApp extends StatelessWidget {
  const ChunyinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '纯音播放器',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: cBg,
        colorScheme: const ColorScheme.dark(
          primary: cAccent,
          secondary: cAccent,
          surface: cPanel,
          onSurface: cText,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: cCard,
          hintStyle: const TextStyle(color: cDim, fontSize: 14),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
        sliderTheme: const SliderThemeData(
          trackHeight: 3,
          activeTrackColor: cAccent,
          inactiveTrackColor: Color(0xFF232d40),
          thumbColor: cAccent,
          overlayColor: Color(0x2237e2c4),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: cPanel,
          indicatorColor: Color(0xFF12202b),
          height: 64,
          elevation: 0,
        ),
      ),
      home: const HomeShell(),
    );
  }
}

// ---------------- 徽章 ----------------
class Badge extends StatelessWidget {
  final String text;
  final Color color;
  const Badge(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

// ---------------- 主框架 ----------------
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: const [LocalPage(), RadioPage(), ArchivePage()],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined, color: cDim),
                selectedIcon: Icon(Icons.library_music, color: cAccent),
                label: '本地',
              ),
              NavigationDestination(
                icon: Icon(Icons.radio_outlined, color: cDim),
                selectedIcon: Icon(Icons.radio, color: cAccent),
                label: '电台',
              ),
              NavigationDestination(
                icon: Icon(Icons.public_outlined, color: cDim),
                selectedIcon: Icon(Icons.public, color: cAccent),
                label: '曲库',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------- 页面标题 ----------------
class PageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const PageHeader(this.title, this.subtitle, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: cDim, fontSize: 12)),
        ],
      ),
    );
  }
}

Widget loadingBody(String msg) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: cAccent, strokeWidth: 2.4),
          const SizedBox(height: 16),
          Text(msg, style: const TextStyle(color: cDim, fontSize: 13)),
        ],
      ),
    );

Widget errorBody(String msg, VoidCallback onRetry) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, color: cDim, size: 42),
          const SizedBox(height: 12),
          Text(msg,
              textAlign: TextAlign.center,
              style: const TextStyle(color: cDim, fontSize: 13)),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: cAccent, foregroundColor: const Color(0xFF06231d)),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重试'),
          ),
        ],
      ),
    );

void playErrorSnackBar(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text('播放失败：$e', style: const TextStyle(fontSize: 13)),
    backgroundColor: const Color(0xFF233043),
    behavior: SnackBarBehavior.floating,
  ));
}

// ---------------- 本地音乐 ----------------
class LocalPage extends StatefulWidget {
  const LocalPage({super.key});
  @override
  State<LocalPage> createState() => _LocalPageState();
}

class _LocalPageState extends State<LocalPage> {
  final OnAudioQuery _oq = OnAudioQuery();
  List<PTrack> _all = [];
  List<PTrack> _shown = [];
  String _q = '';
  bool _loading = true;
  bool _denied = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _denied = false;
      _err = null;
    });
    try {
      var st = await Permission.audio.request();
      if (!st.isGranted) st = await Permission.storage.request();
      if (!st.isGranted) {
        setState(() {
          _denied = true;
          _loading = false;
        });
        return;
      }
      final songs = await _oq.querySongs(
          sortType: SongSortType.TITLE, orderType: OrderType.ASC_OR_SMALLER);
      final List<PTrack> out = [];
      for (final s in songs) {
        final src = s.data.isNotEmpty ? s.data : (s.uri ?? '');
        if (src.isEmpty) continue;
        final ext = s.fileExtension.replaceAll('.', '').toLowerCase();
        out.add(PTrack(
          title: s.title.isNotEmpty
              ? s.title
              : (s.displayNameWOExt.isNotEmpty ? s.displayNameWOExt : '未知曲目'),
          artist: (s.artist == null || s.artist == '<unknown>')
              ? '未知艺术家'
              : s.artist!,
          album: s.album ?? '',
          source: src,
          duration: (s.duration ?? 0) > 0
              ? Duration(milliseconds: s.duration!)
              : null,
          isLocal: true,
          isLossless: losslessExts.contains(ext),
          fmt: ext.isEmpty ? 'AUDIO' : ext.toUpperCase(),
          artId: s.id,
        ));
      }
      setState(() {
        _all = out;
        _loading = false;
        _applyFilter();
      });
    } catch (e) {
      setState(() {
        _err = '读取本地音乐失败';
        _loading = false;
      });
    }
  }

  void _applyFilter() {
    final q = _q.trim().toLowerCase();
    _shown = q.isEmpty
        ? _all
        : _all
            .where((t) =>
                t.title.toLowerCase().contains(q) ||
                t.artist.toLowerCase().contains(q) ||
                t.album.toLowerCase().contains(q))
            .toList();
  }

  @override
  Widget build(BuildContext context) {
    final losslessCount = _all.where((t) => t.isLossless).length;
    return Column(
      children: [
        PageHeader('本地音乐',
            '共 ${_all.length} 首 · 无损 $losslessCount 首 · 支持全格式（FLAC/WAV/APE/DSD…）'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            decoration: const InputDecoration(
                hintText: '搜索本地歌曲 / 艺术家 / 专辑', prefixIcon: Icon(Icons.search, color: cDim)),
            onChanged: (v) => setState(() {
              _q = v;
              _applyFilter();
            }),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? loadingBody('正在扫描本地音乐…')
              : _denied
                  ? _deniedBody()
                  : _err != null
                      ? errorBody(_err!, _load)
                      : _shown.isEmpty
                          ? const Center(
                              child: Text('没有找到音乐文件',
                                  style: TextStyle(color: cDim, fontSize: 13)))
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 12),
                              itemCount: _shown.length,
                              itemExtent: 62,
                              itemBuilder: (c, i) {
                                final t = _shown[i];
                                return _localTile(t, i);
                              },
                            ),
        ),
      ],
    );
  }

  Widget _deniedBody() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.music_off_outlined, color: cDim, size: 44),
          const SizedBox(height: 12),
          const Text('需要音乐访问权限才能读取本地歌曲',
              style: TextStyle(color: cDim, fontSize: 13)),
          const SizedBox(height: 16),
          Row(mainAxisSize: MainAxisSize.min, children: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                  foregroundColor: cAccent,
                  side: const BorderSide(color: Color(0xFF2a5a52))),
              onPressed: openAppSettings,
              child: const Text('打开设置'),
            ),
            const SizedBox(width: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: cAccent,
                  foregroundColor: const Color(0xFF06231d)),
              onPressed: _load,
              child: const Text('重试'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _localTile(PTrack t, int index) {
    return InkWell(
      onTap: () async {
        try {
          await gHandler.loadQueue(_shown, index);
        } catch (e) {
          if (mounted) playErrorSnackBar(context, e);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 46,
                height: 46,
                child: t.artId != null
                    ? QueryArtworkWidget(
                        id: t.artId!,
                        type: ArtworkType.AUDIO,
                        artworkWidth: 92,
                        artworkHeight: 92,
                        artworkFit: BoxFit.cover,
                        quality: 50,
                        nullArtworkWidget: Container(
                          color: cCard,
                          child: const Icon(Icons.music_note, color: cDim),
                        ),
                      )
                    : Container(
                        color: cCard,
                        child: const Icon(Icons.music_note, color: cDim)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Text(
                    '${t.artist}${t.album.isNotEmpty ? ' · ${t.album}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: cDim, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (t.isLossless) const Badge('无损', cGreen),
            const SizedBox(width: 6),
            Text(t.duration != null ? fmtTime(t.duration!) : '--:--',
                style: const TextStyle(color: cDim, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

// ---------------- 全球电台 ----------------
const radioCountries = [
  ('', '全部地区'),
  ('CN', '中国'),
  ('US', '美国'),
  ('GB', '英国'),
  ('DE', '德国'),
  ('FR', '法国'),
  ('JP', '日本'),
  ('KR', '韩国'),
  ('IT', '意大利'),
  ('ES', '西班牙'),
  ('BR', '巴西'),
  ('RU', '俄罗斯'),
  ('CA', '加拿大'),
  ('AU', '澳大利亚'),
  ('NL', '荷兰'),
  ('SE', '瑞典'),
  ('AT', '奥地利'),
  ('PL', '波兰'),
  ('IN', '印度'),
  ('MX', '墨西哥'),
  ('TH', '泰国'),
  ('VN', '越南'),
  ('SG', '新加坡'),
  ('MY', '马来西亚'),
];

class RadioPage extends StatefulWidget {
  const RadioPage({super.key});
  @override
  State<RadioPage> createState() => _RadioPageState();
}

class _RadioPageState extends State<RadioPage> {
  String _country = '';
  List<RadioStation> _stations = [];
  bool _loading = false;
  String? _err;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final st = await fetchRadioStations(
          country: _country, limit: _country.isEmpty ? 200 : 120);
      setState(() {
        _stations = st;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _err = '电台目录暂时不可用，请检查网络';
        _loading = false;
      });
    }
  }

  Future<void> _search() async {
    final kw = _searchCtrl.text.trim();
    if (kw.isEmpty) return;
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final st = await searchRadio(kw);
      setState(() {
        _stations = st;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _err = '搜索失败，请重试';
        _loading = false;
      });
    }
  }

  void _playStation(RadioStation st) async {
    try {
      await gHandler.loadQueue([
        PTrack(
          title: st.name,
          artist: '${st.country} · 直播电台',
          album: 'Radio Browser',
          source: st.url,
          isLive: true,
        ),
      ], 0);
    } catch (e) {
      if (mounted) playErrorSnackBar(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const PageHeader('全球电台', 'Radio Browser · 全球数万个网络电台实时直播'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                      hintText: '搜索电台名称',
                      prefixIcon: Icon(Icons.search, color: cDim)),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: cAccent,
                    foregroundColor: const Color(0xFF06231d),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12)),
                onPressed: _search,
                child: const Text('搜索'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            children: [
              for (final (code, name) in radioCountries)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(name),
                    selected: _country == code,
                    onSelected: (_) {
                      if (_country != code) {
                        setState(() => _country = code);
                        _load();
                      }
                    },
                    labelStyle: TextStyle(
                        fontSize: 12.5,
                        color: _country == code ? cAccent : cDim),
                    selectedColor: const Color(0xFF12202b),
                    backgroundColor: cCard,
                    side: BorderSide(
                        color: _country == code
                            ? const Color(0xFF2a5a52)
                            : Colors.transparent),
                    showCheckmark: false,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? loadingBody('正在获取电台列表…')
              : _err != null
                  ? errorBody(_err!, _load)
                  : _stations.isEmpty
                      ? const Center(
                          child: Text('没有找到电台',
                              style: TextStyle(color: cDim, fontSize: 13)))
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 12),
                          itemCount: _stations.length,
                          itemExtent: 62,
                          itemBuilder: (c, i) => _stationTile(_stations[i]),
                        ),
        ),
      ],
    );
  }

  Widget _stationTile(RadioStation st) {
    final hifi = st.bitrate >= 320;
    return InkWell(
      onTap: () => _playStation(st),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                  color: cCard, borderRadius: BorderRadius.circular(23)),
              child: const Icon(Icons.sensors, color: cAccent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(st.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Text(
                    st.country.isEmpty ? '未知地区' : st.country,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: cDim, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Badge('直播', cPink),
            const SizedBox(width: 6),
            if (st.bitrate > 0)
              Badge('${st.bitrate}K${hifi ? ' · HiFi' : ''}',
                  hifi ? cGreen : cDim),
          ],
        ),
      ),
    );
  }
}

// ---------------- 曲库页：全网搜索 + Internet Archive ----------------
class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key});
  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  // 模式：true = 全网聚合搜索（网易云+QQ+酷我+B站）；false = 公版曲库（Internet Archive）
  bool _webMode = true;

  // ---- 全网搜索状态 ----
  List<WebTrack> _webResults = [];
  bool _webLoading = false;
  String? _webErr;
  List<String> _sources = const ['netease', 'qq', 'kuwo', 'bili'];
  String _webTitle = '全网聚合 · 每一首都可播放（B站音频无会员限制）';
  final _webCtrl = TextEditingController();

  // ---- 公版曲库状态 ----
  List<IaTrack> _tracks = [];
  bool _loading = false;
  String? _err;
  String _collection = 'etree';
  String _title = '现场音乐 Live Music';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _browse('etree', '现场音乐 Live Music');
  }

  // ---- 全网搜索 ----
  Future<void> _searchWeb() async {
    final kw = _webCtrl.text.trim();
    if (kw.isEmpty) return;
    setState(() {
      _webLoading = true;
      _webErr = null;
      _webTitle = '正在聚合全网曲库搜索「$kw」…';
    });
    try {
      final t = await webSearch(kw, sources: _sources);
      setState(() {
        _webResults = t;
        _webLoading = false;
        if (t.isEmpty) {
          _webErr = '没有找到相关歌曲，换个关键词试试';
        } else {
          _webTitle =
              '共 ${t.length} 首 · 四源聚合（B站音频无会员限制，付费歌曲自动匹配免费来源）';
        }
      });
    } catch (e) {
      setState(() {
        _webErr = '搜索失败，请检查网络后重试';
        _webLoading = false;
      });
    }
  }

  void _playWeb(int index) async {
    final list = _webResults
        .map((t) => PTrack(
              title: t.title,
              artist: t.artist,
              album: t.album,
              source: '',
              duration: t.duration > 0
                  ? Duration(seconds: t.duration.round())
                  : null,
              wsrc: t.src,
              rid: t.rid,
              fmt: t.src == 'bili' ? 'B站音频 · AAC/Hi-Res' : '全网聚合 · MP3',
            ))
        .toList();
    try {
      await gHandler.loadQueue(list, index);
    } catch (e) {
      if (mounted) playErrorSnackBar(context, e);
    }
  }

  // ---- 公版曲库 ----
  Future<void> _browse(String col, String title) async {
    setState(() {
      _loading = true;
      _err = null;
      _collection = col;
      _title = title;
    });
    try {
      final t = await iaBrowse(col);
      setState(() {
        _tracks = t;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _err = 'Internet Archive 暂时不可用，请检查网络';
        _loading = false;
      });
    }
  }

  Future<void> _search() async {
    final kw = _searchCtrl.text.trim();
    if (kw.isEmpty) return;
    setState(() {
      _loading = true;
      _err = null;
      _title = '搜索：$kw';
      _collection = '';
    });
    try {
      final t = await iaSearch(kw);
      setState(() {
        _tracks = t;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _err = '搜索失败，请重试';
        _loading = false;
      });
    }
  }

  void _play(int index) async {
    final list = _tracks
        .map((t) => PTrack(
              title: t.title,
              artist: t.artist,
              album: t.album,
              source: t.url,
              isLossless: t.fmt == 'FLAC' || t.fmt == 'WAV' || t.fmt == 'AIFF',
              fmt: t.fmt,
            ))
        .toList();
    try {
      await gHandler.loadQueue(list, index);
    } catch (e) {
      if (mounted) playErrorSnackBar(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PageHeader(
          _webMode ? '全网搜索' : '海量曲库',
          _webMode
              ? '搜索结果自动验证 · 每一首都免费可播'
              : 'Internet Archive · 数百万首公版音乐 · 优先无损格式',
        ),
        // 模式切换
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Row(
            children: [
              Expanded(child: _modeChip(true, '全网搜索', Icons.travel_explore)),
              const SizedBox(width: 8),
              Expanded(child: _modeChip(false, '公版曲库', Icons.album)),
            ],
          ),
        ),
        Expanded(child: _webMode ? _webBody() : _iaBody()),
      ],
    );
  }

  Widget _modeChip(bool mode, String label, IconData icon) {
    final sel = _webMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _webMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF12202b) : cCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: sel ? const Color(0xFF2a5a52) : Colors.transparent),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: sel ? cAccent : cDim),
            const SizedBox(width: 7),
            Text(label,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                    color: sel ? cAccent : cDim)),
          ],
        ),
      ),
    );
  }

  Widget _webBody() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _webCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _searchWeb(),
                  decoration: const InputDecoration(
                      hintText: '搜歌名 / 歌手，如：周杰伦',
                      prefixIcon: Icon(Icons.search, color: cDim)),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: cAccent,
                    foregroundColor: const Color(0xFF06231d),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12)),
                onPressed: _searchWeb,
                child: const Text('搜索'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            children: [
              for (final (label, srcs) in const [
                ('全网聚合（四源）', ['netease', 'qq', 'kuwo', 'bili']),
                ('网易云+QQ', ['netease', 'qq']),
                ('仅网易云', ['netease']),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _sources.length == srcs.length,
                    onSelected: (_) => setState(() => _sources = srcs),
                    labelStyle: TextStyle(
                        fontSize: 12.5,
                        color: _sources.length == srcs.length
                            ? cAccent
                            : cDim),
                    selectedColor: const Color(0xFF12202b),
                    backgroundColor: cCard,
                    side: BorderSide(
                        color: _sources.length == srcs.length
                            ? const Color(0xFF2a5a52)
                            : Colors.transparent),
                    showCheckmark: false,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(_webTitle,
                style: const TextStyle(color: cDim, fontSize: 12)),
          ),
        ),
        Expanded(
          child: _webLoading
              ? loadingBody('正在聚合全网曲库搜索…')
              : _webErr != null
                  ? errorBody(_webErr!, _searchWeb)
                  : _webResults.isEmpty
                      ? const Center(
                          child: Text('输入关键词，搜索全网上千万首免费歌曲',
                              style: TextStyle(color: cDim, fontSize: 13)))
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 12),
                          itemCount: _webResults.length,
                          itemExtent: 62,
                          itemBuilder: (c, i) => _webTile(_webResults[i], i),
                        ),
        ),
      ],
    );
  }

  Widget _webTile(WebTrack t, int index) {
    final isBili = t.src == 'bili';
    final srcName = isBili
        ? 'B站'
        : (t.src == 'qq'
            ? 'QQ'
            : (t.src == 'kuwo' ? '酷我' : '网易云'));
    final dur = t.duration > 0
        ? fmtTime(Duration(seconds: t.duration.round()))
        : '--:--';
    return InkWell(
      onTap: () => _playWeb(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                  color: cCard, borderRadius: BorderRadius.circular(6)),
              child: const Icon(Icons.graphic_eq, color: cAccent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Text(
                    '${t.artist}${!isBili && t.album.isNotEmpty ? ' · ${t.album}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: cDim, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Badge(srcName,
                isBili ? const Color(0xFF6ba9ff) : (t.src == 'qq' ? cPink : cAccent)),
            const SizedBox(width: 6),
            Text(dur, style: const TextStyle(color: cDim, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }

  Widget _iaBody() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(
                      hintText: '搜索公版音乐 / 艺术家',
                      prefixIcon: Icon(Icons.search, color: cDim)),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: cAccent,
                    foregroundColor: const Color(0xFF06231d),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12)),
                onPressed: _search,
                child: const Text('搜索'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            children: [
              for (final (col, name) in iaCollections)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(name),
                    selected: _collection == col,
                    onSelected: (_) => _browse(col, name),
                    labelStyle: TextStyle(
                        fontSize: 12.5,
                        color: _collection == col ? cAccent : cDim),
                    selectedColor: const Color(0xFF12202b),
                    backgroundColor: cCard,
                    side: BorderSide(
                        color: _collection == col
                            ? const Color(0xFF2a5a52)
                            : Colors.transparent),
                    showCheckmark: false,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(_title,
                style: const TextStyle(color: cDim, fontSize: 12)),
          ),
        ),
        Expanded(
          child: _loading
              ? loadingBody('正在获取曲目…')
              : _err != null
                  ? errorBody(_err!, () => _browse(_collection, _title))
                  : _tracks.isEmpty
                      ? const Center(
                          child: Text('没有找到曲目',
                              style: TextStyle(color: cDim, fontSize: 13)))
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 12),
                          itemCount: _tracks.length,
                          itemExtent: 62,
                          itemBuilder: (c, i) {
                            final t = _tracks[i];
                            final lossless =
                                t.fmt == 'FLAC' || t.fmt == 'WAV' || t.fmt == 'AIFF';
                            return InkWell(
                              onTap: () => _play(i),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 8),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(
                                          color: cCard,
                                          borderRadius: BorderRadius.circular(6)),
                                      child: const Icon(Icons.album,
                                          color: cAccent, size: 22),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(t.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14.5,
                                                  fontWeight: FontWeight.w500)),
                                          const SizedBox(height: 3),
                                          Text('${t.artist} · ${t.album}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  color: cDim, fontSize: 12)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (lossless) const Badge('无损', cGreen),
                                    const SizedBox(width: 6),
                                    Badge(t.fmt, cDim),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

// ---------------- 迷你播放条 ----------------
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: gHandler.mediaItem,
      builder: (context, snap) {
        final item = snap.data;
        if (item == null) return const SizedBox.shrink();
        return Material(
          color: cPanel,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StreamBuilder<Duration>(
                  stream: gHandler.positionStream,
                  builder: (context, ps) {
                    return StreamBuilder<Duration?>(
                      stream: gHandler.durationStream,
                      builder: (context, ds) {
                        final dur = ds.data;
                        final pos = ps.data ?? Duration.zero;
                        final v = (dur != null && dur.inMilliseconds > 0)
                            ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                            : null;
                        return LinearProgressIndicator(
                          value: v,
                          minHeight: 2,
                          backgroundColor: const Color(0xFF232d40),
                          valueColor: const AlwaysStoppedAnimation(cAccent),
                        );
                      },
                    );
                  },
                ),
                InkWell(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const PlayerPage())),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      children: [
                        StreamBuilder<PTrack?>(
                          stream: gHandler.mediaItem.map((m) => m == null
                              ? null
                              : gHandler.currentTrack),
                          builder: (context, s) {
                            final t = s.data;
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: SizedBox(
                                width: 42,
                                height: 42,
                                child: (t?.artId != null)
                                    ? QueryArtworkWidget(
                                        id: t!.artId!,
                                        type: ArtworkType.AUDIO,
                                        artworkWidth: 84,
                                        artworkHeight: 84,
                                        artworkFit: BoxFit.cover,
                                        quality: 50,
                                        nullArtworkWidget: Container(
                                          color: cCard,
                                          child: const Icon(
                                              Icons.music_note,
                                              color: cAccent,
                                              size: 20),
                                        ),
                                      )
                                    : Container(
                                        color: cCard,
                                        child: const Icon(Icons.graphic_eq,
                                            color: cAccent, size: 20)),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(
                                  child: Text(item.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600)),
                                ),
                                if (gHandler.currentTrack?.isLossless == true)
                                  const Badge('无损', cGreen)
                                else if (gHandler.currentTrack?.isLive == true)
                                  const Badge('直播', cPink),
                              ]),
                              const SizedBox(height: 2),
                              Text(item.artist ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      const TextStyle(color: cDim, fontSize: 11)),
                            ],
                          ),
                        ),
                        _miniCtrl(Icons.skip_previous, gHandler.skipToPrevious),
                        StreamBuilder<bool>(
                          stream: gHandler.playingStream,
                          builder: (context, s) {
                            final playing = s.data ?? false;
                            return _miniMain(playing);
                          },
                        ),
                        _miniCtrl(Icons.skip_next, gHandler.skipToNext),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _miniCtrl(IconData icon, Future<void> Function() onTap) {
    return IconButton(
      icon: Icon(icon, color: cText, size: 26),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _miniMain(bool playing) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(
          color: cAccent, borderRadius: BorderRadius.all(Radius.circular(21))),
      child: IconButton(
        icon: Icon(playing ? Icons.pause : Icons.play_arrow,
            color: const Color(0xFF06231d), size: 26),
        onPressed: () => playing ? gHandler.pause() : gHandler.play(),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ---------------- 全屏播放页 ----------------
class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: SafeArea(
        child: StreamBuilder<MediaItem?>(
          stream: gHandler.mediaItem,
          builder: (context, snap) {
            final item = snap.data;
            if (item == null) {
              return const Center(
                  child: Text('暂无播放',
                      style: TextStyle(color: cDim, fontSize: 14)));
            }
            final track = gHandler.currentTrack;
            final live = track?.isLive ?? false;
            return Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down,
                            color: cText, size: 30),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Text('正在播放',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cDim, fontSize: 13)),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        color: cCard,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 30,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: track?.artId != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: QueryArtworkWidget(
                                id: track!.artId!,
                                type: ArtworkType.AUDIO,
                                artworkWidth: 500,
                                artworkHeight: 500,
                                artworkFit: BoxFit.cover,
                                quality: 80,
                                size: 500,
                                nullArtworkWidget: const _BigArtFallback(),
                              ),
                            )
                          : const _BigArtFallback(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      Text(item.title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              height: 1.3)),
                      const SizedBox(height: 8),
                      Text(item.artist ?? '',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: cDim, fontSize: 14)),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (track?.isLossless == true) ...[
                            const Badge('无损音质', cGreen),
                            const SizedBox(width: 8),
                          ],
                          if (live) ...[
                            const Badge('直播中', cPink),
                            const SizedBox(width: 8),
                          ],
                          if (track?.fmt.isNotEmpty == true)
                            Badge(track!.fmt, cDim),
                          if (track != null && track.fmt.isEmpty && !live)
                            const Badge('在线流媒体', cDim),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                // 进度条
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: live
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text('电台直播 · 实时流',
                              style: TextStyle(color: cDim, fontSize: 12)),
                        )
                      : StreamBuilder<Duration>(
                          stream: gHandler.positionStream,
                          builder: (context, ps) {
                            return StreamBuilder<Duration?>(
                              stream: gHandler.durationStream,
                              builder: (context, ds) {
                                final dur = ds.data;
                                final pos = ps.data ?? Duration.zero;
                                final ms = dur?.inMilliseconds ?? 0;
                                return Column(children: [
                                  Slider(
                                    value: ms > 0
                                        ? pos.inMilliseconds
                                            .clamp(0, ms)
                                            .toDouble()
                                        : 0,
                                    max: ms > 0 ? ms.toDouble() : 1,
                                    onChanged: ms > 0
                                        ? (v) => gHandler
                                            .seek(Duration(milliseconds: v.toInt()))
                                        : null,
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(fmtTime(pos),
                                            style: const TextStyle(
                                                color: cDim, fontSize: 11)),
                                        Text(
                                            dur != null ? fmtTime(dur) : '--:--',
                                            style: const TextStyle(
                                                color: cDim, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                ]);
                              },
                            );
                          },
                        ),
                ),
                const SizedBox(height: 6),
                // 控制区
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.skip_previous,
                            color: cText, size: 38),
                        onPressed: gHandler.skipToPrevious,
                      ),
                      const SizedBox(width: 26),
                      Container(
                        decoration: const BoxDecoration(
                            color: cAccent, shape: BoxShape.circle),
                        child: StreamBuilder<bool>(
                          stream: gHandler.playingStream,
                          builder: (context, s) {
                            final playing = s.data ?? false;
                            return IconButton(
                              iconSize: 40,
                              icon: Icon(
                                  playing ? Icons.pause : Icons.play_arrow,
                                  color: const Color(0xFF06231d),
                                  size: 36),
                              onPressed: () => playing
                                  ? gHandler.pause()
                                  : gHandler.play(),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 26),
                      IconButton(
                        icon:
                            const Icon(Icons.skip_next, color: cText, size: 38),
                        onPressed: gHandler.skipToNext,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BigArtFallback extends StatelessWidget {
  const _BigArtFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cCard, cCard.withValues(alpha: 0.6)],
        ),
      ),
      child: const Icon(Icons.graphic_eq, color: cAccent, size: 84),
    );
  }
}
