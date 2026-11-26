import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/ui/design.dart' show muted;
import 'package:passpace_mobile/ui/subject_color_picker.dart';

import 'study_records_test.dart' show tapStudy;
import 'support/draft_storage.dart';
import 'support/study_fixture.dart';
import 'timer_navigation_test.dart' show boot, nav;

void main() {
  test('팔레트보다 많은 과목에도 서로 다른 색을 배정하고 과목 순서가 바뀌어도 유지한다', () {
    final subjects = List.generate(24, (index) => '과목 $index');
    final colors = automaticSubjectColors(subjects, 'SAMPLE 계정');
    expect(
      colors.values.map((color) => color.toARGB32()).toSet(),
      hasLength(24),
    );
    expect(
      automaticSubjectColors([
        ...subjects.reversed,
        subjects.first,
      ], 'SAMPLE 계정'),
      colors,
    );
    for (final color in colors.values) {
      final contrast =
          (subjectColorTrack(color).computeLuminance() + .05) /
          (color.computeLuminance() + .05);
      expect(contrast, greaterThanOrEqualTo(3));
    }
  });

  testWidgets('자동 색은 겹치지 않고 직접 고른 같은 색은 앱을 다시 열어도 유지된다', (t) async {
    final tomorrow = isoDay(plusDays(dayInSeoul(), 1));
    final emptyDay = isoDay(plusDays(dayInSeoul(), 2));
    late final StudyFixture fixture;
    fixture = StudyFixture(
      override: (request) async {
        if (request.url.path != '$plannerPath/saved') return null;
        return studyEnvelope({
          'plan': {
            'planId': 5,
            'versionNo': 3,
            'planName': 'SAMPLE 색상 계획',
            'startDate': fixture.planTasks.first['scheduledDate'],
            'endDate': emptyDay,
            'tasks': [
              for (final item in fixture.planTasks)
                {
                  'taskId': item['taskId'],
                  'certificationName': item['certificationName'],
                  'subjectName': item['subjectName'],
                  'date': item['scheduledDate'],
                  'minutes': 120,
                },
              {
                'taskId': 503,
                'certificationName':
                    fixture.planTasks.first['certificationName'],
                'subjectName': fixture.planTasks.first['subjectName'],
                'date': tomorrow,
                'minutes': 120,
              },
            ],
          },
        });
      },
    );
    addTearDown(fixture.dispose);
    await boot(t, fixture);
    final bar = find.byKey(const ValueKey('today-task-progress-501'));
    final other = find.byKey(const ValueKey('today-task-progress-502'));
    final marker = find.byKey(const ValueKey('today-task-color-501'));
    const teal = Color(0xff17846f);
    Color? barColor(Finder finder) =>
        t.widget<LinearProgressIndicator>(finder).color;
    Future<void> pick(int taskId, String label) async {
      await tapStudy(t, find.byKey(ValueKey('planned-task-actions-$taskId')));
      expect(find.text('다른 날짜로 옮기기'), findsOneWidget);
      await tapStudy(t, find.text('색상 변경'));
      expect(find.text('자동 배정'), findsNothing);
      expect(
        t.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor,
        Colors.white,
      );
      expect(find.text(label), findsOneWidget);
      await tapStudy(t, find.text(label));
    }

    Future<Color?> planDot(int id) async {
      final dot = find.byKey(ValueKey('plan-task-color-$id'));
      if (dot.evaluate().isEmpty) {
        await t.scrollUntilVisible(
          dot,
          250,
          scrollable: find.byType(Scrollable).hitTestable().first,
          maxScrolls: 6,
        );
      }
      return (t.widget<DecoratedBox>(dot).decoration as BoxDecoration).color;
    }

    expect(marker, findsOneWidget);
    final firstAutomatic = barColor(bar), secondAutomatic = barColor(other);
    expect(firstAutomatic, isNotNull);
    expect(secondAutomatic, isNotNull);
    expect(firstAutomatic, isNot(secondAutomatic));
    int historyReads() =>
        fixture.requests.where((r) => r.url.path == '/study/sessions').length;
    final beforePlan = historyReads();
    await nav(t, '학습계획');
    expect(await planDot(501), firstAutomatic);
    expect(find.byKey(const ValueKey('plan-month-calendar')), findsOneWidget);
    final planProgress = find.byKey(const ValueKey('plan-task-progress-501'));
    expect(barColor(planProgress), firstAutomatic);
    expect(t.widget<LinearProgressIndicator>(planProgress).value, .5);
    expect(historyReads(), beforePlan);
    await nav(t, '홈');
    await pick(501, '청록');
    expect(
      (t.widget<DecoratedBox>(marker).decoration as BoxDecoration).color,
      teal,
    );
    expect(barColor(bar), teal);
    expect(t.widget<LinearProgressIndicator>(bar).value, .5);
    expect(barColor(other), secondAutomatic);
    final homeCalendar = find.byKey(
      const PageStorageKey('home-month-calendar'),
    );
    final toggle = find.byKey(
      const PageStorageKey('home-month-calendar-toggle'),
    );
    final calendarTitle = find.text('월간 일정');
    expect(homeCalendar, findsOneWidget);
    expect(t.getTopLeft(toggle).dy, greaterThan(t.getBottomLeft(other).dy));
    await tapStudy(t, calendarTitle);
    expect(homeCalendar, findsNothing);
    await tapStudy(t, calendarTitle);
    final tomorrowCell = find.byKey(ValueKey('calendar-day-$tomorrow'));
    await tapStudy(t, tomorrowCell);
    final preview = find.byKey(const ValueKey('home-month-selected-day'));
    expect(
      find.descendant(of: preview, matching: find.text('2시간')),
      findsOneWidget,
    );
    final coloredMarker = find.descendant(
      of: tomorrowCell,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color == teal,
      ),
    );
    expect(coloredMarker, findsOneWidget);
    await tapStudy(t, find.byKey(ValueKey('calendar-day-$emptyDay')));
    expect(
      find.descendant(of: preview, matching: find.text('계획된 학습 없음')),
      findsOneWidget,
    );
    await tapStudy(t, calendarTitle);
    expect(homeCalendar, findsNothing);
    final openSchedule = find.byKey(const ValueKey('home-open-schedule'));
    expect(find.descendant(of: toggle, matching: openSchedule), findsOneWidget);
    await tapStudy(t, openSchedule);
    expect(
      t
          .widget<Semantics>(find.byKey(ValueKey('calendar-day-$emptyDay')))
          .properties
          .selected,
      isTrue,
    );
    await tapStudy(t, find.byKey(ValueKey('calendar-day-$tomorrow')));
    expect(await planDot(503), teal);
    expect(find.byKey(const ValueKey('plan-task-progress-503')), findsNothing);
    await nav(t, '홈');
    await pick(502, '청록');
    expect(barColor(other), teal);
    await t.pumpWidget(const SizedBox.shrink());
    await boot(t, fixture);
    expect(barColor(bar), teal);
    expect(barColor(other), teal);

    final storage = fixture.session.drafts as MemoryDraftStorage;
    storage.failWrites = true;
    await pick(501, '보라');
    expect(find.text('과목 색상을 저장하지 못했어요.'), findsOneWidget);
    expect(barColor(bar), teal);
    storage.failWrites = false;
    String colorName(Color? color) => SubjectColorChoice.values
        .firstWhere((choice) => choice.color == color)
        .label!;
    await pick(501, colorName(firstAutomatic));
    await pick(502, colorName(secondAutomatic));
    expect(marker, findsOneWidget);
    expect(barColor(bar), firstAutomatic);
    expect(barColor(other), secondAutomatic);

    final ring = find.byKey(const ValueKey('study-timer-progress'));
    Color? ringColor() => t.widget<CircularProgressIndicator>(ring).color;
    await tapStudy(t, find.text('SAMPLE 정보처리기사의 긴 과목 이름'));
    expect(ringColor(), firstAutomatic);
    await tapStudy(t, find.text('과목 선택'));
    final connectedDot = find.byKey(const ValueKey('study-task-color-502'));
    expect(
      (t.widget<DecoratedBox>(connectedDot).decoration as BoxDecoration).color,
      secondAutomatic,
    );
    await tapStudy(t, find.byKey(const ValueKey('study-task-502')));
    expect(ringColor(), secondAutomatic);

    await nav(t, '홈');
    await pick(501, '청록');
    await tapStudy(t, find.text('SAMPLE 정보처리기사의 긴 과목 이름'));
    expect(ringColor(), teal);
    await tapStudy(t, find.text('과목 선택'));
    final manualDot = find.byKey(const ValueKey('study-task-color-501'));
    expect(
      (t.widget<DecoratedBox>(manualDot).decoration as BoxDecoration).color,
      teal,
    );
    await tapStudy(t, find.text('과목 연결 없음'));
    expect(ringColor(), const Color(0xff3155c7));

    fixture.planTasks.add({
      ...fixture.planTasks.first,
      'taskId': 810,
      'planId': 10,
      'planStatus': 'REPLACED',
    });
    fixture.history.add({
      ...fixture.history.first,
      'sessionId': 3,
      'taskId': 810,
      'planId': 10,
      'durationMinutes': 20,
    });
    Color? dotColor(String key) =>
        (t.widget<DecoratedBox>(find.byKey(ValueKey(key))).decoration
                as BoxDecoration)
            .color;
    await tapStudy(t, find.byKey(const ValueKey('open-study-history')));
    expect(dotColor('study-record-color-1'), teal);
    expect(dotColor('study-record-color-3'), teal);
    expect(find.byKey(const ValueKey('study-record-color-2')), findsNothing);
    fixture.history.add({
      ...fixture.history.first,
      'sessionId': 4,
      'taskId': 502,
      'subjectId': 12,
      'subjectName': 'SAMPLE 데이터베이스',
      'durationMinutes': 10,
    });
    await tapStudy(t, find.byKey(const ValueKey('open-study-statistics')));
    expect(dotColor('study-subject-color-0'), teal);
    final subjectBar = find.byKey(const ValueKey('study-subject-bar-0'));
    expect(barColor(subjectBar), teal);
    expect(t.widget<LinearProgressIndicator>(subjectBar).value, 1);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('study-subject-breakdown')),
        matching: find.text('1시간 20분'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('study-subject-color-1')), findsNothing);
    final breakdown = find.byKey(const ValueKey('study-selected-subjects'));
    Finder selectedText(String value) =>
        find.descendant(of: breakdown, matching: find.text(value));
    expect(selectedText('SAMPLE 정보처리기사의 긴 과목 이름'), findsOneWidget);
    expect(selectedText('1시간 20분'), findsOneWidget);
    expect(selectedText('SAMPLE 데이터베이스'), findsOneWidget);
    expect(selectedText('10분'), findsOneWidget);
    final plot = find.byKey(const ValueKey('study-plot'));
    final legend = find.byKey(const ValueKey('study-chart-legend'));
    void expectLegendColor(String name, Color? color) {
      final label = find.descendant(of: legend, matching: find.text(name));
      expect(label, findsOneWidget);
      final entry = find.ancestor(of: label, matching: find.byType(Row)).first;
      final dot = find.descendant(
        of: entry,
        matching: find.byType(SubjectColorDot),
      );
      expect(t.widget<SubjectColorDot>(dot).color, color);
    }

    expect(legend, findsOneWidget);
    expect(t.getTopLeft(legend).dy, greaterThan(t.getBottomLeft(plot).dy));
    expectLegendColor('SAMPLE 정보처리기사의 긴 과목 이름', teal);
    expectLegendColor('SAMPLE 데이터베이스', secondAutomatic);
    expectLegendColor('과목 미연결', muted);
    expect(
      t.renderObject(plot),
      paints
        ..rect(color: muted)
        ..rect(color: teal)
        ..rect(color: secondAutomatic),
    );
    final segments = find.byKey(
      ValueKey('study-day-segments-${isoDay(fixture.today)}'),
    );
    final bars = t.widget<Row>(segments).children.cast<Expanded>();
    expect(bars.map((bar) => bar.flex), [80, 10]);
    expect(bars.map((bar) => (bar.child as ColoredBox).color), [
      teal,
      secondAutomatic,
    ]);
    final databaseFilter = find.descendant(
      of: legend,
      matching: find.text('SAMPLE 데이터베이스'),
    );
    final selectedDay = find.byKey(const ValueKey('study-selected-day'));
    final total = find.byKey(const ValueKey('study-total'));
    final databaseChip = find.widgetWithText(FilterChip, 'SAMPLE 데이터베이스');
    await tapStudy(t, databaseFilter);
    expect(t.widget<FilterChip>(databaseChip).selected, isTrue);
    expect(t.widget<Text>(selectedDay).data, '10분');
    expect(t.widget<Text>(total).data, '2시간');
    expect(selectedText('SAMPLE 정보처리기사의 긴 과목 이름'), findsNothing);
    expect(t.renderObject(plot), paints..rect(color: secondAutomatic));
    await tapStudy(t, find.byTooltip('이전 날짜'));
    expect(t.widget<Text>(selectedDay).data, '0분');
    expect(selectedText('과목 미연결'), findsNothing);
    await tapStudy(t, databaseFilter);
    expect(t.widget<FilterChip>(databaseChip).selected, isFalse);
    expect(t.widget<Text>(selectedDay).data, '30분');
    expect(selectedText('과목 미연결'), findsOneWidget);
    await tapStudy(t, find.byTooltip('다음 날짜'));
    expect(t.widget<Text>(selectedDay).data, '1시간 30분');
    await tapStudy(t, find.byTooltip('이전 날짜'));
    expect(selectedText('과목 미연결'), findsOneWidget);
    expect(selectedText('30분'), findsOneWidget);
    expectLegendColor('SAMPLE 데이터베이스', secondAutomatic);
    await tapStudy(t, find.text('꺾은선'));
    expect(selectedText('30분'), findsOneWidget);
    expect(legend, findsNothing);
    expect(
      fixture.requests.where((request) => request.method != 'GET'),
      isEmpty,
    );
  });
}
