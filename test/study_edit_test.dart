import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/data/study_models.dart';

import 'study_records_test.dart'
    show openStudy, openStudyDay, selectStudyRecordAction, tapStudy;
import 'support/study_fixture.dart';

Future<void> studyEditDate(WidgetTester t, DateTime target) async {
  await tapStudy(t, find.text('공부한 날짜'));
  t
      .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
      .onDateChanged(target);
  await t.pumpAndSettle();
  await tapStudy(t, find.text('확인'));
}

void main() {
  setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
  testWidgets('직접 입력 기록의 수정 화면에 기존 날짜와 시간을 채운다', (t) async {
    final fixture = StudyFixture();
    addTearDown(fixture.dispose);
    await openStudy(t, fixture);
    await openStudyDay(t, fixture.today);
    await selectStudyRecordAction(t, 1, 'edit');
    expect(find.text('공부시간 수정'), findsOneWidget);
    expect(
      t
          .widget<TextFormField>(find.byKey(const ValueKey('study-minutes')))
          .controller!
          .text,
      '60',
    );
    expect(find.text('수정 내용 저장'), findsOneWidget);
    await tapStudy(t, find.byType(BackButton));
    expect(
      fixture.requests.where((r) => r.method == 'POST' || r.method == 'PATCH'),
      isEmpty,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('날짜와 시간을 수정하면 같은 기록을 갱신하고 서버 통계를 다시 조회한다', (t) async {
    final fixture = StudyFixture();
    addTearDown(fixture.dispose);
    await openStudy(t, fixture);
    await openStudyDay(t, fixture.today);
    await selectStudyRecordAction(t, 1, 'edit');
    final target = plusDays(fixture.today, -2);
    await studyEditDate(t, target);
    await t.enterText(find.byKey(const ValueKey('study-minutes')), '45');
    await tapStudy(t, find.text('수정 내용 저장'));
    final request = fixture.requests.singleWhere((r) => r.method == 'PATCH');
    expect(request.url.path, '/study/sessions/1');
    expect(jsonDecode(request.body), {
      'studyDate': isoDay(target),
      'durationMinutes': 45,
      'expectedStudyDate': isoDay(fixture.today),
      'expectedDurationMinutes': 60,
      'expectedTask': {'taskId': 501},
    });
    expect(fixture.requests.where((r) => r.method == 'POST'), isEmpty);
    expect(fixture.history.length, 2);
    expect(fixture.history.first['taskId'], 501);
    await tapStudy(t, find.byKey(const ValueKey('open-study-statistics')));
    expect(
      t.widget<Text>(find.byKey(const ValueKey('study-total'))).data,
      '1시간 15분',
    );
    expect(t.takeException(), isNull);
  });

  for (final code in [400, 409]) {
    testWidgets('수정 $code 실패 시 기존 기록을 보존하고 입력을 유지한다', (t) async {
      final fixture = StudyFixture(
        override: (r) async => r.method == 'PATCH'
            ? studyEnvelope({'detail': 'SAMPLE 수정 거부: 기록을 확인해 주세요'}, code)
            : null,
      );
      addTearDown(fixture.dispose);
      await openStudy(t, fixture);
      await openStudyDay(t, fixture.today);
      await selectStudyRecordAction(t, 1, 'edit');
      await t.enterText(find.byKey(const ValueKey('study-minutes')), '90');
      await tapStudy(t, find.text('수정 내용 저장'));
      expect(find.text('SAMPLE 수정 거부: 기록을 확인해 주세요'), findsOneWidget);
      expect(
        t
            .widget<TextFormField>(find.byKey(const ValueKey('study-minutes')))
            .controller!
            .text,
        '90',
      );
      expect(fixture.history.first['durationMinutes'], 60);
      expect(fixture.requests.where((r) => r.method == 'PATCH'), hasLength(1));
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('수정 이중 탭은 PATCH 한 번만 전송한다', (t) async {
    final response = Completer<http.Response>();
    final fixture = StudyFixture(
      override: (r) async => r.method == 'PATCH' ? response.future : null,
    );
    addTearDown(fixture.dispose);
    await openStudy(t, fixture);
    await openStudyDay(t, fixture.today);
    await selectStudyRecordAction(t, 1, 'edit');
    await t.enterText(find.byKey(const ValueKey('study-minutes')), '45');
    final save = find.text('수정 내용 저장');
    await t.ensureVisible(save);
    await t.pumpAndSettle();
    await t.tap(save);
    await t.tap(save);
    await t.pump();
    expect(fixture.requests.where((r) => r.method == 'PATCH'), hasLength(1));
    response.complete(
      studyEnvelope(
        fixture.updateRecord(1, {
          'studyDate': isoDay(fixture.today),
          'durationMinutes': 45,
        }),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('공부시간 수정'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('직접 입력 기록만 수정할 수 있고 타이머 이력은 유지한다', (t) async {
    final fixture = StudyFixture();
    addTearDown(fixture.dispose);
    fixture.history.first['inputMethod'] = 'TIMER';
    await openStudy(t, fixture);
    await openStudyDay(t, fixture.today.subtract(const Duration(days: 1)));
    await openStudyDay(t, fixture.today);
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('study-record-2')),
      250,
      scrollable: find.byType(Scrollable).hitTestable().first,
    );
    expect(find.byKey(const ValueKey('study-actions-1')), findsNothing);
    await tapStudy(t, find.byKey(const ValueKey('study-actions-2')));
    expect(find.byKey(const ValueKey('study-edit-2')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('수정 응답 유실이면 이전 날짜와 새 날짜를 확인하고 자동 재전송하지 않는다', (t) async {
    late StudyFixture fixture;
    fixture = StudyFixture(
      override: (r) async {
        if (r.method != 'PATCH') return null;
        fixture.updateRecord(1, object(jsonDecode(r.body)));
        throw http.ClientException('SAMPLE edit response lost');
      },
    );
    addTearDown(fixture.dispose);
    await openStudy(t, fixture);
    await openStudyDay(t, fixture.today);
    await selectStudyRecordAction(t, 1, 'edit');
    await studyEditDate(t, plusDays(fixture.today, -2));
    await t.enterText(find.byKey(const ValueKey('study-minutes')), '45');
    await tapStudy(t, find.text('수정 내용 저장'));
    expect(find.textContaining('수정 결과를 확인하지 못했어요'), findsOneWidget);
    await tapStudy(t, find.text('기록 목록 확인'));
    expect(
      t
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '기록 확인 완료'),
          )
          .onPressed,
      isNull,
    );
    await tapStudy(t, find.text('수정 전 날짜 보기'));
    expect(
      t
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '기록 확인 완료'),
          )
          .onPressed,
      isNotNull,
    );
    await tapStudy(t, find.text('수정 요청 날짜 보기'));
    await tapStudy(t, find.text('기록 확인 완료'));
    expect(fixture.requests.where((r) => r.method == 'PATCH'), hasLength(1));
    expect(fixture.history.length, 2);
    expect(t.takeException(), isNull);
  });

  testWidgets('조회 기간 밖 날짜로 수정하면 해당 날짜로 이동해 서버 통계를 확인한다', (t) async {
    final fixture = StudyFixture();
    addTearDown(fixture.dispose);
    await openStudy(t, fixture);
    await openStudyDay(t, fixture.today);
    await selectStudyRecordAction(t, 1, 'edit');
    final target = plusDays(fixture.today, -45);
    await studyEditDate(t, target);
    await t.enterText(find.byKey(const ValueKey('study-minutes')), '20');
    await tapStudy(t, find.text('수정 내용 저장'));
    final query = fixture.requests.lastWhere(
      (r) => r.url.path == '/study/sessions',
    );
    expect(query.url.queryParameters['startDate'], isoDay(target));
    expect(query.url.queryParameters['endDate'], isoDay(target));
    await tapStudy(t, find.byKey(const ValueKey('open-study-statistics')));
    expect(
      t.widget<Text>(find.byKey(const ValueKey('study-total'))).data,
      '20분',
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('수정 권한 오류 뒤 기존 기록을 다시 표시하지 않는다', (t) async {
    final fixture = StudyFixture(
      override: (r) async => r.method == 'PATCH'
          ? studyEnvelope({'ko': 'SAMPLE 권한 없음'}, 403)
          : null,
    );
    addTearDown(fixture.dispose);
    await openStudy(t, fixture);
    await openStudyDay(t, fixture.today);
    await selectStudyRecordAction(t, 1, 'edit');
    await t.enterText(find.byKey(const ValueKey('study-minutes')), '45');
    await tapStudy(t, find.text('수정 내용 저장'));
    await tapStudy(t, find.text('기록으로 돌아가기'));
    expect(find.text('기록을 확인할 수 없어요'), findsOneWidget);
    expect(find.text('SAMPLE 정보처리기사의 긴 과목 이름'), findsNothing);
    expect(t.takeException(), isNull);
  });

  test('다른 기록 ID의 PATCH 성공 응답은 결과 불확실로 처리한다', () async {
    final fixture = StudyFixture(
      override: (r) async => r.method == 'PATCH'
          ? studyEnvelope({
              'sessionId': 999,
              'studyDate': jsonDecode(r.body)['studyDate'],
              'durationMinutes': 45,
              'inputMethod': 'MANUAL',
            })
          : null,
    );
    addTearDown(fixture.dispose);
    await fixture.session.restore();
    await expectLater(
      fixture.session.account!.updateStudySession(
        StudyRecord.from(fixture.history.first),
        fixture.today,
        45,
      ),
      throwsA(isA<StudySaveUncertain>()),
    );
    expect(fixture.requests.where((r) => r.method == 'PATCH'), hasLength(1));
  });

  for (final width in [320.0, 360.0, 412.0]) {
    for (final scale in [1.5, 2.0]) {
      testWidgets('수정 화면 $width/$scale 글자·키보드에서도 입력과 취소가 동작한다', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(width, 820);
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          t.view.resetDevicePixelRatio();
          t.view.resetPhysicalSize();
          t.view.resetViewInsets();
          t.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final fixture = StudyFixture();
        addTearDown(fixture.dispose);
        await openStudy(t, fixture);
        await openStudyDay(t, fixture.today);
        await selectStudyRecordAction(t, 1, 'edit');
        t.view.viewInsets = const FakeViewPadding(bottom: 300);
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const ValueKey('study-minutes')), '0');
        await tapStudy(t, find.text('수정 내용 저장'));
        expect(find.text('공부한 시간을 1~1,440분 사이로 입력해 주세요.'), findsOneWidget);
        expect(fixture.requests.where((r) => r.method == 'PATCH'), isEmpty);
        await tapStudy(t, find.byType(BackButton));
        expect(fixture.history.first['durationMinutes'], 60);
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('응답 유실 기록이 다음 페이지에 있으면 확인을 마치기 전까지 쓰기를 잠근다', (t) async {
    late StudyFixture fixture;
    fixture = StudyFixture(
      empty: true,
      override: (r) async {
        if (r.method != 'PATCH') return null;
        fixture.updateRecord(1, object(jsonDecode(r.body)));
        throw http.ClientException('SAMPLE edit response lost');
      },
    );
    addTearDown(fixture.dispose);
    for (var i = 1; i <= 21; i++) {
      fixture.history.add({
        'sessionId': i,
        'studyDate': isoDay(fixture.today),
        'durationMinutes': 1,
        'inputMethod': 'MANUAL',
        'subjectName': 'SAMPLE 과목 $i',
      });
    }
    await openStudy(t, fixture);
    await openStudyDay(t, fixture.today);
    Future<void> more() async {
      await t.scrollUntilVisible(
        find.text('이전 기록 더 보기'),
        400,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('study-view-0')),
          matching: find.byType(Scrollable),
        ),
      );
      await tapStudy(t, find.text('이전 기록 더 보기'));
    }

    await more();
    await selectStudyRecordAction(t, 1, 'edit');
    await t.enterText(find.byKey(const ValueKey('study-minutes')), '2');
    await tapStudy(t, find.text('수정 내용 저장'));
    await tapStudy(t, find.text('기록 목록 확인'));
    await t.fling(
      find.byKey(const ValueKey('study-view-0')),
      const Offset(0, 12000),
      12000,
    );
    await t.pumpAndSettle();
    expect(
      t
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '기록 확인 완료'),
          )
          .onPressed,
      isNull,
    );
    await more();
    await t.fling(
      find.byKey(const ValueKey('study-view-0')),
      const Offset(0, 12000),
      12000,
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('기록 확인 완료'));
    await t.pumpAndSettle();
    expect(
      t
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, '기록 확인 완료'),
          )
          .onPressed,
      isNotNull,
    );
    expect(fixture.requests.where((r) => r.method == 'PATCH'), hasLength(1));
    expect(t.takeException(), isNull);
  });
}
