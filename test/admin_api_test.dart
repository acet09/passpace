import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/ui/admin_api.dart';

import 'support/admin_fixture.dart';

void main() {
  test('병렬 조회 중 권한 거부를 받은 뒤 도착한 데이터도 반환하지 않는다', () async {
    final db = Completer<http.Response>(), summary = Completer<http.Response>();
    final f = AdminFixture(
      override: (r) async {
        if (r.url.path == '/admin/collect/db-status') return db.future;
        if (r.url.path == '/admin/collect/data/summary') return summary.future;
        return null;
      },
    );
    addTearDown(f.dispose);
    await f.restore();
    final api = AdminApi(f.session);
    final denied = expectLater(api.get('/db-status'), throwsA(isA<ApiError>()));
    final late = expectLater(
      api.get('/data/summary'),
      throwsA(isA<ApiError>()),
    );
    db.complete(adminResponse({}, 403));
    await denied;
    summary.complete(adminResponse({'total': 21}));
    await late;
  });
  test('관리자 폼은 UTF-8으로 기존 서버에 보내며 배열·숫자 응답도 읽는다', () async {
    final f = AdminFixture(
      override: (r) async =>
          r.url.path == '/admin/collect/sources/velog-keyword'
          ? adminResponse(1)
          : null,
    );
    addTearDown(f.dispose);
    await f.restore();
    final api = AdminApi(f.session);
    expect(
      await api.post('/sources/velog-keyword', {'keyword': '정처기 + 실기&합격'}),
      1,
    );
    final r = f.requests.last;
    expect(r.method, 'POST');
    expect(
      r.url.toString(),
      '$emulatorOrigin/admin/collect/sources/velog-keyword',
    );
    expect(r.bodyFields, {'keyword': '정처기 + 실기&합격'});
    expect(
      r.headers['content-type'],
      contains('application/x-www-form-urlencoded'),
    );
    expect(r.followRedirects, false);
    expect(await api.post('/reference-stats'), isA<List>());
    expect(await api.post('/reviews/subject-backfill'), isA<Map>());
    expect(
      f.requests.last.url.path,
      '/admin/collect/reviews/subject-backfill',
    );
  });
  test('리다이렉트는 따르지 않고 토큰을 외부 주소로 전달하지 않는다', () async {
    final f = AdminFixture(
      override: (r) async => r.url.path.startsWith('/admin/')
          ? http.Response(
              '',
              302,
              headers: {'location': 'https://example.invalid/elsewhere'},
            )
          : null,
    );
    addTearDown(f.dispose);
    await f.restore();
    await expectLater(
      AdminApi(f.session).get('/db-status'),
      throwsA(isA<ApiError>()),
    );
    expect(
      f.requests.where((r) => r.url.path.startsWith('/admin/')),
      hasLength(1),
    );
    expect(f.requests.every((r) => r.url.host == '10.0.2.2'), true);
  });
  test('403 뒤 추가 관리자 요청을 막으며 일반 로그인은 유지한다', () async {
    final f = AdminFixture(
      override: (r) async =>
          r.url.path.startsWith('/admin/') ? adminResponse({}, 403) : null,
    );
    addTearDown(f.dispose);
    await f.restore();
    final api = AdminApi(f.session);
    await expectLater(
      api.get('/db-status'),
      throwsA(isA<ApiError>().having((e) => e.status, 'status', 403)),
    );
    await expectLater(api.post('/exam'), throwsA(isA<ApiError>()));
    expect(
      f.requests.where((r) => r.url.path.startsWith('/admin/')),
      hasLength(1),
    );
    expect(f.session.user?.id, 'SAMPLE');
  });
  test('401은 기존 세션 만료 처리를 호출하고 다음 요청을 차단한다', () async {
    final f = AdminFixture(
      override: (r) async =>
          r.url.path.startsWith('/admin/') ? adminResponse({}, 401) : null,
    );
    addTearDown(f.dispose);
    await f.restore();
    final api = AdminApi(f.session);
    await expectLater(
      api.get('/db-status'),
      throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)),
    );
    expect(f.session.user, isNull);
    expect(f.session.account, isNull);
    await expectLater(api.get('/reviews/status'), throwsA(isA<ApiError>()));
    expect(
      f.requests.where((r) => r.url.path.startsWith('/admin/')),
      hasLength(1),
    );
  });
  test('응답 대기 중 로그아웃하면 이전 관리자 데이터는 반환하지 않는다', () async {
    final pending = Completer<http.Response>();
    final f = AdminFixture(
      override: (r) async => r.url.path == '/admin/collect/db-status'
          ? await pending.future
          : null,
    );
    addTearDown(f.dispose);
    await f.restore();
    final result = AdminApi(f.session).get('/db-status');
    final assertion = expectLater(result, throwsA(isA<ApiError>()));
    await f.session.logout();
    pending.complete(adminResponse({'connected': true}));
    await assertion;
  });
  test('일반 회원·절대 주소·관리자 외 경로는 요청 전에 차단한다', () async {
    final f = AdminFixture(role: 'USER');
    addTearDown(f.dispose);
    await f.restore();
    final api = AdminApi(f.session);
    await expectLater(api.get('/db-status'), throwsA(isA<ApiError>()));
    await expectLater(
      api.get('https://example.invalid/admin/collect/db-status'),
      throwsA(isA<ApiError>()),
    );
    expect(f.requests.where((r) => r.url.path.startsWith('/admin/')), isEmpty);
  });
  test('HTML·망가진 JSON·연결 실패는 안내 가능한 오류로 처리한다', () async {
    for (final branch in ['html', 'json', 'network']) {
      final f = AdminFixture(
        override: (r) async {
          if (!r.url.path.startsWith('/admin/')) return null;
          if (branch == 'network') throw http.ClientException('SAMPLE');
          return http.Response(
            branch == 'html' ? '<html>SAMPLE</html>' : '{',
            200,
          );
        },
      );
      addTearDown(f.dispose);
      await f.restore();
      await expectLater(
        AdminApi(f.session).get('/db-status'),
        throwsA(isA<ApiError>()),
      );
    }
  });
}
