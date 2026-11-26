import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:passpace_mobile/data/api.dart';

import 'support/study_fixture.dart';

void main() {
  test('탈퇴는 Bearer DELETE로 입력 원문과 영구 삭제 동의 3개 필드만 한 번 보낸다', () async {
    var calls = 0;
    Map<String, dynamic>? sentBody;
    final client = MockClient((request) async {
      calls++;
      expect(request.method, 'DELETE');
      expect(request.url.toString(), '$emulatorOrigin/users/me');
      expect(request.followRedirects, isFalse);
      expect(request.headers['Authorization'], 'Bearer SAMPLE');
      expect(request.headers['Content-Type'], contains('application/json'));
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return studyEnvelope({'withdrawn': true, 'personalDataDeleted': true});
    });
    addTearDown(client.close);
    await PassApi(
      client,
      emulatorOrigin,
      token: 'SAMPLE',
    ).withdrawAccount(' SAMPLE password ', 'SAMPLE_ID회원탈퇴');
    expect(calls, 1);
    expect(sentBody!.keys.toSet(), {
      'password',
      'confirmation',
      'deletePersonalData',
    });
    expect(sentBody!['password'], ' SAMPLE password ');
    expect(sentBody!['confirmation'], 'SAMPLE_ID회원탈퇴');
    expect(sentBody!['deletePersonalData'], isTrue);
  });

  test('이전 서버의 정확한 미지원 응답은 회원탈퇴 서버 연결을 안내한다', () async {
    final client = MockClient(
      (_) async => studyEnvelope({'code': 'METHOD_NOT_ALLOWED'}, 405),
    );
    addTearDown(client.close);
    final api = PassApi(client, emulatorOrigin, token: 'SAMPLE');
    await expectLater(
      api.withdrawAccount('SAMPLE password', 'SAMPLE_ID회원탈퇴'),
      throwsA(
        isA<ApiError>()
            .having((e) => e.status, 'status', 405)
            .having((e) => e.message, 'message', contains('1122jhg 서버')),
      ),
    );
  });

  for (final status in [400, 401, 403, 409]) {
    test('탈퇴 JSON $status는 거부로 처리하고 민감한 응답 상세를 표시하지 않는다', () async {
      var expired = 0;
      final client = MockClient(
        (_) async => studyEnvelope({
          'detail': 'SAMPLE_secret_password SAMPLE_ID회원탈퇴',
        }, status),
      );
      addTearDown(client.close);
      final api = PassApi(
        client,
        emulatorOrigin,
        token: 'SAMPLE',
        onExpired: () => expired++,
      );
      await expectLater(
        api.withdrawAccount('SAMPLE_secret_password', 'SAMPLE_ID회원탈퇴'),
        throwsA(
          isA<ApiError>()
              .having((e) => e.status, 'status', status)
              .having(
                (e) => e.message,
                'password',
                isNot(contains('SAMPLE_secret_password')),
              )
              .having(
                (e) => e.message,
                'confirmation',
                isNot(contains('(SAMPLE_ID)')),
              ),
        ),
      );
      expect(expired, status == 401 ? 1 : 0);
    });
  }

  for (final failure in [
    'connection',
    'unexpected-stream',
    'timeout',
    'io',
    'html',
    'html400',
    'missing',
    'false',
    'string',
    'personal-data-missing',
    'personal-data-false',
    'personal-data-string',
    'personal-data-number',
    'personal-data-null',
    'list',
    '201',
    'wrong-code',
    '500',
    '503',
    'redirect',
  ]) {
    test('탈퇴 $failure 응답은 불확실하며 자동 재전송하지 않는다', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        switch (failure) {
          case 'connection':
            throw http.ClientException('SAMPLE lost');
          case 'unexpected-stream':
            throw StateError('SAMPLE response stream lost');
          case 'timeout':
            throw TimeoutException('SAMPLE lost');
          case 'io':
            throw const SocketException('SAMPLE lost');
          case 'html':
            return http.Response('<html>SAMPLE</html>', 200);
          case 'html400':
            return http.Response('<html>SAMPLE</html>', 400);
          case 'missing':
            return studyEnvelope({'personalDataDeleted': true});
          case 'false':
            return studyEnvelope({
              'withdrawn': false,
              'personalDataDeleted': true,
            });
          case 'string':
            return studyEnvelope({
              'withdrawn': 'true',
              'personalDataDeleted': true,
            });
          case 'personal-data-missing':
            return studyEnvelope({'withdrawn': true});
          case 'personal-data-false':
            return studyEnvelope({
              'withdrawn': true,
              'personalDataDeleted': false,
            });
          case 'personal-data-string':
            return studyEnvelope({
              'withdrawn': true,
              'personalDataDeleted': 'true',
            });
          case 'personal-data-number':
            return studyEnvelope({'withdrawn': true, 'personalDataDeleted': 1});
          case 'personal-data-null':
            return studyEnvelope({
              'withdrawn': true,
              'personalDataDeleted': null,
            });
          case 'list':
            return studyEnvelope([]);
          case '201':
            return studyEnvelope({
              'withdrawn': true,
              'personalDataDeleted': true,
            }, 201);
          case 'wrong-code':
            return http.Response(
              jsonEncode({
                'status': 'SUCCESS',
                'code': 201,
                'data': {'withdrawn': true, 'personalDataDeleted': true},
              }),
              200,
            );
          case '500':
            return studyEnvelope({'ko': 'SAMPLE'}, 500);
          case '503':
            return studyEnvelope({'ko': 'SAMPLE'}, 503);
          default:
            return http.Response('', 302);
        }
      });
      addTearDown(client.close);
      await expectLater(
        PassApi(
          client,
          emulatorOrigin,
          token: 'SAMPLE',
        ).withdrawAccount('SAMPLE_password', 'SAMPLE_ID회원탈퇴'),
        throwsA(isA<AccountWithdrawalUncertain>()),
      );
      expect(calls, 1);
    });
  }
}
