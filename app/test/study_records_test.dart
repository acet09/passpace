import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/main.dart';
import 'package:passpace_mobile/ui/study_chart.dart';
import 'package:passpace_mobile/ui/study_records.dart';
import 'package:passpace_mobile/ui/design.dart';

import 'support/study_fixture.dart';

Future<void> tapStudy(WidgetTester t, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).hitTestable().first,
    );
  }
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  await t.tap(finder);
  await t.pumpAndSettle();
}

Future<void> openStudy(WidgetTester t, StudyFixture fixture) async {
  await fixture.session.restore();
  await t.pumpWidget(PassPaceApp(fixture.session));
  await t.pumpAndSettle();
  await tapStudy(
    t,
    find.descendant(of: find.byType(NavigationBar), matching: find.text('기록')),
  );
  await tapStudy(t, find.byKey(const ValueKey('open-study-history')));
}

void main() {
  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
  testWidgets('기록 탭에서 기존 계정의 실제 공부시간 목록을 연다', (t) async {
    final fixture = StudyFixture();
    addTearDown(fixture.dispose);
    await fixture.session.restore();
    await t.pumpWidget(PassPaceApp(fixture.session));
    await t.pumpAndSettle();
    final entry = find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('기록'),
    );
    expect(entry, findsOneWidget);
    await t.tap(entry);
    await t.pumpAndSettle();
    await tapStudy(t, find.byKey(const ValueKey('open-study-history')));
    expect(find.text('공부시간 추가'), findsOneWidget);
    expect(find.text('SAMPLE 정보처리기사의 긴 과목 이름'), findsOneWidget);
    expect(
      fixture.requests.where((r) => r.url.path == '/study/sessions'),
      isNotEmpty,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('공부시간을 한 번만 저장하고 목록과 서버 통계를 갱신한다', (t) async {
    final response = Completer<http.Response>();
    late StudyFixture fixture;
    fixture = StudyFixture(
      override: (r) async => r.method == 'POST' ? response.future : null,
    );
    addTearDown(fixture.dispose);
    await openStudy(t, fixture);
    await tapStudy(t, find.text('공부시간 추가'));
    await t.enterText(find.byKey(const ValueKey('study-minutes')), '45');
    final save = find.text('공부시간 저장');
    await t.ensureVisible(save);
    await t.tap(save);
    await t.tap(save);
    await t.pump();
    expect(fixture.requests.where((r) => r.method == 'POST'), hasLength(1));
    response.complete(
      studyEnvelope(
        fixture.storeRecord({
          'studyDate': isoDay(fixture.today),
          'durationMinutes': 45,
        }),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('45분'), findsOneWidget);
    await tapStudy(t, find.byKey(const ValueKey('open-study-statistics')));
    expect(find.byType(StudyChart), findsOneWidget);
    expect(
      t.widget<Text>(find.byKey(const ValueKey('study-total'))).data,
      '2시간 15분',
    );
    await tapStudy(t, find.widgetWithText(ChoiceChip, '막대'));
    expect(
      t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '막대')).selected,
      true,
    );
    expect(find.textContaining('완료율'), findsNothing);
    expect(t.takeException(), isNull);
  });

  for (final code in [400, 409]) {
    testWidgets('저장 $code 실패 후 입력한 날짜와 시간이 남는다', (t) async {
      final fixture = StudyFixture(
        override: (r) async => r.method == 'POST'
            ? studyEnvelope({'detail': 'SAMPLE 하루 공부시간 한도 확인'}, code)
            : null,
      );
      addTearDown(fixture.dispose);
      await openStudy(t, fixture);
      await tapStudy(t, find.text('공부시간 추가'));
      await t.enterText(find.byKey(const ValueKey('study-minutes')), '90');
      await tapStudy(t, find.text('공부시간 저장'));
      expect(find.text('SAMPLE 하루 공부시간 한도 확인'), findsOneWidget);
      expect(
        t
            .widget<TextFormField>(find.byKey(const ValueKey('study-minutes')))
            .controller!
            .text,
        '90',
      );
      expect(find.text(isoDay(fixture.today)), findsOneWidget);
      expect(fixture.history.length, 2);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('응답 유실 후 목록을 확인하기 전까지 중복 저장하지 않는다', (t) async {
    late StudyFixture fixture;
    fixture = StudyFixture(
      override: (r) async {
        if (r.method != 'POST') return null;
        fixture.storeRecord(object(jsonDecode(r.body)));
        throw http.ClientException('SAMPLE acknowledgement lost');
      },
    );
    addTearDown(fixture.dispose);
    await openStudy(t, fixture);
    await tapStudy(t, find.text('공부시간 추가'));
    await t.enterText(find.byKey(const ValueKey('study-minutes')), '45');
    await tapStudy(t, find.text('공부시간 저장'));
    expect(find.textContaining('이미 저장되었을 수'), findsOneWidget);
    expect(find.text('공부시간 저장'), findsNothing);
    await tapStudy(t, find.text('기록 목록 확인'));
    expect(find.text('45분'), findsOneWidget);
    expect(
      t
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '공부시간 추가'),
          )
          .onPressed,
      isNull,
    );
    expect(fixture.requests.where((r) => r.method == 'POST'), hasLength(1));
    await tapStudy(t, find.text('기록 확인 완료'));
    expect(
      t
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '공부시간 추가'),
          )
          .onPressed,
      isNotNull,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('목록 페이지와 최근 30일 기간은 조회 API의 조건을 따른다', (t) async {
    final fixture = StudyFixture(empty: true);
    addTearDown(fixture.dispose);
    for (var i = 0; i < 25; i++) {
      fixture.history.add({
        'sessionId': i + 1,
        'studyDate': isoDay(fixture.today),
        'durationMinutes': 1,
        'subjectName': 'SAMPLE 과목 ${i + 1}',
      });
    }
    await openStudy(t, fixture);
    await t.scrollUntilVisible(
      find.text('이전 기록 더 보기'),
      400,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('study-view-0')),
        matching: find.byType(Scrollable),
      ),
    );
    await tapStudy(t, find.text('이전 기록 더 보기'));
    expect(
      fixture.requests.where((r) => r.url.queryParameters['page'] == '1'),
      hasLength(1),
    );
    await t.scrollUntilVisible(
      find.text('SAMPLE 과목 1'),
      250,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('study-view-0')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('SAMPLE 과목 1'), findsOneWidget);
    await t.fling(
      find.byKey(const ValueKey('study-view-0')),
      const Offset(0, 8000),
      10000,
    );
    await t.pumpAndSettle();
    await tapStudy(t, find.text('최근 30일'));
    final req = fixture.requests.lastWhere(
      (r) => r.url.path == '/study/sessions',
    );
    expect(
      req.url.queryParameters['startDate'],
      isoDay(plusDays(fixture.today, -29)),
    );
    expect(req.url.queryParameters['endDate'], isoDay(fixture.today));
    expect(req.url.queryParameters['page'], '0');
    expect(t.takeException(), isNull);
  });

  testWidgets('403 뒤 늦게 도착한 통계로 개인 정보를 다시 표시하지 않는다', (t) async {
    final history = Completer<http.Response>(),
        stats = Completer<http.Response>();
    final fixture = StudyFixture(
      override: (r) async {
        if (r.url.path == '/study/sessions') return history.future;
        if (r.url.path == '/dashboard/study-stats') return stats.future;
        return null;
      },
    );
    addTearDown(fixture.dispose);
    await fixture.session.restore();
    await t.pumpWidget(PassPaceApp(fixture.session));
    await t.pumpAndSettle();
    await t.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('기록'),
      ),
    );
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byKey(const ValueKey('open-study-history')));
    await t.pump(const Duration(milliseconds: 300));
    history.complete(studyEnvelope({'ko': 'SAMPLE 권한 없음'}, 403));
    await t.pumpAndSettle();
    stats.complete(
      studyEnvelope({
        'period': 'CUSTOM',
        'startDate': isoDay(plusDays(fixture.today, -6)),
        'endDate': isoDay(fixture.today),
        'timezone': 'Asia/Seoul',
        'totalMinutes': 420,
        'dailyStudyMinutes': [
          for (var i = 0; i < 7; i++)
            {
              'studyDate': isoDay(plusDays(fixture.today, i - 6)),
              'durationMinutes': 60,
            },
        ],
        'completionRate': null,
      }),
    );
    await t.pumpAndSettle();
    expect(find.text('기록을 확인할 수 없어요'), findsOneWidget);
    expect(find.byType(StudyChart), findsNothing);
    expect(find.textContaining('SAMPLE 정보처리'), findsNothing);
    expect(t.takeException(), isNull);
  });

  for (final size in [320.0, 360.0, 412.0]) {
    for (final scale in [1.5, 2.0]) {
      testWidgets('기록·통계·입력 $size/$scale 글자 확대와 키보드에서 넘치지 않는다', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(size, 820);
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
          t.platformDispatcher.clearTextScaleFactorTestValue();
          t.view.resetViewInsets();
        });
        final fixture = StudyFixture();
        addTearDown(fixture.dispose);
        await openStudy(t, fixture);
        expect(t.takeException(), isNull);
        await tapStudy(t, find.byKey(const ValueKey('open-study-statistics')));
        await tapStudy(t, find.widgetWithText(ChoiceChip, '막대'));
        expect(t.takeException(), isNull);
        await t.fling(
          find.byKey(const ValueKey('study-view-1')),
          const Offset(0, 5000),
          5000,
        );
        await t.pumpAndSettle();
        await tapStudy(t, find.byKey(const ValueKey('open-study-history')));
        await tapStudy(t, find.text('공부시간 추가'));
        t.view.viewInsets = const FakeViewPadding(bottom: 300);
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const ValueKey('study-minutes')), '0');
        await tapStudy(t, find.text('공부시간 저장'));
        expect(find.text('공부한 시간을 1~1,440분 사이로 입력해 주세요.'), findsOneWidget);
        expect(fixture.requests.where((r) => r.method == 'POST'), isEmpty);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('빈 기록과 통계 0분을 연결 오류 상태와 구분한다', (t) async {
    final fixture = StudyFixture(empty: true);
    addTearDown(fixture.dispose);
    await openStudy(t, fixture);
    expect(find.text('이 기간에 저장한 기록이 없어요'), findsOneWidget);
    await tapStudy(t, find.byKey(const ValueKey('open-study-statistics')));
    expect(
      t.widget<Text>(find.byKey(const ValueKey('study-total'))).data,
      '0분',
    );
    await t.pumpWidget(const SizedBox());
    final failed = StudyFixture(
      override: (r) async =>
          r.url.path == '/study/sessions' ||
              r.url.path == '/dashboard/study-stats'
          ? studyEnvelope({'ko': 'SAMPLE 연결 오류'}, 503)
          : null,
    );
    addTearDown(failed.dispose);
    await openStudy(t, failed);
    expect(find.text('이 기간에 저장한 기록이 없어요'), findsNothing);
    expect(find.text('다시 불러오기'), findsOneWidget);
    await tapStudy(t, find.byKey(const ValueKey('open-study-statistics')));
    expect(find.byKey(const ValueKey('study-total')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('화면에 진입하기 전에는 기록 API를 호출하지 않고 401은 기존 로그인을 만료시킨다', (t) async {
    final fixture = StudyFixture(
      override: (r) async => r.url.path == '/study/sessions'
          ? studyEnvelope({'ko': 'SAMPLE 로그인 만료'}, 401)
          : null,
    );
    addTearDown(fixture.dispose);
    await fixture.session.restore();
    await t.pumpWidget(PassPaceApp(fixture.session));
    await t.pumpAndSettle();
    expect(
      fixture.requests.where((r) => r.url.path == '/study/sessions'),
      isEmpty,
    );
    await tapStudy(
      t,
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('기록'),
      ),
    );
    await tapStudy(t, find.byKey(const ValueKey('open-study-history')));
    expect(fixture.session.account, isNull);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.textContaining('SAMPLE 정보처리'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('기간을 바꾼 뒤 이전 기간 응답이 도착해도 새 기록을 덮지 않는다', (t) async {
    final oldHistory = Completer<http.Response>(),
        oldStats = Completer<http.Response>();
    var histories = 0, statistics = 0;
    final fixture = StudyFixture(
      override: (r) async {
        if (r.url.path == '/study/sessions' && histories++ == 0) {
          return oldHistory.future;
        }
        if (r.url.path == '/dashboard/study-stats' && statistics++ == 0) {
          return oldStats.future;
        }
        return null;
      },
    );
    addTearDown(fixture.dispose);
    await fixture.session.restore();
    await t.pumpWidget(PassPaceApp(fixture.session));
    await t.pumpAndSettle();
    await t.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('기록'),
      ),
    );
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byKey(const ValueKey('open-study-history')));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('최근 30일'));
    await t.pumpAndSettle();
    expect(find.text('SAMPLE 정보처리기사의 긴 과목 이름'), findsOneWidget);
    oldHistory.complete(
      studyEnvelope({'items': [], 'page': 0, 'pageSize': 20, 'hasNext': false}),
    );
    oldStats.complete(studyEnvelope({'ko': 'SAMPLE 이전 기간 응답'}, 500));
    await t.pumpAndSettle();
    expect(find.text('SAMPLE 정보처리기사의 긴 과목 이름'), findsOneWidget);
    expect(find.text('이 기간에 저장한 기록이 없어요'), findsNothing);
    await tapStudy(t, find.byKey(const ValueKey('open-study-statistics')));
    expect(
      t.widget<Text>(find.byKey(const ValueKey('study-total'))).data,
      '1시간 30분',
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('같은 계정의 인증 갱신 뒤 이전 요청을 폐기하고 다시 조회한다', (t) async {
    final oldHistory = Completer<http.Response>(),
        oldStats = Completer<http.Response>();
    var histories = 0, statistics = 0;
    final fixture = StudyFixture(
      override: (r) async {
        if (r.url.path == '/users/me' && r.method == 'PUT') {
          return studyEnvelope({'accessToken': 'SAMPLE_RENEWED'});
        }
        if (r.url.path == '/study/sessions' && histories++ == 0) {
          return oldHistory.future;
        }
        if (r.url.path == '/dashboard/study-stats' && statistics++ == 0) {
          return oldStats.future;
        }
        return null;
      },
    );
    addTearDown(fixture.dispose);
    await fixture.session.restore();
    await t.pumpWidget(PassPaceApp(fixture.session));
    await t.pumpAndSettle();
    await t.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('기록'),
      ),
    );
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.byKey(const ValueKey('open-study-history')));
    await t.pump(const Duration(milliseconds: 300));
    await fixture.session.updateProfile(
      'SAMPLE 갱신',
      'sample@example.invalid',
      'MAJOR',
    );
    await t.pumpAndSettle();
    expect(find.text('SAMPLE 정보처리기사의 긴 과목 이름'), findsOneWidget);
    oldHistory.complete(
      studyEnvelope({'items': [], 'page': 0, 'pageSize': 20, 'hasNext': false}),
    );
    oldStats.complete(studyEnvelope({'ko': 'SAMPLE 이전 인증 응답'}, 500));
    await t.pumpAndSettle();
    expect(find.text('SAMPLE 정보처리기사의 긴 과목 이름'), findsOneWidget);
    expect(histories, 2);
    final query = fixture.requests.lastWhere(
      (r) => r.url.path == '/study/sessions',
    );
    expect(query.headers['Authorization'], 'Bearer SAMPLE_RENEWED');
    expect(t.takeException(), isNull);
  });

  testWidgets('입력 중 인증이 갱신되면 이전 입력을 저장하지 않는다', (t) async {
    final fixture = StudyFixture(
      override: (r) async => r.url.path == '/users/me' && r.method == 'PUT'
          ? studyEnvelope({'accessToken': 'SAMPLE_RENEWED'})
          : null,
    );
    addTearDown(fixture.dispose);
    await openStudy(t, fixture);
    await tapStudy(t, find.text('공부시간 추가'));
    await t.enterText(find.byKey(const ValueKey('study-minutes')), '90');
    await fixture.session.updateProfile(
      'SAMPLE 갱신',
      'sample@example.invalid',
      'MAJOR',
    );
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('study-minutes')), findsNothing);
    expect(find.text('기록으로 돌아가기'), findsOneWidget);
    expect(fixture.requests.where((r) => r.method == 'POST'), isEmpty);
    await tapStudy(t, find.text('기록으로 돌아가기'));
    expect(find.text('공부시간 추가'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('소수나 긴 숫자를 다른 공부시간으로 바꾸지 않고 입력 오류로 안내한다', (t) async {
    final fixture = StudyFixture();
    addTearDown(fixture.dispose);
    await openStudy(t, fixture);
    await tapStudy(t, find.text('공부시간 추가'));
    for (final raw in ['1.5', '10000', '-10', 'abc', '1441']) {
      await t.enterText(find.byKey(const ValueKey('study-minutes')), raw);
      await tapStudy(t, find.text('공부시간 저장'));
      expect(find.text('공부한 시간을 1~1,440분 사이로 입력해 주세요.'), findsOneWidget);
      expect(fixture.requests.where((r) => r.method == 'POST'), isEmpty);
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('한국 날짜가 바뀌어 앱에 복귀하면 최근 기간이 오늘까지 갱신된다', (t) async {
    final fixture = StudyFixture();
    addTearDown(fixture.dispose);
    await fixture.session.restore();
    var now = fixture.today;
    await t.pumpWidget(
      MaterialApp(
        theme: paceTheme(),
        home: Scaffold(
          body: StudyRecordsScreen(
            fixture.session,
            active: true,
            today: () => now,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    for (final n in [7, 30]) {
      if (find
          .byKey(const ValueKey('open-study-history'))
          .evaluate()
          .isNotEmpty) {
        await tapStudy(t, find.byKey(const ValueKey('open-study-history')));
      }
      await tapStudy(t, find.text('최근 $n일'));
      now = plusDays(now, 1);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      final query = fixture.requests.lastWhere(
        (r) => r.url.path == '/study/sessions',
      );
      expect(query.url.queryParameters['endDate'], isoDay(now));
      expect(
        query.url.queryParameters['startDate'],
        isoDay(plusDays(now, 1 - n)),
      );
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('조회 기간이 연도를 넘으면 목록 날짜에 연도를 표시한다', (t) async {
    final fixture = StudyFixture(empty: true);
    addTearDown(fixture.dispose);
    fixture.history.addAll([
      {'sessionId': 1, 'studyDate': '2026-12-31', 'durationMinutes': 15},
      {'sessionId': 2, 'studyDate': '2027-01-01', 'durationMinutes': 15},
    ]);
    await fixture.session.restore();
    await t.pumpWidget(
      MaterialApp(
        theme: paceTheme(),
        home: Scaffold(
          body: StudyRecordsScreen(
            fixture.session,
            active: true,
            today: () => DateTime(2027, 1, 2),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await tapStudy(t, find.byKey(const ValueKey('open-study-history')));
    expect(find.text('2026년 12월 31일'), findsOneWidget);
    expect(find.text('2027년 1월 1일'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
