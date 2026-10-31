import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.code, this.message, [this.details = const <String, dynamic>{}]);

  final int statusCode;
  final String code;
  final String message;
  final Map<String, dynamic> details;

  bool get isNetwork => statusCode == 0;
  bool get isAuth => statusCode == 401 || statusCode == 403;
  bool get isConflict => statusCode == 409;

  @override
  String toString() => message;
}

/// Thin JSON client. Every request carries the device id and — for project
/// scoped calls — the long lived project token.
class ApiClient {
  ApiClient({required String baseUrl}) : _baseUrl = _normalise(baseUrl);

  static const Duration defaultTimeout = Duration(seconds: 20);

  final http.Client _http = http.Client();
  String _baseUrl;
  String? deviceId;
  String? deviceSecret;

  String get baseUrl => _baseUrl;

  set baseUrl(String value) => _baseUrl = _normalise(value);

  static String _normalise(String value) {
    String url = value.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  void _assertSecure(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      throw ApiException(0, 'invalid_url', '服务器地址无效，请检查设置。');
    }
    if (uri.scheme == 'https') return;
    if (uri.scheme == 'http' && AppConfig.isLocalHost(uri)) return;
    throw ApiException(0, 'insecure_transport', '必须使用 HTTPS 地址，明文 HTTP 已被拒绝。');
  }

  Uri _buildUri(String path, Map<String, String>? query) {
    final Uri base = Uri.parse('$_baseUrl$path');
    if (query == null || query.isEmpty) return base;
    return base.replace(queryParameters: <String, String>{...base.queryParameters, ...query});
  }

  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    String? projectToken,
    bool withDeviceSecret = false,
    bool withDeviceId = true,
    Duration? timeout,
  }) async {
    final Uri uri = _buildUri(path, query);
    _assertSecure(uri.toString());

    final Map<String, String> headers = <String, String>{'Accept': 'application/json'};
    if (withDeviceId && deviceId != null) headers['X-Device-Id'] = deviceId!;
    if (withDeviceSecret && deviceSecret != null) headers['X-Device-Secret'] = deviceSecret!;
    if (projectToken != null && projectToken.isNotEmpty) headers['X-Project-Token'] = projectToken;
    if (body != null) headers['Content-Type'] = 'application/json; charset=utf-8';

    http.Response response;
    try {
      final http.Request request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final http.StreamedResponse streamed = await _http.send(request).timeout(timeout ?? defaultTimeout);
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException(0, 'timeout', '请求超时，操作未提交。请检查网络后重试。');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException(0, 'network', '网络连接失败，操作未提交。请检查网络后重试。');
    }

    dynamic decoded;
    final String text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        decoded = null;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    String code = 'http_${response.statusCode}';
    String message = '请求失败（${response.statusCode}）';
    Map<String, dynamic> details = const <String, dynamic>{};
    if (decoded is Map && decoded['error'] is Map) {
      final Map<dynamic, dynamic> error = decoded['error'] as Map<dynamic, dynamic>;
      code = '${error['code'] ?? code}';
      message = '${error['message'] ?? message}';
      if (error['details'] is Map) {
        details = Map<String, dynamic>.from(error['details'] as Map);
      }
    } else if (response.statusCode == 403) {
      message = '无权访问该项目，请重新扫码加入。';
    }
    throw ApiException(response.statusCode, code, message, details);
  }

  Future<dynamic> get(String path, {Map<String, String>? query, String? projectToken, bool withDeviceSecret = false}) =>
      request('GET', path, query: query, projectToken: projectToken, withDeviceSecret: withDeviceSecret);

  Future<dynamic> post(
    String path, {
    Object? body,
    String? projectToken,
    bool withDeviceSecret = false,
    bool withDeviceId = true,
    Map<String, String>? query,
    Duration? timeout,
  }) =>
      request('POST', path, body: body, projectToken: projectToken, withDeviceSecret: withDeviceSecret, withDeviceId: withDeviceId, query: query, timeout: timeout);

  Future<dynamic> patch(String path, {Object? body, String? projectToken}) =>
      request('PATCH', path, body: body, projectToken: projectToken);

  Future<dynamic> delete(String path, {Object? body, String? projectToken}) =>
      request('DELETE', path, body: body, projectToken: projectToken);
}
