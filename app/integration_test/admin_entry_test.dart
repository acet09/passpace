import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:passpace_mobile/main.dart';
import 'package:passpace_mobile/ui/admin_screen.dart';

import '../test/support/admin_fixture.dart';
import '../test/admin_native_test.dart' show tapVisible;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> capture(WidgetTester t, String name) async {
    await t.pumpAndSettle();
    await binding.takeScreenshot(name);
  }

  testWidgets('SAMPLE: 앱 내부 관리자 조회·수집·출처·초기화 확인 동선', (t) async {
    final f = AdminFixture();
    addTearDown(f.dispose);
    await f.restore();
    await t.pumpWidget(PassPaceApp(f.session));
    await t.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await tapVisible(
      t,
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('내 정보'),
      ),
    );
    await t.ensureVisible(find.text('관리자 페이지'));
    await t.pumpAndSettle();
    await capture(t, 'admin-profile');
    await tapVisible(t, find.text('관리자 페이지'));
    expect(find.byType(AdminScreen), findsOneWidget);
    expect(find.text('DB 연결 정상'), findsOneWidget);
    await capture(t, 'admin-home');
    await tapVisible(t, find.text('후기 수집'));
    await capture(t, 'admin-collect');
    await t.enterText(find.byType(TextFormField), '37');
    await tapVisible(t, find.text('수집 시작'));
    await t.tap(find.text('취소'));
    await t.pumpAndSettle();
    expect(f.requests.where((r) => r.method == 'POST'), isEmpty);
    await tapVisible(t, find.text('수집 시작'));
    await t.tap(find.text('시작하기'));
    await t.pumpAndSettle();
    expect(
      f.requests.singleWhere((r) => r.method == 'POST').bodyFields['limit'],
      '37',
    );
    await capture(t, 'admin-running');
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await tapVisible(t, find.text('수집 데이터'));
    await capture(t, 'admin-reviews');
    await tapVisible(t, find.text('상세 보기'));
    await capture(t, 'admin-review-detail');
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await t.tap(find.text('다음'));
    await t.pumpAndSettle();
    expect(find.text('#21'), findsOneWidget);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await tapVisible(t, find.text('수집 범위'));
    await capture(t, 'admin-sources');
    await t.enterText(find.byType(TextField).first, 'SAMPLE 앱 관리자');
    await tapVisible(t, find.text('검색어 추가'));
    expect(find.text('출처 추가 결과'), findsOneWidget);
    expect(
      f.requests.lastWhere((r) => r.method == 'POST').url.path,
      '/admin/collect/sources/velog-keyword',
    );
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await tapVisible(t, find.text('시험일정'));
    await capture(t, 'admin-schedules');
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    await tapVisible(t, find.text('복구 리포트·후기 초기화'));
    await tapVisible(t, find.text('후기 초기화'));
    await t.enterText(find.byType(TextField), '초기화');
    await t.pumpAndSettle();
    await capture(t, 'admin-reset-confirm');
    await t.tap(find.text('취소'));
    await t.pumpAndSettle();
    expect(
      f.requests.where(
        (r) => r.method == 'POST' && r.url.path.endsWith('/reset'),
      ),
      isEmpty,
    );
    expect(f.requests.every((r) => r.url.host == '10.0.2.2'), true);
    expect(t.takeException(), isNull);
  });
  testWidgets('SAMPLE: 연결 실패·재시도·일반 회원 메뉴 숨김', (t) async {
    bool fail = true;
    final f = AdminFixture(
      override: (r) async => fail && r.url.path == '/admin/collect/db-status'
          ? adminResponse({}, 503)
          : null,
    );
    addTearDown(f.dispose);
    await f.restore();
    await t.pumpWidget(PassPaceApp(f.session));
    await t.pumpAndSettle();
    await tapVisible(
      t,
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('내 정보'),
      ),
    );
    await tapVisible(t, find.text('관리자 페이지'));
    await binding.convertFlutterSurfaceToImage();
    await capture(t, 'admin-error');
    fail = false;
    await tapVisible(t, find.text('다시 불러오기'));
    expect(find.text('DB 연결 정상'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    final user = AdminFixture(role: 'USER');
    addTearDown(user.dispose);
    await user.restore();
    await t.pumpWidget(PassPaceApp(user.session));
    await t.pumpAndSettle();
    await tapVisible(
      t,
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('내 정보'),
      ),
    );
    expect(find.text('관리자 페이지'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
