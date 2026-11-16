import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'study_models.dart';

const emulatorOrigin = 'http://10.0.2.2:8080';
const usbOrigin = 'http://127.0.0.1:8080';
const configuredOrigin = String.fromEnvironment(
  'PASS_PACE_API_URL',
  defaultValue: kDebugMode ? emulatorOrigin : '',
);
const plannerPath = '/api/chat/planner/review-based';

String validOrigin(String raw) {
  final u = Uri.tryParse(raw.trim());
  if (u == null ||
      u.host.isEmpty ||
      u.userInfo.isNotEmpty ||
      u.hasQuery ||
      u.hasFragment ||
      (u.path.isNotEmpty && u.path != '/')) {
    throw const ApiError('서버 주소를 포트까지 입력해 주세요. 예: https://study.example.com');
  }
  const local = {'10.0.2.2', '127.0.0.1', 'localhost'};
  if (u.scheme != 'https' &&
      !(kDebugMode && u.scheme == 'http' && local.contains(u.host))) {
    throw const ApiError(
      'HTTPS 주소를 입력해 주세요. 개발 중에는 에뮬레이터 또는 USB 주소도 사용할 수 있어요.',
    );
  }
  return u.origin;
}

class ApiError implements Exception {
  final String message;
  final int? status;
  const ApiError(this.message, [this.status]);
  @override
  String toString() => message;
}

/// A study write may have committed. Check records before another request.
class StudySaveUncertain extends ApiError {
  const StudySaveUncertain({bool editing = false})
    : super(
        editing
            ? '수정 결과를 확인하지 못했어요. 이미 수정되었을 수 있으니 기록 목록을 먼저 확인해 주세요.'
            : '저장 결과를 확인하지 못했어요. 이미 저장되었을 수 있으니 기록 목록을 먼저 확인해 주세요.',
      );
}

class StudyDeleteUncertain extends ApiError {
  const StudyDeleteUncertain()
    : super('삭제 결과를 확인하지 못했어요. 이미 삭제되었을 수 있으니 기록 목록을 먼저 확인해 주세요.');
}

String friendly(Object e) =>
    e is ApiError ? e.message : '데이터를 읽지 못했어요. 잠시 후 다시 시도해 주세요.';

class PassApi {
  final http.Client client;
  final String origin;
  final String? token;
  final VoidCallback? onExpired;
  PassApi(this.client, this.origin, {this.token, this.onExpired});

  Future<Json> _send(
    String method,
    String path, {
    Json? body,
    int seconds = 18,
  }) async {
    final base = validOrigin(origin);
    final request = http.Request(method, Uri.parse(base).resolve(path))
      ..followRedirects = false;
    request.headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.bodyBytes = utf8.encode(jsonEncode(body));
    }
    try {
      final res = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(Duration(seconds: seconds));
      final status = res.statusCode;
      if (status == 401 && token != null) onExpired?.call();
      Json? envelope;
      try {
        envelope = object(jsonDecode(utf8.decode(res.bodyBytes)));
      } on FormatException {
        throw ApiError(
          status >= 500
              ? '서버가 응답하지 못했어요. 잠시 후 다시 시도해 주세요.'
              : 'PASS PACE 서버 응답을 확인할 수 없어요. 연결 주소를 확인해 주세요.',
          status,
        );
      }
      if (status < 200 || status >= 300 || envelope['status'] != 'SUCCESS') {
        final info = envelope['data'];
        final detail = info is Json ? info['detail'] : null;
        final ko = info is Json ? info['ko'] : null;
        final fallback = status == 401 ? '로그인 정보를 확인해 주세요.' : '요청을 처리하지 못했어요.';
        throw ApiError(
          status < 500 && detail is String && detail.trim().isNotEmpty
              ? detail
              : ko is String
              ? ko
              : fallback,
          status,
        );
      }
      return envelope['data'] == null
          ? <String, dynamic>{}
          : object(envelope['data']);
    } on TimeoutException {
      throw const ApiError('응답을 기다리는 시간이 길어졌어요. 서버 연결을 확인하고 다시 시도해 주세요.');
    } on http.ClientException {
      throw const ApiError('서버에 연결할 수 없어요. 서버 실행 상태와 연결 주소를 확인해 주세요.');
    } on IOException {
      throw const ApiError('서버에 연결할 수 없어요. 네트워크와 연결 주소를 확인해 주세요.');
    }
  }

  Future<String> login(String id, String password) async {
    final result = await _send(
      'POST',
      '/auth/login',
      body: {'loginId': id, 'password': password},
    );
    return result['accessToken'] as String;
  }

  Future<void> signup(Json form) => _send('POST', '/auth/signup', body: form);
  Future<Profile> profile() async =>
      Profile.from(await _send('GET', '/auth/user-info'));
  Future<SavedPlan?> saved() async {
    final data = await _send('GET', '$plannerPath/saved');
    return data['plan'] == null ? null : SavedPlan.from(object(data['plan']));
  }

  Future<GoalData> goal() async =>
      GoalData.from(await _send('GET', '/users/me/goal'));
  Future<void> updateGoal(Json form) =>
      _send('PUT', '/users/me/goal', body: form);
  Future<Catalog> catalog() async =>
      Catalog.from(await _send('GET', '$plannerPath/catalog'));
  Future<String> updateProfile(Json form) async {
    final data = await _send('PUT', '/users/me', body: form);
    return data['accessToken'] as String;
  }

  Future<Preview> preview(Json form) async =>
      Preview.from(await _send('POST', '$plannerPath/preview', body: form));
  Future<void> save(Json form) =>
      _send('POST', '$plannerPath/save', body: form);
  Future<Reply> chat(String message, int? conversation) async => Reply.from(
    await _send(
      'POST',
      '/api/chat',
      body: {'message': message, 'conId': conversation},
      seconds: 205,
    ),
  );

  Future<StudyRecord> saveStudySession(
    DateTime date,
    int minutes, {
    StudyTaskChoice? task,
  }) async {
    try {
      return StudyRecord.from(
        await _send(
          'POST',
          '/study/sessions',
          body: {
            'studyDate': isoDay(date),
            'durationMinutes': minutes,
            if (task != null) ...{
              'taskId': task.id,
              'expectedPlanVersion': task.planVersion,
            },
          },
        ),
      );
    } on ApiError catch (e) {
      if (e.status != null && e.status! >= 400 && e.status! < 500) rethrow;
      throw const StudySaveUncertain();
    } on FormatException {
      throw const StudySaveUncertain();
    } on TypeError {
      throw const StudySaveUncertain();
    }
  }

  Future<StudyRecord> updateStudySession(
    StudyRecord original,
    DateTime date,
    int minutes, {
    bool changeTask = false,
    StudyTaskChoice? task,
  }) async {
    try {
      final result = StudyRecord.from(
        await _send(
          'PATCH',
          '/study/sessions/${original.id}',
          body: {
            'studyDate': isoDay(date),
            'durationMinutes': minutes,
            'expectedStudyDate': isoDay(original.date),
            'expectedDurationMinutes': original.minutes,
            'expectedTask': {'taskId': original.taskId},
            if (changeTask)
              'taskLink': {
                'taskId': task?.id,
                'expectedPlanVersion': task?.planVersion,
                'expectedTaskId': original.taskId,
              },
          },
        ),
      );
      if (result.id != original.id ||
          result.date != date ||
          result.minutes != minutes ||
          (changeTask && result.taskId != task?.id)) {
        throw const FormatException('Unexpected updated study record');
      }
      return result;
    } on ApiError catch (e) {
      if (e.status != null && e.status! >= 400 && e.status! < 500) rethrow;
      throw const StudySaveUncertain(editing: true);
    } on FormatException {
      throw const StudySaveUncertain(editing: true);
    } on TypeError {
      throw const StudySaveUncertain(editing: true);
    }
  }

  Future<void> deleteStudySession(StudyRecord original) async {
    try {
      final data = await _send(
        'DELETE',
        '/study/sessions/${original.id}',
        body: {
          'expectedStudyDate': isoDay(original.date),
          'expectedDurationMinutes': original.minutes,
          'expectedTaskId': original.taskId,
        },
      );
      if (data['sessionId'] != original.id || data['deleted'] != true) {
        throw const FormatException('Unexpected deleted study record');
      }
    } on ApiError catch (e) {
      if (e.status != null && e.status! >= 400 && e.status! < 500) rethrow;
      throw const StudyDeleteUncertain();
    } on FormatException {
      throw const StudyDeleteUncertain();
    } on TypeError {
      throw const StudyDeleteUncertain();
    }
  }

  Future<StudyTaskPage> studyPlanTasks({
    DateTime? date,
    bool includeReplaced = false,
    int page = 0,
  }) async => StudyTaskPage.from(
    await _send(
      'GET',
      Uri(
        path: '/study/plan-tasks',
        queryParameters: {
          if (date != null) 'date': isoDay(date),
          'includeReplaced': '$includeReplaced',
          'page': '$page',
          'pageSize': '50',
        },
      ).toString(),
    ),
  );

  Future<StudyRecordPage> studySessions(
    DateTime start,
    DateTime end, {
    int page = 0,
    int pageSize = 20,
  }) async => StudyRecordPage.from(
    await _send(
      'GET',
      Uri(
        path: '/study/sessions',
        queryParameters: {
          'startDate': isoDay(start),
          'endDate': isoDay(end),
          'page': '$page',
          'pageSize': '$pageSize',
        },
      ).toString(),
    ),
  );

  Future<StudyStats> studyStats(DateTime start, DateTime end) async =>
      StudyStats.from(
        await _send(
          'GET',
          Uri(
            path: '/dashboard/study-stats',
            queryParameters: {
              'period': 'CUSTOM',
              'startDate': isoDay(start),
              'endDate': isoDay(end),
            },
          ).toString(),
        ),
      );
}
