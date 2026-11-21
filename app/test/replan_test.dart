import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/ui/design.dart';
import 'package:passpace_mobile/ui/replan.dart';

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

/// 서버가 보내는 추천: 100시간 계획에서 20시간(20%)이 밀렸다.
Json advice({int shortfall = 0}) => {
  'needed': true,
  'planId': 11,
  'planName': '챗봇 학습계획 (SQLD, 하루 120분)',
  'status': {
    'needed': true,
    'totalMinutes': 6000,
    'dueMinutes': 1500,
    'doneMinutes': 300,
    'behindMinutes': 1200,
    'behindPercent': 20,
    'thresholdPercent': 20,
  },
  'proposal': {
    'calculatedOn': '2026-11-27',
    'dailyMinutes': 120,
    'totalRemainingMinutes': 5700,
    'totalShortfallMinutes': shortfall,
    'minimumDailyMinutes': 80,
    'additionalDailyMinutes': 0,
    'feasible': shortfall == 0,
    'notices': [],
    'goals': [],
    'days': [
      {
        'date': '2026-11-28',
        'availableMinutes': 120,
        'allocatedMinutes': 90,
        'allocations': [
          {'certificationName': 'SQLD', 'subjectName': 'SQL', 'minutes': 90},
        ],
      },
      {
        'date': '2026-11-27',
        'availableMinutes': 120,
        'allocatedMinutes': 80,
        'allocations': [
          {'certificationName': 'SQLD', 'subjectName': 'DB', 'minutes': 80},
        ],
      },
    ],
  },
};

void main() {
  test('추천이 없거나 일정이 비어 있으면 null, 있으면 밀린 정도와 새 일정을 읽는다', () async {
    Object? body;
    final api = PassApi(
      MockClient((r) async => envelope(body)),
      emulatorOrigin,
      token: 'fixture',
    );
    body = {'needed': false, 'planId': 11, 'status': null, 'proposal': null};
    expect(await api.replan(), isNull);
    body = {...advice(), 'proposal': null};
    expect(await api.replan(), isNull);
    body = advice();
    final found = (await api.replan())!;
    expect(found.percent, 20);
    expect(found.behindMinutes, 1200);
    expect(found.proposal.requiredMinutes, 5700);
    expect(found.proposal.days.length, 2);
  });

  testWidgets('홈 카드는 밀린 정도를 알리고, 확인 화면에서 받아들이면 서버에 반영한다', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(420, 2000);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final calls = <String>[];
    var fail = true;
    final api = PassApi(
      MockClient((r) async {
        calls.add('${r.method} ${r.url.path.substring(plannerPath.length)}');
        if (r.url.path == '$plannerPath/replan/accept') {
          // 첫 번째 요청은 실패한다 (그사이 계획이 바뀐 경우).
          if (fail) {
            fail = false;
            return envelope({'detail': '지금은 다시 짤 일정이 없습니다.'}, 400);
          }
          return envelope({'planId': 12, 'days': 2});
        }
        throw StateError(r.url.path);
      }),
      emulatorOrigin,
      token: 'fixture',
    );
    final found = ReplanAdvice.from(advice(shortfall: 120));
    bool? result;
    var later = 0;
    await t.pumpWidget(
      MaterialApp(
        theme: paceTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: ReplanCard(
              found,
              onLater: () => later++,
              onOpen: () async => result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => ReplanScreen(api, found)),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('계획이 밀렸어요. 일정을 다시 짤까요?'), findsOneWidget);
    expect(find.textContaining('계획한 25시간 중 5시간을 기록'), findsOneWidget);
    expect(find.textContaining('밀린 20시간은 전체 계획의 20%'), findsOneWidget);
    await t.tap(find.text('나중에'));
    expect(later, 1);

    await t.tap(find.text('다시 짠 일정 보기'));
    await t.pumpAndSettle();
    expect(find.text('남은 공부를 오늘부터 다시 나눴어요'), findsOneWidget);
    expect(find.text('95시간'), findsOneWidget);
    expect(find.textContaining('공부하는 날 2일'), findsOneWidget);
    // 날짜 순서대로 보여 준다.
    expect(
      t.getTopLeft(find.text('SQLD · DB · 80분')).dy,
      lessThan(t.getTopLeft(find.text('SQLD · SQL · 90분')).dy),
    );
    // 기간 안에 다 넣지 못한 양은 숨기지 않는다.
    expect(find.textContaining('2시간은 넣지 못했어요'), findsOneWidget);
    expect(calls, isEmpty);

    await t.tap(find.text('이 일정으로 바꾸기'));
    await t.pumpAndSettle();
    expect(find.textContaining('지금은 다시 짤 일정이 없습니다'), findsOneWidget);
    expect(result, isNull);

    await t.tap(find.text('이 일정으로 바꾸기'));
    await t.pumpAndSettle();
    expect(calls, ['POST /replan/accept', 'POST /replan/accept']);
    expect(result, isTrue);
    expect(find.text('남은 공부를 오늘부터 다시 나눴어요'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
