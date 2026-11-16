import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/api.dart';
import '../data/session.dart';

// Display only. The existing server authorizes every administrator request.
bool showsAdminPage(Session session, {DateTime? now}) {
  final token = session.account?.token, user = session.user;
  if (token == null || user == null) return false;
  try {
    final parts = token.split('.');
    if (parts.length != 3) return false;
    final data = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (data is! Map<String, dynamic>) return false;
    final expiry = data['exp'];
    return data['role'] == 'ADMIN' &&
        data['loginId'] == user.id &&
        expiry is num &&
        expiry.isFinite &&
        expiry * 1000 > (now ?? DateTime.now()).millisecondsSinceEpoch;
  } on FormatException {
    return false;
  }
}

/// Adapter for the existing form-based admin endpoints; no session is stored here.
class AdminApi extends ChangeNotifier {
  final Session session;
  bool _forbidden = false;
  bool _disposed = false;
  AdminApi(this.session);
  static const _reads = {
    '/db-status',
    '/data/summary',
    '/data/reviews',
    '/sources',
    '/reviews/status',
    '/naver/status',
    '/status/by-cert',
    '/reviews/recovery-report',
    '/reviews/reset',
  };
  static const _writes = {
    '/exam',
    '/sqld-schedule',
    '/manual/dataq-schedule',
    '/reference-stats',
    '/reviews/start',
    '/reviews/cancel',
    '/naver/start',
    '/naver/cancel',
    '/sources/velog-keyword',
    '/sources/tistory-keyword',
    '/sources/naver-keyword',
    '/sources/urls',
    '/sources/remove',
    '/sources/inspect',
    '/reviews/preview',
    '/reviews/discover',
    '/reviews/reset',
  };
  bool get accessible => !_disposed && !_forbidden && showsAdminPage(session);
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<Object?> get(String path, [Map<String, String> query = const {}]) =>
      _request('GET', path, query: query);
  Future<Object?> post(String path, [Map<String, String> fields = const {}]) =>
      _request('POST', path, fields: fields);
  Future<Object?> _request(
    String method,
    String path, {
    Map<String, String> query = const {},
    Map<String, String> fields = const {},
  }) async {
    if (!(method == 'GET' ? _reads : _writes).contains(path)) {
      throw const ApiError('지원하지 않는 관리자 요청입니다.');
    }
    if (!accessible) throw const ApiError('관리자 권한이 없거나 로그인이 만료되었어요.', 403);
    final account = session.account!;
    final base = validOrigin(account.origin);
    final relative = Uri(
      path: '/admin/collect$path',
      queryParameters: query.isEmpty ? null : query,
    );
    final request = http.Request(method, Uri.parse(base).resolveUri(relative))
      ..followRedirects = false;
    request.headers.addAll({
      'Accept': 'application/json',
      'Authorization': 'Bearer ${account.token}',
    });
    if (fields.isNotEmpty) request.bodyFields = fields;
    try {
      final response = await session.client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(Duration(seconds: method == 'GET' ? 18 : 205));
      if (!identical(account, session.account)) {
        throw const ApiError('로그인 정보가 변경되었어요. 관리 화면을 다시 열어 주세요.', 401);
      }
      if (response.statusCode == 401) {
        account.onExpired?.call();
        throw const ApiError('로그인이 만료되었어요. 다시 로그인해 주세요.', 401);
      }
      if (response.statusCode == 403) {
        _forbidden = true;
        if (!_disposed) notifyListeners();
        throw const ApiError('관리자 권한이 없어 이 기능을 사용할 수 없어요.', 403);
      }
      if (!accessible) {
        throw const ApiError('관리자 권한이 없거나 관리 화면이 닫혔어요.', 403);
      }
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw const ApiError('서버 응답 주소를 확인해 주세요. 관리자 요청은 다른 주소로 이동하지 않아요.');
      }
      final raw = jsonDecode(utf8.decode(response.bodyBytes));
      if (raw is! Map<String, dynamic>) throw const FormatException();
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          raw['status'] != 'SUCCESS') {
        final data = raw['data'];
        final message = data is Map ? data['detail'] ?? data['ko'] : null;
        throw ApiError(
          response.statusCode < 500 && message is String
              ? message
              : '관리자 요청을 처리하지 못했어요. 서버 상태를 확인해 주세요.',
          response.statusCode,
        );
      }
      return raw['data'];
    } on TimeoutException {
      throw const ApiError(
        '응답을 기다리는 시간이 길어졌어요. 실행한 작업은 서버에서 계속될 수 있으니 상태를 확인해 주세요.',
      );
    } on http.ClientException {
      throw const ApiError('서버에 연결하지 못했어요. 연결 상태를 확인해 주세요.');
    } on IOException {
      throw const ApiError('서버에 연결하지 못했어요. 네트워크를 확인해 주세요.');
    } on FormatException {
      throw const ApiError('관리자 응답을 읽지 못했어요. 서버 연결 주소를 확인해 주세요.');
    }
  }
}
