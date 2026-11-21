import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/session.dart';
import 'package:passpace_mobile/main.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/ui/dashboard.dart';
import 'package:passpace_mobile/ui/design.dart';
import 'package:passpace_mobile/ui/planner.dart';
import 'package:passpace_mobile/ui/plan_comparison.dart';
import 'package:passpace_mobile/data/plan_comparison.dart';

Json samplePlanData() => {
  'planId': 1,
  'planName': 'SAMPLE',
  'versionNo': 1,
  'startDate': '2026-11-15',
  'endDate': '2026-11-21',
  'tasks': [
    {
      'date': '2026-11-15',
      'certificationName': '정보처리기사 필기 (2027~)',
      'subjectName': '데이터베이스 구축과 소프트웨어 개발 기초',
      'minutes': 960,
    },
  ],
};

SavedPlan samplePlan() => SavedPlan.from(samplePlanData());

class _Store implements SessionStore {
  String value = jsonEncode({'origin': emulatorOrigin, 'token': 'SAMPLE'});
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    value = next;
  }
}

Future<void> screen(
  WidgetTester t,
  Widget child, {
  required double width,
  required double scale,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(width, 720);
  await t.pumpWidget(
    MaterialApp(
      theme: paceTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: child),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('처리 중 표시도 비활성 버튼 배경에서 읽을 수 있다', (t) async {
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        theme: paceTheme(),
        home: const Scaffold(
          body: Center(child: PrimaryAction('저장', null, busy: true)),
        ),
      ),
    );
    await t.pump();
    final progress = t.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    final fill = t
        .widget<Material>(
          find
              .descendant(
                of: find.byType(FilledButton),
                matching: find.byType(Material),
              )
              .first,
        )
        .color!;
    final foreground = progress.color ?? blue;
    final background = Color.alphaBlend(fill, paper);
    final a = foreground.computeLuminance(), b = background.computeLuminance();
    final ratio = (a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05));
    expect(ratio, greaterThanOrEqualTo(3));
  });
  for (final width in [320.0, 360.0, 412.0]) {
    for (final scale in [1.5, 2.0]) {
      testWidgets('앱의 계획·프로필·목표: 너비 $width, 글자 $scale', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(width, 720);
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final client = MockClient((r) async {
          final Object data;
          if (r.url.path == '/auth/user-info') {
            data = {
              'loginId': 'SAMPLE',
              'nickname': '화면검증',
              'email': 'sample@example.invalid',
              'majorType': 'RELATED',
              'majorTypeLabel': '유사전공',
            };
          } else if (r.url.path == '/users/me/goal') {
            data = {
              'goal': {
                'dailyMinutes': 180,
                'targetExamDate': '2026-12-20',
                'familiarity': {},
              },
              'subjects': [],
              'examRounds': [],
            };
          } else if (r.url.path == '$plannerPath/saved') {
            final p = samplePlanData();
            final today = dayInSeoul();
            p['startDate'] = isoDay(today);
            p['endDate'] = isoDay(plusDays(today, 7));
            p['tasks'][0]['date'] = isoDay(today);
            data = {'plan': p};
          } else {
            throw StateError(r.url.path);
          }
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({'status': 'SUCCESS', 'code': 200, 'data': data}),
            ),
            200,
          );
        });
        addTearDown(client.close);
        final session = Session(_Store(), client);
        await session.restore();
        await t.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              size: Size(width, 720),
              textScaler: TextScaler.linear(scale),
            ),
            child: PassPaceApp(session),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('학습계획'),
          ),
        );
        await t.pumpAndSettle();
        final scroll = find
            .descendant(
              of: find.byKey(const PageStorageKey('plan-scroll')),
              matching: find.byType(Scrollable),
            )
            .first;
        await t.ensureVisible(find.text('전체 일정'));
        await t.pumpAndSettle();
        await t.tap(find.text('전체 일정'));
        await t.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('plan-month-calendar')),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.text('이번 주'));
        await t.pumpAndSettle();
        await t.tap(find.text('이번 주'));
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.textContaining('오늘 ·'),
          260,
          scrollable: scroll,
        );
        expect(t.takeException(), isNull);
        await t.tap(find.text('내 정보').last);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.text('학습계획 관리'));
        await t.tap(find.text('학습계획 관리'));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('설정 수정'));
        await t.tap(find.text('설정 수정'));
        await t.pumpAndSettle();
        expect(find.text('목표 저장'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
      testWidgets('긴 과목·그래프·비교: 너비 $width, 글자 $scale', (t) async {
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final p = samplePlan();
        final preview = Preview.from({
          'totalRemainingMinutes': 960,
          'totalShortfallMinutes': 0,
          'feasible': true,
          'notices': [],
          'days': [
            {'date': '2026-11-15', 'allocatedMinutes': 960, 'allocations': []},
          ],
        });
        await screen(
          t,
          ScrollBody(
            children: [
              TaskTile(p.on(DateTime(2026, 11, 15)).single, onTap: () {}),
              WeekLoad(preview.weekAt(0)),
              PlanComparisonSummary(PlanComparison(p, preview)),
            ],
          ),
          width: width,
          scale: scale,
        );
        expect(t.takeException(), isNull);
        final details = find.text('변경 상세 1건 보기');
        await t.ensureVisible(details);
        await t.tap(details);
        await t.pumpAndSettle();
        expect(find.text('계획 변경 상세'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  }
  testWidgets('작은 화면의 날짜 선택도 Android 터치 영역을 충족한다', (t) async {
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final semantics = t.ensureSemantics();
    try {
      await screen(
        t,
        ScrollBody(
          children: [
            WeekStrip(
              selected: DateTime(2026, 11, 15),
              today: DateTime(2026, 11, 15),
              plan: samplePlan(),
              change: (_) {},
            ),
          ],
        ),
        width: 320,
        scale: 1.5,
      );
      final day = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            (w.properties.label ?? '').contains('15일') &&
            w.properties.button == true,
      );
      expect(t.getSize(day).width, greaterThanOrEqualTo(48));
      final viewport = t.getRect(find.byType(HorizontalChoices));
      expect(t.getRect(day).left, greaterThanOrEqualTo(viewport.left - 1));
      expect(t.getRect(day).right, lessThanOrEqualTo(viewport.right + 1));
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
    } finally {
      semantics.dispose();
    }
  });
  testWidgets('큰 글자·키보드·긴 오류에서도 다음 버튼을 사용할 수 있다', (t) async {
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    var pressed = 0;
    await screen(
      t,
      Column(
        children: [
          const Expanded(child: SingleChildScrollView(child: Text('입력 내용'))),
          StickyActions(
            '계획 미리보기',
            () => pressed++,
            onBack: () {},
            summary: '12개 시험 · 주 7일 · 하루 960분',
            error: '목표 시험일과 학습 시작일을 확인해 주세요. 입력한 내용은 보존됩니다. 날짜를 수정한 뒤 다시 계획을 확인해 주세요.',
          ),
        ],
      ),
      width: 320,
      scale: 2,
    );
    // A small visible area represents the space left above the keyboard.
    t.view.physicalSize = const Size(320, 420);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.tap(find.widgetWithText(FilledButton, '계획 미리보기'));
    expect(pressed, 1);
  });
}
