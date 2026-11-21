import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/data/study_models.dart';

import 'support/study_fixture.dart';

void main() {
  test('기존 Bearer 인증과 서버 계약으로 날짜·정수 분만 저장한다', () async {
    final fixture = StudyFixture(empty: true);
    addTearDown(fixture.dispose);
    await fixture.session.restore();
    final api = fixture.session.account!;
    final record = await api.saveStudySession(fixture.today, 45);
    expect(record.minutes, 45);
    expect(record.taskId, isNull);
    final post = fixture.requests.singleWhere((r) => r.method == 'POST');
    expect(post.headers['Authorization'], 'Bearer SAMPLE');
    expect(post.followRedirects, false);
    expect(jsonDecode(post.body), {
      'studyDate': isoDay(fixture.today),
      'durationMinutes': 45,
    });
    final result = await api.studySessions(
      fixture.today,
      fixture.today,
      page: 0,
      pageSize: 1,
    );
    expect(result.items.single.id, record.id);
    expect(result.hasNext, false);
    final stats = await api.studyStats(fixture.today, fixture.today);
    expect(stats.totalMinutes, 45);
    expect(stats.days.single.minutes, 45);
    expect(fixture.requests.last.url.queryParameters, {
      'period': 'CUSTOM',
      'startDate': isoDay(fixture.today),
      'endDate': isoDay(fixture.today),
    });
  });

  for (final failure in ['connection', '500', 'malformed', 'wrong-type']) {
    test('저장 응답 $failure: 결과 불확실, 자동 POST 재전송 없음', () async {
      final fixture = StudyFixture(
        override: (r) async {
          if (r.method != 'POST') return null;
          if (failure == 'connection') {
            throw http.ClientException('SAMPLE response lost');
          }
          if (failure == '500') return studyEnvelope({'ko': 'SAMPLE'}, 500);
          if (failure == 'malformed') {
            return http.Response('<html>SAMPLE</html>', 200);
          }
          return studyEnvelope({'sessionId': 'wrong-type'});
        },
      );
      addTearDown(fixture.dispose);
      await fixture.session.restore();
      await expectLater(
        fixture.session.account!.saveStudySession(fixture.today, 45),
        throwsA(isA<StudySaveUncertain>()),
      );
      expect(fixture.requests.where((r) => r.method == 'POST'), hasLength(1));
    });
  }

  for (final status in [400, 409, 403]) {
    test('저장 $status는 서버 거부 상태를 보존한다', () async {
      final fixture = StudyFixture(
        override: (r) async => r.method == 'POST'
            ? studyEnvelope({'detail': 'SAMPLE 거부'}, status)
            : null,
      );
      addTearDown(fixture.dispose);
      await fixture.session.restore();
      await expectLater(
        fixture.session.account!.saveStudySession(fixture.today, 45),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', status)),
      );
    });
  }

  test('통계의 빈 날짜·시간대·합계 모순과 잘못된 날짜를 정상값으로 표시하지 않는다', () {
    final data = <String, dynamic>{
      'period': 'CUSTOM',
      'startDate': '2026-11-14',
      'endDate': '2026-11-15',
      'timezone': 'Asia/Seoul',
      'totalMinutes': 45,
      'dailyStudyMinutes': [
        {'studyDate': '2026-11-14', 'durationMinutes': 0},
        {'studyDate': '2026-11-15', 'durationMinutes': 45},
      ],
      'completionRate': null,
    };
    expect(StudyStats.from(data).totalMinutes, 45);
    expect(
      () => StudyStats.from({...data, 'timezone': 'UTC'}),
      throwsFormatException,
    );
    expect(
      () => StudyStats.from({...data, 'totalMinutes': 90}),
      throwsFormatException,
    );
    expect(
      () => StudyStats.from({
        ...data,
        'dailyStudyMinutes': [
          {'studyDate': '2026-11-15', 'durationMinutes': 45},
        ],
      }),
      throwsFormatException,
    );
    for (final invalid in [
      '2026-02-30',
      '2026-1-01',
      '2026-11-15+09:00',
      '2026-11-15T00:00:00Z',
    ]) {
      expect(() => studyDate(invalid), throwsFormatException);
    }
  });
}
