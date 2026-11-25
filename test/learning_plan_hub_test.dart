import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/data/session.dart';
import 'package:passpace_mobile/main.dart';

import 'support/draft_storage.dart';

class _Store implements SessionStore {
  String value = jsonEncode({'origin': emulatorOrigin, 'token': 'SAMPLE'});
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    value = next;
  }
}

http.Response ok(Object? data, [int code = 200]) => http.Response.bytes(
  utf8.encode(
    jsonEncode({
      'status': code == 200 ? 'SUCCESS' : 'ERROR',
      'code': code,
      'data': data,
    }),
  ),
  code,
);

class HubFixture {
  final today = dayInSeoul();
  late Json goal = {
    'examRoundId': null,
    'targetExamDate': isoDay(plusDays(today, 35)),
    'dailyMinutes': 90,
    'familiarity': {'11': 3},
  };
  final goalWrites = <Json>[];
  int planWrites = 0;
  int taskDays = 1;
  Completer<http.Response>? pendingGoal, pendingPlan;
  bool goalError = false, planError = false, updateError = false;
  Json goalData() => {
    'goal': goal,
    'examRounds': [],
    'subjects': [
      {'subjectId': 11, 'subjectName': 'SQL 활용'},
    ],
  };
  Json planData() => {
    'plan': {
      'planId': 11,
      'versionNo': 2,
      'planName': 'SQLD',
      'startDate': isoDay(today),
      'endDate': isoDay(plusDays(today, 35)),
      'tasks': [
        for (var i = 0; i < taskDays; i++)
          {
            'date': isoDay(plusDays(today, i)),
            'certificationName': 'SQLD',
            'subjectName': 'SQL 활용',
            'minutes': 45,
          },
      ],
    },
  };
  late final http.Client client = MockClient((r) async {
    if (r.url.path == '/auth/user-info') {
      return ok({
        'loginId': 'SAMPLE',
        'nickname': '목표검증',
        'email': 'sample@example.invalid',
        'majorType': 'RELATED',
        'majorTypeLabel': '유사전공',
      });
    }
    if (r.url.path == '/users/me/goal') {
      if (r.method == 'PUT') {
        goalWrites.add(object(jsonDecode(r.body)));
        if (updateError) return ok({'ko': '저장 실패'}, 503);
        goal = object(jsonDecode(r.body));
        return ok({});
      }
      if (goalError) return ok({'ko': '목표 조회 실패'}, 503);
      if (pendingGoal != null) return pendingGoal!.future;
      return ok(goalData());
    }
    if (r.url.path == '$plannerPath/saved') {
      if (planError) return ok({'ko': '계획 조회 실패'}, 503);
      if (pendingPlan != null) return pendingPlan!.future;
      return ok(planData());
    }
    if (r.url.path == '$plannerPath/catalog') {
      return ok({
        'profileDailyMinutes': 150,
        'notices': [],
        'goals': [
          {
            'key': 'sqld',
            'certificationName': 'SQLD',
            'suggestedExamDate': isoDay(plusDays(today, 35)),
            'subjects': [
              {'subjectId': 11, 'name': 'SQL 활용', 'baseHours': 10},
            ],
          },
        ],
      });
    }
    if (r.url.path == '$plannerPath/save') {
      planWrites++;
      return ok({'planId': 12});
    }
    throw StateError('${r.method} ${r.url.path}');
  });
  late final session = Session(_Store(), client, drafts: MemoryDraftStorage());
}

Future<void> tap(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  await t.tap(finder);
  await t.pumpAndSettle();
}

Finder tab(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Future<void> open(WidgetTester t, HubFixture f) async {
  addTearDown(f.client.close);
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = const Size(360, 720);
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.view.resetPhysicalSize);
  await f.session.restore();
  await t.pumpWidget(PassPaceApp(f.session));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('월간 달력에서 선택한 날짜의 과목 목록이 열린다', (t) async {
    final f = HubFixture()..taskDays = 2;
    await open(t, f);
    await tap(t, tab('학습계획'));
    final tomorrow = plusDays(f.today, 1);
    if (tomorrow.month != f.today.month) {
      await tap(t, find.byTooltip('다음 달'));
    }
    await tap(t, find.byKey(ValueKey('calendar-day-${isoDay(tomorrow)}')));
    final selected = find.widgetWithText(ExpansionTile, shortDay(tomorrow));
    expect(selected, findsOneWidget);
    expect(
      find.descendant(of: selected, matching: find.text('SQL 활용')),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('전체 일정의 달력에서 빈 날짜를 선택하고 기존 목록으로 전환한다', (t) async {
    final f = HubFixture();
    await open(t, f);
    await tap(t, tab('학습계획'));
    expect(find.byKey(const ValueKey('plan-month-calendar')), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('SQL 활용'),
      240,
      scrollable: find
          .descendant(
            of: find.byKey(const PageStorageKey('plan-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tap(t, find.text('SQL 활용'));
    expect(find.text('계획 45분'), findsWidgets);
    expect(find.text('SQLD'), findsWidgets);
    expect(find.text('이 과목 공부 방법 상담'), findsOneWidget);
    await t.tapAt(const Offset(10, 100));
    await t.pumpAndSettle();
    final tomorrow = plusDays(f.today, 1);
    if (tomorrow.month != f.today.month) {
      await tap(t, find.byTooltip('다음 달'));
    }
    await tap(t, find.byKey(ValueKey('calendar-day-${isoDay(tomorrow)}')));
    expect(find.text('계획된 학습 없음'), findsOneWidget);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.text('계획된 학습 없음'), findsOneWidget);
    expect(
      t
          .widget<Semantics>(
            find.byKey(ValueKey('calendar-day-${isoDay(tomorrow)}')),
          )
          .properties
          .selected,
      true,
    );
    await tap(t, find.byTooltip('목록으로 보기'));
    expect(find.byKey(const ValueKey('plan-month-calendar')), findsNothing);
    expect(find.text('날짜별 학습'), findsOneWidget);
    final monthHeading = find.text('${f.today.year}년 ${f.today.month}월');
    final dayHeading = find.text(
      '오늘 · ${f.today.day}일 ${weekdays[f.today.weekday - 1]}요일',
    );
    expect(monthHeading, findsOneWidget);
    expect(
      t.getTopLeft(monthHeading).dy,
      lessThan(t.getTopLeft(dayHeading).dy),
    );
    expect(
      t.getTopLeft(dayHeading).dy,
      lessThan(t.getTopLeft(find.text('SQL 활용')).dy),
    );
    expect(f.goalWrites, isEmpty);
    expect(f.planWrites, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets('기본값은 학습계획 탭에 없고 새 계획 첫 단계에서만 열 수 있다', (t) async {
    final f = HubFixture()..taskDays = 30;
    await open(t, f);
    await tap(t, tab('학습계획'));
    await tap(t, find.byTooltip('목록으로 보기'));
    expect(find.text('새 계획 기본값'), findsNothing);
    expect(find.byTooltip('목표와 기본 설정'), findsNothing);
    await tap(t, tab('내 정보'));
    await tap(t, tab('학습계획'));
    expect(find.text('새 계획 기본값'), findsNothing);
    await tap(t, find.byTooltip('새 계획 만들기'));
    expect(find.text('새 계획 기본값'), findsOneWidget);
    await tap(t, find.text('새 계획 기본값'));
    expect(find.text('기존 값 불러오기'), findsOneWidget);
    expect(find.text('기본값 수정'), findsOneWidget);
    expect(f.goalWrites, isEmpty);
    expect(f.planWrites, 0);
    expect(t.takeException(), isNull);
  });

  testWidgets('기본값 저장 후에도 현재 입력을 유지하고 필요할 때 다시 불러올 수 있다', (t) async {
    final f = HubFixture();
    await open(t, f);
    await tap(t, tab('학습계획'));
    await tap(t, find.byTooltip('새 계획 만들기'));
    await t.enterText(find.byType(TextField).first, '130');
    await tap(t, find.text('새 계획 기본값'));
    await tap(t, find.text('기본값 수정'));
    await t.enterText(find.byType(TextField).first, '180');
    await tap(t, find.text('기본값 저장'));
    await tap(t, find.text('현재 입력 유지'));
    expect(
      t.widget<TextField>(find.byType(TextField).first).controller!.text,
      '130',
    );
    await tap(t, find.text('새 계획 기본값'));
    await tap(t, find.text('기존 값 불러오기'));
    await tap(t, find.text('불러오기'));
    expect(
      t.widget<TextField>(find.byType(TextField).first).controller!.text,
      '180',
    );
    expect(f.goalWrites, hasLength(1));
    expect(f.planWrites, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets('애니메이션 제거 설정에서도 내려간 학습계획에서 요약으로 돌아온다', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final f = HubFixture()..taskDays = 30;
    await open(t, f);
    await tap(t, tab('학습계획'));
    await tap(t, find.byTooltip('목록으로 보기'));
    final list = find.byKey(const PageStorageKey('plan-scroll'));
    final controller = t.widget<ListView>(list).controller!;
    controller.jumpTo(1200);
    await t.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    await tap(t, tab('학습계획'));
    expect(t.takeException(), isNull);
    expect(controller.offset, 0);
    expect(find.text('저장된 학습계획').hitTestable(), findsOneWidget);
    expect(find.text('새 계획 기본값'), findsNothing);
  });
  testWidgets('다시 불러오는 동안에도 보고 있던 일정과 위치를 유지한다', (t) async {
    final f = HubFixture()..taskDays = 30;
    await open(t, f);
    await tap(t, tab('학습계획'));
    await tap(t, find.byTooltip('목록으로 보기'));
    final list = find.byKey(const PageStorageKey('plan-scroll'));
    final controller = t.widget<ListView>(list).controller!;
    controller.jumpTo(1200);
    await t.pumpAndSettle();
    final offset = controller.offset;
    f.pendingGoal = Completer<http.Response>();
    f.pendingPlan = Completer<http.Response>();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    await t.pump(const Duration(milliseconds: 20));
    try {
      expect(t.widget(list), isA<ListView>());
      expect(controller.offset, closeTo(offset, 1));
    } finally {
      f.pendingGoal!.complete(ok(f.goalData()));
      f.pendingPlan!.complete(ok(f.planData()));
      await t.pumpAndSettle();
    }
    expect(controller.offset, closeTo(offset, 1));
    expect(f.goalWrites, isEmpty);
    expect(f.planWrites, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets('홈의 목표일은 기본값이 없는 학습계획 탭을 연다', (t) async {
    final f = HubFixture();
    await open(t, f);
    String selectedTab() {
      final bar = t.widget<NavigationBar>(find.byType(NavigationBar));
      return (bar.destinations[bar.selectedIndex] as NavigationDestination)
          .label;
    }

    await tap(t, find.text('D-35'));
    expect(selectedTab(), '학습계획');
    expect(find.text('새 계획 기본값'), findsNothing);
    expect(find.text('저장된 학습계획'), findsOneWidget);
    await tap(t, tab('내 정보'));
    expect(find.text('학습계획 관리'), findsNothing);
    expect(find.text('학습 설정'), findsNothing);
    expect(find.text('회원정보 수정'), findsOneWidget);
    await tap(t, tab('학습계획'));
    expect(selectedTab(), '학습계획');
    expect(find.text('저장된 학습계획').hitTestable(), findsOneWidget);
    expect(find.text('새 계획 기본값'), findsNothing);
    expect(f.goalWrites, isEmpty);
    expect(f.planWrites, 0);
  });
  testWidgets('설정 저장 후 같은 화면에서 불러온 값으로 계획 작성을 이어간다', (t) async {
    final f = HubFixture();
    await open(t, f);
    await tap(t, tab('학습계획'));
    await tap(t, find.byTooltip('새 계획 만들기'));
    await tap(t, find.text('새 계획 기본값'));
    await tap(t, find.text('기본값 수정'));
    await t.enterText(find.byType(TextField).first, '180');
    await tap(t, find.text('기본값 저장'));
    await tap(t, find.text('기본값 적용'));
    expect(find.text('저장한 기본값을 적용했어요.'), findsOneWidget);
    expect(f.goalWrites.single, {
      'examRoundId': null,
      'targetExamDate': isoDay(plusDays(f.today, 35)),
      'dailyMinutes': 180,
      'familiarity': {'11': 3},
    });
    expect(f.planWrites, 0);
    expect(
      t.widget<TextField>(find.byType(TextField).first).controller!.text,
      '180',
    );
    await tap(t, find.widgetWithText(FilledButton, '다음'));
    await tap(t, find.byType(CheckboxListTile));
    await tap(t, find.widgetWithText(FilledButton, '다음'));
    expect(
      t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '익숙함')).selected,
      true,
    );
    expect(f.planWrites, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets('설정 취소와 저장 실패는 기존 일정과 입력을 유지한다', (t) async {
    final f = HubFixture();
    await open(t, f);
    await tap(t, tab('학습계획'));
    await tap(t, find.byTooltip('새 계획 만들기'));
    await tap(t, find.text('새 계획 기본값'));
    await tap(t, find.text('기본값 수정'));
    await t.enterText(find.byType(TextField).first, '120');
    await tap(t, find.byType(BackButton));
    expect(f.goalWrites, isEmpty);
    await tap(t, find.text('새 계획 기본값'));
    await tap(t, find.text('기본값 수정'));
    expect(
      t.widget<TextField>(find.byType(TextField).first).controller!.text,
      '90',
    );
    await t.enterText(find.byType(TextField).first, '120');
    f.updateError = true;
    await tap(t, find.text('기본값 저장'));
    expect(find.byType(TextField), findsOneWidget);
    expect(
      t.widget<TextField>(find.byType(TextField).first).controller!.text,
      '120',
    );
    expect(f.planWrites, 0);
    expect(f.goal['dailyMinutes'], 90);
    expect(t.takeException(), isNull);
  });
  for (final goalFails in [true, false]) {
    testWidgets('조회 오류는 다른 영역을 막지 않는다: 목표 오류 $goalFails', (t) async {
      final f = HubFixture()
        ..goalError = goalFails
        ..planError = !goalFails;
      await open(t, f);
      await tap(t, tab('학습계획'));
      expect(find.text('새 계획 기본값'), findsNothing);
      if (goalFails) {
        expect(find.text('저장된 학습계획'), findsOneWidget);
        await tap(t, find.byTooltip('새 계획 만들기'));
        expect(find.textContaining('저장한 목표를 불러오지 못했어요'), findsOneWidget);
      } else {
        expect(find.text('계획을 불러오지 못했어요'), findsOneWidget);
        await tap(t, find.byTooltip('새 계획 만들기'));
        await tap(t, find.text('새 계획 기본값'));
        await tap(t, find.text('기본값 수정'));
        expect(find.text('기본값 저장'), findsOneWidget);
      }
      expect(f.goalWrites, isEmpty);
      expect(f.planWrites, 0);
    });
  }
}
