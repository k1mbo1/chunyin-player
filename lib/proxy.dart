// 本地 HTTP 代理 —— 解决 iOS（AVPlayer）不支持自定义请求头的问题
// B 站直链必须带 Referer 防盗链；AVPlayer 无法附加 headers，
// 故在本机起一个极简流式代理：播放器请求 127.0.0.1，代理转发时补上
// Referer/UA，并透传 Range 分段（保证进度拖动、边下边播）。
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

int? _port;
int _seq = 0;
final _routes = <String, ({String url, Map<String, String> headers})>{};
final http.Client _client = http.Client();

const _passHeaders = [
  HttpHeaders.contentTypeHeader,
  HttpHeaders.contentLengthHeader,
  HttpHeaders.contentRangeHeader,
  HttpHeaders.acceptRangesHeader,
];

Future<int> _ensureServer() async {
  final p = _port;
  if (p != null) return p;
  final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  _port = s.port;
  unawaited(_serve(s));
  return s.port;
}

/// 为带自定义头的直链生成本机代理地址；headers 为空时原样返回
Future<String> proxiedUrl(String url, Map<String, String> headers) async {
  if (headers.isEmpty) return url;
  final port = await _ensureServer();
  final id = 'r${_seq++}';
  _routes[id] = (url: url, headers: headers);
  return 'http://127.0.0.1:$port/p/$id';
}

Future<void> _serve(HttpServer s) async {
  await for (final req in s) {
    _handle(req).catchError((_) async {
      try {
        req.response.statusCode = 502;
        await req.response.close();
      } catch (_) {}
    });
  }
}

Future<void> _handle(HttpRequest req) async {
  final segs = req.uri.pathSegments;
  final route = segs.length == 2 && segs[0] == 'p' ? _routes[segs[1]] : null;
  if (route == null) {
    req.response.statusCode = 404;
    await req.response.close();
    return;
  }
  final headers = {...route.headers};
  final range = req.headers.value(HttpHeaders.rangeHeader);
  if (range != null) headers['Range'] = range;
  final up = http.Request('GET', Uri.parse(route.url))
    ..headers.addAll(headers)
    ..followRedirects = true;
  final rs = await _client.send(up).timeout(const Duration(seconds: 20));
  req.response.statusCode = rs.statusCode;
  for (final k in _passHeaders) {
    final v = rs.headers[k];
    if (v != null) req.response.headers.set(k, v);
  }
  req.response.bufferOutput = false;
  await rs.stream.pipe(req.response);
}
