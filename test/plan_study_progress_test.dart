import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/data/study_models.dart';
import 'package:passpace_mobile/ui/dashboard.dart';
import 'package:passpace_mobile/ui/plan_list.dart';
import 'package:passpace_mobile/ui/study_records.dart';
import 'package:passpace_mobile/ui/today_study_progress.dart';

import 'study_records_test.dart' show tapStudy;
import 'support/study_fixture.dart';
import 'timer_navigation_test.dart' show boot, nav;

void main() {
  testWidgets('좁은 화면과 큰 글자에서도 전체 진행률과 시간을 모두 표시한다', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(320, 600);
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: TodayProgressSummary(
              plannedMinutes: 960,
              studied: Duration(hours: 8),
            ),
          ),
        ),
      ),
    );
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('8시간'), findsOneWidget);
    expect(find.text('16시간'), findsOneWidget);
    final accent = find.byKey(const ValueKey('today-progress-accent'));
    expect(t.widget<ColoredBox>(accent).color, const Color(0xff3155c7));
    expect(t.getSize(accent).width, 4);
    expect(
      t.getTopLeft(accent).dx,
      lessThan(t.getTopLeft(find.text('50%')).dx),
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('배정 시간을 채운 과목 다음으로 공부할 과목의 타이머를 연다', (t) async {
    final day = isoDay(dayInSeoul());
    final fixture = StudyFixture(
      override: (r) async => r.url.path == '$plannerPath/saved'
          ? studyEnvelope({
              'plan': {
                'planId': 5,
                'planName': 'SAMPLE 계획',
                'versionNo': 3,
                'startDate': day,
                'endDate': day,
                'tasks': [
                  for (final (id, name) in [
                    (501, 'SAMPLE 정보처리기사의 긴 과목 이름'),
                    (502, 'SAMPLE 데이터베이스'),
                  ])
                    {
                      'taskId': id,
                      'date': day,
                      'certificationName': 'SAMPLE 기사',
                      'subjectName': name,
                      'minutes': 60,
                    },
                ],
              },
            })
          : null,
    );
    addTearDown(fixture.dispose);
    await boot(t, fixture);
    final action = find.text('SAMPLE 데이터베이스');
    final next = find.ancestor(of: action, matching: find.byType(TaskTile));
    final total = find.byKey(const ValueKey('today-study-progress'));
    expect(total, findsOneWidget);
    expect(find.text('다음 학습'), findsNothing);
    expect(find.text('타이머 열기'), findsNothing);
    final studied = find.text('공부');
    final planned = find.text('배정');
    expect(
      t.getTopLeft(studied).dx,
      greaterThan(t.getTopLeft(find.text('오늘 전체 진행률')).dx),
    );
    expect(t.getTopLeft(planned).dy, greaterThan(t.getTopLeft(studied).dy));
    expect(t.getBottomLeft(total).dy, lessThan(t.getTopLeft(next).dy));
    expect(t.widget<TaskTile>(next).task.id, 502);
    expect(find.text('100%'), findsOneWidget);
    await tapStudy(t, action);
    final records = t.state<StudyRecordsScreenState>(
      find.byType(StudyRecordsScreen),
    );
    expect(records.timer?.task?.id, 502);

    fixture.history.add({
      ...fixture.history.first,
      'sessionId': 3,
      'taskId': 502,
      'subjectId': 12,
      'subjectName': 'SAMPLE 데이터베이스',
    });
    await t.pumpWidget(const SizedBox.shrink());
    await boot(t, fixture);
    expect(t.widget<LinearProgressIndicator>(total).value, 1);
    expect(action, findsOneWidget);
    expect(find.text('오늘 배정된 과목의 공부 시간을 채웠어요.'), findsNothing);
  });

  testWidgets('오늘 진행률은 현재 계획에 연결된 오늘 시간과 측정 중 시간을 합산한다', (t) async {
    final day = isoDay(dayInSeoul());
    final fixture = StudyFixture(
      override: (r) async => r.url.path == '$plannerPath/saved'
          ? studyEnvelope({
              'plan': {
                'planId': 5,
                'planName': 'SAMPLE 진행률',
                'versionNo': 7,
                'startDate': day,
                'endDate': day,
                'tasks': [
                  {
                    'date': day,
                    'certificationName': 'SAMPLE 기사',
                    'subjectName': 'SAMPLE 정보처리기사의 긴 과목 이름',
                    'minutes': 120,
                  },
                ],
              },
            })
          : null,
    );
    addTearDown(fixture.dispose);
    fixture.history.add({
      ...fixture.history.first,
      'sessionId': 3,
      'planId': 99,
      'durationMinutes': 90,
    });
    await boot(t, fixture);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('버전 7'), findsNothing);
    final clock = t
        .state<StudyRecordsScreenState>(
          find.byType(StudyRecordsScreen, skipOffstage: false),
        )
        .timer!;
    await clock.choose(
      StudyTaskChoice.from({...fixture.planTasks.first, 'planVersion': 7}),
    );
    expect(await clock.start(), isTrue);
    await clock.alignElapsed(const Duration(minutes: 12).inMilliseconds);
    await t.pump();
    expect(find.text('60%'), findsOneWidget);
    await clock.pause();
    await t.pumpAndSettle();
    expect(find.text('60%'), findsOneWidget);

    expect(await clock.beginSave(), isTrue);
    await fixture.session.account!.saveStudySession(
      fixture.today,
      12,
      task: clock.task,
    );
    await t.pump();
    expect(find.text('저장 상태를 확인한 뒤 진행률을 표시해요.'), findsOneWidget);
    await clock.complete();
    await t.pumpAndSettle();
    expect(find.text('60%'), findsOneWidget);
  });

  testWidgets('미저장 측정 중에는 계획 쓰기를 보내지 않고 계획 적용 중에는 측정을 시작하지 않는다', (t) async {
    final changed = Completer<void>();
    final fixture = StudyFixture(
      override: (r) async {
        if (r.method == 'POST' &&
            r.url.path == '$plannerPath/plans/8/activate') {
          await changed.future;
          return studyEnvelope({});
        }
        return null;
      },
    );
    addTearDown(fixture.dispose);
    await boot(t, fixture);
    final clock = t
        .state<StudyRecordsScreenState>(
          find.byType(StudyRecordsScreen, skipOffstage: false),
        )
        .timer!;
    final api = fixture.session.account!;
    expect(await clock.start(), isTrue);
    await expectLater(api.usePlan(8), throwsA(isA<ApiError>()));
    await clock.alignElapsed(5000);
    await clock.pause();
    await expectLater(api.deletePlan(8), throwsA(isA<ApiError>()));
    await expectLater(api.save({}), throwsA(isA<ApiError>()));
    await expectLater(api.acceptReplan(), throwsA(isA<ApiError>()));
    expect(fixture.requests.where((r) => r.method != 'GET'), isEmpty);
    expect(await clock.reset(), isTrue);
    await clock.choose(StudyTaskChoice.from(fixture.planTasks.first));
    final activating = api.usePlan(8);
    expect(await clock.start(), isFalse);
    changed.complete();
    await activating;
    expect(clock.task, isNull);
  });

  testWidgets('측정 중과 일시정지 중에는 기존 과목을 유지하며 계획을 목록에 추가할 수 있다', (t) async {
    final fixture = StudyFixture(
      override: (request) async =>
          request.method == 'POST' &&
              request.url.path == '$plannerPath/save' &&
              request.url.queryParameters['activate'] == 'false'
          ? studyEnvelope({'planId': 8})
          : null,
    );
    addTearDown(fixture.dispose);
    await boot(t, fixture);
    final screen = find.byType(StudyRecordsScreen, skipOffstage: false);
    final timer = t.state<StudyRecordsScreenState>(screen).timer!;
    final task = StudyTaskChoice.from(fixture.planTasks.first);
    await timer.choose(task);
    expect(await timer.start(), isTrue);
    await timer.alignElapsed(5000);
    final api = fixture.session.account!;

    expect(await api.save({}, activate: false), {'planId': 8});
    expect(timer.task, same(task));
    expect(timer.blocksPlanChanges, isTrue);

    await timer.pause();
    final elapsed = timer.elapsed;
    await expectLater(api.save({}), throwsA(isA<ApiError>()));
    expect(await api.save({}, activate: false), {'planId': 8});
    expect(timer.task, same(task));
    expect(timer.elapsed, elapsed);
    final writes = fixture.requests.where((request) => request.method != 'GET');
    expect(writes.length, 2);
    expect(
      writes.every((r) => r.url.queryParameters['activate'] == 'false'),
      isTrue,
    );

    final choice = askPlanSave(t.element(screen), api);
    await t.pumpAndSettle();
    expect(find.textContaining('기록 탭'), findsOneWidget);
    final activate = find.widgetWithText(FilledButton, '바로 사용');
    expect(t.widget<FilledButton>(activate).onPressed, isNull);
    await t.tap(find.text('목록에만 추가'));
    await t.pumpAndSettle();
    expect(await choice, isFalse);
  });

  testWidgets('과목별 통계는 다음 페이지와 과목 미연결 시간까지 합산한다', (t) async {
    final fixture = StudyFixture();
    addTearDown(fixture.dispose);
    final day = isoDay(fixture.today);
    for (var id = 3; id < 105; id++) {
      fixture.history.add({
        'sessionId': id,
        'studyDate': day,
        'durationMinutes': 2,
        'taskId': 502,
        'planId': 5,
        'subjectId': 12,
        'subjectName': 'SAMPLE 데이터베이스',
        'inputMethod': 'MANUAL',
      });
    }
    await boot(t, fixture);
    await nav(t, '기록');
    await tapStudy(t, find.byKey(const ValueKey('open-study-statistics')));
    expect(find.text('과목별 공부시간'), findsOneWidget);
    expect(
      t.getTopLeft(find.byKey(const ValueKey('study-total'))).dy,
      lessThan(t.getTopLeft(find.text('과목별 공부시간')).dy),
    );
    for (final section in [
      'study-subject-breakdown',
      'study-selected-subjects',
    ]) {
      final area = find.byKey(ValueKey(section));
      for (final text in ['SAMPLE 데이터베이스', '3시간 24분']) {
        expect(
          find.descendant(of: area, matching: find.text(text)),
          findsOneWidget,
        );
      }
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('study-subject-breakdown')),
        matching: find.text('과목 미연결'),
      ),
      findsOneWidget,
    );
    expect(
      fixture.requests.any(
        (r) =>
            r.url.path == '/study/sessions' &&
            r.url.queryParameters['page'] == '1',
      ),
      isTrue,
    );
  });

  testWidgets('보관된 계획에 연결한 이름 없는 기록은 과목을 확인해 통계에 합산한다', (t) async {
    final fixture = StudyFixture();
    addTearDown(fixture.dispose);
    final oldTask = {
      ...fixture.planTasks.last,
      'taskId': 810,
      'planId': 10,
      'planStatus': 'REPLACED',
    };
    fixture.planTasks.add(oldTask);
    fixture.history.addAll([
      {
        ...fixture.history.first,
        'sessionId': 4,
        'taskId': 810,
        'planId': 10,
        'subjectName': null,
        'subjectId': null,
        'durationMinutes': 45,
      },
      {
        ...fixture.history.first,
        'sessionId': 5,
        'taskId': 502,
        'subjectName': fixture.planTasks[1]['subjectName'],
        'subjectId': 12,
        'durationMinutes': 30,
      },
    ]);
    await boot(t, fixture);
    await nav(t, '기록');
    await tapStudy(t, find.byKey(const ValueKey('open-study-statistics')));
    final breakdown = find.byKey(const ValueKey('study-subject-breakdown'));
    final label = find.descendant(
      of: breakdown,
      matching: find.text('SAMPLE 데이터베이스'),
    );
    final row = find.ancestor(of: label, matching: find.byType(Row)).first;
    expect(
      find.descendant(of: row, matching: find.text('1시간 15분')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: breakdown, matching: find.text('과목 미연결')),
      findsOneWidget,
    );
  });
}
