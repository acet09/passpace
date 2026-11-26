import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:passpace_mobile/data/study_timer.dart';

import 'study_records_test.dart' show openStudy, tapStudy;
import 'support/study_fixture.dart';
import 'support/draft_storage.dart';

Future<void> seedTimer(StudyFixture fixture, {int seconds = 85}) async {
  await fixture.session.restore();
  var ticks = 0;
  final day = fixture.today;
  var now = DateTime.utc(day.year, day.month, day.day, 3);
  final timer = StudyTimer(
    fixture.session.drafts,
    fixture.session.origin,
    fixture.session.user!.id,
    now: () => now,
    ticks: () => ticks,
  );
  await timer.restore();
  await timer.start();
  ticks += seconds * 1000;
  now = now.add(Duration(seconds: seconds));
  await timer.pause();
  timer.dispose();
}

void main() {
  testWidgets('타이머가 저장되지 않았음을 확인하면 측정값을 보존하고 자동 재전송하지 않는다', (t) async {
    final fixture = StudyFixture(
      empty: true,
      override: (r) async {
        if (r.method == 'POST') {
          throw http.ClientException('SAMPLE before commit');
        }
        return null;
      },
    );
    addTearDown(fixture.dispose);
    await seedTimer(fixture);
    await openStudy(t, fixture);
    await tapStudy(t, find.byKey(const ValueKey('study-timer-open')));
    await tapStudy(t, find.text('기록 저장'));
    await tapStudy(t, find.text('기록 목록에서 확인'));
    await tapStudy(t, find.text('기록 확인 완료'));
    await tapStudy(t, find.text('기록 없음 · 측정 유지'));
    await tapStudy(t, find.byKey(const ValueKey('study-timer-open')));
    expect(find.text('00:01:25'), findsOneWidget);
    expect(fixture.requests.where((r) => r.method == 'POST'), hasLength(1));
    expect(fixture.history, isEmpty);
    expect(t.takeException(), isNull);
  });
  testWidgets('타이머 저장 이중 탭은 POST 한 번만 보내고 성공 뒤 다시 열어도0부터 시작한다', (t) async {
    final pending = Completer<http.Response>();
    final fixture = StudyFixture(
      override: (r) async => r.method == 'POST' ? pending.future : null,
    );
    addTearDown(fixture.dispose);
    await seedTimer(fixture);
    await openStudy(t, fixture);
    await tapStudy(t, find.byKey(const ValueKey('study-timer-open')));
    final save = find.widgetWithText(OutlinedButton, '기록 저장');
    await t.ensureVisible(save);
    await t.tap(save);
    await t.tap(save);
    await t.pumpAndSettle();
    expect(fixture.requests.where((r) => r.method == 'POST'), hasLength(1));
    final record = {
      'sessionId': 3,
      'studyDate': fixture.history.first['studyDate'],
      'durationMinutes': 1,
      'taskId': null,
      'inputMethod': 'MANUAL',
    };
    fixture.history.add(record);
    pending.complete(studyEnvelope(record));
    await t.pumpAndSettle();
    await tapStudy(t, find.byKey(const ValueKey('study-timer-open')));
    expect(find.text('00:00:00'), findsOneWidget);
    expect(fixture.requests.where((r) => r.method == 'POST'), hasLength(1));
    expect(t.takeException(), isNull);
  });
  testWidgets('타이머 응답 유실은 목록 확인 전까지 새 저장을 막고 재전송하지 않는다', (t) async {
    late StudyFixture fixture;
    fixture = StudyFixture(
      override: (r) async {
        if (r.method != 'POST') return null;
        fixture.history.add({
          'sessionId': 3,
          'studyDate': fixture.history.first['studyDate'],
          'durationMinutes': 1,
          'taskId': null,
          'inputMethod': 'MANUAL',
        });
        throw http.ClientException('SAMPLE acknowledgement lost');
      },
    );
    addTearDown(fixture.dispose);
    await seedTimer(fixture);
    await openStudy(t, fixture);
    await tapStudy(t, find.byKey(const ValueKey('study-timer-open')));
    await tapStudy(t, find.text('기록 저장'));
    expect(find.textContaining('저장 결과를 확인하지 못했어요'), findsOneWidget);
    await tapStudy(t, find.text('기록 목록에서 확인'));
    expect(
      t.widget<TextButton>(find.byKey(const ValueKey('history-add'))).onPressed,
      isNull,
    );
    await tapStudy(t, find.text('기록 확인 완료'));
    await tapStudy(t, find.text('저장된 기록 확인'));
    expect(fixture.requests.where((r) => r.method == 'POST'), hasLength(1));
    await tapStudy(t, find.byKey(const ValueKey('study-timer-open')));
    expect(find.text('00:00:00'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('타이머 저장409는 측정값을 유지하고 자동으로 다시 보내지 않는다', (t) async {
    final fixture = StudyFixture(
      override: (r) async => r.method == 'POST'
          ? studyEnvelope({'detail': 'SAMPLE 계획 변경 확인'}, 409)
          : null,
    );
    addTearDown(fixture.dispose);
    await seedTimer(fixture);
    await openStudy(t, fixture);
    await tapStudy(t, find.byKey(const ValueKey('study-timer-open')));
    await tapStudy(t, find.text('기록 저장'));
    expect(find.text('SAMPLE 계획 변경 확인'), findsOneWidget);
    expect(find.text('00:01:25'), findsOneWidget);
    expect(fixture.requests.where((r) => r.method == 'POST'), hasLength(1));
    expect(t.takeException(), isNull);
  });
  testWidgets('타이머 저장 전 기기 쓰기가 실패하면 API에 보내지 않는다', (t) async {
    final fixture = StudyFixture();
    addTearDown(fixture.dispose);
    await seedTimer(fixture);
    await openStudy(t, fixture);
    await tapStudy(t, find.byKey(const ValueKey('study-timer-open')));
    (fixture.session.drafts as MemoryDraftStorage).failWrites = true;
    await tapStudy(t, find.text('기록 저장'));
    expect(find.textContaining('기기에 타이머 상태를 저장하지 못했어요'), findsOneWidget);
    expect(fixture.requests.where((r) => r.method == 'POST'), isEmpty);
    expect(t.takeException(), isNull);
  });
  testWidgets('저장 중 로그아웃 뒤 도착한 응답은 이전 계정 화면을 다시 열지 않는다', (t) async {
    final pending = Completer<http.Response>();
    final fixture = StudyFixture(
      override: (r) async => r.method == 'POST' ? pending.future : null,
    );
    addTearDown(fixture.dispose);
    await seedTimer(fixture);
    await openStudy(t, fixture);
    await tapStudy(t, find.byKey(const ValueKey('study-timer-open')));
    await tapStudy(t, find.text('기록 저장'));
    await fixture.session.logout();
    await t.pumpAndSettle();
    pending.complete(
      studyEnvelope({
        'sessionId': 3,
        'studyDate': fixture.history.first['studyDate'],
        'durationMinutes': 1,
        'taskId': null,
        'inputMethod': 'MANUAL',
      }),
    );
    await t.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const ValueKey('study-timer-clock')), findsNothing);
    expect(t.takeException(), isNull);
  });
  for (final width in [320.0, 360.0, 412.0]) {
    for (final scale in [1.5, 2.0]) {
      testWidgets('타이머 $width/$scale 글자 확대에서 과목·저장 버튼에 접근한다', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(width, 820);
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
          t.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final fixture = StudyFixture();
        addTearDown(fixture.dispose);
        await seedTimer(fixture);
        await openStudy(t, fixture);
        await tapStudy(t, find.byKey(const ValueKey('study-timer-open')));
        await tapStudy(t, find.text('과목 선택'));
        await tapStudy(t, find.text('SAMPLE 데이터베이스'));
        await t.ensureVisible(find.text('기록 저장'));
        await t.pumpAndSettle();
        expect(find.text('00:01:25'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }
  }
  testWidgets('타이머를 시작·정지하고 뒤로 가도 이어서 측정할 수 있다', (t) async {
    final fixture = StudyFixture();
    addTearDown(fixture.dispose);
    await openStudy(t, fixture);
    await tapStudy(t, find.byKey(const ValueKey('study-timer-open')));
    await tapStudy(t, find.text('측정 시작'));
    expect(find.text('일시정지'), findsOneWidget);
    await tapStudy(t, find.text('일시정지'));
    expect(find.text('계속 측정'), findsOneWidget);
    await tapStudy(t, find.byKey(const ValueKey('open-study-history')));
    await tapStudy(t, find.byKey(const ValueKey('study-timer-open')));
    expect(find.text('계속 측정'), findsOneWidget);
    expect(fixture.requests.where((r) => r.method == 'POST'), isEmpty);
    expect(t.takeException(), isNull);
  });
  testWidgets('측정한 정수 분만 기존 API에 저장하고 통계를 갱신한다', (t) async {
    final fixture = StudyFixture();
    addTearDown(fixture.dispose);
    await seedTimer(fixture);
    await openStudy(t, fixture);
    await tapStudy(t, find.byKey(const ValueKey('study-timer-open')));
    expect(find.textContaining('25초'), findsOneWidget);
    await tapStudy(t, find.text('기록 저장'));
    final request = fixture.requests.singleWhere((r) => r.method == 'POST');
    expect(jsonDecode(request.body)['durationMinutes'], 1);
    expect(fixture.history.last['durationMinutes'], 1);
    await tapStudy(t, find.byKey(const ValueKey('open-study-statistics')));
    expect(
      t.widget<Text>(find.byKey(const ValueKey('study-total'))).data,
      '1시간 31분',
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('과목 선택은 날짜별 목록 없이4과목만 표시한다', (t) async {
    final fixture = StudyFixture();
    addTearDown(fixture.dispose);
    final template = Map<String, dynamic>.from(fixture.planTasks.first);
    fixture.planTasks.clear();
    for (var i = 0; i < 64; i++) {
      fixture.planTasks.add({
        ...template,
        'taskId': i + 1000,
        'subjectName': 'SAMPLE 과목${i % 4}',
        'scheduledDate': '2026-11-${10 + i ~/ 16}',
      });
    }
    await openStudy(t, fixture);
    await tapStudy(t, find.byKey(const ValueKey('history-add')));
    await tapStudy(t, find.byKey(const ValueKey('study-task-picker')));
    expect(find.text('전체 일정'), findsNothing);
    expect(find.text('선택한 날짜'), findsNothing);
    for (var i = 0; i < 4; i++) {
      expect(find.text('SAMPLE 과목$i'), findsOneWidget);
    }
    expect(find.text('4개 과목'), findsOneWidget);
    expect(
      fixture.requests.where((r) => r.url.path == '/study/plan-tasks'),
      hasLength(2),
    );
    expect(t.takeException(), isNull);
  });
}
