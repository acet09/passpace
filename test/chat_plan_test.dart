import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/chat_plan.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/ui/chat.dart';
import 'package:passpace_mobile/ui/design.dart';

http.Response envelope(Object? data, [int code = 200]) => http.Response.bytes(
  utf8.encode(
    jsonEncode({
      'status': code == 200 ? 'SUCCESS' : 'ERROR',
      'code': code,
      'data': data,
    }),
  ),
  code,
);

void main() {
  test('질문 속 날짜를 공부 기간으로 읽는다', () {
    final today = DateTime(2026, 11, 17);
    final both = datesInMessage('11월 20일부터 1월 10일까지 SQLD 계획', today);
    expect(both.start, DateTime(2026, 11, 20));
    expect(both.end, DateTime(2027, 1, 10));
    expect(datesInMessage('2027-03-20 시험', today).end, DateTime(2027, 3, 20));
    expect(datesInMessage('2월 30일까지', today).end, isNull);
    final reversed = datesInMessage('2027-03-20부터 2027-03-01까지', today);
    expect(reversed.start, isNull);
    expect(reversed.end, isNull);
    expect(datesInMessage('하루 2시간 공부', today).start, isNull);
  });

  test('질문 속 하루 공부시간을 읽고 전체 예산과 구분한다', () {
    expect(dailyMinutesInMessage('하루 2시간이면 정보처리기사 필기를 어떻게'), 120);
    expect(dailyMinutesInMessage('매일 90분씩 SQLD 계획'), 90);
    expect(dailyMinutesInMessage('하루에 1시간 30분 공부'), 90);
    expect(dailyMinutesInMessage('하루 2시간 반 정처기'), 150);
    expect(dailyMinutesInMessage('하루 1.5시간'), 90);
    expect(dailyMinutesInMessage('3시간씩 공부할게'), 180);
    expect(dailyMinutesInMessage('총 100시간으로 SQLD 계획'), isNull);
    expect(dailyMinutesInMessage('하루 20분'), isNull);
    expect(dailyMinutesInMessage('SQLD 계획 세워줘'), isNull);
  });

  test('자격증별 하루 시간을 읽고, 한쪽만 있으면 하루 총 시간으로 본다', () {
    final each = examMinutesInMessage('SQLD 1시간, 정처기는 하루 2시간 30분으로 계획');
    expect(each.sqld, 60);
    expect(each.ipe, 150);
    final shared = examMinutesInMessage('정처기랑 SQLD 하루 2시간 계획');
    expect(shared.ipe, isNull);
    expect(shared.sqld, 120);
    expect(examMinutesInMessage('SQLD 계획 세워줘').sqld, isNull);

    final catalog = Catalog.from({
      'goals': [
        for (final name in ['SQLD', '정보처리기사 필기 (2027)'])
          {
            'key': name,
            'certificationName': name,
            'suggestedExamDate': '2027-03-01',
            'subjects': [
              {'name': '$name 과목', 'baseHours': 10.0},
            ],
          },
      ],
      'notices': [],
    });
    final today = DateTime(2026, 11, 17);
    final inputs = ChatPlanInputs();
    final setup = ChatPlanSetup.from(
      'SQLD 1시간 정처기 2시간씩 계획 세워줘',
      catalog,
      inputs,
      today,
    );
    expect(setup.splitFromQuestion, isTrue);
    expect(setup.dailyTotal(inputs), 180);
    for (final g in inputs.goals.values) {
      g.familiarity.addAll({'SQLD 과목': 2, '정보처리기사 필기 (2027) 과목': 2});
    }
    final request = setup.buildRequest(inputs);
    expect(request['dailyMinutes'], 180);
    expect(rows(request['goals']).map((g) => g['dailyMinutes']), [60, 120]);

    // 한쪽 자격증에만 붙은 시간은 하루 총 시간이다.
    final total = ChatPlanSetup.from(
      '정처기랑 SQLD 하루 2시간 계획',
      catalog,
      inputs,
      today,
    );
    expect(total.splitFromQuestion, isFalse);
    expect(inputs.split, isFalse);
    expect(total.dailyTotal(inputs), 120);
    expect(
      rows(total.buildRequest(inputs)['goals']).first
          .containsKey('dailyMinutes'),
      isFalse,
    );
  });

  test('질문에서 종목을 고르고 지원하지 않으면 알린다', () {
    final catalog = Catalog.from({
      'goals': [
        for (final name in ['SQLD', '정보처리기사 필기 (2027)', '정보처리기사 실기'])
          {'key': name, 'certificationName': name, 'subjects': []},
      ],
      'notices': [],
    });
    final today = DateTime(2026, 11, 17);
    List<String> picked(String message) => ChatPlanSetup.from(
      message,
      catalog,
      ChatPlanInputs(),
      today,
    ).exams.map((e) => e.name).toList();
    expect(picked('정처기랑 sqld 계획'), ['SQLD', '정보처리기사 필기 (2027)']);
    expect(picked('정보처리기사 실기 준비'), ['정보처리기사 실기']);
    expect(() => picked('토익 계획'), throwsA(isA<ApiError>()));
    final inputs = ChatPlanInputs()..minutes = 60;
    final setup = ChatPlanSetup.from('하루 3시간 SQLD 계획', catalog, inputs, today);
    expect(inputs.minutes, 180);
    expect(setup.minutesFromQuestion, 180);
    ChatPlanSetup.from('SQLD 계획', catalog, inputs, today);
    expect(inputs.minutes, 180);
  });

  testWidgets('상담 안에서 계획을 계산하고 학습계획에 저장한다', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(420, 3200);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final today = dayInSeoul();
    final calls = <String, Json>{};
    var savedCount = 0;
    final api = PassApi(
      MockClient((r) async {
        final path = r.url.path;
        if (r.method == 'POST') calls[path] = object(jsonDecode(r.body));
        if (path == '/api/chat') {
          return envelope({
            'answer': '학습계획을 계산할게요.',
            'conId': 7,
            'llmUsed': false,
            'sources': [],
            'notice': 'AUTO_PLAN_SETUP',
          });
        }
        if (path == '$plannerPath/catalog') {
          return envelope({
            'goals': [
              {
                'key': 'db-2-WRITTEN',
                'certificationName': 'SQLD',
                'suggestedExamDate': isoDay(plusDays(today, 40)),
                'subjects': [
                  {'name': '데이터 모델링의 이해', 'baseHours': 10.0},
                  {'name': 'SQL 기본 및 활용', 'baseHours': 20.0},
                ],
              },
            ],
            'notices': [],
          });
        }
        if (path == '$plannerPath/preview-chat') {
          return envelope({
            'answer': '다중 자격증 자동 학습계획 요약',
            'plan': {
              'calculatedOn': isoDay(today),
              'dailyMinutes': 120,
              'totalRemainingMinutes': 1800,
              'totalShortfallMinutes': 0,
              'minimumDailyMinutes': 60,
              'additionalDailyMinutes': 0,
              'feasible': true,
              'notices': [],
              'goals': [
                {
                  'key': 'db-2-WRITTEN',
                  'certificationName': 'SQLD',
                  'startDate': isoDay(today),
                  'examDate': isoDay(plusDays(today, 40)),
                  'remainingMinutes': 1800,
                  'subjects': [
                    {
                      'name': '데이터 모델링의 이해',
                      'baseHours': 10.0,
                      'weight': 1.0,
                      'remainingMinutes': 600,
                    },
                  ],
                },
              ],
              'days': [
                {
                  'date': isoDay(today),
                  'availableMinutes': 120,
                  'allocatedMinutes': 90,
                  'allocations': [
                    {
                      'certificationName': 'SQLD',
                      'subjectName': '데이터 모델링의 이해',
                      'minutes': 90,
                    },
                  ],
                },
              ],
            },
          });
        }
        if (path == '$plannerPath/save') {
          return envelope({'planId': 1, 'days': 1, 'totalMinutes': 90});
        }
        throw StateError(path);
      }),
      emulatorOrigin,
      token: 'fixture',
    );
    await t.pumpWidget(
      MaterialApp(
        theme: paceTheme(),
        home: Scaffold(body: ChatScreen(api, onPlanSaved: () => savedCount++)),
      ),
    );
    await t.enterText(find.byType(TextField), 'SQLD 계획 세워줘');
    await t.pump();
    await t.tap(find.byTooltip('질문 보내기'));
    await t.pumpAndSettle();

    expect(find.text('학습계획을 계산할게요.'), findsOneWidget);
    expect(find.text('AUTO_PLAN_SETUP'), findsNothing);
    expect(find.text('자동 학습계획'), findsOneWidget);
    expect(find.text('하루 공부 가능시간을 먼저 선택해 주세요'), findsOneWidget);
    expect(calls.containsKey('$plannerPath/preview-chat'), isFalse);

    await t.tap(find.text('2시간'));
    await t.pumpAndSettle();
    expect(find.text('과목별 이해도를 선택해 주세요'), findsOneWidget);
    await t.tap(find.text('보통').at(0));
    await t.tap(find.text('익숙함').at(1));
    await t.pumpAndSettle();
    await t.tap(find.text('학습계획 자동 생성'));
    await t.pumpAndSettle();

    final sent = calls['$plannerPath/preview-chat']!;
    expect(sent['conId'], 7);
    final plan = object(sent['plan']);
    expect(plan['dailyMinutes'], 120);
    expect(plan['studyWeekdays'], [1, 2, 3, 4, 5, 6, 7]);
    final goal = rows(plan['goals']).single;
    expect(goal['key'], 'db-2-WRITTEN');
    expect(goal['startDate'], isoDay(today));
    expect(goal['examDate'], isoDay(plusDays(today, 40)));
    expect(rows(goal['subjects']).map((s) => s['familiarity']), [2, 3]);

    expect(find.text('다중 자격증 자동 학습계획 요약'), findsOneWidget);
    expect(find.text('날짜별 계획 (1일)'), findsOneWidget);
    expect(find.text('- SQLD / 데이터 모델링의 이해: 90분'), findsOneWidget);
    expect(find.text('변경된 입력으로 다시 계산'), findsOneWidget);
    expect(calls.containsKey('$plannerPath/save'), isFalse);

    await t.tap(find.text('이 계획을 학습계획에 넣기'));
    await t.pumpAndSettle();
    await t.tap(find.text('저장하기'));
    await t.pumpAndSettle();
    expect(calls['$plannerPath/save'], plan);
    expect(savedCount, 1);
    expect(find.text('학습계획에 넣기 완료'), findsOneWidget);
    expect(find.textContaining('1일치'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
