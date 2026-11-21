import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/data/session.dart';

import 'draft_storage.dart';

http.Response studyEnvelope(Object? data, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'status': status >= 200 && status < 300 ? 'SUCCESS' : 'ERROR',
          'code': status,
          'data': data,
        }),
      ),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

class StudyMemoryStore implements SessionStore {
  String? value = jsonEncode({'origin': emulatorOrigin, 'token': 'SAMPLE'});
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
}

/// SAMPLE API stand-in. Production screens contain no fixture records.
class StudyFixture {
  final requests = <http.Request>[];
  final history = <Json>[];
  final planTasks = <Json>[];
  final Future<http.Response?> Function(http.Request)? override;
  late final http.Client client;
  late final Session session;
  final DateTime today = dayInSeoul();

  StudyFixture({this.override, bool empty = false}) {
    planTasks.addAll([
      {
        'taskId': 501,
        'planId': 5,
        'planName': 'SAMPLE 계획',
        'planVersion': 3,
        'subjectId': null,
        'subjectName': 'SAMPLE 정보처리기사의 긴 과목 이름',
        'certificationName': 'SAMPLE 기사',
        'scheduledDate': isoDay(today),
        'planStatus': 'ACTIVE',
      },
      {
        'taskId': 502,
        'planId': 5,
        'planName': 'SAMPLE 계획',
        'planVersion': 3,
        'subjectId': 12,
        'subjectName': 'SAMPLE 데이터베이스',
        'certificationName': 'SAMPLE 기사',
        'scheduledDate': isoDay(today),
        'planStatus': 'ACTIVE',
      },
    ]);
    if (!empty) {
      history.addAll([
        {
          'sessionId': 1,
          'studyDate': isoDay(today),
          'durationMinutes': 60,
          'taskId': 501,
          'planId': 5,
          'subjectId': null,
          'subjectName': 'SAMPLE 정보처리기사의 긴 과목 이름',
          'inputMethod': 'MANUAL',
        },
        {
          'sessionId': 2,
          'studyDate': isoDay(plusDays(today, -1)),
          'durationMinutes': 30,
          'taskId': null,
          'planId': null,
          'subjectId': null,
          'subjectName': null,
          'inputMethod': 'MANUAL',
        },
      ]);
    }
    client = MockClient((request) async {
      requests.add(request);
      final custom = await override?.call(request);
      if (custom != null) return custom;
      final path = request.url.path;
      if (path == '/auth/user-info') {
        return studyEnvelope({
          'loginId': 'SAMPLE_RECORDS',
          'nickname': 'SAMPLE 학습자',
          'email': 'sample@example.invalid',
          'majorType': 'MAJOR',
          'majorTypeLabel': '전공',
        });
      }
      if (path == '/users/me/goal') {
        return studyEnvelope({'goal': {}, 'examRounds': [], 'subjects': []});
      }
      if (path == '$plannerPath/saved') return studyEnvelope({'plan': null});
      if (path == '/study/sessions' && request.method == 'POST') {
        return studyEnvelope(storeRecord(object(jsonDecode(request.body))));
      }
      if (path == '/study/plan-tasks') {
        final query = request.url.queryParameters;
        final all = planTasks
            .where(
              (v) =>
                  (query['date'] == null ||
                      v['scheduledDate'] == query['date']) &&
                  (query['includeReplaced'] == 'true' ||
                      v['planStatus'] == 'ACTIVE'),
            )
            .toList();
        final page = int.parse(query['page'] ?? '0'),
            size = int.parse(query['pageSize'] ?? '50');
        return studyEnvelope({
          'items': all.skip(page * size).take(size).toList(),
          'page': page,
          'pageSize': size,
          'hasNext': all.length > (page + 1) * size,
        });
      }
      if (request.method == 'DELETE' && path.startsWith('/study/sessions/')) {
        final id = int.parse(path.split('/').last),
            body = object(jsonDecode(request.body));
        final index = history.indexWhere((r) => r['sessionId'] == id);
        if (index < 0) return studyEnvelope({'ko': 'SAMPLE 권한 없음'}, 403);
        final old = history[index];
        if (old['studyDate'] != body['expectedStudyDate'] ||
            old['durationMinutes'] != body['expectedDurationMinutes'] ||
            old['taskId'] != body['expectedTaskId']) {
          return studyEnvelope({'detail': 'SAMPLE 변경된 기록'}, 409);
        }
        history.removeAt(index);
        return studyEnvelope({'sessionId': id, 'deleted': true});
      }
      if (request.method == 'PATCH' && path.startsWith('/study/sessions/')) {
        final id = int.parse(path.split('/').last);
        final body = object(jsonDecode(request.body));
        final index = history.indexWhere((r) => r['sessionId'] == id);
        if (index < 0) return studyEnvelope({'ko': 'SAMPLE 권한 없음'}, 403);
        final old = history[index];
        if (old['studyDate'] != body['expectedStudyDate'] ||
            old['durationMinutes'] != body['expectedDurationMinutes']) {
          return studyEnvelope({'detail': 'SAMPLE 다른 기기에서 변경된 기록'}, 409);
        }
        return studyEnvelope(updateRecord(id, body));
      }
      final query = request.url.queryParameters;
      if (path == '/study/sessions') {
        final all = selected(query);
        final page = int.parse(query['page'] ?? '0');
        final size = int.parse(query['pageSize'] ?? '20');
        return studyEnvelope({
          'items': all.skip(page * size).take(size).toList(),
          'page': page,
          'pageSize': size,
          'hasNext': all.length > (page + 1) * size,
        });
      }
      if (path == '/dashboard/study-stats') {
        final start = DateTime.parse(query['startDate']!);
        final end = DateTime.parse(query['endDate']!);
        final all = selected(query);
        final daily = <Json>[];
        for (var d = start; !d.isAfter(end); d = plusDays(d, 1)) {
          final minutes = all
              .where((r) => r['studyDate'] == isoDay(d))
              .fold(0, (n, r) => n + (r['durationMinutes'] as int));
          daily.add({'studyDate': isoDay(d), 'durationMinutes': minutes});
        }
        return studyEnvelope({
          'period': 'CUSTOM',
          'startDate': isoDay(start),
          'endDate': isoDay(end),
          'timezone': 'Asia/Seoul',
          'totalMinutes': all.fold(
            0,
            (n, r) => n + (r['durationMinutes'] as int),
          ),
          'dailyStudyMinutes': daily,
          'completionRate': null,
        });
      }
      return studyEnvelope({'ko': 'SAMPLE 지원하지 않는 요청'}, 404);
    });
    session = Session(StudyMemoryStore(), client, drafts: MemoryDraftStorage());
  }

  List<Json> selected(Map<String, String> query) {
    final start = query['startDate']!, end = query['endDate']!;
    return history
        .where(
          (r) =>
              (r['studyDate'] as String).compareTo(start) >= 0 &&
              (r['studyDate'] as String).compareTo(end) <= 0,
        )
        .toList()
      ..sort((a, b) {
        final date = (b['studyDate'] as String).compareTo(
          a['studyDate'] as String,
        );
        return date != 0
            ? date
            : (b['sessionId'] as int).compareTo(a['sessionId'] as int);
      });
  }

  Json storeRecord(Json body) {
    final matches = planTasks
        .where((t) => t['taskId'] == body['taskId'])
        .toList();
    final task = matches.isEmpty ? null : matches.first;
    final record = <String, dynamic>{
      'sessionId':
          history.fold(
            0,
            (n, r) => n > (r['sessionId'] as int) ? n : r['sessionId'] as int,
          ) +
          1,
      'studyDate': body['studyDate'],
      'durationMinutes': body['durationMinutes'],
      'taskId': task?['taskId'],
      'planId': task?['planId'],
      'subjectId': task?['subjectId'],
      'subjectName': task?['subjectName'],
      'inputMethod': 'MANUAL',
    };
    history.add(record);
    return record;
  }

  Json updateRecord(int id, Json body) {
    final index = history.indexWhere((r) => r['sessionId'] == id);
    Json? selection;
    if (body['taskLink'] case final Json link) {
      final choices = planTasks
          .where((t) => t['taskId'] == link['taskId'])
          .toList();
      final task = choices.isEmpty ? null : choices.first;
      selection = {
        'taskId': task?['taskId'],
        'planId': task?['planId'],
        'subjectId': task?['subjectId'],
        'subjectName': task?['subjectName'],
      };
    }
    return history[index] = {
      ...history[index],
      ...?selection,
      'studyDate': body['studyDate'],
      'durationMinutes': body['durationMinutes'],
    };
  }

  void dispose() {
    session.dispose();
    client.close();
  }
}
