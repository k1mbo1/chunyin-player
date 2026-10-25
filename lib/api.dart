// 纯音播放器手机版 —— 在线音源 API
// 与 PC 版同款：Radio Browser 全球电台 + Internet Archive 海量曲库
import 'dart:convert';
import 'package:http/http.dart' as http;

const _ua = 'ChunYinMobile/1.0';

Map<String, String> get _headers => {'User-Agent': _ua};

const _rbServers = [
  'https://de1.api.radio-browser.info',
  'https://de2.api.radio-browser.info',
  'https://fi1.api.radio-browser.info',
];

class RadioStation {
  final String name, url, country, favicon;
  final int bitrate;
  RadioStation(this.name, this.url, this.country, this.bitrate, this.favicon);
}

class IaTrack {
  final String title, artist, album, url, fmt;
  IaTrack(this.title, this.artist, this.album, this.url, this.fmt);
}

Future<String> _rbBase() async {
  for (final s in _rbServers) {
    try {
      final r = await http
          .get(Uri.parse('$s/json/stations/topclick?limit=1'), headers: _headers)
          .timeout(const Duration(seconds: 6));
      if (r.statusCode == 200) return s;
    } catch (_) {}
  }
  return _rbServers[0];
}

Future<List<RadioStation>> fetchRadioStations(
    {String country = '', int limit = 300}) async {
  final base = await _rbBase();
  final q = {
    'limit': '$limit',
    'order': 'votes',
    'reverse': 'true',
    'hidebroken': 'true',
    if (country.isNotEmpty) 'country': country,
  };
  final uri = Uri.parse('$base/json/stations/search').replace(queryParameters: q);
  final r = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
  if (r.statusCode != 200) throw Exception('电台目录暂时不可用');
  final data = json.decode(utf8.decode(r.bodyBytes)) as List;
  return data
      .map((s) => RadioStation(
            ((s['name'] ?? '') as String).replaceAll(RegExp(r'\s+'), ' ').trim(),
            ((s['url_resolved'] ?? s['url'] ?? '') as String).trim(),
            (s['country'] ?? '') as String,
            (s['bitrate'] ?? 0) as int,
            (s['favicon'] ?? '') as String,
          ))
      .where((s) => s.url.isNotEmpty && s.name.isNotEmpty)
      .toList();
}

Future<List<RadioStation>> searchRadio(String keyword) async {
  final base = await _rbBase();
  final q = {
    'name': keyword,
    'limit': '100',
    'order': 'votes',
    'reverse': 'true',
    'hidebroken': 'true',
  };
  final uri = Uri.parse('$base/json/stations/search').replace(queryParameters: q);
  final r = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
  if (r.statusCode != 200) throw Exception('搜索失败');
  final data = json.decode(utf8.decode(r.bodyBytes)) as List;
  return data
      .map((s) => RadioStation(
            ((s['name'] ?? '') as String).replaceAll(RegExp(r'\s+'), ' ').trim(),
            ((s['url_resolved'] ?? s['url'] ?? '') as String).trim(),
            (s['country'] ?? '') as String,
            (s['bitrate'] ?? 0) as int,
            (s['favicon'] ?? '') as String,
          ))
      .where((s) => s.url.isNotEmpty)
      .toList();
}

// ---------------- Internet Archive ----------------

const iaCollections = [
  ('etree', '现场音乐 Live Music'),
  ('78rpm', '78 转老唱片'),
  ('audio_music', '音乐库'),
  ('netlabels', '独立厂牌'),
];

Future<List<String>> _iaSearchIdents(String query, int rows) async {
  final uri = Uri.parse('https://archive.org/advancedsearch.php').replace(
    queryParameters: {
      'q': '($query) AND mediatype:(audio)',
      'fl[]': 'identifier',
      'rows': '$rows',
      'page': '1',
      'output': 'json',
      'sort[]': 'downloads desc',
    },
  );
  final r = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
  if (r.statusCode != 200) throw Exception('Internet Archive 暂时不可用');
  final data = json.decode(utf8.decode(r.bodyBytes));
  final docs = (data['response']?['docs'] ?? []) as List;
  return docs.map((d) => d['identifier'] as String).toList();
}

Future<List<IaTrack>> _iaTracksFromIdent(String ident) async {
  final r = await http.get(Uri.parse('https://archive.org/metadata/$ident'),
      headers: _headers);
  if (r.statusCode != 200) return [];
  final meta = json.decode(utf8.decode(r.bodyBytes));
  final files = (meta['files'] ?? []) as List;
  const prefer = {'.flac': 5, '.wav': 4, '.aiff': 4, '.m4a': 3, '.mp3': 3, '.ogg': 2};
  final cands = <(int, Map)>[];
  for (final f in files) {
    final name = (f['name'] ?? '') as String;
    if (name.contains('/')) continue;
    final ext = name.contains('.') ? '.${name.split('.').last.toLowerCase()}' : '';
    if (!prefer.containsKey(ext)) continue;
    var score = prefer[ext]!;
    if (f['source'] == 'original' && (ext == '.flac' || ext == '.wav')) score += 2;
    cands.add((score, f as Map));
  }
  cands.sort((a, b) => b.$1.compareTo(a.$1));
  return cands.take(2).map((c) {
    final f = c.$2;
    final name = f['name'] as String;
    final ext = name.contains('.') ? name.split('.').last.toUpperCase() : 'AUDIO';
    final url = 'https://archive.org/download/$ident/${Uri.encodeComponent(name)}';
    return IaTrack(
      name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name,
      'Internet Archive',
      ident,
      url,
      ext,
    );
  }).toList();
}

Future<List<IaTrack>> iaSearch(String keyword) async {
  final idents = await _iaSearchIdents(keyword, 25);
  final out = <IaTrack>[];
  for (final id in idents) {
    if (out.length >= 40) break;
    try {
      out.addAll(await _iaTracksFromIdent(id));
    } catch (_) {}
  }
  return out;
}

Future<List<IaTrack>> iaBrowse(String collection) async {
  final idents = await _iaSearchIdents('collection:($collection)', 20);
  final out = <IaTrack>[];
  for (final id in idents) {
    if (out.length >= 40) break;
    try {
      out.addAll(await _iaTracksFromIdent(id));
    } catch (_) {}
  }
  return out;
}

// ---------------- 全网聚合搜索 + 多源自动兜底播放 ----------------
// 与 PC 版同款链路：
//   搜索聚合：网易云 + QQ（曲库覆盖最全，结果全量显示、不过滤）
//   播放解析：优先原平台直链（网易云 outer/url 非VIP）；
//             失败自动按“歌名 歌手”跨平台匹配免费来源，
//             并校验直链完整性（拒绝试听片段）

const _webHeaders = {
  'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
};

class WebTrack {
  final String title, artist, album, src, rid;
  final double duration; // 秒
  const WebTrack(this.title, this.artist, this.album, this.duration, this.src, this.rid);
}

String _webUnescape(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('\\u0026', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .trim();

/// Python 字面量（单引号 dict）→ JSON 文本
String _pyLitToJson(String s) {
  final sb = StringBuffer();
  var inStr = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (!inStr) {
      if (c == "'") {
        inStr = true;
        sb.write('"');
      } else {
        sb.write(c);
      }
    } else if (c == r'\' && i + 1 < s.length) {
      final n = s[i + 1];
      if (n == "'") {
        sb.write("'");
      } else if (n == '"') {
        sb.write(r'\"');
      } else if (n == r'\') {
        sb.write(r'\\');
      } else if (n == 'n' || n == 't') {
        sb.write(r'\');
        sb.write(n);
      } else if (n == 'u' && i + 6 <= s.length) {
        sb.write(r'\u');
        sb.write(s.substring(i + 2, i + 6));
        i += 4;
      } else {
        sb.write(n);
      }
      i++;
    } else if (c == "'") {
      inStr = false;
      sb.write('"');
    } else if (c == '"') {
      sb.write(r'\"');
    } else {
      sb.write(c);
    }
  }
  return sb.toString();
}

Future<List<WebTrack>> kuwoSearch(String keyword, {int n = 30}) async {
  final uri = Uri.http('search.kuwo.cn', '/r.s', {
    'all': keyword,
    'ft': 'music',
    'itemset': 'web_2013',
    'client': 'kt',
    'pn': '0',
    'rn': '$n',
    'rformat': 'json',
    'encoding': 'utf8',
  });
  final r =
      await http.get(uri, headers: _webHeaders).timeout(const Duration(seconds: 12));
  final data = json.decode(_pyLitToJson(utf8.decode(r.bodyBytes).trim()));
  final list = (data['abslist'] ?? []) as List;
  final out = <WebTrack>[];
  for (final t in list.take(n)) {
    final rid = ((t['MUSICRID'] ?? '') as String).replaceAll('MUSIC_', '');
    if (rid.isEmpty) continue;
    final dur = double.tryParse('${t['DURATION'] ?? ''}') ?? 0;
    out.add(WebTrack(
      _webUnescape('${t['SONGNAME'] ?? ''}'),
      _webUnescape('${t['ARTIST'] ?? ''}'),
      _webUnescape('${t['ALBUM'] ?? ''}'),
      dur,
      'kuwo',
      rid,
    ));
  }
  return out;
}

Future<List<WebTrack>> neteaseSearch(String keyword, {int n = 30}) async {
  final uri = Uri.https('music.163.com', '/api/search/get/web', {
    's': keyword,
    'type': '1',
    'offset': '0',
    'limit': '$n',
    'total': 'true',
  });
  final r = await http
      .get(uri, headers: {..._webHeaders, 'Referer': 'https://music.163.com/'})
      .timeout(const Duration(seconds: 12));
  final data = json.decode(utf8.decode(r.bodyBytes));
  final songs = (data['result']?['songs'] ?? []) as List;
  final out = <WebTrack>[];
  for (final s in songs.take(n)) {
    final sid = '${s['id'] ?? ''}';
    if (sid.isEmpty) continue;
    final artists = (s['artists'] ?? []) as List;
    final artist = artists.take(2).map((a) => '${a['name'] ?? ''}').join('/');
    final dur = ((s['duration'] ?? 0) as num) / 1000.0;
    out.add(WebTrack(
      '${s['name'] ?? ''}',
      artist,
      '${s['album']?['name'] ?? ''}',
      dur,
      'netease',
      sid,
    ));
  }
  return out;
}

Future<List<WebTrack>> qqSearch(String keyword, {int n = 30}) async {
  final body = json.encode({
    'req_1': {
      'method': 'DoSearchForQQMusicDesktop',
      'module': 'music.search.SearchCgiService',
      'param': {
        'search_type': 0,
        'query': keyword,
        'page_num': 1,
        'num_per_page': n,
      },
    },
  });
  final r = await http
      .post(Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg'),
          headers: {
            ..._webHeaders,
            'Content-Type': 'application/json',
            'Referer': 'https://y.qq.com/',
          },
          body: body)
      .timeout(const Duration(seconds: 12));
  final data = json.decode(utf8.decode(r.bodyBytes));
  final songs = (data['req_1']?['data']?['body']?['song']?['list'] ?? []) as List;
  final out = <WebTrack>[];
  for (final s in songs.take(n)) {
    final mid = '${s['mid'] ?? ''}';
    if (mid.isEmpty) continue;
    final singers = (s['singer'] ?? []) as List;
    final artist = singers.take(2).map((a) => '${a['name'] ?? ''}').join('/');
    var dur = (s['interval'] ?? -1) as int;
    if (dur < 0) dur = (((s['duration'] ?? 0) as num) / 1000).round();
    out.add(WebTrack(
      _webUnescape('${s['name'] ?? ''}'),
      artist,
      _webUnescape('${s['album']?['name'] ?? ''}'),
      dur.toDouble(),
      'qq',
      mid,
    ));
  }
  return out;
}

/// 全网聚合搜索（网易云 + QQ + B站）：交错合并 + (title, artist) 去重，
/// 结果全量显示、不过滤
Future<List<WebTrack>> webSearch(String keyword,
    {List<String> sources = const ['netease', 'qq', 'bili']}) async {
  Future<List<WebTrack>> shield(Future<List<WebTrack>> f) => f
      .timeout(const Duration(seconds: 15), onTimeout: () => <WebTrack>[])
      .catchError((_) => <WebTrack>[]);
  final futures = <Future<List<WebTrack>>>[];
  for (final src in sources) {
    if (src == 'netease') futures.add(shield(neteaseSearch(keyword)));
    if (src == 'qq') futures.add(shield(qqSearch(keyword)));
    if (src == 'bili') futures.add(shield(biliSearch(keyword)));
  }
  final lists = await Future.wait(futures);
  final merged = <WebTrack>[];
  var maxLen = 0;
  for (final l in lists) {
    if (l.length > maxLen) maxLen = l.length;
  }
  for (var i = 0; i < maxLen; i++) {
    for (final l in lists) {
      if (i < l.length) merged.add(l[i]);
    }
  }
  final seen = <String>{};
  final out = <WebTrack>[];
  for (final t in merged) {
    final key = '${t.title}\u0000${t.artist}';
    if (seen.contains(key)) continue;
    seen.add(key);
    out.add(t);
  }
  return out;
}

// ---------------- B 站音源（视频稿件音频轨，含 Hi-Res 无损） ----------------
// 链路（免登录）：finger/spi 拿 buvid3/buvid4 → search/type 搜索 →
//                view 拿 cid → player/playurl 拿 DASH 音频直链（需带 Referer）

const _biliUa = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/89.0.4389.90 Safari/537.36';
String? _biliB3;
String? _biliB4;

Future<void> _biliCookie() async {
  if (_biliB3 != null) return;
  final r = await http.get(
      Uri.parse('https://api.bilibili.com/x/frontend/finger/spi'),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) '
                'AppleWebKit/605.1.15',
      }).timeout(const Duration(seconds: 12));
  final d = json.decode(utf8.decode(r.bodyBytes));
  _biliB3 = '${d['data']['b_3']}';
  _biliB4 = '${d['data']['b_4']}';
}

double _biliDur(dynamic s) {
  if (s is num) return s.toDouble();
  var sec = 0;
  for (final p in '$s'.split(':')) {
    final v = int.tryParse(p.trim());
    if (v == null) return 0;
    sec = sec * 60 + v;
  }
  return sec.toDouble();
}

Future<List<WebTrack>> biliSearch(String keyword, {int n = 30}) async {
  await _biliCookie();
  final uri = Uri.https('api.bilibili.com', '/x/web-interface/search/type', {
    'context': '',
    'page': '1',
    'order': '',
    'page_size': '${n < 50 ? n : 50}',
    'keyword': keyword,
    'duration': '',
    'tids_1': '',
    'tids_2': '',
    '__refresh__': 'true',
    '_extra': '',
    'highlight': '1',
    'single_column': '0',
    'platform': 'pc',
    'from_source': '',
    'search_type': 'video',
    'dynamic_offset': '0',
  });
  final r = await http.get(uri, headers: {
    'User-Agent': _biliUa,
    'Accept': 'application/json, text/plain, */*',
    'Origin': 'https://search.bilibili.com',
    'Referer': 'https://search.bilibili.com/',
    'Cookie': 'buvid3=$_biliB3;buvid4=$_biliB4',
  }).timeout(const Duration(seconds: 15));
  final data = json.decode(utf8.decode(r.bodyBytes));
  final result = (data['data']?['result'] ?? []) as List;
  final out = <WebTrack>[];
  for (final it in result.take(n)) {
    final bvid = '${it['bvid'] ?? ''}';
    final aid = '${it['aid'] ?? 0}';
    if (bvid.isEmpty && aid == '0') continue;
    final title = (it['title'] ?? '')
        .toString()
        .replaceAll(RegExp(r'<em[^>]*>|</em>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
    out.add(WebTrack(
      title,
      '${it['author'] ?? 'B站UP主'}',
      bvid,
      _biliDur(it['duration']),
      'bili',
      '$bvid|$aid|${it['cid'] ?? 0}',
    ));
  }
  return out;
}

/// 播放直链解析结果：url + 播放所需 HTTP 头（B站 Referer 防盗链）
class ResolvedUrl {
  final String url;
  final Map<String, String> headers;
  const ResolvedUrl(this.url, this.headers);
}

Future<ResolvedUrl?> biliResolve(String rid) async {
  final parts = rid.split('|');
  final bvid = parts.isNotEmpty ? parts[0] : '';
  final aid = parts.length > 1 ? parts[1] : '';
  var cid = parts.length > 2 ? parts[2] : '';
  if (cid.isEmpty || cid == '0') {
    final q = bvid.isNotEmpty
        ? {'bvid': bvid}
        : {'aid': aid};
    final v = await http
        .get(
            Uri.https('api.bilibili.com', '/x/web-interface/view', q),
            headers: {'User-Agent': _biliUa})
        .timeout(const Duration(seconds: 12));
    cid = '${json.decode(utf8.decode(v.bodyBytes))['data']?['cid'] ?? 0}';
  }
  final pu = await http
      .get(
          Uri.https('api.bilibili.com', '/x/player/playurl',
              {'bvid': bvid, 'aid': aid, 'cid': cid, 'fnval': '272'}),
          headers: {'User-Agent': _biliUa})
      .timeout(const Duration(seconds: 12));
  final d = json.decode(utf8.decode(pu.bodyBytes))['data'] ?? {};
  final dash = d['dash'] ?? {};
  String? url;
  final flac = dash['flac'];
  if (flac is Map && (flac['audio'] ?? []).isNotEmpty) {
    url = '${flac['audio'][0]['baseUrl']}';
  }
  url ??= (() {
    final audios = (dash['audio'] ?? []) as List;
    if (audios.isEmpty) return null;
    dynamic best = audios[0];
    for (final a in audios) {
      if ((a['bandwidth'] ?? 0) > (best['bandwidth'] ?? 0)) best = a;
    }
    return '${best['baseUrl']}';
  })();
  url ??= (((d['durl'] ?? []) as List).isNotEmpty)
      ? '${d['durl'][0]['url']}'
      : null;
  if (url == null || url.isEmpty) return null;
  final page = bvid.isNotEmpty ? bvid : 'av$aid';
  return ResolvedUrl(url, {
    'Referer': 'https://www.bilibili.com/video/$page',
    'User-Agent': _biliUa,
  });
}



String _norm(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

/// 去掉歌名尾部括注（Live/DJ版/年份等），便于跨版本匹配
String _cleanTitle(String t) {
  var prev = '';
  var s = t.trim();
  while (prev != s) {
    prev = s;
    s = s.replaceAll(RegExp(r'[（(][^（）()]*[）)]\s*$'), '').trim();
  }
  return s;
}

/// 取第一歌手（'蔡依林/周杰伦' → '蔡依林'）
String _firstArtist(String a) =>
    a.split(RegExp(r'[/&,，、]| feat\.? ', caseSensitive: false)).first.trim();

bool _coverMark(String t) =>
    RegExp(r'cover|翻唱|翻奏|翻自|片段|秒版|铃声|伴奏|DJ版', caseSensitive: false)
        .hasMatch(t);

/// 候选与目标曲目的相似打分；歌名不匹配返回 -1
double _matchScore(WebTrack c, String title, String artist, double duration) {
  final nt = _norm(_cleanTitle(c.title)), t = _norm(_cleanTitle(title));
  if (nt.isEmpty || t.isEmpty) return -1;
  double score;
  if (nt == t) {
    score = 10;
  } else if ((nt.contains(t) || t.contains(nt)) &&
      nt.length <= (t.length * 3 > t.length + 4 ? t.length * 3 : t.length + 4)) {
    score = 6; // 歌名含目标（串烧/加长版等）
  } else if (nt.contains(t) || t.contains(nt)) {
    score = 4;
  } else {
    return -1;
  }
  final na = _norm(c.artist), a = _norm(_firstArtist(artist));
  if (na.isNotEmpty && a.isNotEmpty) {
    if (na == a) {
      score += 4;
    } else if (na.contains(a) || a.contains(na)) {
      score += 2;
    }
  } else {
    score *= 0.6; // 歌手完全不相关（多为翻唱）
  }
  if (_coverMark(c.title)) score *= 0.5; // 翻唱/片段降权
  if (duration > 0 && c.duration > 0) {
    final diff = (c.duration - duration).abs();
    if (diff <= 5) {
      score += 3;
    } else if (diff <= 15) {
      score += 1;
    }
  }
  return score;
}

/// HEAD 检查直链大小，推算时长是否接近目标（过滤平台返回的试听片段）
Future<bool> _urlLooksFull(String url, double duration) async {
  if (url.isEmpty || duration <= 0 || duration < 30) return true;
  try {
    final req = http.Request('HEAD', Uri.parse(url));
    req.headers.addAll(_webHeaders);
    final rs = await http.Client().send(req).timeout(const Duration(seconds: 8));
    final cl = int.tryParse(rs.headers['content-length'] ?? '') ?? 0;
    if (cl <= 0) return true;
    // 按最低 96kbps 估算可达的最大时长；仍不足目标 60% 必为片段
    final estMaxSec = cl * 8 / 96000;
    return estMaxSec >= duration * 0.6;
  } catch (_) {
    return true; // HEAD 不可用时不阻塞播放
  }
}

/// 多源自动兜底解析：优先原平台直链，失败则按“歌名 歌手”
/// 跨平台匹配免费可播来源（多级降级 + 直链完整性校验）。
/// 返回 ResolvedUrl（B站直链含播放所需 Referer 头）
Future<ResolvedUrl?> webResolveAuto(String title, String artist, String src,
    String rid, double duration) async {
  if (src == 'bili') {
    try {
      return await biliResolve(rid);
    } catch (_) {
      return null;
    }
  }
  final url = await webResolve(src, rid);
  if (url != null) return ResolvedUrl(url, const {});
  final a1 = _firstArtist(artist);
  final t1 = _cleanTitle(title);
  final queries = ['$title $a1', '$t1 $a1', t1];
  final tried = <String>{};
  for (final q in queries) {
    if (q.trim().isEmpty) continue;
    List<WebTrack> cands;
    try {
      cands = await kuwoSearch(q, n: 8);
    } catch (_) {
      continue;
    }
    final scored = <(double, WebTrack)>[];
    for (final c in cands) {
      final s = _matchScore(c, title, artist, duration);
      if (s >= 3 && !tried.contains(c.rid)) scored.add((s, c));
    }
    scored.sort((x, y) => y.$1.compareTo(x.$1));
    // 依次尝试高分候选，直链需通过完整性校验（拒绝试听片段）
    for (final (_, c) in scored.take(4)) {
      tried.add(c.rid);
      final u = await webResolve('kuwo', c.rid);
      if (u != null &&
          await _urlLooksFull(u, duration > 0 ? duration : c.duration)) {
        return ResolvedUrl(u, const {});
      }
    }
  }
  return null;
}

/// 获取播放直链（时效性数小时）；失败返回 null（VIP/下架曲目）
Future<String?> webResolve(String src, String rid) async {
  try {
    if (src == 'kuwo') {
      final uri = Uri.http('antiserver.kuwo.cn', '/anti.s', {
        'type': 'convert_url3',
        'rid': 'MUSIC_$rid',
        'format': 'mp3',
        'br': '320kmp3',
      });
      final r = await http
          .get(uri, headers: _webHeaders)
          .timeout(const Duration(seconds: 12));
      final m = RegExp(r'''https?://[^\s"'<>]+''').firstMatch(r.body);
      return m?.group(0);
    }
    if (src == 'netease') {
      final url = 'https://music.163.com/song/media/outer/url?id=$rid.mp3';
      final req = http.Request('GET', Uri.parse(url))..followRedirects = false;
      req.headers.addAll(_webHeaders);
      final rs =
          await http.Client().send(req).timeout(const Duration(seconds: 12));
      if (rs.statusCode == 200) return url;
      final loc = rs.headers['location'] ?? '';
      if ((rs.statusCode == 301 || rs.statusCode == 302) &&
          loc.isNotEmpty &&
          !loc.contains('404')) {
        return loc;
      }
      return null;
    }
  } catch (_) {}
  return null;
}
