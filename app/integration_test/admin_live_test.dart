import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:passpace_mobile/data/session.dart';
import 'package:passpace_mobile/main.dart';
import 'package:passpace_mobile/ui/admin_api.dart';
import 'package:passpace_mobile/ui/admin_widgets.dart';

import '../test/admin_native_test.dart' show tapVisible;
import '../test/support/draft_storage.dart';

class _LiveMemoryStore implements SessionStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    value = next;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const origin = String.fromEnvironment('ADMIN_TEST_ORIGIN');
  const adminId = String.fromEnvironment('ADMIN_TEST_ID');
  const userId = String.fromEnvironment('ADMIN_TEST_USER');
  const password = String.fromEnvironment('ADMIN_TEST_PASSWORD');
  testWidgets('격리된 실제 API: 관리자 로그인·조회·출처 추가와 삭제·재집계·초기화·401/403', (t) async {
    if (origin != 'http://10.0.2.2:18085' ||
        adminId.isEmpty ||
        password.isEmpty) {
      throw StateError('격리 환경 전용 검증입니다.');
    }
    final client = http.Client();
    addTearDown(client.close);
    final session = Session(
      _LiveMemoryStore(),
      client,
      drafts: MemoryDraftStorage(),
    );
    addTearDown(session.dispose);
    await session.changeOrigin(origin);
    await session.signIn(adminId, password);
    final api = AdminApi(session);
    addTearDown(api.dispose);
    await t.pumpWidget(PassPaceApp(session));
    await t.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    Future<void> capture(String name) async {
      await t.pumpAndSettle();
      await binding.takeScreenshot(name);
    }

    Future<void> back() async {
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
    }

    await tapVisible(
      t,
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('내 정보'),
      ),
    );
    await tapVisible(t, find.text('관리자 페이지'));
    expect(find.text('DB 연결 정상'), findsOneWidget);
    await capture('live-admin-home');
    await tapVisible(t, find.text('수집 데이터'));
    expect(find.textContaining('SAMPLE 앱 내부 관리자 검증'), findsWidgets);
    await capture('live-admin-reviews');
    await back();
    await tapVisible(t, find.text('수집 범위'));
    final keyword = '앱 검증 $adminId';
    await t.enterText(find.byType(TextField).first, keyword);
    await tapVisible(t, find.text('검색어 추가'));
    expect(find.text('출처 추가 결과'), findsOneWidget);
    await back();
    final sources = adminObject(await api.get('/sources'));
    final matching = (sources['listings'] as List)
        .where((v) => Uri.parse(v as String).queryParameters['q'] == keyword)
        .toList();
    expect(matching, hasLength(1));
    final item = find
        .ancestor(of: find.text(keyword), matching: find.byType(Column))
        .first;
    await tapVisible(t, find.descendant(of: item, matching: find.text('삭제')));
    await t.tap(find.widgetWithText(FilledButton, '삭제'));
    await t.pumpAndSettle();
    expect(find.text('출처 삭제 결과'), findsOneWidget);
    final after = adminObject(await api.get('/sources'));
    expect((after['listings'] as List).contains(matching.single), false);
    await back();
    await back();
    await tapVisible(t, find.text('시험일정'));
    await tapVisible(t, find.text('참고 학습시간 재집계'));
    await t.tap(find.text('실행하기'));
    await t.pumpAndSettle();
    expect(find.text('처리 결과'), findsOneWidget);
    await back();
    await back();
    final preview = adminObject(await api.get('/reviews/reset'));
    expect(preview['velog'], 2);
    expect(preview['tistory'], 1);
    await tapVisible(t, find.text('복구 리포트·후기 초기화'));
    await tapVisible(t, find.text('후기 초기화'));
    await t.enterText(find.byType(TextField), '틀린 문구');
    await t.pumpAndSettle();
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, '초기화 실행'))
          .onPressed,
      isNull,
    );
    await t.tap(find.text('취소'));
    await t.pumpAndSettle();
    final unchanged = adminObject(await api.get('/reviews/reset'));
    expect(unchanged['velog'], 2);
    expect(unchanged['tistory'], 1);
    await tapVisible(t, find.text('후기 초기화'));
    await t.enterText(find.byType(TextField), '초기화');
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, '초기화 실행'));
    await t.pumpAndSettle();
    expect(find.text('초기화 결과'), findsOneWidget);
    final empty = adminObject(await api.get('/reviews/reset'));
    expect(empty['velog'], 0);
    expect(empty['tistory'], 0);
    final unauth = await client.get(
      Uri.parse('$origin/admin/collect/db-status'),
    );
    expect(unauth.statusCode, 401);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    final user = Session(
      _LiveMemoryStore(),
      client,
      drafts: MemoryDraftStorage(),
    );
    addTearDown(user.dispose);
    await user.changeOrigin(origin);
    await user.signIn(userId, password);
    final forbidden = await client.get(
      Uri.parse('$origin/admin/collect/db-status'),
      headers: {'Authorization': 'Bearer ${user.account!.token}'},
    );
    expect(forbidden.statusCode, 403);
    await t.pumpWidget(PassPaceApp(user));
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
