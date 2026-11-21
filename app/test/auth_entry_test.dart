import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:passpace_mobile/data/session.dart';
import 'package:passpace_mobile/main.dart';

class _Store implements SessionStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
}

void main() {
  testWidgets('소개 문구와 로그인은 유지하고 세 단계 안내만 제거한다', (t) async {
    final client = MockClient(
      (r) async => throw StateError('로그인 전에는 요청하지 않습니다.'),
    );
    addTearDown(client.close);
    final session = Session(_Store(), client);
    addTearDown(session.dispose);
    await session.restore();
    await t.pumpWidget(PassPaceApp(session));
    await t.pumpAndSettle();
    expect(find.textContaining('목표와 가능한 시간을 정하고,'), findsOneWidget);
    for (final label in ['목표 설정', '학습계획', '오늘의 학습']) {
      expect(find.text(label), findsNothing);
    }
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.widgetWithText(FilledButton, '로그인'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '회원가입'), findsOneWidget);
  });
  for (final width in [320.0, 360.0, 412.0]) {
    for (final scale in [1.5, 2.0]) {
      testWidgets('로그인 입력·오류·회원가입 복귀: 너비 $width 글자 $scale', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(width, 720);
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetViewInsets);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final writes = <Map<String, dynamic>>[];
        final client = MockClient((r) async {
          expect(r.url.path, '/auth/login');
          writes.add(jsonDecode(r.body) as Map<String, dynamic>);
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'code': 503,
                'data': {'ko': '연결을 다시 확인해 주세요.'},
              }),
            ),
            503,
          );
        });
        addTearDown(client.close);
        final session = Session(_Store(), client);
        await session.restore();
        await t.pumpWidget(PassPaceApp(session));
        await t.pumpAndSettle();
        expect(
          MediaQuery.textScalerOf(t.element(find.byType(Scaffold).first))
              .scale(10),
          10 * scale,
        );
        final id = find.byType(TextFormField).first;
        final password = find.byType(TextFormField).last;
        await t.ensureVisible(id);
        await t.enterText(id, 'SAMPLE');
        await t.ensureVisible(password);
        await t.enterText(password, 'SAMPLE_password');
        t.view.viewInsets = const FakeViewPadding(bottom: 280);
        await t.pumpAndSettle();
        expect(
          MediaQuery.viewInsetsOf(t.element(find.byType(Scaffold).first))
              .bottom,
          280,
        );
        final login = find.widgetWithText(FilledButton, '로그인');
        await t.ensureVisible(login);
        await t.pumpAndSettle();
        expect(t.getSize(login).height, greaterThanOrEqualTo(48));
        await t.tap(login);
        await t.pumpAndSettle();
        expect(writes.single, {
          'loginId': 'SAMPLE',
          'password': 'SAMPLE_password',
        });
        expect(t.widget<TextFormField>(id).controller!.text, 'SAMPLE');
        expect(
          t.widget<TextFormField>(password).controller!.text,
          'SAMPLE_password',
        );
        expect(t.takeException(), isNull);
        t.view.resetViewInsets();
        await t.pumpAndSettle();
        final signup = find.widgetWithText(OutlinedButton, '회원가입');
        await t.ensureVisible(signup);
        await t.pumpAndSettle();
        await t.tap(signup);
        await t.pumpAndSettle();
        expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
        await t.tap(find.byType(BackButton));
        await t.pumpAndSettle();
        expect(t.widget<TextFormField>(id).controller!.text, 'SAMPLE');
        expect(t.takeException(), isNull);
      });
    }
  }
}
