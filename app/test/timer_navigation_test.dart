import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/models.dart';
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
  testWidgets('미래 계획의 월간 달력과 홈 학습 목록은 같은 선택 날짜를 보여준다', (t) async {
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
    await tapStudy(t, find.byKey(const ValueKey('home-calendar-expand')));
    expect(find.text('${shortDay(start)} 학습'), findsOneWidget);
    expect(find.text('SAMPLE 미래 과목'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('하단 홈·기록의 기본 화면은 타이머이고 목록과 통계는 별도로 연다', (t) async {
    final f = StudyFixture();
    addTearDown(f.dispose);
    await boot(t, f);
    expect(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('홈')),
      findsOneWidget,
    );
    await nav(t, '기록');
    expect(find.byKey(const ValueKey('study-timer-clock')), findsOneWidget);
    expect(find.byKey(const ValueKey('study-total')), findsNothing);
    expect(f.requests.where((r) => r.url.path == '/study/sessions'), isEmpty);
    final clock = t
        .state<StudyRecordsScreenState>(find.byType(StudyRecordsScreen))
        .timer!;
    await clock.start();
    await t.pumpAndSettle();
    await tapStudy(t, find.byKey(const ValueKey('open-study-history')));
    expect(find.text('공부시간 추가'), findsOneWidget);
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
    await nav(t, '기록');
    expect(find.byKey(const ValueKey('study-timer-clock')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('홈은 주간을 월간으로 펼치고 계획은 월간 달력부터 표시한다', (t) async {
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
    await tapStudy(t, find.byKey(const ValueKey('home-calendar-expand')));
    expect(find.byKey(const ValueKey('home-month-calendar')), findsOneWidget);
    await tapStudy(t, find.byTooltip('다음 달'));
    expect(find.text('${end.year}년 ${end.month}월'), findsOneWidget);
    await tapStudy(t, find.byKey(const ValueKey('home-calendar-week')));
    expect(find.byKey(const ValueKey('home-month-calendar')), findsNothing);
    expect(find.text('이번 주 학습'), findsOneWidget);
    await tapStudy(t, find.byKey(const ValueKey('home-calendar-expand')));
    await nav(t, '학습계획');
    final month = find.byKey(const ValueKey('plan-month-calendar'));
    if (month.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        month,
        350,
        scrollable: find.byType(Scrollable).hitTestable().first,
      );
    }
    expect(t.widget<PlanMonthCalendar>(month).plan.end, end);
    expect(t.takeException(), isNull);
  });
}
