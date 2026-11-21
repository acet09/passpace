import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/data/session.dart';
import 'package:passpace_mobile/main.dart';

import '../test/support/draft_storage.dart';

// This UI-only scenario never reads the device account or calls a real server.
class _MemoryStore implements SessionStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
}

http.Response _ok(Object? data) => http.Response.bytes(
  utf8.encode(jsonEncode({'code': 200, 'status': 'SUCCESS', 'data': data})),
  200,
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('SAMPLE: 로그인 화면과 설정 접기·저장 후 펼침을 Android에서 확인한다', (t) async {
    final today = dayInSeoul();
    var minutes = 125, goalWrites = 0;
    final client = MockClient((r) async {
      if (r.url.path == '/auth/login') {
        return _ok({'accessToken': 'SAMPLE', 'expiresInSeconds': 3600});
      }
      if (r.url.path == '/auth/user-info') {
        return _ok({
          'loginId': 'SAMPLE',
          'nickname': 'SAMPLE 화면검증',
          'email': 'sample@example.invalid',
          'majorType': 'RELATED',
          'majorTypeLabel': '유사전공',
        });
      }
      if (r.url.path == '/users/me/goal') {
        if (r.method == 'PUT') {
          minutes = object(jsonDecode(r.body))['dailyMinutes'] as int;
          goalWrites++;
          return _ok({});
        }
        return _ok({
          'goal': {
            'examRoundId': null,
            'targetExamDate': isoDay(plusDays(today, 35)),
            'dailyMinutes': minutes,
            'familiarity': {'11': 3},
          },
          'examRounds': [],
          'subjects': [
            {'subjectId': 11, 'subjectName': 'SQL 활용'},
          ],
        });
      }
      if (r.url.path == '$plannerPath/saved') {
        return _ok({
          'plan': {
            'planId': 11,
            'versionNo': 2,
            'planName': 'SQLD',
            'startDate': isoDay(today),
            'endDate': isoDay(plusDays(today, 35)),
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
      throw StateError('Unexpected ${r.method} ${r.url.path}');
    });
    addTearDown(client.close);
    final session = Session(
      _MemoryStore(),
      client,
      drafts: MemoryDraftStorage(),
    );
    await session.restore();
    await t.pumpWidget(PassPaceApp(session));
    await t.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();

    Future<void> capture(String name) async {
      await t.pumpAndSettle();
      await t.pump(const Duration(milliseconds: 500));
      final bytes = await binding.takeScreenshot(name);
      await File('${Directory.systemTemp.path}/entry-$name.png')
          .writeAsBytes(bytes);
    }

    Future<void> tap(Finder finder) async {
      await t.ensureVisible(finder);
      await t.pumpAndSettle();
      await t.tap(finder);
      await t.pumpAndSettle();
    }

    await capture('login');
    await tap(find.widgetWithText(OutlinedButton, '회원가입'));
    await capture('signup');
    await tap(find.byType(BackButton));
    await t.enterText(find.byType(TextFormField).first, 'SAMPLE');
    await t.enterText(find.byType(TextFormField).last, 'SAMPLE_password');
    FocusManager.instance.primaryFocus?.unfocus();
    await tap(find.widgetWithText(FilledButton, '로그인'));
    await tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('학습계획'),
      ),
    );
    await capture('plan-expanded');
    await tap(find.byTooltip('목표와 기본 설정 접기'));
    await tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('학습계획'),
      ),
    );
    await capture('plan-collapsed');
    expect(find.text('설정 수정'), findsNothing);
    await tap(find.byTooltip('목표와 기본 설정'));
    await t.enterText(find.byType(TextField).first, '180');
    FocusManager.instance.primaryFocus?.unfocus();
    await tap(find.text('목표 저장'));
    expect(goalWrites, 1);
    expect(find.byTooltip('목표와 기본 설정 접기'), findsOneWidget);
    expect(find.text('목표를 저장했어요'), findsOneWidget);
    await capture('goal-saved');
    expect(t.takeException(), isNull);
  });
}
