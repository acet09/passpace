import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/data/study_models.dart';
import 'package:passpace_mobile/ui/design.dart';
import 'package:passpace_mobile/ui/study_chart.dart';

void main() {
  testWidgets('일별 수치는 날짜·요일·시간으로 보이고7일씩 이동한다', (t) async {
    final start = DateTime(2026, 11, 7), end = DateTime(2026, 11, 16);
    final stats = StudyStats.from({
      'startDate': isoDay(start),
      'endDate': isoDay(end),
      'timezone': 'Asia/Seoul',
      'totalMinutes': 850,
      'dailyStudyMinutes': [
        for (var i = 0; i < 10; i++)
          {'studyDate': isoDay(plusDays(start, i)), 'durationMinutes': 85},
      ],
    });
    await t.pumpWidget(
      MaterialApp(
        theme: paceTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StudyChart(
              stats,
              subjectsByDay: {
                end: [(name: 'SAMPLE 과목', minutes: 30, color: blue)],
              },
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('한국 시간'), findsNothing);
    expect(find.text('일별 공부시간'), findsOneWidget);
    expect(find.byKey(const ValueKey('study-day-2026-11-16')), findsOneWidget);
    expect(find.textContaining('1시간 25분'), findsWidgets);
    expect(find.textContaining('이 날짜의 과목별 시간을 확인할 수 없어요'), findsOneWidget);
    expect(find.text('SAMPLE 과목'), findsNothing);
    final ink = find.descendant(
      of: find.byKey(const ValueKey('study-day-2026-11-16')),
      matching: find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == muted,
      ),
    );
    expect(t.getSize(ink).height, 5);
    expect(t.getSize(ink).width, greaterThan(0));
    final previous = find.byTooltip('이전 7일');
    await t.ensureVisible(previous);
    await t.tap(previous);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('study-day-2026-11-07')), findsOneWidget);
    expect(find.byKey(const ValueKey('study-day-2026-11-16')), findsNothing);
    expect(t.takeException(), isNull);
  });
  for (final count in [30, 366]) {
    testWidgets('$count일 그래프의 첫 점과 마지막 점은 해당 날짜를 선택한다', (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(320, 1000);
      addTearDown(() {
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      final start = DateTime(2026, 1, 1),
          end = plusDays(DateTime(2026, 1, 1), count - 1);
      final stats = StudyStats.from({
        'startDate': isoDay(start),
        'endDate': isoDay(end),
        'timezone': 'Asia/Seoul',
        'totalMinutes': 0,
        'dailyStudyMinutes': [
          for (var i = 0; i < count; i++)
            {'studyDate': isoDay(plusDays(start, i)), 'durationMinutes': 0},
        ],
      });
      await t.pumpWidget(
        MaterialApp(
          theme: paceTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: StudyChart(stats),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final rect = t.getRect(find.byKey(const ValueKey('study-plot')));
      await t.tapAt(Offset(rect.left + 5, rect.center.dy));
      await t.pumpAndSettle();
      expect(find.text(isoDay(start)), findsOneWidget);
      await t.tapAt(Offset(rect.right - 5, rect.center.dy));
      await t.pumpAndSettle();
      expect(find.text(isoDay(end)), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
