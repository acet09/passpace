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

  test('질문 속 되는 요일·안 되는 요일을 공부 요일로 읽는다', () {
    List<int>? read(String message) =>
        weekdaysInMessage(message)?.toList()?..sort();
    expect(read('월수금만 가능해'), [1, 3, 5]);
    expect(read('월, 수, 금에 공부할게'), [1, 3, 5]);
    expect(read('화요일이랑 목요일은 안 돼'), [1, 3, 5, 6, 7]);
    expect(read('주말은 안 되고 평일만 가능'), [1, 2, 3, 4, 5]);
    expect(read('주말 빼고 계획 세워줘'), [1, 2, 3, 4, 5]);
    expect(read('주말에만 공부할 수 있어'), [6, 7]);
    expect(read('월~금 하루 2시간 가능'), [1, 2, 3, 4, 5]);
    expect(read('월요일부터 목요일까지만 돼'), [1, 2, 3, 4]);
    expect(read('월수금은 되는데 화목은 안돼'), [1, 3, 5]);
    expect(read('평일은 되는데 수요일은 못 해'), [1, 2, 4, 5]);
    expect(read('토요일은 공부 못 해'), [1, 2, 3, 4, 5, 7]);
    expect(read('일요일만 쉬고 싶어'), [1, 2, 3, 4, 5, 6]);
    expect(read('평일엔 2시간, 주말에도 1시간 가능'), [1, 2, 3, 4, 5, 6, 7]);
    // 요일 이야기가 아니거나, 되는지 안 되는지 알 수 없는 말은 읽지 않는다.
    expect(read('SQLD 계획 세워줘'), isNull);
    expect(read('11월 20일부터 1월 10일까지 하루 2시간'), isNull);
    expect(read('일일 2시간씩 공부 가능'), isNull);
    expect(read('매일 일정이 바빠서 수목원은 못 가'), isNull);
    expect(read('이번 주말까지 끝내고 싶어'), isNull);
    expect(read('그럴 일 수 있어'), isNull);

    final catalog = Catalog.from({
      'goals': [
        {'key': 'SQLD', 'certificationName': 'SQLD', 'subjects': []},
      ],
      'notices': [],
    });
    final inputs = ChatPlanInputs();
    final setup = ChatPlanSetup.from(
      'SQLD 계획 세워줘. 화요일이랑 일요일은 안 돼',
      catalog,
      inputs,
      DateTime(2026, 11, 17),
    );
    expect(setup.weekdaysFromQuestion, {1, 3, 4, 5, 6});
    expect(inputs.weekdays, {1, 3, 4, 5, 6});
    // 요일을 말하지 않은 다음 질문은 앞에서 정한 요일을 그대로 둔다.
    final next = ChatPlanSetup.from(
      'SQLD 계획 다시',
      catalog,
      inputs,
      DateTime(2026, 11, 17),
    );
    expect(next.weekdaysFromQuestion, isNull);
    expect(inputs.weekdays, {1, 3, 4, 5, 6});
  });

  test('요일마다 다른 시간을 요일별 시간으로 읽고 그대로 요청한다', () {
    expect(weekdayMinutesInMessage('평일엔 2시간, 주말엔 4시간 가능'), {
      1: 120,
      2: 120,
      3: 120,
      4: 120,
      5: 120,
      6: 240,
      7: 240,
    });
    expect(weekdayMinutesInMessage('월수금 1시간씩 토요일은 3시간 반'), {
      1: 60,
      3: 60,
      5: 60,
      6: 210,
    });
    expect(weekdayMinutesInMessage('평일 1시간 주말 3시간인데 일요일은 안 돼'), {
      1: 60,
      2: 60,
      3: 60,
      4: 60,
      5: 60,
      6: 180,
    });
    // 시간이 하나뿐이면 요일과 하루 시간으로 따로 읽는다.
    expect(weekdayMinutesInMessage('월수금 하루 2시간 가능'), isNull);
    expect(weekdayMinutesInMessage('평일 2시간 주말도 2시간'), isNull);
    expect(weekdayMinutesInMessage('SQLD 계획 세워줘'), isNull);

    final catalog = Catalog.from({
      'goals': [
        {
          'key': 'SQLD',
          'certificationName': 'SQLD',
          'suggestedExamDate': '2027-03-01',
          'subjects': [
            {'name': 'SQL', 'baseHours': 10.0},
          ],
        },
      ],
      'notices': [],
    });
    final inputs = ChatPlanInputs();
    final setup = ChatPlanSetup.from(
      'SQLD 계획. 월요일은 1시간, 토요일은 4시간 가능해',
      catalog,
      inputs,
      DateTime(2026, 11, 17),
    );
    expect(setup.dayMinutesFromQuestion, isTrue);
    expect(inputs.byWeekday, isTrue);
    expect(inputs.weekdays, {1, 6});
    // 요일은 시간 질문에서 함께 정하므로 따로 묻지 않고, 시간은 이미 읽었으니 기간부터 묻는다.
    expect(setup.steps(inputs), ['time', 'period', 'level:SQLD']);
    expect(setup.current(inputs), 'period');
    inputs.goals['SQLD']!.familiarity['SQL'] = 2;
    final request = setup.buildRequest(inputs);
    expect(request['weekdayMinutes'], {'1': 60, '6': 240});
    expect(request['studyWeekdays'], [1, 6]);
    expect(request['dailyMinutes'], 240);

    // 하루 시간을 다시 말하면 요일별 시간을 끈다.
    final uniform = ChatPlanSetup.from(
      'SQLD 하루 2시간 계획',
      catalog,
      inputs,
      DateTime(2026, 11, 17),
    );
    expect(inputs.byWeekday, isFalse);
    expect(uniform.buildRequest(inputs).containsKey('weekdayMinutes'), isFalse);
    expect(uniform.steps(inputs), ['time', 'days', 'period', 'level:SQLD']);
  });

  test('자격증별 하루 시간을 읽고, 한쪽만 있으면 하루 총 시간으로 본다', () {
    final each = examMinutesInMessage('SQLD 1시간, 정처기는 하루 2시간 30분으로 계획');
    expect(each, {'SQLD': 60, 'IPE': 150});
    final shared = examMinutesInMessage('정처기랑 SQLD 하루 2시간 계획');
    expect(shared, {'SQLD': 120});
    expect(examMinutesInMessage('SQLD 계획 세워줘'), isEmpty);
    expect(examMinutesInMessage('ADsP 1시간 컴활 1급 필기는 하루 90분'), {
      'ADSP': 60,
      'CA1': 90,
    });

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

  test('이어 말한 자격증·긴 문장·일부만 적은 시간도 자격증별로 읽는다', () {
    // "각각"이면 이어 말한 자격증 모두 같은 시간.
    expect(examMinutesInMessage('정처기랑 SQLD 각각 1시간씩 계획 짜줘'), {
      'IPE': 60,
      'SQLD': 60,
    });
    expect(examMinutesInMessage('정처기랑 SQLD랑 ADsP 각각 하루 1시간씩'), {
      'IPE': 60,
      'SQLD': 60,
      'ADSP': 60,
    });
    // 다른 자격증에 따로 시간을 적었으면 묶어 말한 쪽도 각자의 시간.
    expect(examMinutesInMessage('정처기 2시간, SQLD랑 ADsP는 1시간씩'), {
      'IPE': 120,
      'SQLD': 60,
      'ADSP': 60,
    });
    // 이름과 시간 사이 말이 길어도 같은 절이면 읽는다.
    expect(examMinutesInMessage('정처기는 평일 저녁에 퇴근하고 하루 2시간, SQLD는 1시간'), {
      'IPE': 120,
      'SQLD': 60,
    });
    // 앞에서 이름만 나열한 것은 뒤의 시간과 묶지 않는다.
    expect(
      examMinutesInMessage('정처기 필기랑 SQLD 같이 계획 짜줘. 정처기 2시간 SQLD 1시간'),
      {'IPE': 120, 'SQLD': 60},
    );

    final catalog = Catalog.from({
      'goals': [
        for (final name in ['SQLD', '정보처리기사 필기 (2027)', 'ADsP'])
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
    final all = ChatPlanSetup.from(
      '정처기랑 SQLD랑 ADsP 각각 하루 1시간씩 계획',
      catalog,
      inputs,
      today,
    );
    expect(all.splitFromQuestion, isTrue);
    expect(all.dailyTotal(inputs), 180);
    expect(all.confirmed, contains(ChatPlanSetup.stepTime));

    // 셋 중 둘만 시간을 적으면 적은 것은 넣어 두고, 빠진 자격증은 카드에서 묻는다.
    final part = ChatPlanSetup.from(
      '정처기 하루 2시간, SQLD 1시간, 그리고 ADsP 계획',
      catalog,
      inputs,
      today,
    );
    expect(part.splitFromQuestion, isTrue);
    expect(inputs.split, isTrue);
    expect(inputs.examMinutes, {'정보처리기사 필기 (2027)': 120, 'SQLD': 60});
    expect(part.dailyTotal(inputs), isNull);
    expect(part.current(inputs), ChatPlanSetup.stepTime);
  });

  test('ADsP·컴활 1급과 필기·실기 구분을 알아듣고 3개까지만 묶는다', () {
    String read(String message) => certsInMessage(message)
        .map(
          (c) => '${c.id}${c.written ? ' 필기' : ''}${c.practical ? ' 실기' : ''}',
        )
        .join(', ');
    expect(read('정처기 필기랑 컴활 실기, ADsP 계획'), 'IPE 필기, CA1 실기, ADSP 필기');
    expect(read('정처기 필기 실기 둘 다'), 'IPE 필기 실기');
    expect(read('데이터분석 준전문가 준비'), 'ADSP 필기');
    expect(read('컴퓨터활용능력 1급 실기 계획'), 'CA1 실기');
    expect(read('컴활 2급 계획'), '');

    final catalog = Catalog.from({
      'goals': [
        for (final name in [
          'SQLD',
          '정보처리기사 필기 (2027~)',
          '정보처리기사 실기',
          'ADsP',
          '컴퓨터활용능력 1급 필기',
          '컴퓨터활용능력 1급 실기',
        ])
          {'key': name, 'certificationName': name, 'subjects': []},
      ],
      'notices': [],
    });
    final today = DateTime(2026, 11, 17);
    final inputs = ChatPlanInputs();
    final setup = ChatPlanSetup.from(
      'ADsP 1시간, 컴활 필기 2시간 계획 세워줘',
      catalog,
      inputs,
      today,
    );
    expect(setup.exams.map((e) => e.name), ['ADsP', '컴퓨터활용능력 1급 필기']);
    expect(setup.splitFromQuestion, isTrue);
    expect(setup.dailyTotal(inputs), 180);
    // 상시시험은 목표일이 비어 있어 날짜를 고르기 전에는 준비되지 않는다.
    expect(setup.datesChosen(inputs), isFalse);

    // 한 자격증의 필기·실기를 함께 고르면 시간을 나누지 않는다.
    final both = ChatPlanSetup.from(
      '컴활 필기 실기 하루 2시간 계획',
      catalog,
      inputs,
      today,
    );
    expect(both.exams.length, 2);
    expect(both.splitFromQuestion, isFalse);
    expect(both.dailyTotal(inputs), 120);

    expect(
      () =>
          ChatPlanSetup.from('정처기, SQLD, ADsP, 컴활 계획', catalog, inputs, today),
      throwsA(isA<ApiError>()),
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

  testWidgets('과목 목록을 못 읽었을 때만 다시 열기를 보여 주고, 누르면 카드가 열린다', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(420, 3200);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    var catalogCalls = 0;
    final api = PassApi(
      MockClient((r) async {
        final path = r.url.path;
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
          // 첫 번째 요청만 실패한다.
          if (++catalogCalls == 1) return envelope({'ko': '서버 오류'}, 500);
          return envelope({
            'goals': [
              for (final name in ['SQLD', '정보처리기사 필기 (2027~)', 'ADsP'])
                {
                  'key': name,
                  'certificationName': name,
                  'subjects': [
                    {'name': '$name 과목', 'baseHours': 10.0},
                  ],
                },
              {
                'key': 'ca1',
                'certificationName': '컴퓨터활용능력 1급 필기',
                'subjects': [],
              },
            ],
            'notices': [],
          });
        }
        throw StateError(path);
      }),
      emulatorOrigin,
      token: 'fixture',
    );
    await t.pumpWidget(
      MaterialApp(
        theme: paceTheme(),
        home: Scaffold(body: ChatScreen(api)),
      ),
    );
    Future<void> ask(String message) async {
      await t.enterText(find.byType(TextField).last, message);
      await t.pump();
      await t.tap(find.byTooltip('질문 보내기'));
      await t.pumpAndSettle();
    }

    // 목록 요청 실패: 안내와 다시 열기 버튼이 보인다.
    await ask('SQLD 계획 세워줘');
    expect(find.text('자동 학습계획'), findsNothing);
    expect(find.text('계획 입력 다시 열기'), findsOneWidget);
    await t.tap(find.text('계획 입력 다시 열기'));
    await t.pumpAndSettle();
    expect(catalogCalls, 2);
    expect(find.text('자동 학습계획'), findsOneWidget);
    expect(find.text('계획 입력 다시 열기'), findsNothing);

    // 질문 자체의 문제(자격증 4개): 안내만 보이고 다시 열기는 없다.
    await ask('정처기, SQLD, ADsP, 컴활 계획 세워줘');
    expect(find.textContaining('한 번에 3개까지'), findsOneWidget);
    expect(find.text('계획 입력 다시 열기'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('계획 카드를 연 뒤 요일만 다시 말해도 카드의 공부 요일이 바뀐다', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(420, 3200);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final api = PassApi(
      MockClient((r) async {
        final path = r.url.path;
        if (path == '/api/chat') {
          final message = object(jsonDecode(r.body))['message'] as String;
          return envelope({
            'answer': '답변',
            'conId': 7,
            'llmUsed': false,
            'sources': [],
            'notice': message.contains('계획') ? 'AUTO_PLAN_SETUP' : null,
          });
        }
        if (path == '$plannerPath/catalog') {
          return envelope({
            'goals': [
              {'key': 'SQLD', 'certificationName': 'SQLD', 'subjects': []},
            ],
            'notices': [],
          });
        }
        throw StateError(path);
      }),
      emulatorOrigin,
      token: 'fixture',
    );
    await t.pumpWidget(
      MaterialApp(
        theme: paceTheme(),
        home: Scaffold(body: ChatScreen(api)),
      ),
    );
    Future<void> ask(String message) async {
      await t.enterText(find.byType(TextField).last, message);
      await t.pump();
      await t.tap(find.byTooltip('질문 보내기'));
      await t.pumpAndSettle();
    }

    // 카드가 없을 때는 요일을 말해도 아무 안내도 하지 않는다.
    await ask('주말은 안 돼');
    expect(find.textContaining('공부 요일을 바꿨어요'), findsNothing);

    // 질문에서 읽은 요일은 다시 묻지 않고 접힌 줄로 보여 준다. 시간부터 묻는다.
    await ask('SQLD 계획 세워줘. 월수금만 가능해');
    expect(find.text('공부할 요일 · 질문에서 읽음'), findsOneWidget);
    expect(find.text('월·수·금'), findsOneWidget);
    expect(find.text('하루에 얼마나 공부할 수 있나요?'), findsOneWidget);
    expect(find.text('어느 요일에 공부할 수 있나요?'), findsNothing);

    await ask('아 그리고 수요일은 안 돼');
    expect(find.text('월·화·목·금·토·일'), findsOneWidget);
    expect(find.textContaining('공부 요일을 바꿨어요: 월·화·목·금·토·일'), findsOneWidget);

    // 접힌 줄을 누르면 그 질문이 다시 열리고, 고른 요일이 그대로 있다.
    await t.tap(find.text('월·화·목·금·토·일'));
    await t.pumpAndSettle();
    expect(find.text('어느 요일에 공부할 수 있나요?'), findsOneWidget);
    expect(
      [
        for (final chip in t.widgetList<FilterChip>(find.byType(FilterChip)))
          if (chip.selected) (chip.label as Text).data!,
      ],
      ['월', '화', '목', '금', '토', '일'],
    );

    // 요일마다 다른 시간을 말하면 요일별 시간으로 바뀌고, 요일 질문은 시간 질문에 합쳐진다.
    await ask('평일엔 1시간, 토요일은 3시간 가능해');
    expect(find.textContaining('요일별 공부시간을 바꿨어요'), findsOneWidget);
    expect(find.text('요일마다 얼마나 공부할 수 있나요?'), findsOneWidget);
    expect(find.text('어느 요일에 공부할 수 있나요?'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('상담 안에서 계획을 계산하고 학습계획에 저장한다', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(420, 3200);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final today = dayInSeoul();
    final calls = <String, Json>{};
    final savedQueries = <String>[];
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
          savedQueries.add(r.url.query);
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
    // 한 번에 하나씩 묻는다: 처음에는 시간 질문만 보인다.
    expect(find.text('질문 1 / 4'), findsOneWidget);
    expect(find.text('하루에 얼마나 공부할 수 있나요?'), findsOneWidget);
    expect(find.text('하루 공부 가능시간을 먼저 선택해 주세요'), findsOneWidget);
    expect(find.text('어느 요일에 공부할 수 있나요?'), findsNothing);
    expect(find.textContaining('과목별로 얼마나 알고 있나요?'), findsNothing);
    expect(find.text('학습계획 자동 생성'), findsNothing);
    expect(calls.containsKey('$plannerPath/preview-chat'), isFalse);

    // 시간을 누르면 답이 한 줄로 접히고 요일 질문이 열린다.
    await t.tap(find.text('2시간'));
    await t.pumpAndSettle();
    expect(find.text('하루 2시간'), findsOneWidget);
    expect(find.text('질문 2 / 4'), findsOneWidget);
    expect(find.text('어느 요일에 공부할 수 있나요?'), findsOneWidget);
    await t.tap(find.widgetWithText(ChoiceChip, '매일'));
    await t.pumpAndSettle();

    // 기간은 채워진 날짜를 확인하고 [다음].
    expect(find.text('언제부터 언제까지 공부할까요?'), findsOneWidget);
    await t.tap(find.text('다음'));
    await t.pumpAndSettle();

    // 이해도는 마지막 과목을 고르는 순간 넘어가고, 그때 계산 버튼이 나온다.
    expect(find.text('SQLD, 과목별로 얼마나 알고 있나요?'), findsOneWidget);
    expect(find.text('과목별 이해도를 선택해 주세요'), findsOneWidget);
    await t.tap(find.text('보통').at(0));
    await t.pumpAndSettle();
    expect(find.text('학습계획 자동 생성'), findsNothing);
    await t.tap(find.text('익숙함').at(1));
    await t.pumpAndSettle();
    expect(find.text('질문 4개 완료'), findsOneWidget);
    expect(find.text('데이터 모델링의 이해 보통 · SQL 기본 및 활용 익숙함'), findsOneWidget);
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
    // 바로 사용 · 목록에만 추가 중에서 고른다. 덮어쓴다는 안내는 없다.
    expect(find.text('목록에만 추가'), findsOneWidget);
    expect(find.textContaining('교체'), findsNothing);
    await t.tap(find.text('바로 사용'));
    await t.pumpAndSettle();
    expect(calls['$plannerPath/save'], plan);
    expect(savedQueries.single, isEmpty);
    expect(savedCount, 1);
    expect(find.text('학습계획에 넣기 완료'), findsOneWidget);
    expect(find.textContaining('1일치'), findsOneWidget);
    expect(find.textContaining('계획 목록에 보관'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
