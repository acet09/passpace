import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passpace_mobile/ui/admin_link.dart';
import 'package:passpace_mobile/ui/admin_widgets.dart';
import 'package:passpace_mobile/ui/design.dart';

import 'support/admin_fixture.dart';

Future<AdminFixture> openAdmin(
  WidgetTester t, {
  AdminFixture? fixture,
  double width = 360,
  double scale = 1,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(width, 800);
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  final f = fixture ?? AdminFixture();
  await f.restore();
  addTearDown(f.dispose);
  await t.pumpWidget(
    MaterialApp(
      theme: paceTheme(),
      home: Scaffold(body: AdminPageLink(f.session)),
    ),
  );
  await t.tap(find.text('관리자 페이지'));
  await t.pumpAndSettle();
  return f;
}

void main() {
  testWidgets('상세 화면 뒤의 수집 화면은 앱 복귀 때도 조회하지 않으며 돌아오면 진행 조회를 잇는다', (t) async {
    final f = AdminFixture(
      override: (r) async => r.url.path == '/admin/collect/reviews/status'
          ? adminResponse({
              ...sampleJob,
              'state': 'RUNNING',
              'processed': 2,
              'candidates': 100,
            })
          : null,
    );
    await openAdmin(t, fixture: f);
    await tapVisible(t, find.text('후기 수집'));
    await tapVisible(t, find.text('실행 상세 보기').first);
    final before = f.requests.length;
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(f.requests.length, before);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
    expect(f.requests.length, greaterThan(before));
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
  testWidgets('권한 거부 즉시 현재·이전 관리 화면의 조회 데이터를 숨기고 일반 세션은 유지한다', (t) async {
    bool deny = false;
    final f = AdminFixture(
      override: (r) async => deny && r.url.path == '/admin/collect/sources'
          ? adminResponse({}, 403)
          : null,
    );
    await openAdmin(t, fixture: f);
    await tapVisible(t, find.text('수집 범위'));
    expect(find.text('https://velog.io/search?q=SAMPLE'), findsOneWidget);
    deny = true;
    await t.tap(find.byTooltip('수집 범위 새로고침'));
    await t.pumpAndSettle();
    expect(find.text('https://velog.io/search?q=SAMPLE'), findsNothing);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('DB 연결 정상'), findsNothing);
    expect(find.text('DB 상세'), findsNothing);
    expect(f.session.user?.id, 'SAMPLE');
    expect(t.takeException(), isNull);
  });
  testWidgets('관리자 메뉴는 브라우저 없이 앱 안의 관리 화면을 열고 기존 토큰으로 조회한다', (t) async {
    final browserCalls = <MethodCall>[];
    const channel = MethodChannel('kr.passpace.mobile/navigation');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
          browserCalls.add(c);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final f = await openAdmin(t);
    expect(find.text('수집 관리'), findsOneWidget);
    expect(find.text('수집 데이터'), findsOneWidget);
    expect(browserCalls, isEmpty);
    final adminRequests = f.requests.where(
      (r) => r.url.path.startsWith('/admin/'),
    );
    expect(adminRequests, isNotEmpty);
    for (final r in adminRequests) {
      expect(r.headers['Authorization'], 'Bearer ${f.session.account!.token}');
      expect(r.url.query, isNot(contains('token')));
      expect(r.method, 'GET');
    }
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('관리자 페이지'), findsOneWidget);
  });

  testWidgets('수집 입력·확인·취소와 폼 요청을 보존하고 화면 종료 후 조회를 멈춘다', (t) async {
    final f = await openAdmin(t);
    await tapVisible(t, find.text('후기 수집'));
    await t.enterText(find.byType(TextFormField), '37');
    await choose(t, '수집 사이트', '티스토리');
    await choose(t, '수집 방식', '복구 수집');
    await tapVisible(t, find.byType(SwitchListTile).first);
    await tapVisible(t, find.text('수집 시작'));
    await t.tap(find.text('취소'));
    await t.pumpAndSettle();
    expect(f.requests.where((r) => r.method == 'POST'), isEmpty);
    await tapVisible(t, find.text('수집 시작'));
    await t.tap(find.text('시작하기'));
    await t.pumpAndSettle();
    final writes = f.requests.where((r) => r.method == 'POST').toList();
    expect(writes, hasLength(1));
    expect(writes.single.url.path, '/admin/collect/reviews/start');
    expect(writes.single.bodyFields, {
      'limit': '37',
      'site': 'TISTORY',
      'mode': 'RECOVER',
      'rss': 'false',
      'tsearch': 'true',
    });
    expect(find.text('수집 중'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    final reads = f.requests.length;
    await t.pump(const Duration(seconds: 10));
    expect(f.requests.length, reads);
    expect(t.takeException(), isNull);
  });
  testWidgets('초기화는 대상 건수와 정확한 확인 문구를 요구하며 취소는 삭제하지 않는다', (t) async {
    final f = await openAdmin(t);
    await tapVisible(t, find.text('복구 리포트·후기 초기화'));
    await tapVisible(t, find.text('후기 초기화'));
    expect(find.textContaining('velog 2건 · 티스토리 1건'), findsOneWidget);
    final execute = find.widgetWithText(FilledButton, '초기화 실행');
    expect(t.widget<FilledButton>(execute).onPressed, isNull);
    await t.enterText(find.byType(TextField), '초기회');
    await t.pump();
    expect(t.widget<FilledButton>(execute).onPressed, isNull);
    await t.tap(find.text('취소'));
    await t.pumpAndSettle();
    expect(f.requests.where((r) => r.method == 'POST'), isEmpty);
    await tapVisible(t, find.text('후기 초기화'));
    await t.enterText(find.byType(TextField), '초기화');
    await t.pump();
    await t.tap(execute);
    await t.pumpAndSettle();
    final writes = f.requests.where((r) => r.method == 'POST').toList();
    expect(writes, hasLength(1));
    expect(writes.single.url.path, '/admin/collect/reviews/reset');
    expect(writes.single.bodyFields, {'confirm': '초기화'});
    expect(find.text('초기화 결과'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('검색어 추가는 기존 폼 규격을 사용하고 삭제 취소는 요청하지 않는다', (t) async {
    final f = await openAdmin(t);
    await tapVisible(t, find.text('수집 범위'));
    await t.enterText(find.byType(TextField).at(0), '정처기 + 실기&합격');
    await tapVisible(t, find.text('검색어 추가'));
    final write = f.requests.singleWhere((r) => r.method == 'POST');
    expect(write.url.path, '/admin/collect/sources/velog-keyword');
    expect(write.bodyFields, {'keyword': '정처기 + 실기&합격'});
    await t.pageBack();
    await t.pumpAndSettle();
    await tapVisible(t, find.text('삭제'));
    await t.tap(find.text('취소'));
    await t.pumpAndSettle();
    expect(
      f.requests.where((r) => r.url.path == '/admin/collect/sources/remove'),
      isEmpty,
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('후기 페이지 이동과 상세 조회는 서버 페이지·기존 데이터를 사용한다', (t) async {
    final f = await openAdmin(t);
    await tapVisible(t, find.text('수집 데이터'));
    expect(find.text('전체 21건 · 1 / 2쪽'), findsOneWidget);
    await t.tap(find.text('다음'));
    await t.pumpAndSettle();
    expect(f.requests.last.url.queryParameters, {
      'source': 'ALL',
      'cert': 'ALL',
      'status': 'ALL',
      'q': '',
      'sort': 'id',
      'dir': 'desc',
      'size': '20',
      'page': '1',
    });
    expect(find.text('#21'), findsOneWidget);
    await tapVisible(t, find.text('상세 보기'));
    expect(find.text('SAMPLE 요약문'), findsOneWidget);
    expect(find.text('https://example.invalid/sample-review'), findsOneWidget);
    expect(f.requests.where((r) => r.method == 'POST'), isEmpty);
  });
  testWidgets('크롤링 중단은 취소 시 요청하지 않고 확인 후 기존 중단 API를 한 번 호출한다', (t) async {
    bool cancelled = false;
    final f = AdminFixture(
      override: (r) async {
        if (r.url.path == '/admin/collect/reviews/cancel') {
          cancelled = true;
          return adminResponse({...sampleJob, 'state': 'CANCELLED'});
        }
        if (r.url.path == '/admin/collect/reviews/status') {
          return adminResponse({
            ...sampleJob,
            'state': cancelled ? 'CANCELLED' : 'RUNNING',
            'processed': 2,
            'candidates': 100,
          });
        }
        return null;
      },
    );
    await openAdmin(t, fixture: f);
    await tapVisible(t, find.text('후기 수집'));
    await tapVisible(t, find.text('크롤링 중단'));
    await t.tap(find.text('취소'));
    await t.pumpAndSettle();
    expect(f.requests.where((r) => r.method == 'POST'), isEmpty);
    await tapVisible(t, find.text('크롤링 중단'));
    await t.tap(find.text('중단하기'));
    await t.pumpAndSettle();
    final write = f.requests.singleWhere((r) => r.method == 'POST');
    expect(write.url.path, '/admin/collect/reviews/cancel');
    expect(write.body, '');
    expect(find.text('관리자가 중단함'), findsOneWidget);
    final count = f.requests.length;
    await t.pump(const Duration(seconds: 4));
    expect(f.requests.length, count);
  });
  testWidgets('네이버 수집 시작·중단은 기존 상태 모양과 두 API를 사용한다', (t) async {
    String state = 'IDLE';
    final f = AdminFixture(
      override: (r) async {
        if (!r.url.path.startsWith('/admin/collect/naver/')) return null;
        if (r.url.path.endsWith('/start')) state = 'RUNNING';
        if (r.url.path.endsWith('/cancel')) state = 'CANCELLED';
        return adminResponse({
          'job': {...sampleJob, 'state': state, 'processed': 1},
          'keyReady': true,
          'usedToday': 1,
          'dailyLimit': 20000,
          'recentNews': [],
        });
      },
    );
    await openAdmin(t, fixture: f);
    await tapVisible(t, find.text('후기 수집'));
    await tapVisible(t, find.text('네이버 수집 시작'));
    await t.tap(find.text('시작하기'));
    await t.pumpAndSettle();
    await tapVisible(t, find.text('네이버 수집 중단'));
    await t.tap(find.text('중단하기'));
    await t.pumpAndSettle();
    final writes = f.requests.where((r) => r.method == 'POST').toList();
    expect(writes.map((r) => r.url.path).toList(), [
      '/admin/collect/naver/start',
      '/admin/collect/naver/cancel',
    ]);
    expect(writes.every((r) => r.body.isEmpty), true);
    expect(find.text('관리자가 중단함'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  for (final width in [320.0, 360.0, 412.0]) {
    for (final scale in [1.5, 2.0]) {
      testWidgets('관리 화면·수집 입력·조회 조건은 작은 화면과 큰 글자에서 넘치지 않는다 $width/$scale', (
        t,
      ) async {
        await openAdmin(t, width: width, scale: scale);
        expect(t.takeException(), isNull);
        for (final menu in ['후기 수집', '수집 범위', '수집 데이터']) {
          await tapVisible(t, find.text(menu));
          if (menu == '수집 데이터') await tapVisible(t, find.text('조회 조건'));
          await t.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -400),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          await t.pageBack();
          await t.pumpAndSettle();
        }
      });
    }
  }
}

Future<void> tapVisible(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  await t.tap(finder);
  await t.pumpAndSettle();
}

Future<void> choose(WidgetTester t, String label, String value) async {
  final field = find.byWidgetPredicate(
    (w) => w is AdminChoice && w.label == label,
  );
  await tapVisible(
    t,
    find.descendant(of: field, matching: find.byType(DropdownButton<String>)),
  );
  await t.tap(find.text(value).last);
  await t.pumpAndSettle();
}
