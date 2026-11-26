import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/session.dart';
import 'package:passpace_mobile/ui/auth.dart';
import 'package:passpace_mobile/ui/admin_link.dart';
import 'package:passpace_mobile/ui/design.dart';

import 'support/admin_fixture.dart';

String sampleToken(String role, {String id = 'SAMPLE', DateTime? expires}) {
  String part(Object data) =>
      base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'loginId': id, 'role': role, 'exp': (expires ?? DateTime.now().add(const Duration(hours: 1))).millisecondsSinceEpoch ~/ 1000})}.SAMPLE';
}

class _Store implements SessionStore {
  String value;
  _Store(String token)
    : value = jsonEncode({'origin': emulatorOrigin, 'token': token});
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    value = next;
  }
}

Future<Session> sampleSession(String token, {AdminFixture? fixture}) async {
  final f = fixture ?? AdminFixture();
  addTearDown(f.dispose);
  final session = Session(_Store(token), f.client);
  addTearDown(session.dispose);
  await session.restore();
  return session;
}

Future<void> mountProfile(
  WidgetTester t,
  String token, {
  double width = 360,
  double scale = 1,
  AdminFixture? fixture,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(width, 720);
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  final session = await sampleSession(token, fixture: fixture);
  await t.pumpWidget(
    MaterialApp(
      theme: paceTheme(),
      home: Scaffold(body: ProfileScreen(session)),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  test('관리자 메뉴 표시는 만료·누락·불일치 토큰을 거부하고 세션을 수정하지 않는다', () async {
    final missingExpiry = base64Url
        .encode(utf8.encode(jsonEncode({'role': 'ADMIN', 'loginId': 'SAMPLE'})))
        .replaceAll('=', '');
    for (final token in [
      sampleToken('USER'),
      sampleToken('ROLE_ADMIN'),
      sampleToken('ADMIN', id: 'OTHER'),
      sampleToken('ADMIN', expires: DateTime.utc(2000)),
      'SAMPLE',
      'a.not-base64.a',
      'a.$missingExpiry.SAMPLE',
    ]) {
      final session = await sampleSession(token);
      final before = await session.store.read();
      expect(showsAdminPage(session), false);
      expect(await session.store.read(), before);
      expect(session.user?.id, 'SAMPLE');
    }
  });
  for (final width in [320.0, 360.0, 412.0]) {
    testWidgets('관리자는 내 정보에서 앱 내부 관리 화면에 진입하고 복귀한다: $width', (t) async {
      await mountProfile(t, sampleToken('ADMIN'), width: width, scale: 2);
      final menu = find.text('관리자 페이지');
      await t.ensureVisible(menu);
      await t.pumpAndSettle();
      await t.tap(menu);
      await t.pumpAndSettle();
      expect(find.text('수집 관리'), findsOneWidget);
      expect(find.text('DB 연결 정상'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('관리자 페이지'), findsOneWidget);
    });
  }
  testWidgets('일반 회원에게 관리자 메뉴를 표시하지 않는다', (t) async {
    await mountProfile(t, sampleToken('USER'));
    expect(find.text('관리자 페이지'), findsNothing);
  });
  testWidgets('관리자 조회 실패는 앱에서 안내하고 재시도로 복구한다', (t) async {
    bool fail = true;
    final fixture = AdminFixture(
      override: (r) async => r.url.path == '/admin/collect/db-status' && fail
          ? adminResponse({'detail': 'SAMPLE 오류'}, 503)
          : null,
    );
    await mountProfile(t, sampleToken('ADMIN'), fixture: fixture);
    final menu = find.text('관리자 페이지');
    await t.ensureVisible(menu);
    await t.pumpAndSettle();
    await t.tap(menu);
    await t.pumpAndSettle();
    expect(find.text('다시 불러오기'), findsOneWidget);
    fail = false;
    await t.tap(find.text('다시 불러오기'));
    await t.pumpAndSettle();
    expect(find.text('DB 연결 정상'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
