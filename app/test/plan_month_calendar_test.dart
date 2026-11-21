import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/ui/design.dart';
import 'package:passpace_mobile/ui/plan_month_calendar.dart';

SavedPlan sample() => SavedPlan.from({
  'planName': 'SAMPLE',
  'versionNo': 1,
  'startDate': '2027-12-20',
  'endDate': '2028-03-05',
  'tasks': [
    {
      'date': '2028-02-29',
      'certificationName': 'SQLD',
      'subjectName': 'SQL 활용',
      'minutes': 45,
    },
    {
      'date': '2028-02-29',
      'certificationName': 'SQLD',
      'subjectName': '모델링',
      'minutes': 30,
    },
  ],
});

Future<void> mount(
  WidgetTester t,
  DateTime initial, {
  double width = 412,
  double scale = 1,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(width, 1100);
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  var selected = initial;
  await t.pumpWidget(
    MaterialApp(
      theme: paceTheme(),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: PlanMonthCalendar(
              plan: sample(),
              selected: selected,
              today: DateTime(2028, 2, 29),
              onSelect: (d) => setState(() => selected = d),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> press(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  testWidgets('월 제목을 누르면 계획 기간 안의 다른 날짜로 바로 이동할 수 있다', (t) async {
    await mount(t, DateTime(2028, 2, 29));
    await press(t, find.byTooltip('다른 날짜로 이동'));
    final picker = t.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    expect(picker.firstDate, sample().start);
    expect(picker.lastDate, sample().end);
    await t.tap(find.widgetWithText(TextButton, 'Cancel'));
    await t.pumpAndSettle();
    expect(find.text('2028년 2월'), findsOneWidget);
  });
  testWidgets('선택한 날짜는 파란 강조와 접근성 상태를 유지하고 선택 문구는 표시하지 않는다', (t) async {
    await mount(t, DateTime(2028, 2, 29));
    final day = find.byKey(const ValueKey('calendar-day-2028-02-29'));
    expect(t.widget<Semantics>(day).properties.selected, true);
    expect(
      t
          .widget<Material>(
            find.descendant(of: day, matching: find.byType(Material)).first,
          )
          .color,
      blue,
    );
    expect(find.descendant(of: day, matching: find.text('선택')), findsNothing);
  });
  testWidgets('오늘이 계획 밖이면 계획 시작 또는 마지막 날짜를 보여준다', (t) async {
    await mount(t, DateTime(2026, 1, 1));
    expect(find.text('2027년 12월'), findsOneWidget);
    expect(
      t
          .widget<Semantics>(
            find.byKey(const ValueKey('calendar-day-2027-12-20')),
          )
          .properties
          .selected,
      true,
    );
    await mount(t, DateTime(2030, 1, 1));
    expect(find.text('2028년 3월'), findsOneWidget);
    expect(
      t
          .widget<Semantics>(
            find.byKey(const ValueKey('calendar-day-2028-03-05')),
          )
          .properties
          .selected,
      true,
    );
  });
  testWidgets('실행 중 글자를 확대해도 선택한 일요일 열이 보인다', (t) async {
    await mount(t, DateTime(2028, 3, 5), width: 320);
    t.platformDispatcher.textScaleFactorTestValue = 2;
    await t.pumpAndSettle();
    final viewport = t.getRect(
      find.byKey(const ValueKey('calendar-horizontal-scroll')),
    );
    final day = t.getRect(
      find.byKey(const ValueKey('calendar-day-2028-03-05')),
    );
    expect(day.left, greaterThanOrEqualTo(viewport.left - 1));
    expect(day.right, lessThanOrEqualTo(viewport.right + 1));
    expect(t.takeException(), isNull);
  });
  testWidgets('윤년·합계·빈 날짜와 선택 상태를 서버 배정으로 표시한다', (t) async {
    await mount(t, DateTime(2028, 2, 29));
    expect(find.text('2028년 2월'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar-day-2028-02-29')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('calendar-day-2028-02-30')), findsNothing);
    expect(find.text('1일 배정 · 계획 1시간 15분'), findsOneWidget);
    final assigned = t.widget<Semantics>(
      find.byKey(const ValueKey('calendar-day-2028-02-29')),
    );
    expect(assigned.properties.label, contains('계획 1시간 15분'));
    expect(assigned.properties.selected, true);
    final empty = find.byKey(const ValueKey('calendar-day-2028-02-28'));
    expect(t.widget<Semantics>(empty).properties.label, contains('계획된 학습 없음'));
    await press(t, empty);
    expect(t.widget<Semantics>(empty).properties.selected, true);
    expect(t.takeException(), isNull);
  });
  testWidgets('연도·월 경계 이동과 계획 기간 밖 선택을 제한한다', (t) async {
    await mount(t, DateTime(2027, 12, 31));
    expect(
      t
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == '이전 달',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      t
          .widget<Semantics>(
            find.byKey(const ValueKey('calendar-day-2027-12-19')),
          )
          .properties
          .enabled,
      false,
    );
    await press(t, find.byTooltip('다음 달'));
    expect(find.text('2028년 1월'), findsOneWidget);
    await press(t, find.byTooltip('다음 달'));
    expect(find.text('2028년 2월'), findsOneWidget);
    expect(
      t
          .widget<Semantics>(
            find.byKey(const ValueKey('calendar-day-2028-02-29')),
          )
          .properties
          .selected,
      true,
    );
    await press(t, find.byTooltip('다음 달'));
    expect(find.text('2028년 3월'), findsOneWidget);
    expect(
      t
          .widget<Semantics>(
            find.byKey(const ValueKey('calendar-day-2028-03-05')),
          )
          .properties
          .selected,
      true,
    );
    expect(
      t
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == '다음 달',
            ),
          )
          .onPressed,
      isNull,
    );
    await press(t, find.widgetWithText(TextButton, '오늘'));
    expect(find.text('2028년 2월'), findsOneWidget);
  });
  for (final width in [320.0, 360.0, 412.0]) {
    for (final scale in [1.5, 2.0]) {
      testWidgets('달력 날짜 48dp와 선택 열 노출: $width / $scale', (t) async {
        // March 5 is a Sunday; its column must be visible even in a narrow viewport.
        await mount(t, DateTime(2028, 3, 5), width: width, scale: scale);
        final day = find.byKey(const ValueKey('calendar-day-2028-03-05'));
        expect(t.getSize(day).width, greaterThanOrEqualTo(48));
        expect(t.getSize(day).height, greaterThanOrEqualTo(48));
        final viewport = t.getRect(
          find.byKey(const ValueKey('calendar-horizontal-scroll')),
        );
        expect(t.getRect(day).left, greaterThanOrEqualTo(viewport.left - 1));
        expect(t.getRect(day).right, lessThanOrEqualTo(viewport.right + 1));
        await press(t, day);
        expect(t.takeException(), isNull);
      });
    }
  }
}
