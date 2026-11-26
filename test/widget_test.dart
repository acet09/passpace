import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/data/session.dart';
import 'package:passpace_mobile/main.dart';
import 'package:passpace_mobile/ui/design.dart';
import 'package:passpace_mobile/ui/planner.dart';
import 'package:passpace_mobile/data/plan_draft.dart';

import 'support/draft_storage.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

class MemoryStore implements SessionStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async {
    value = v;
  }
}

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
final person = {
  'loginId': 'planner_01',
  'nickname': '민지',
  'email': 'm@example.org',
  'majorType': 'RELATED',
  'majorTypeLabel': '유사전공',
};

void main() {
  test('서울 기준 자정과 날짜별 과목 시간을 구분한다', () {
    expect(isoDay(dayInSeoul(DateTime.utc(2026, 11, 14, 15))), '2026-11-15');
    final p = SavedPlan.from({
      'planName': 'SQLD',
      'startDate': '2026-12-01',
      'endDate': '2026-12-15',
      'versionNo': 2,
      'tasks': [
        {
          'date': '2026-12-01',
          'certificationName': 'SQLD',
          'subjectName': '모델링',
          'minutes': 75,
        },
      ],
    });
    expect(
      durationLabel(p.on(DateTime(2026, 12, 1)).single.minutes),
      '1시간 15분',
    );
    expect(p.on(DateTime(2026, 12, 2)), isEmpty);
  });
  test('서버 주소를 제한하고 리다이렉트에 인증 정보를 전달하지 않는다', () async {
    for (final bad in [
      'http://example.org',
      'https://me@host',
      'https://host/path',
      'ftp://host',
      'https://host?q=a',
      'http://100.63.255.255:8102',
      'http://100.128.0.1:8102',
      'http://100.95.33:8102',
    ]) {
      expect(() => validOrigin(bad), throwsA(isA<ApiError>()));
    }
    expect(
      validOrigin('http://100.95.33.60:8102'),
      'http://100.95.33.60:8102',
    );
    expect(
      validOrigin('http://100.112.211.106:8102/'),
      'http://100.112.211.106:8102',
    );
    expect(
      validOrigin('https://study.example.org/'),
      'https://study.example.org',
    );
    final api = PassApi(
      MockClient((r) async {
        expect(r.followRedirects, isFalse);
        expect(r.headers['Authorization'], 'Bearer test');
        return http.Response(
          '',
          302,
          headers: {'location': 'https://different.example.org'},
        );
      }),
      emulatorOrigin,
      token: 'test',
    );
    await expectLater(api.saved(), throwsA(isA<ApiError>()));
  });
  test('일시적인 연결 실패 시 저장된 로그인을 유지하고 만료 시 지운다', () async {
    final store = MemoryStore()
      ..value = jsonEncode({'origin': emulatorOrigin, 'token': 'fixture'});
    var status = 503;
    final session = Session(
      store,
      MockClient(
        (_) async => status == 200
            ? envelope(person)
            : envelope({'ko': '다시 시도'}, status),
      ),
    );
    await session.restore();
    expect(session.user, isNull);
    expect(session.restoreError, isNotNull);
    expect(store.value, contains('fixture'));
    status = 200;
    await session.restore();
    expect(session.user!.id, person['loginId']);
    status = 401;
    await expectLater(session.account!.saved(), throwsA(isA<ApiError>()));
    await Future<void>.delayed(Duration.zero);
    expect(session.user, isNull);
    expect(jsonDecode(store.value!)['token'], isNull);
  });
  testWidgets('작은 휴대폰에서 로그인 후 주간 일정, 상담, 로그아웃이 이어진다', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(360, 720);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final today = dayInSeoul(), store = MemoryStore();
    final messages = <Json>[];
    final session = Session(
      store,
      MockClient((r) async {
        final path = r.url.path;
        if (path == '/auth/login') {
          expect(jsonDecode(r.body)['loginId'], person['loginId']);
          return envelope({'accessToken': 'fixture', 'expiresInSeconds': 3600});
        }
        expect(r.headers['Authorization'], 'Bearer fixture');
        if (path == '/auth/user-info') return envelope(person);
        if (path == '/users/me/goal') {
          return envelope({
            'goal': {
              'targetExamDate': isoDay(plusDays(today, 35)),
              'dailyMinutes': 120,
              'familiarity': {},
            },
            'examRounds': [],
            'subjects': [],
          });
        }
        if (path == '$plannerPath/saved') {
          return envelope({
            'plan': {
              'planName': 'SQLD 필기',
              'versionNo': 1,
              'startDate': isoDay(today),
              'endDate': isoDay(plusDays(today, 10)),
              'tasks': [
                {
                  'date': isoDay(today),
                  'certificationName': 'SQLD',
                  'subjectName': 'SQL 활용',
                  'minutes': 45,
                },
              ],
            },
          });
        }
        if (path == '/api/chat') {
          messages.add(object(jsonDecode(r.body)));
          return envelope({
            'answer': '데이터 모델링부터 공부하세요.',
            'conId': 7,
            'llmUsed': false,
            'sources': [],
          });
        }
        throw StateError(path);
      }),
    );
    await session.restore();
    await t.pumpWidget(PassPaceApp(session));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField).at(0), 'planner_01');
    await t.enterText(find.byType(TextFormField).at(1), 'fixture-password');
    final login = find.widgetWithText(FilledButton, '로그인');
    await t.ensureVisible(login);
    await t.tap(login);
    await t.pumpAndSettle();
    expect(find.text('오늘 할 학습'), findsOneWidget);
    expect(find.text('D-35'), findsOneWidget);
    final mark = find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(Image),
    );
    expect(
      (t.widget<Image>(mark).image as AssetImage).assetName,
      'assets/passpace_launcher.png',
    );
    expect(find.text(shortDay(plusDays(today, 35))), findsNothing);
    expect(find.text('SQL 활용'), findsOneWidget);
    expect(
      t.getTopLeft(find.text('D-35')).dy,
      lessThan(t.getTopLeft(find.text('오늘 전체 진행률')).dy),
    );
    expect(
      t.getBottomLeft(find.text('SQL 활용')).dy,
      lessThan(t.getTopLeft(find.byType(NavigationBar)).dy),
    );
    expect(
      t.getTopLeft(find.text('SQL 활용')).dy,
      lessThan(
        t.getTopLeft(find.byKey(const ValueKey('home-open-schedule'))).dy,
      ),
    );
    expect(find.text('학습 달력'), findsNothing);
    expect(find.text('오늘 할 학습'), findsOneWidget);
    expect(find.text('타이머 열기'), findsNothing);
    expect(find.text('SQL 활용'), findsOneWidget);
    await t.tap(find.text('상담'));
    await t.pumpAndSettle();
    await t.tap(find.text('SQLD는 어떤 과목부터 공부할까요?'));
    await t.pumpAndSettle();
    expect(find.text('데이터 모델링부터 공부하세요.'), findsOneWidget);
    await t.enterText(find.byType(TextField), '다음 과목은요?');
    await t.pump();
    await t.tap(find.byTooltip('질문 보내기'));
    await t.pumpAndSettle();
    expect(messages.map((m) => m['conId']), [null, 7]);
    await t.tap(find.text('내 정보'));
    await t.pumpAndSettle();
    final logout = find.widgetWithText(OutlinedButton, '로그아웃');
    await t.ensureVisible(logout);
    await t.tap(logout);
    await t.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '로그인'), findsOneWidget);
    expect(jsonDecode(store.value!)['token'], isNull);
    expect(t.takeException(), isNull);
  });
  testWidgets('계획 단계를 오가며 입력을 보존하고 미리보기 전에는 저장하지 않는다', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(360, 720);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final today = dayInSeoul(), requests = <String>[];
    final api = PassApi(
      MockClient((r) async {
        requests.add(r.url.path);
        if (r.url.path == '$plannerPath/catalog') {
          return envelope({
            'goals': [
              {
                'key': 'sqld',
                'certificationName': 'SQLD 필기',
                'temporaryCatalog': false,
                'suggestedExamDate': isoDay(plusDays(today, 35)),
                'subjects': [
                  {'name': 'SQL 활용', 'baseHours': 10},
                ],
              },
            ],
            'notices': [],
            'profileDailyMinutes': 120,
          });
        }
        if (r.url.path == '/users/me/goal') {
          return envelope({'goal': {}, 'examRounds': [], 'subjects': []});
        }
        if (r.url.path == '$plannerPath/saved') return envelope({'plan': null});
        if (r.url.path == '$plannerPath/preview') {
          final p = object(jsonDecode(r.body));
          expect(p['dailyMinutes'], 90);
          expect(p['studyWeekdays'], [1, 2, 3, 4, 5, 6, 7]);
          expect(p['goals'][0]['subjects'][0]['familiarity'], 2);
          return envelope({
            'totalRemainingMinutes': 600,
            'totalShortfallMinutes': 0,
            'feasible': true,
            'notices': [],
            'days': List.generate(
              7,
              (i) => {
                'date': isoDay(plusDays(today, i)),
                'availableMinutes': 90,
                'allocatedMinutes': 60,
                'allocations': [
                  {'subjectName': 'SQL 활용', 'minutes': 60},
                ],
              },
            ),
          });
        }
        throw StateError(r.url.path);
      }),
      emulatorOrigin,
      token: 'fixture',
    );
    await t.pumpWidget(
      MaterialApp(
        theme: paceTheme(),
        locale: const Locale('ko'),
        supportedLocales: const [Locale('ko')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: PlannerScreen(
          api,
          draftRepository: PlanDraftRepository(
            MemoryDraftStorage(),
            emulatorOrigin,
            'fixture',
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '90');
    await t.tap(find.widgetWithText(FilledButton, '다음'));
    await t.pumpAndSettle();
    await t.tap(find.byType(CheckboxListTile));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(OutlinedButton, '이전'));
    await t.pumpAndSettle();
    expect(
      t.widget<TextField>(find.byType(TextField).first).controller!.text,
      '90',
    );
    await t.tap(find.widgetWithText(FilledButton, '다음'));
    await t.pumpAndSettle();
    expect(
      t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      true,
    );
    await t.tap(find.widgetWithText(FilledButton, '다음'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, '계획 미리보기'));
    await t.pumpAndSettle();
    expect(find.text('SQL 활용 과목의 이해도를 선택해 주세요.'), findsOneWidget);
    await t.tap(find.widgetWithText(ChoiceChip, '보통'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, '계획 미리보기'));
    await t.pumpAndSettle();
    expect(find.text('주간 배정'), findsOneWidget);
    expect(requests.where((s) => s.endsWith('/save')), isEmpty);
    final edit = find.text('입력 수정');
    await t.ensureVisible(edit);
    await t.tap(edit);
    await t.pumpAndSettle();
    expect(
      t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '보통')).selected,
      true,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('작은 화면과 큰 글자에서도 로그인 폼을 사용할 수 있다', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(320, 640);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final session = Session(
      MemoryStore(),
      MockClient((_) async => envelope(null)),
    );
    await session.restore();
    await t.pumpWidget(PassPaceApp(session));
    await t.pumpAndSettle();
    final ctx = t.element(find.byType(Scaffold).first);
    final media = MediaQuery.of(ctx);
    await t.pumpWidget(
      MediaQuery(
        data: media.copyWith(textScaler: TextScaler.linear(1.5)),
        child: PassPaceApp(session),
      ),
    );
    await t.pumpAndSettle();
    final login = find.widgetWithText(FilledButton, '로그인');
    await t.ensureVisible(login);
    await t.tap(login);
    await t.pumpAndSettle();
    expect(find.text('아이디를 입력해 주세요.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('큰 글자의 홈과 학습 항목 상담 동선에서 내용이 넘치지 않는다', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(320, 700);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final today = dayInSeoul();
    final store = MemoryStore()
      ..value = jsonEncode({'origin': emulatorOrigin, 'token': 'fixture'});
    final s = Session(
      store,
      MockClient((r) async {
        if (r.url.path == '/auth/user-info') return envelope(person);
        if (r.url.path == '/users/me/goal') {
          return envelope({
            'goal': {
              'targetExamDate': isoDay(plusDays(today, 35)),
              'familiarity': {},
            },
            'examRounds': [],
            'subjects': [],
          });
        }
        if (r.url.path.endsWith('/saved')) {
          return envelope({
            'plan': {
              'planName': '복수 자격증 학습계획',
              'versionNo': 1,
              'startDate': isoDay(today),
              'endDate': isoDay(plusDays(today, 35)),
              'tasks': [
                {
                  'date': isoDay(today),
                  'certificationName': 'SQLD 필기',
                  'subjectName': 'SQL 활용',
                  'minutes': 90,
                },
              ],
            },
          });
        }
        throw StateError(r.url.path);
      }),
    );
    await s.restore();
    await t.pumpWidget(PassPaceApp(s));
    await t.pumpAndSettle();
    final media = MediaQuery.of(t.element(find.byType(Scaffold).first));
    await t.pumpWidget(
      MediaQuery(
        data: media.copyWith(textScaler: TextScaler.linear(1.5)),
        child: PassPaceApp(s),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    final task = find.byTooltip('SQL 활용 메뉴');
    await t.ensureVisible(task);
    await t.tap(task);
    await t.pumpAndSettle();
    await t.tap(find.text('상세 보기'));
    await t.pumpAndSettle();
    await t.tap(find.text('이 과목 공부 방법 상담'));
    await t.pumpAndSettle();
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      contains('SQL 활용'),
    );
    expect(t.takeException(), isNull);
  });
  test('띄엄띄엄 배정된 학습일도 미리보기는 달력 기준 7일씩 표시한다', () {
    final first = DateTime(2026, 11, 14);
    final p = Preview.from({
      'totalRemainingMinutes': 90,
      'totalShortfallMinutes': 0,
      'feasible': true,
      'notices': [],
      'days': [
        {'date': isoDay(first), 'allocatedMinutes': 45, 'allocations': []},
        {
          'date': isoDay(plusDays(first, 28)),
          'allocatedMinutes': 45,
          'allocations': [],
        },
      ],
    });
    expect(p.calendarWeeks, 5);
    expect(
      p.weekAt(0).map((d) => d['date']),
      List.generate(7, (i) => isoDay(plusDays(first, i))),
    );
    expect(p.weekAt(0)[1]['allocatedMinutes'], 0);
    expect(p.weekAt(4).first['allocatedMinutes'], 45);
  });
}
