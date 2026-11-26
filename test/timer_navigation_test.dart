import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/data/study_models.dart';
import 'package:passpace_mobile/data/study_timer.dart';
import 'package:passpace_mobile/main.dart';
import 'package:passpace_mobile/ui/plan_month_calendar.dart';
import 'package:passpace_mobile/ui/study_records.dart';

import 'dart:async';

import 'study_records_test.dart' show tapStudy;
import 'support/study_fixture.dart';

Future<void> boot(WidgetTester t, StudyFixture f) async {
  await f.session.restore();
  await t.pumpWidget(PassPaceApp(f.session));
  await t.pumpAndSettle();
}

Future<void> nav(WidgetTester t, String text) => tapStudy(
  t,
  find.descendant(of: find.byType(NavigationBar), matching: find.text(text)),
);
void main() {
  testWidgets('홈 오늘 과목을 누르면 정확한 과목이 선택된 타이머로 열린다', (t) async {
    final day = isoDay(dayInSeoul());
    final f = StudyFixture(
      override: (r) async => r.url.path == '$plannerPath/saved'
          ? studyEnvelope({
              'plan': {
                'planId': 5,
                'planName': 'SAMPLE 홈',
                'versionNo': 3,
                'startDate': day,
                'endDate': day,
                'tasks': [
                  {
                    'date': day,
                    'certificationName': 'SAMPLE 기사',
                    'subjectName': 'SAMPLE 데이터베이스',
                    'minutes': 45,
                  },
                ],
              },
            })
          : null,
    );
    addTearDown(f.dispose);
    f.planTasks.insert(0, {
      ...f.planTasks.last,
      'taskId': 801,
      'certificationName': 'SAMPLE 다른 시험',
    });
    await boot(t, f);
    await tapStudy(t, find.text('SAMPLE 데이터베이스'));
    expect(find.byKey(const ValueKey('study-timer-clock')), findsOneWidget);
    final clock = t
        .state<StudyRecordsScreenState>(find.byType(StudyRecordsScreen))
        .timer!;
    expect(clock.task?.id, 502);
    expect(clock.phase, StudyTimerPhase.idle);
    expect(
      f.requests.any(
        (r) =>
            r.url.path == '/study/plan-tasks' &&
            r.url.queryParameters['date'] == day,
      ),
      isTrue,
    );
    expect(f.requests.where((r) => r.method == 'POST'), isEmpty);
    await clock.choose(StudyTaskChoice.from(f.planTasks.first));
    await clock.start();
    await nav(t, '홈');
    await tapStudy(t, find.text('SAMPLE 데이터베이스'));
    expect(find.textContaining('기존 측정 시간이 남아 있어요'), findsOneWidget);
    expect(clock.task?.id, 801);
    expect(clock.phase, StudyTimerPhase.running);
    await clock.pause();
  });

  testWidgets('입력 화면 위에서 알림을 열면 타이머가 보이고 원래 입력은 보존한다', (t) async {
    final f = StudyFixture();
    addTearDown(f.dispose);
    await boot(t, f);
    await nav(t, '기록');
    final records = t.state<StudyRecordsScreenState>(
      find.byType(StudyRecordsScreen),
    );
    final input = TextEditingController(text: 'SAMPLE 보존할 입력');
    addTearDown(input.dispose);
    unawaited(
      Navigator.of(t.element(find.byType(NavigationBar))).push<void>(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('SAMPLE 입력')),
            body: TextField(controller: input),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    unawaited(records.openNotificationTimer());
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('study-timer-clock')), findsOneWidget);
    await tapStudy(t, find.byType(BackButton));
    expect(find.text('SAMPLE 입력'), findsOneWidget);
    expect(input.text, 'SAMPLE 보존할 입력');
    expect(t.takeException(), isNull);
  });
  testWidgets('오늘 일정이 비어 있으면 학습계획에서 미래 일정을 볼 수 있다', (t) async {
    final start = plusDays(dayInSeoul(), 35), end = plusDays(dayInSeoul(), 70);
    final f = StudyFixture(
      override: (r) async => r.url.path == '$plannerPath/saved'
          ? studyEnvelope({
              'plan': {
                'planName': 'SAMPLE 미래',
                'versionNo': 3,
                'startDate': isoDay(start),
                'endDate': isoDay(end),
                'tasks': [
                  {
                    'date': isoDay(start),
                    'certificationName': 'SAMPLE',
                    'subjectName': 'SAMPLE 미래 과목',
                    'minutes': 40,
                  },
                ],
              },
            })
          : null,
    );
    addTearDown(f.dispose);
    await boot(t, f);
    expect(find.text('계획된 학습 없음'), findsOneWidget);
    expect(find.text('SAMPLE 미래 과목'), findsNothing);
    await tapStudy(t, find.byKey(const ValueKey('home-open-schedule')));
    final subject = find.text('SAMPLE 미래 과목');
    await t.scrollUntilVisible(
      subject,
      250,
      scrollable: find.byType(Scrollable).hitTestable().first,
    );
    expect(subject, findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('하단 홈·기록의 기본 화면은 타이머이고 목록과 통계는 별도로 연다', (t) async {
    final f = StudyFixture();
    addTearDown(f.dispose);
    await boot(t, f);
    NavigationBar navigation() =>
        t.widget<NavigationBar>(find.byType(NavigationBar));
    expect(
      navigation().destinations.cast<NavigationDestination>().map(
        (item) => item.label,
      ),
      ['학습계획', '기록', '홈', '상담', '내 정보'],
    );
    expect(navigation().selectedIndex, 2);
    await nav(t, '기록');
    expect(navigation().selectedIndex, 1);
    expect(find.byKey(const ValueKey('study-timer-clock')), findsOneWidget);
    expect(find.byKey(const ValueKey('study-total')), findsNothing);
    expect(f.requests.where((r) => r.url.path == '/study/sessions'), isEmpty);
    final clock = t
        .state<StudyRecordsScreenState>(find.byType(StudyRecordsScreen))
        .timer!;
    await clock.start();
    await t.pumpAndSettle();
    await tapStudy(t, find.byKey(const ValueKey('open-study-history')));
    expect(find.byKey(const ValueKey('history-add')), findsOneWidget);
    expect(find.byKey(const ValueKey('study-timer-clock')), findsNothing);
    await nav(t, '기록');
    expect(find.byKey(const ValueKey('study-timer-clock')), findsOneWidget);
    await tapStudy(t, find.byKey(const ValueKey('open-study-statistics')));
    expect(find.byKey(const ValueKey('study-total')), findsOneWidget);
    expect(find.byKey(const ValueKey('study-timer-clock')), findsNothing);
    final switcher = find.byKey(const ValueKey('study-pane-switch'));
    final beforeScroll = t.getRect(switcher);
    await t.drag(
      find.byKey(const ValueKey('study-view-1')),
      const Offset(0, -500),
    );
    await t.pumpAndSettle();
    expect(t.getRect(switcher), beforeScroll);
    await tapStudy(t, find.byKey(const ValueKey('study-timer-open')));
    expect(find.byKey(const ValueKey('study-timer-clock')), findsOneWidget);
    expect(
      t.state<StudyRecordsScreenState>(find.byType(StudyRecordsScreen)).timer,
      same(clock),
    );
    expect(clock.phase, StudyTimerPhase.running);
    expect(f.requests.where((r) => r.method == 'POST'), isEmpty);
    await clock.pause();
    await nav(t, '홈');
    expect(navigation().selectedIndex, 2);
    await nav(t, '기록');
    expect(find.byKey(const ValueKey('study-timer-clock')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('학습계획은 월간 일정으로 열리고 전체 목록으로 전환할 수 있다', (t) async {
    final day = dayInSeoul(),
        start = DateTime(dayInSeoul().year, dayInSeoul().month, 1);
    final end = DateTime(start.year, start.month + 2, 0);
    final f = StudyFixture(
      override: (r) async => r.url.path == '$plannerPath/saved'
          ? studyEnvelope({
              'plan': {
                'planName': 'SAMPLE',
                'versionNo': 3,
                'startDate': isoDay(start),
                'endDate': isoDay(end),
                'tasks': [
                  {
                    'date': isoDay(day),
                    'certificationName': 'SAMPLE',
                    'subjectName': 'SAMPLE 과목',
                    'minutes': 30,
                  },
                ],
              },
            })
          : null,
    );
    addTearDown(f.dispose);
    await boot(t, f);
    expect(find.text('학습 달력'), findsNothing);
    expect(
      find.byKey(const PageStorageKey('home-month-calendar')),
      findsOneWidget,
    );
    final calendar = t.widget<ExpansionTile>(
      find.byKey(const PageStorageKey('home-month-calendar-toggle')),
    );
    expect((calendar.shape as Border).top.width, 1);
    await tapStudy(t, find.byKey(const ValueKey('home-open-schedule')));
    final month = find.byKey(const ValueKey('plan-month-calendar'));
    expect(find.text('이번 주'), findsNothing);
    if (month.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        month,
        350,
        scrollable: find.byType(Scrollable).hitTestable().first,
      );
    }
    expect(t.widget<PlanMonthCalendar>(month).plan.end, end);
    await tapStudy(t, find.byTooltip('다음 달'));
    expect(find.text('${end.year}년 ${end.month}월'), findsOneWidget);
    await tapStudy(t, find.byTooltip('목록으로 보기'));
    expect(month, findsNothing);
    expect(t.takeException(), isNull);
  });
}
