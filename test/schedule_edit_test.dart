import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/models.dart';

import 'study_records_test.dart' show tapStudy;
import 'support/study_fixture.dart';
import 'timer_navigation_test.dart' show boot, nav;

void main() {
  testWidgets('홈 날짜 이동을 유지하고 저장한 계획에서 기간과 과목을 편집한다', (t) async {
    final today = dayInSeoul();
    final day = isoDay(today);
    var version = 3;
    var firstMinutes = 120;
    Json? savedChange;
    late final StudyFixture fixture;
    fixture = StudyFixture(
      override: (r) async {
        if (r.method == 'PATCH') {
          expect(r.url.path, '$plannerPath/plans/5/tasks/501');
          savedChange = object(jsonDecode(r.body));
          firstMinutes = savedChange!['estimatedMinutes'] as int;
          return studyEnvelope({
            'planId': 5,
            'taskId': 501,
            'planVersion': ++version,
            'scheduledDate': day,
            'estimatedMinutes': firstMinutes,
          });
        }
        final plan = {
          'planId': 5,
          'planName': 'SAMPLE 계획',
          'versionNo': version,
          'startDate': day,
          'endDate': isoDay(plusDays(today, 2)),
          'tasks': [
            for (final task in fixture.planTasks)
              {
                'taskId': task['taskId'],
                'date': day,
                'certificationName': task['certificationName'],
                'subjectName': task['subjectName'],
                'minutes': task['taskId'] == 501 ? firstMinutes : 120,
              },
          ],
        };
        return switch (r.url.path) {
          '$plannerPath/saved' ||
          '$plannerPath/plans/5' => studyEnvelope({'plan': plan}),
          '$plannerPath/plans' => studyEnvelope({
            'plans': [plan],
          }),
          _ => null,
        };
      },
    );
    addTearDown(fixture.dispose);
    await boot(t, fixture);
    double? progress(int id) => t
        .widget<LinearProgressIndicator>(
          find.byKey(ValueKey('today-task-progress-$id')),
        )
        .value;
    expect(progress(501), .5);
    expect(progress(502), 0);
    await tapStudy(t, find.byKey(const ValueKey('planned-task-actions-501')));
    await tapStudy(t, find.text('다른 날짜로 옮기기'));
    expect(find.text('학습 날짜 옮기기'), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-minutes')), findsNothing);
    expect(find.byKey(const ValueKey('schedule-end-date')), findsNothing);
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, '옮기기'))
          .onPressed,
      isNull,
    );
    await tapStudy(t, find.byKey(const ValueKey('schedule-move-date')));
    final picker = find.byType(DatePickerDialog);
    expect(t.widget<DatePickerDialog>(picker).firstDate, plusDays(today, 1));
    expect(t.widget<DatePickerDialog>(picker).lastDate, plusDays(today, 2));
    final ok = MaterialLocalizations.of(t.element(picker)).okButtonLabel;
    await tapStudy(t, find.descendant(of: picker, matching: find.text(ok)));
    expect(find.text(isoDay(plusDays(today, 1))), findsOneWidget);
    await tapStudy(t, find.text('취소'));
    await nav(t, '학습계획');
    await tapStudy(t, find.byTooltip('계획 수정'));
    await tapStudy(t, find.text('계획 기간 수정'));
    expect(find.byKey(const ValueKey('schedule-start-date')), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-end-date')), findsOneWidget);
    await tapStudy(t, find.text('취소'));
    await tapStudy(t, find.byTooltip('저장한 계획 목록'));
    await tapStudy(t, find.byType(ListTile).first);
    expect(find.text('계획 일정'), findsOneWidget);
    expect(find.text('계획 기간 수정'), findsOneWidget);
    await tapStudy(t, find.widgetWithText(TextButton, '수정').first);
    expect(find.text('학습 일정 수정'), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-start-date')), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('schedule-minutes')), '75');
    await tapStudy(t, find.widgetWithText(FilledButton, '저장'));
    expect(savedChange, {'expectedPlanVersion': 3, 'estimatedMinutes': 75});
    expect(find.textContaining('75분'), findsOneWidget);
  });

  testWidgets('기존 서버가 계획에 항목 ID를 생략해도 과목과 시험을 대조해 진행률을 표시한다', (t) async {
    final today = dayInSeoul();
    final day = isoDay(today);
    late final StudyFixture fixture;
    fixture = StudyFixture(
      override: (r) async => r.url.path == '$plannerPath/saved'
          ? studyEnvelope({
              'plan': {
                'planId': 5,
                'planName': 'SAMPLE 기존 계획',
                'versionNo': 3,
                'startDate': day,
                'endDate': isoDay(plusDays(today, 2)),
                'tasks': [
                  for (final item in fixture.planTasks.take(2))
                    {
                      'date': day,
                      'certificationName': item['certificationName'],
                      'subjectName': item['subjectName'],
                      'minutes': 120,
                    },
                ],
              },
            })
          : null,
    );
    addTearDown(fixture.dispose);
    fixture.planTasks.add({
      ...fixture.planTasks.first,
      'taskId': 799,
      'certificationName': 'SAMPLE 다른 시험',
    });
    await boot(t, fixture);
    for (final (id, value) in [(501, .5), (502, 0.0)]) {
      final bar = find.byKey(ValueKey('today-task-progress-$id'));
      expect(bar, findsOneWidget);
      expect(t.widget<LinearProgressIndicator>(bar).value, value);
    }
    expect(find.byKey(const ValueKey('today-task-progress-799')), findsNothing);
    expect(
      find.byKey(const ValueKey('planned-task-actions-501')),
      findsNothing,
    );
    await nav(t, '학습계획');
    expect(find.byTooltip('계획 수정'), findsNothing);
  });

  test('날짜 이동은 선택 날짜와 현재 계획 버전만 전송한다', () async {
    final today = dayInSeoul(), tomorrow = plusDays(today, 1);
    final changes = <Json>[];
    final fixture = StudyFixture(
      override: (r) async {
        if (r.method != 'PATCH') return null;
        expect(r.url.path, '$plannerPath/plans/5/tasks/501');
        final body = object(jsonDecode(r.body));
        changes.add(body);
        return studyEnvelope({
          ...body,
          'planId': 5,
          'taskId': 501,
          'planVersion': (body['expectedPlanVersion'] as int) + 1,
          'estimatedMinutes': 120,
        });
      },
    );
    addTearDown(fixture.dispose);
    await fixture.session.restore();
    final api = fixture.session.account!;
    await api.movePlanTask(5, 501, 3, tomorrow);
    expect(changes, [
      {'expectedPlanVersion': 3, 'scheduledDate': isoDay(tomorrow)},
    ]);
  });

  test('계획 기간 수정은 시작일·종료일과 현재 계획 버전을 전송한다', () async {
    final today = dayInSeoul(), end = plusDays(today, 9);
    final fixture = StudyFixture(
      override: (r) async {
        if (r.method != 'PATCH') return null;
        expect(r.url.path, '$plannerPath/plans/5/period');
        expect(object(jsonDecode(r.body)), {
          'expectedPlanVersion': 3,
          'startDate': isoDay(today),
          'endDate': isoDay(end),
        });
        return studyEnvelope({
          'planId': 5,
          'planVersion': 4,
          'startDate': isoDay(today),
          'endDate': isoDay(end),
        });
      },
    );
    addTearDown(fixture.dispose);
    await fixture.session.restore();
    await fixture.session.account!.changePlanPeriod(5, 3, today, end);
    expect(fixture.requests.where((r) => r.method == 'PATCH'), hasLength(1));
  });
}
