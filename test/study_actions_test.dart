import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'study_records_test.dart'
    show openStudy, openStudyDay, selectStudyRecordAction, tapStudy;
import 'support/study_fixture.dart';

void main() {
  testWidgets('기록 삭제는 확인창에서 취소할 수 있고 확정하면 통계도 갱신한다', (t) async {
    final fixture = StudyFixture();
    addTearDown(fixture.dispose);
    await openStudy(t, fixture);
    await openStudyDay(t, fixture.today.subtract(const Duration(days: 1)));
    await selectStudyRecordAction(t, 2, 'delete');
    expect(find.text('학습기록 삭제'), findsOneWidget);
    await tapStudy(t, find.widgetWithText(TextButton, '취소'));
    expect(fixture.requests.where((r) => r.method == 'DELETE'), isEmpty);
    await selectStudyRecordAction(t, 2, 'delete');
    await tapStudy(t, find.widgetWithText(FilledButton, '삭제'));
    expect(fixture.history.length, 1);
    final request = fixture.requests.singleWhere((r) => r.method == 'DELETE');
    expect(request.url.path, '/study/sessions/2');
    expect(jsonDecode(request.body)['expectedDurationMinutes'], 30);
    await tapStudy(t, find.byKey(const ValueKey('open-study-statistics')));
    expect(
      t.widget<Text>(find.byKey(const ValueKey('study-total'))).data,
      '1시간',
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('새 기록에서 실제 계획 과목을 선택하고 공부시간은 직접 입력한다', (t) async {
    final fixture = StudyFixture();
    addTearDown(fixture.dispose);
    await openStudy(t, fixture);
    await tapStudy(t, find.byKey(const ValueKey('history-add')));
    await t.enterText(find.byKey(const ValueKey('study-minutes')), '25');
    await tapStudy(t, find.byKey(const ValueKey('study-task-picker')));
    await tapStudy(t, find.text('SAMPLE 데이터베이스'));
    expect(
      t
          .widget<TextFormField>(find.byKey(const ValueKey('study-minutes')))
          .controller!
          .text,
      '25',
    );
    await tapStudy(t, find.text('공부시간 저장'));
    final body = jsonDecode(
      fixture.requests.singleWhere((r) => r.method == 'POST').body,
    );
    expect(body['taskId'], 502);
    expect(body['expectedPlanVersion'], 3);
    expect(body['durationMinutes'], 25);
    expect(fixture.history.last['subjectName'], 'SAMPLE 데이터베이스');
    expect(t.takeException(), isNull);
  });

  testWidgets('기존 미연결 기록도 중복 없는 과목을 선택해 연결한다', (t) async {
    final fixture = StudyFixture();
    addTearDown(fixture.dispose);
    await openStudy(t, fixture);
    await openStudyDay(t, fixture.today.subtract(const Duration(days: 1)));
    await selectStudyRecordAction(t, 2, 'edit');
    await tapStudy(t, find.byKey(const ValueKey('study-task-picker')));
    await tapStudy(t, find.text('SAMPLE 데이터베이스'));
    await tapStudy(t, find.text('수정 내용 저장'));
    final body = jsonDecode(
      fixture.requests.singleWhere((r) => r.method == 'PATCH').body,
    );
    expect(body['taskLink'], {
      'taskId': 502,
      'expectedPlanVersion': 3,
      'expectedTaskId': null,
    });
    expect(
      fixture.history.singleWhere((r) => r['sessionId'] == 2)['taskId'],
      502,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('삭제 거부는 기록을 보존하고 목록에서 다시 확인하게 한다', (t) async {
    final fixture = StudyFixture(
      override: (r) async => r.method == 'DELETE'
          ? studyEnvelope({'detail': 'SAMPLE 변경된 기록'}, 409)
          : null,
    );
    addTearDown(fixture.dispose);
    await openStudy(t, fixture);
    await openStudyDay(t, fixture.today.subtract(const Duration(days: 1)));
    await selectStudyRecordAction(t, 2, 'delete');
    await tapStudy(t, find.widgetWithText(FilledButton, '삭제'));
    expect(find.text('SAMPLE 변경된 기록'), findsOneWidget);
    await tapStudy(t, find.text('기록 목록 확인'));
    expect(fixture.history.length, 2);
    expect(fixture.requests.where((r) => r.method == 'DELETE'), hasLength(1));
    expect(t.takeException(), isNull);
  });

  testWidgets('삭제 이중 탭은 한 번만 보내고 처리 중 취소를 막는다', (t) async {
    final response = Completer<http.Response>();
    final fixture = StudyFixture(
      override: (r) async => r.method == 'DELETE' ? response.future : null,
    );
    addTearDown(fixture.dispose);
    await openStudy(t, fixture);
    await openStudyDay(t, fixture.today.subtract(const Duration(days: 1)));
    await selectStudyRecordAction(t, 2, 'delete');
    final button = find.widgetWithText(FilledButton, '삭제');
    await t.tap(button);
    await t.tap(button);
    await t.pump();
    expect(fixture.requests.where((r) => r.method == 'DELETE'), hasLength(1));
    expect(
      t.widget<TextButton>(find.widgetWithText(TextButton, '취소')).onPressed,
      isNull,
    );
    fixture.history.removeWhere((r) => r['sessionId'] == 2);
    response.complete(studyEnvelope({'sessionId': 2, 'deleted': true}));
    await t.pumpAndSettle();
    expect(fixture.history.length, 1);
    expect(t.takeException(), isNull);
  });

  testWidgets('삭제 응답이 유실되어도 재삭제하지 않고 목록에서 결과를 확인한다', (t) async {
    late StudyFixture fixture;
    fixture = StudyFixture(
      override: (r) async {
        if (r.method != 'DELETE') return null;
        fixture.history.removeWhere((v) => v['sessionId'] == 2);
        throw http.ClientException('SAMPLE acknowledgement lost');
      },
    );
    addTearDown(fixture.dispose);
    await openStudy(t, fixture);
    await openStudyDay(t, fixture.today.subtract(const Duration(days: 1)));
    await selectStudyRecordAction(t, 2, 'delete');
    await tapStudy(t, find.widgetWithText(FilledButton, '삭제'));
    expect(find.textContaining('삭제 결과를 확인하지 못했어요'), findsOneWidget);
    await tapStudy(t, find.text('기록 목록 확인'));
    expect(find.textContaining('기록의 삭제 결과를 확인해 주세요'), findsOneWidget);
    await tapStudy(t, find.text('기록 확인 완료'));
    expect(fixture.requests.where((r) => r.method == 'DELETE'), hasLength(1));
    expect(t.takeException(), isNull);
  });

  testWidgets('과목 연결 해제는 기록 ID와 시간을 유지한다', (t) async {
    final fixture = StudyFixture();
    addTearDown(fixture.dispose);
    await openStudy(t, fixture);
    await openStudyDay(t, fixture.today);
    await selectStudyRecordAction(t, 1, 'edit');
    await tapStudy(t, find.byKey(const ValueKey('study-task-picker')));
    await tapStudy(t, find.text('과목 연결 없음'));
    await tapStudy(t, find.text('수정 내용 저장'));
    final record = fixture.history.singleWhere((r) => r['sessionId'] == 1);
    expect(record['taskId'], isNull);
    expect(record['durationMinutes'], 60);
    final body = jsonDecode(
      fixture.requests.singleWhere((r) => r.method == 'PATCH').body,
    );
    expect(body['taskLink'], {
      'taskId': null,
      'expectedTaskId': 501,
      'expectedPlanVersion': null,
    });
    expect(t.takeException(), isNull);
  });

  testWidgets('연결할 계획이 없어도 시간을 보존하고 미연결 기록을 저장한다', (t) async {
    final fixture = StudyFixture();
    fixture.planTasks.clear();
    addTearDown(fixture.dispose);
    await openStudy(t, fixture);
    await tapStudy(t, find.byKey(const ValueKey('history-add')));
    await t.enterText(find.byKey(const ValueKey('study-minutes')), '17');
    await tapStudy(t, find.byKey(const ValueKey('study-task-picker')));
    expect(find.text('연결할 학습계획이 없어요'), findsOneWidget);
    await tapStudy(t, find.byType(BackButton));
    await tapStudy(t, find.text('공부시간 저장'));
    final body = jsonDecode(
      fixture.requests.singleWhere((r) => r.method == 'POST').body,
    );
    expect(body['durationMinutes'], 17);
    expect(body.containsKey('taskId'), false);
    expect(t.takeException(), isNull);
  });

  for (final width in [320.0, 360.0, 412.0]) {
    for (final scale in [1.5, 2.0]) {
      testWidgets('삭제·과목 선택 $width/$scale 글자 확대에서 가려지지 않는다', (t) async {
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
        await openStudy(t, fixture);
        await openStudyDay(t, fixture.today.subtract(const Duration(days: 1)));
        await selectStudyRecordAction(t, 2, 'delete');
        await tapStudy(t, find.widgetWithText(TextButton, '취소'));
        await selectStudyRecordAction(t, 2, 'edit');
        await tapStudy(t, find.byKey(const ValueKey('study-task-picker')));
        await tapStudy(t, find.text('SAMPLE 데이터베이스'));
        expect(
          t
              .widget<TextFormField>(
                find.byKey(const ValueKey('study-minutes')),
              )
              .controller!
              .text,
          '30',
        );
        expect(t.takeException(), isNull);
      });
    }
  }
}
