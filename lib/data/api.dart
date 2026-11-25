import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'study_models.dart';
import 'study_timer.dart';
import 'whole_plan.dart';

const emulatorOrigin = 'http://10.0.2.2:8082';
const usbOrigin = 'http://127.0.0.1:8082';
const configuredOrigin = String.fromEnvironment(
  'PASS_PACE_API_URL',
  defaultValue: kDebugMode ? emulatorOrigin : '',
);
const plannerPath = '/api/chat/planner/review-based';
const planTimerBlockedMessage =
    '기록 탭에서 타이머를 멈추고 측정 시간을 저장하거나 초기화한 뒤 계획을 변경해 주세요.';

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

/// The server may have withdrawn the account. Never resend automatically.
class AccountWithdrawalUncertain extends ApiError {
  const AccountWithdrawalUncertain()
    : super(
        '회원탈퇴 결과를 확인하지 못했어요. 이미 처리되었을 수 있어요. '
        '자동으로 다시 요청하지 않으니 연결 상태를 확인하고 다시 로그인해 계정 상태를 확인해 주세요.',
      );
}

String friendly(Object e) =>
    e is ApiError ? e.message : '데이터를 읽지 못했어요. 잠시 후 다시 시도해 주세요.';

class PassApi {
  final http.Client client;
  final String origin;
  final String? token;
  final VoidCallback? onExpired;
  PassApi(this.client, this.origin, {this.token, this.onExpired});

  StudyTimer? planTimer;
  bool _changingPlan = false;
  bool get changingPlan => _changingPlan;
  bool get timerBlocksPlanChanges => planTimer?.blocksPlanChanges == true;

  Future<T> _changePlan<T>(
    Future<T> Function() request, {
    bool changesActivePlan = true,
    bool allowWithTimer = false,
  }) async {
    if (_changingPlan) {
      throw const ApiError('계획을 변경하고 있어요. 잠시 후 다시 시도해 주세요.');
    }
    final timer = planTimer;
    if (!allowWithTimer && timerBlocksPlanChanges) {
      throw const ApiError(planTimerBlockedMessage);
    }
    _changingPlan = true;
    var invalidateSelection = changesActivePlan;
    try {
      return await request();
    } on ApiError catch (error) {
      final status = error.status;
      if (status != null && status >= 400 && status < 500 && status != 409) {
        invalidateSelection = false;
      }
      rethrow;
    } finally {
      try {
        // Even a lost response can mean the active plan changed on the server.
        if (invalidateSelection &&
            timer != null &&
            identical(timer, planTimer) &&
            timer.task != null) {
          await timer.choose(null);
        }
      } finally {
        _changingPlan = false;
      }
    }
  }

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

  Future<void> withdrawAccount(String password, String confirmation) async {
    final base = validOrigin(origin);
    if (token == null) throw const ApiError('다시 로그인해 주세요.', 401);
    final request = http.Request('DELETE', Uri.parse(base).resolve('/users/me'))
      ..followRedirects = false
      ..headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json; charset=utf-8',
      })
      ..bodyBytes = utf8.encode(
        jsonEncode({
          'password': password,
          'confirmation': confirmation,
          'deletePersonalData': true,
        }),
      );
    try {
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 18));
      final envelope = object(jsonDecode(utf8.decode(response.bodyBytes)));
      final status = response.statusCode;
      if (status == 200 &&
          envelope['status'] == 'SUCCESS' &&
          envelope['code'] == 200 &&
          envelope['data'] is Json &&
          (envelope['data'] as Json)['withdrawn'] == true &&
          (envelope['data'] as Json)['personalDataDeleted'] == true) {
        return;
      }
      final data = envelope['data'];
      if (envelope['status'] == 'ERROR' &&
          envelope['code'] == status &&
          data is Json &&
          (status == 405 && data['code'] == 'METHOD_NOT_ALLOWED' ||
              status == 404 && data['code'] == 'NOT_FOUND_ENDPOINT')) {
        throw ApiError('회원탈퇴는 1122jhg 서버에 연결하면 사용할 수 있어요.', status);
      }
      if (envelope['status'] == 'ERROR' &&
          envelope['code'] == status &&
          envelope['data'] is Json &&
          const {400, 401, 403, 409}.contains(status)) {
        if (status == 401) onExpired?.call();
        throw ApiError(switch (status) {
          400 => '비밀번호와 아이디 확인 문구를 확인해 주세요.',
          401 => '로그인 정보를 확인할 수 없어요. 다시 로그인해 주세요.',
          403 => '계정의 전공 정보가 바뀌었어요. 다시 로그인해 주세요.',
          _ => '다른 계정 변경이 진행 중이에요. 계정 정보를 확인한 뒤 다시 시도해 주세요.',
        }, status);
      }
      throw const AccountWithdrawalUncertain();
    } on ApiError {
      rethrow;
    } catch (_) {
      throw const AccountWithdrawalUncertain();
    }
  }

  Future<Preview> preview(Json form) async =>
      Preview.from(await _send('POST', '$plannerPath/preview', body: form));

  /// [activate] 가 true 면 바로 사용하고 쓰던 계획은 목록에 보관, false 면 목록에만 추가한다.
  Future<Json> save(Json form, {bool activate = true}) => _changePlan(
    () => _send(
      'POST',
      '$plannerPath/save${activate ? '' : '?activate=false'}',
      body: form,
    ),
    changesActivePlan: activate,
    allowWithTimer: !activate,
  );

  /// 저장한 계획 목록 (지금 쓰는 계획이 맨 위).
  Future<List<PlanSummary>> plans() async =>
      rows((await _send('GET', '$plannerPath/plans'))['plans'])
          .map(PlanSummary.from)
          .toList();

  /// 목록의 계획 한 건을 날짜별 할 일까지.
  Future<SavedPlan> plan(int id) async => SavedPlan.from(
    object((await _send('GET', '$plannerPath/plans/$id'))['plan']),
  );
  Future<void> usePlan(int id) =>
      _changePlan(() => _send('POST', '$plannerPath/plans/$id/activate'));
  Future<void> deletePlan(int id) => _changePlan(
    () => _send('DELETE', '$plannerPath/plans/$id'),
    changesActivePlan: planTimer?.task?.planId == id,
  );

  Future<void> movePlanTask(
    int planId,
    int taskId,
    int version,
    DateTime date,
  ) => changePlanTask(planId, taskId, version, date: date);

  Future<void> changePlanTask(
    int planId,
    int taskId,
    int version, {
    DateTime? date,
    int? minutes,
  }) => _changePlan(() async {
    final result = await _send(
      'PATCH',
      '$plannerPath/plans/$planId/tasks/$taskId',
      body: {
        'expectedPlanVersion': version,
        if (date != null) 'scheduledDate': isoDay(date),
        'estimatedMinutes': ?minutes,
      },
    );
    if (result['planId'] != planId ||
        result['taskId'] != taskId ||
        result['planVersion'] is! int ||
        (result['planVersion'] as int) < version ||
        date != null && result['scheduledDate'] != isoDay(date) ||
        minutes != null && result['estimatedMinutes'] != minutes) {
      throw const ApiError('수정 결과를 확인하지 못했어요. 최신 일정을 확인해 주세요.', 409);
    }
  }, changesActivePlan: planTimer?.task?.planId == planId);

  Future<void> changePlanPeriod(
    int planId,
    int version,
    DateTime start,
    DateTime end,
  ) => _changePlan(() async {
    final result = await _send(
      'PATCH',
      '$plannerPath/plans/$planId/period',
      body: {
        'expectedPlanVersion': version,
        'startDate': isoDay(start),
        'endDate': isoDay(end),
      },
    );
    if (result['planId'] != planId ||
        result['planVersion'] is! int ||
        (result['planVersion'] as int) < version ||
        result['startDate'] != isoDay(start) ||
        result['endDate'] != isoDay(end)) {
      throw const ApiError('수정 결과를 확인하지 못했어요. 최신 일정을 확인해 주세요.', 409);
    }
  }, changesActivePlan: planTimer?.task?.planId == planId);

  Future<WholePlanInput> wholePlan(int planId) async {
    final input = WholePlanInput.from(
      await _send('GET', '$plannerPath/plans/$planId/schedule'),
    );
    if (input.id != planId) {
      throw const ApiError('수정할 계획을 확인하지 못했어요.');
    }
    return input;
  }

  Future<WholePlanPreview> previewWholePlan(int planId, Json edit) async =>
      WholePlanPreview.from(
        await _send(
          'POST',
          '$plannerPath/plans/$planId/schedule/preview',
          body: edit,
        ),
      );

  Future<void> applyWholePlan(int planId, Json edit, String approval) =>
      _changePlan(() async {
        final result = await _send(
          'PATCH',
          '$plannerPath/plans/$planId/schedule',
          body: {...edit, 'approval': approval},
        );
        if (result['planId'] != planId ||
            result['planVersion'] != (edit['expectedPlanVersion'] as int) + 1 ||
            result['startDate'] != edit['startDate'] ||
            result['endDate'] != edit['endDate']) {
          throw const ApiError('수정 결과를 확인하지 못했어요. 최신 일정을 확인해 주세요.', 409);
        }
      });

  /// 지금 계획이 많이 밀렸으면 다시 짠 일정을 돌려준다. 추천할 것이 없으면 null.
  Future<ReplanAdvice?> replan() async {
    final data = await _send('GET', '$plannerPath/replan');
    return data['needed'] == true && data['proposal'] != null
        ? ReplanAdvice.from(data)
        : null;
  }

  /// 추천을 받아들인다: 다시 짠 일정이 사용 중인 계획이 되고 쓰던 계획은 목록에 보관된다.
  Future<Json> acceptReplan() =>
      _changePlan(() => _send('POST', '$plannerPath/replan/accept'));

  /// 추천을 거절한다: 한동안 다시 묻지 않는다.
  Future<void> dismissReplan() => _send('POST', '$plannerPath/replan/dismiss');

  /// 채팅 안 계획 계산. 서버가 요약 답변을 같은 대화방에 남긴다.
  Future<ChatPlanReply> previewChat(Json form, int conversation) async =>
      ChatPlanReply.from(
        await _send(
          'POST',
          '$plannerPath/preview-chat',
          body: {'plan': form, 'conId': conversation},
        ),
      );
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
