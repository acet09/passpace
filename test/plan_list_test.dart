import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/ui/design.dart';
import 'package:passpace_mobile/ui/plan_list.dart';

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
  testWidgets('저장한 계획을 여러 개 보고, 사용할 계획을 바꾸고, 지운다', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(320, 2400);
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    // 서버 흉내: 계획 세 개, 그중 하나만 사용 중.
    final plans = <int, String>{9: 'ADsP + SQLD', 8: 'SQLD', 3: '정처기 필기'};
    int? active = 9;
    final calls = <String>[];
    var changed = 0;
    final api = PassApi(
      MockClient((r) async {
        final path = r.url.path.substring(plannerPath.length);
        calls.add('${r.method} $path');
        if (r.method == 'GET' && path == '/plans') {
          return envelope({
            'plans': [
              for (final e in plans.entries)
                {
                  'planId': e.key,
                  'planName': e.value,
                  'versionNo': e.key,
                  'startDate': '2026-11-19',
                  'endDate': '2027-02-27',
                  'active': e.key == active,
                  'days': 52,
                  'totalMinutes': 3235,
                },
            ],
          });
        }
        if (r.method == 'GET' && path == '/plans/8') {
          return envelope({
            'plan': {
              'planId': 8,
              'planName': 'SQLD',
              'versionNo': 8,
              'startDate': '2026-11-19',
              'endDate': '2027-02-27',
              'tasks': [
                {
                  'date': '2026-11-19',
                  'certificationName': 'SQLD',
                  'subjectName': 'SQL 기본 및 활용',
                  'minutes': 90,
                },
              ],
            },
          });
        }
        if (r.method == 'POST' && path == '/plans/8/activate') {
          active = 8;
          return envelope({'planId': 8, 'active': true});
        }
        if (r.method == 'DELETE' && path == '/plans/3') {
          return envelope({
            'ko': '요청 값이 올바르지 않습니다.',
            'detail': '이 계획에 연결된 학습기록이 2건 있어 삭제할 수 없습니다.',
          }, 400);
        }
        if (r.method == 'DELETE' && path == '/plans/9') {
          plans.remove(9);
          return envelope({'planId': 9, 'deleted': true});
        }
        throw StateError('${r.method} $path');
      }),
      emulatorOrigin,
      token: 'fixture',
    );
    await t.pumpWidget(
      MaterialApp(
        theme: paceTheme(),
        home: PlanListScreen(api, onChanged: () => changed++),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text('ADsP + SQLD'), findsOneWidget);
    expect(find.text('SQLD'), findsOneWidget);
    expect(find.text('정처기 필기'), findsOneWidget);
    expect(find.text('사용 중인 계획'), findsOneWidget);
    expect(find.text('보관한 계획'), findsOneWidget);
    expect(find.text('이 계획 사용'), findsNothing);
    expect(find.text('삭제'), findsNothing);
    final activeCard = find.byKey(const ValueKey('active-plan-card-9'));
    expect(
      find.descendant(of: activeCard, matching: find.text('ADsP + SQLD')),
      findsOneWidget,
    );

    // 보관한 계획의 일정을 본다.
    await t.tap(find.text('SQLD'));
    await t.pumpAndSettle();
    expect(find.text('SQLD · SQL 기본 및 활용 · 90분'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();

    // 보관한 계획을 사용하면 그 계획만 사용 중이 된다.
    await t.tap(find.byTooltip('SQLD 더보기'));
    await t.pumpAndSettle();
    await t.tap(find.text('이 계획 사용'));
    await t.pumpAndSettle();
    expect(calls, contains('POST /plans/8/activate'));
    expect(changed, 1);
    // 전환에 성공했으면 오류 안내가 없어야 한다.
    expect(find.byType(AlertText), findsNothing);
    expect(find.byKey(const ValueKey('active-plan-card-8')), findsOneWidget);
    expect(activeCard, findsNothing);

    // 학습기록이 연결된 계획은 서버가 거절하고, 그 이유를 보여 준다.
    await t.tap(find.byTooltip('정처기 필기 더보기'));
    await t.pumpAndSettle();
    await t.tap(find.text('삭제'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, '삭제'));
    await t.pumpAndSettle();
    expect(find.textContaining('연결된 학습기록이 2건'), findsOneWidget);
    expect(find.text('정처기 필기'), findsOneWidget);
    expect(changed, 1);

    // 지울 수 있는 계획은 목록에서 사라진다.
    await t.tap(find.byTooltip('ADsP + SQLD 더보기'));
    await t.pumpAndSettle();
    await t.tap(find.text('삭제'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, '삭제'));
    await t.pumpAndSettle();
    expect(calls, contains('DELETE /plans/9'));
    expect(find.text('ADsP + SQLD'), findsNothing);
    expect(changed, 2);
    expect(t.takeException(), isNull);
  });
}
