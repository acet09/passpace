import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/data/study_models.dart';
import 'package:passpace_mobile/data/study_timer.dart';
import 'package:passpace_mobile/ui/design.dart';
import 'package:passpace_mobile/ui/study_timer_progress.dart';
import 'package:passpace_mobile/ui/study_task_picker.dart';

import 'support/study_fixture.dart';
import 'study_records_test.dart' show openStudy, tapStudy;

Json planFor(StudyFixture f, {int id = 5, int version = 3, int minutes = 30}) =>
    {
      'planId': id,
      'planName': 'SAMPLE 계획',
      'versionNo': version,
      'startDate': isoDay(plusDays(f.today, -2)),
      'endDate': isoDay(plusDays(f.today, 10)),
      'tasks': [
        {
          'date': isoDay(f.today),
          'certificationName': 'SAMPLE 기사',
          'subjectName': 'SAMPLE 데이터베이스',
          'minutes': minutes,
        },
        {
          'date': isoDay(f.today),
          'certificationName': 'SAMPLE 다른 시험',
          'subjectName': 'SAMPLE 데이터베이스',
          'minutes': 200,
        },
        {
          'date': isoDay(plusDays(f.today, 1)),
          'certificationName': 'SAMPLE 기사',
          'subjectName': 'SAMPLE 데이터베이스',
          'minutes': 90,
        },
      ],
    };

Future<void> showProgress(
  WidgetTester t,
  StudyFixture f, {
  Duration elapsed = const Duration(minutes: 15),
  StudyTaskChoice? task,
  DateTime? date,
  bool selected = true,
  VoidCallback? forbidden,
  bool Function()? canRead,
  double? scale,
  StudyTimerPhase phase = StudyTimerPhase.paused,
  bool active = true,
}) async {
  if (f.session.account == null) await f.session.restore();
  await t.pumpWidget(
    MaterialApp(
      theme: paceTheme(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale ?? 1)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: StudyTimerProgress(
                api: f.session.account!,
                task: selected
                    ? task ?? StudyTaskChoice.from(f.planTasks[1])
                    : null,
                date: date ?? f.today,
                elapsed: elapsed,
                label: '00:15:00',
                phase: phase,
                active: active,
                canRead: canRead ?? () => true,
                onForbidden: forbidden ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

double? progress(WidgetTester t) => t
    .widget<CircularProgressIndicator>(
      find.byKey(const ValueKey('study-timer-progress')),
    )
    .value;

void main() {
  testWidgets('일반 글자 360폭에서 원형 시간과 측정 시작이 스크롤 없이 보인다', (t) async {
    t.view.physicalSize = const Size(360, 820);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final f = StudyFixture();
    addTearDown(f.dispose);
    await openStudy(t, f);
    await tapStudy(t, find.byKey(const ValueKey('study-timer-open')));
    expect(
      find.widgetWithText(FilledButton, '측정 시작').hitTestable(),
      findsOneWidget,
    );
  });
  testWidgets('과목 연결은 이전 계획 옵션 없이 현재 ACTIVE 과목만 제공한다', (t) async {
    final f = StudyFixture();
    addTearDown(f.dispose);
    f.planTasks.add({
      ...f.planTasks[1],
      'taskId': 900,
      'subjectName': 'SAMPLE 이전 과목',
      'planStatus': 'REPLACED',
    });
    await f.session.restore();
    await t.pumpWidget(
      MaterialApp(
        home: StudyTaskPicker(
          f.session,
          date: f.today,
          selectedId: null,
          onForbidden: () {},
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('이전 계획 포함'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('SAMPLE 이전 과목'), findsNothing);
    expect(find.text('2개 과목'), findsOneWidget);
    expect(
      f.requests
          .where((r) => r.url.path == '/study/plan-tasks')
          .every((r) => r.url.queryParameters['includeReplaced'] == 'false'),
      isTrue,
    );
  });
  testWidgets('선택 날짜·시험·과목의 배정에만 이번 측정 비율을 표시한다', (t) async {
    late StudyFixture f;
    f = StudyFixture(
      override: (r) async => r.url.path == '$plannerPath/saved'
          ? studyEnvelope({'plan': planFor(f)})
          : null,
    );
    addTearDown(f.dispose);
    await showProgress(t, f);
    expect(progress(t), .5);
    expect(find.text('배정 30분'), findsOneWidget);
    expect(find.textContaining('50%'), findsOneWidget);
    expect(find.byKey(const ValueKey('study-timer-clock')), findsOneWidget);
    final readCount = f.requests.length;
    await showProgress(t, f, elapsed: const Duration(hours: 1));
    expect(progress(t), 1);
    expect(find.textContaining('배정 시간 도달'), findsOneWidget);
    expect(f.requests.length, readCount);
    expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
  });

  testWidgets('같은 날 같은 과목 여러 배정만 합치고 다음 날 시간을 가져오지 않는다', (t) async {
    late StudyFixture f;
    f = StudyFixture(
      override: (r) async {
        if (r.url.path != '$plannerPath/saved') return null;
        final plan = planFor(f, minutes: 10);
        (plan['tasks'] as List).add({
          'date': isoDay(f.today),
          'certificationName': 'SAMPLE 기사',
          'subjectName': 'SAMPLE 데이터베이스',
          'minutes': 20,
        });
        return studyEnvelope({'plan': plan});
      },
    );
    addTearDown(f.dispose);
    await showProgress(t, f);
    expect(progress(t), .5);
    await showProgress(t, f, date: plusDays(f.today, 2));
    expect(progress(t), 0);
    expect(find.textContaining('계획된 학습 없음'), findsOneWidget);
    expect(find.textContaining('100%'), findsNothing);
  });

  testWidgets('과목 미선택은 읽기 요청 없이 빈 원과 선택 안내를 표시한다', (t) async {
    final f = StudyFixture();
    addTearDown(f.dispose);
    await showProgress(t, f, selected: false);
    expect(progress(t), 0);
    expect(find.textContaining('과목을 선택하면'), findsOneWidget);
    expect(
      f.requests.where(
        (r) =>
            r.url.path.contains('/saved') || r.url.path == '/study/plan-tasks',
      ),
      isEmpty,
    );
  });

  testWidgets('계획 ID·버전이 달라졌으면 옛 배정으로 원을 채우지 않는다', (t) async {
    late StudyFixture f;
    f = StudyFixture(
      override: (r) async => r.url.path == '$plannerPath/saved'
          ? studyEnvelope({'plan': planFor(f, id: 9, version: 4)})
          : null,
    );
    addTearDown(f.dispose);
    await showProgress(t, f);
    expect(progress(t), 0);
    expect(find.textContaining('다시 선택'), findsOneWidget);
  });

  testWidgets('현재 계획에 없는 과거 연결은 복원값을 바꾸지 않고 다시 선택 안내한다', (t) async {
    final f = StudyFixture();
    addTearDown(f.dispose);
    final old = StudyTaskChoice.from({
      ...f.planTasks[1],
      'taskId': 999,
      'planStatus': 'REPLACED',
    });
    await showProgress(t, f, task: old);
    expect(progress(t), 0);
    expect(find.textContaining('다시 선택'), findsOneWidget);
    expect(old.status, 'REPLACED');
  });

  testWidgets('같은 이름의 서로 다른 과목 ID는 모호한 배정을 합쳐 표시하지 않는다', (t) async {
    late StudyFixture f;
    f = StudyFixture(
      override: (r) async => r.url.path == '$plannerPath/saved'
          ? studyEnvelope({'plan': planFor(f)})
          : null,
    );
    f.planTasks.add({...f.planTasks[1], 'taskId': 503, 'subjectId': 13});
    addTearDown(f.dispose);
    await showProgress(t, f);
    expect(progress(t), 0);
    expect(find.textContaining('구분할 수 없어요'), findsOneWidget);
  });

  testWidgets('조회 실패 후 다시 불러오며 원은 무한 로딩으로 회전하지 않는다', (t) async {
    late StudyFixture f;
    var fail = true;
    f = StudyFixture(
      override: (r) async => r.url.path == '$plannerPath/saved'
          ? fail
                ? studyEnvelope({'ko': 'SAMPLE 실패'}, 503)
                : studyEnvelope({'plan': planFor(f)})
          : null,
    );
    addTearDown(f.dispose);
    await showProgress(t, f);
    expect(progress(t), 0);
    expect(find.textContaining('불러오지 못했어요'), findsOneWidget);
    fail = false;
    await t.tap(find.text('학습 시간 다시 불러오기'));
    await t.pumpAndSettle();
    expect(progress(t), .5);
  });

  testWidgets('계정이 바뀐 후 늦은 배정 응답은 표시하거나 권한 콜백하지 않는다', (t) async {
    final pending = Completer<http.Response>();
    late StudyFixture f;
    var valid = true, forbidden = 0;
    f = StudyFixture(
      override: (r) async =>
          r.url.path == '$plannerPath/saved' ? pending.future : null,
    );
    addTearDown(f.dispose);
    await showProgress(
      t,
      f,
      canRead: () => valid,
      forbidden: () => forbidden++,
    );
    valid = false;
    pending.complete(studyEnvelope({'ko': 'SAMPLE expired'}, 403));
    await t.pumpAndSettle();
    expect(forbidden, 0);
    expect(progress(t), 0);
  });

  for (final width in [320.0, 360.0, 412.0]) {
    for (final scale in [1.5, 2.0]) {
      testWidgets('원형 시간 $width 폭·$scale 글자에서 넘치지 않는다', (t) async {
        t.view.physicalSize = Size(width, 760);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        late StudyFixture f;
        f = StudyFixture(
          override: (r) async => r.url.path == '$plannerPath/saved'
              ? studyEnvelope({'plan': planFor(f)})
              : null,
        );
        addTearDown(f.dispose);
        await showProgress(t, f, scale: scale);
        expect(t.takeException(), isNull);
        expect(progress(t), .5);
      });
    }
  }
}
