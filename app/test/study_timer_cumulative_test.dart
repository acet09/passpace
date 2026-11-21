import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/data/study_models.dart';
import 'package:passpace_mobile/data/study_timer.dart';

import 'study_timer_progress_test.dart' show planFor, showProgress, progress;
import 'support/study_fixture.dart';
import 'study_records_test.dart' show openStudy, tapStudy;

Json saved(
  StudyFixture f,
  int id,
  int minutes, {
  int? subject = 12,
  int? task = 502,
  int? plan = 5,
  DateTime? date,
}) => {
  'sessionId': id,
  'studyDate': isoDay(date ?? f.today),
  'durationMinutes': minutes,
  'subjectId': subject,
  'taskId': task,
  'planId': plan,
  'subjectName': 'SAMPLE 데이터베이스',
  'inputMethod': 'MANUAL',
};

void main() {
  testWidgets('저장이 한 프레임 안에 거부되어도 폐기된 조회를 다시 읽는다', (t) async {
    late StudyFixture f;
    final pending = Completer<http.Response>();
    var first = true, canRead = true;
    f = StudyFixture(
      empty: true,
      override: (r) async {
        if (r.url.path == '$plannerPath/saved') {
          return studyEnvelope({'plan': planFor(f)});
        }
        if (r.url.path == '/study/sessions' && first) {
          first = false;
          return pending.future;
        }
        return null;
      },
    );
    addTearDown(f.dispose);
    f.history.add(saved(f, 1, 15));
    await showProgress(t, f, elapsed: Duration.zero, canRead: () => canRead);
    canRead = false;
    pending.complete(
      studyEnvelope({
        'items': [saved(f, 1, 15)],
        'page': 0,
        'pageSize': 20,
        'hasNext': false,
      }),
    );
    await t.pump();
    canRead = true;
    await showProgress(t, f, elapsed: Duration.zero, canRead: () => canRead);
    expect(progress(t), .5);
    expect(find.text('학습 시간 불러오는 중…'), findsNothing);
  });
  testWidgets('저장 요청·확정·새 측정에서 방금 저장한 시간을 두 번 더하지 않는다', (t) async {
    late StudyFixture f;
    f = StudyFixture(
      empty: true,
      override: (r) async => r.url.path == '$plannerPath/saved'
          ? studyEnvelope({'plan': planFor(f)})
          : null,
    );
    addTearDown(f.dispose);
    f.history.add(saved(f, 1, 10));
    await showProgress(t, f);
    expect(progress(t), closeTo(25 / 30, .00001));
    f.history.add(saved(f, 2, 15));
    final reads = f.requests.length;
    await showProgress(t, f, phase: StudyTimerPhase.saving);
    expect(progress(t), closeTo(25 / 30, .00001));
    expect(f.requests.length, reads);
    await showProgress(t, f, phase: StudyTimerPhase.saved);
    expect(progress(t), closeTo(25 / 30, .00001));
    await showProgress(
      t,
      f,
      phase: StudyTimerPhase.idle,
      elapsed: Duration.zero,
    );
    expect(progress(t), closeTo(25 / 30, .00001));
    await showProgress(
      t,
      f,
      phase: StudyTimerPhase.running,
      elapsed: const Duration(minutes: 5),
    );
    expect(progress(t), 1);
  });

  testWidgets('저장 결과가 불명확하면 기록 재조회로 현재 시간을 중복 합산하지 않는다', (t) async {
    late StudyFixture f;
    f = StudyFixture(
      empty: true,
      override: (r) async => r.url.path == '$plannerPath/saved'
          ? studyEnvelope({'plan': planFor(f)})
          : null,
    );
    addTearDown(f.dispose);
    f.history.add(saved(f, 1, 10));
    await showProgress(t, f);
    f.history.add(saved(f, 2, 15));
    final reads = f.requests.length;
    await showProgress(t, f, phase: StudyTimerPhase.uncertain);
    expect(progress(t), closeTo(25 / 30, .00001));
    expect(f.requests.length, reads);
    expect(find.textContaining('저장 결과 확인'), findsOneWidget);
  });

  testWidgets('저장 시작 전 진행하던 늦은 기록 응답도 폐기한다', (t) async {
    late StudyFixture f;
    final response = Completer<http.Response>();
    f = StudyFixture(
      empty: true,
      override: (r) async {
        if (r.url.path == '$plannerPath/saved') {
          return studyEnvelope({'plan': planFor(f)});
        }
        if (r.url.path == '/study/sessions') return response.future;
        return null;
      },
    );
    addTearDown(f.dispose);
    await showProgress(t, f);
    await showProgress(t, f, phase: StudyTimerPhase.saving);
    response.complete(
      studyEnvelope({
        'items': [saved(f, 1, 15)],
        'page': 0,
        'pageSize': 20,
        'hasNext': false,
      }),
    );
    await t.pumpAndSettle();
    expect(progress(t), 0);
    expect(find.text('기록 저장 중…'), findsOneWidget);
  });

  testWidgets('과목 ID가 없는 과거 연결은 시험·과목 메타데이터를 확인해 합산한다', (t) async {
    late StudyFixture f;
    f = StudyFixture(
      empty: true,
      override: (r) async => r.url.path == '$plannerPath/saved'
          ? studyEnvelope({'plan': planFor(f)})
          : null,
    );
    f.planTasks[1]['subjectId'] = null;
    f.planTasks.add({
      ...f.planTasks[1],
      'taskId': 600,
      'planId': 4,
      'planStatus': 'REPLACED',
    });
    addTearDown(f.dispose);
    f.history.add(saved(f, 1, 15, subject: null, task: 600, plan: 4));
    await showProgress(t, f, elapsed: const Duration(minutes: 5));
    expect(progress(t), closeTo(2 / 3, .00001));
    expect(
      f.requests.any((r) => r.url.queryParameters['includeReplaced'] == 'true'),
      isTrue,
    );
  });

  testWidgets('안정적인 과목 ID는 이전 계획 기록도 추가 조회 없이 같은 과목으로 합산한다', (t) async {
    late StudyFixture f;
    f = StudyFixture(
      empty: true,
      override: (r) async => r.url.path == '$plannerPath/saved'
          ? studyEnvelope({'plan': planFor(f)})
          : null,
    );
    addTearDown(f.dispose);
    f.history.add(saved(f, 1, 15, task: 600, plan: 4));
    await showProgress(t, f, elapsed: Duration.zero);
    expect(progress(t), .5);
    expect(
      f.requests.any((r) => r.url.queryParameters['includeReplaced'] == 'true'),
      isFalse,
    );
  });

  testWidgets('페이지에 같은 기록 ID가 다시 오면 한 번만 합산한다', (t) async {
    late StudyFixture f;
    f = StudyFixture(
      empty: true,
      override: (r) async {
        if (r.url.path == '$plannerPath/saved') {
          return studyEnvelope({'plan': planFor(f)});
        }
        if (r.url.path != '/study/sessions') return null;
        final page = int.parse(r.url.queryParameters['page']!);
        return studyEnvelope({
          'items': page == 0
              ? [saved(f, 1, 5), saved(f, 2, 5)]
              : [saved(f, 2, 5), saved(f, 3, 5)],
          'page': page,
          'pageSize': 20,
          'hasNext': page == 0,
        });
      },
    );
    addTearDown(f.dispose);
    await showProgress(t, f, elapsed: Duration.zero);
    expect(progress(t), .5);
  });

  testWidgets('기록 다음 페이지 조회 실패에 부분 합계를 표시하지 않고 재시도한다', (t) async {
    late StudyFixture f;
    var fail = true;
    f = StudyFixture(
      empty: true,
      override: (r) async {
        if (r.url.path == '$plannerPath/saved') {
          return studyEnvelope({'plan': planFor(f)});
        }
        if (r.url.path == '/study/sessions' &&
            r.url.queryParameters['page'] == '1' &&
            fail) {
          return studyEnvelope({'ko': 'SAMPLE failed page'}, 503);
        }
        return null;
      },
    );
    addTearDown(f.dispose);
    f.history.addAll(List.generate(21, (i) => saved(f, i + 1, 1)));
    await showProgress(t, f, elapsed: Duration.zero);
    expect(progress(t), 0);
    expect(find.textContaining('불러오지 못했어요'), findsOneWidget);
    fail = false;
    await t.tap(find.text('학습 시간 다시 불러오기'));
    await t.pumpAndSettle();
    expect(progress(t), .7);
  });

  testWidgets('기록 수정·삭제 뒤 다시 진입하면 서버의 새 저장 합계를 반영한다', (t) async {
    late StudyFixture f;
    f = StudyFixture(
      empty: true,
      override: (r) async => r.url.path == '$plannerPath/saved'
          ? studyEnvelope({'plan': planFor(f)})
          : null,
    );
    addTearDown(f.dispose);
    f.history.add(saved(f, 1, 15));
    await showProgress(t, f, elapsed: Duration.zero);
    expect(progress(t), .5);
    f.history.first['durationMinutes'] = 5;
    await showProgress(t, f, active: false, elapsed: Duration.zero);
    await showProgress(t, f, elapsed: Duration.zero);
    expect(progress(t), closeTo(1 / 6, .00001));
    f.history.clear();
    await showProgress(t, f, active: false, elapsed: Duration.zero);
    await showProgress(t, f, elapsed: Duration.zero);
    expect(progress(t), 0);
  });

  testWidgets('저장 시간이 있는 과목도 일반360폭에서 시작 버튼에 바로 접근한다', (t) async {
    t.view.physicalSize = const Size(360, 820);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    late StudyFixture f;
    f = StudyFixture(
      empty: true,
      override: (r) async => r.url.path == '$plannerPath/saved'
          ? studyEnvelope({'plan': planFor(f)})
          : null,
    );
    addTearDown(f.dispose);
    f.history.add(saved(f, 1, 15));
    await f.session.restore();
    final clock = StudyTimer(
      f.session.drafts,
      f.session.origin,
      f.session.user!.id,
    );
    await clock.restore();
    await clock.choose(StudyTaskChoice.from(f.planTasks[1]));
    clock.dispose();
    await openStudy(t, f);
    await tapStudy(t, find.byKey(const ValueKey('study-timer-open')));
    expect(progress(t), .5);
    expect(
      find.widgetWithText(FilledButton, '측정 시작').hitTestable(),
      findsOneWidget,
    );
  });
  testWidgets('같은 날짜·과목 저장15분과 이번15분을 합쳐30분 원을 채운다', (t) async {
    late StudyFixture f;
    f = StudyFixture(
      empty: true,
      override: (r) async => r.url.path == '$plannerPath/saved'
          ? studyEnvelope({'plan': planFor(f)})
          : null,
    );
    addTearDown(f.dispose);
    f.history.add(saved(f, 1, 15));
    await showProgress(t, f);
    expect(progress(t), 1);
    expect(find.text('저장 15분 + 이번 측정 15분'), findsOneWidget);
    expect(find.textContaining('누적'), findsWidgets);
  });

  testWidgets('저장 기록 모든 페이지의 서로 다른 ID는 같은 값이어도 모두 합친다', (t) async {
    late StudyFixture f;
    f = StudyFixture(
      empty: true,
      override: (r) async => r.url.path == '$plannerPath/saved'
          ? studyEnvelope({'plan': planFor(f, minutes: 100)})
          : null,
    );
    addTearDown(f.dispose);
    f.history.addAll(List.generate(41, (i) => saved(f, i + 1, 1)));
    await showProgress(t, f, elapsed: Duration.zero);
    expect(progress(t), .41);
    expect(
      f.requests.where((r) => r.url.path == '/study/sessions'),
      hasLength(3),
    );
  });

  testWidgets('동명 다른 시험·다른 날짜·미연결 시간은 더하지 않는다', (t) async {
    late StudyFixture f;
    f = StudyFixture(
      empty: true,
      override: (r) async => r.url.path == '$plannerPath/saved'
          ? studyEnvelope({'plan': planFor(f)})
          : null,
    );
    addTearDown(f.dispose);
    f.planTasks.add({
      ...f.planTasks[1],
      'taskId': 503,
      'subjectId': 13,
      'certificationName': 'SAMPLE 다른 시험',
    });
    f.history.addAll([
      saved(f, 1, 15),
      saved(f, 2, 30, subject: 13, task: 503),
      saved(f, 3, 60, date: plusDays(f.today, -1)),
      saved(f, 4, 20, subject: null, task: null, plan: null),
    ]);
    await showProgress(t, f, elapsed: const Duration(minutes: 5));
    expect(progress(t), closeTo(2 / 3, .00001));
    expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
  });
}
