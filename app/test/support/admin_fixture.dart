import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/session.dart';

import 'draft_storage.dart';

String adminSampleToken([String role = 'ADMIN']) {
  String part(Object v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'loginId': 'SAMPLE', 'role': role, 'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000})}.SAMPLE';
}

http.Response adminResponse(Object? data, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'status': status == 200 ? 'SUCCESS' : 'FAIL',
          'code': status,
          'data': data,
        }),
      ),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

class AdminMemoryStore implements SessionStore {
  String value;
  AdminMemoryStore(String role)
    : value = jsonEncode({
        'origin': emulatorOrigin,
        'token': adminSampleToken(role),
      });
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    value = next;
  }
}

const sampleJob = <String, dynamic>{
  'state': 'IDLE',
  'mode': 'NEW',
  'target': 100,
  'processed': 0,
  'saved': 0,
  'valid': 0,
  'failed': 0,
  'skipped': 0,
  'oldSkipped': 0,
  'retryable': 0,
  'elapsedSeconds': 0,
  'candidates': 0,
  'message': 'SAMPLE 수집 대기 중',
};
const sampleReview = <String, dynamic>{
  'reviewId': 1,
  'source': 'VELOG',
  'certName': '정보처리기사',
  'examType': 'WRITTEN',
  'reviewStatus': 'VALID',
  'passYn': 'Y',
  'majorType': 'NON_MAJOR',
  'prepDays': 30,
  'dailyMinutes': 90,
  'totalHours': 45,
  'studySubjects': '소프트웨어 설계',
  'studyMethod': 'SAMPLE 기출 학습',
  'evidenceText': 'SAMPLE 요약문',
  'postedAt': '2026-11-01',
  'sourceUrl': 'https://example.invalid/sample-review',
  'collectedAt': '2026-11-15T10:00:00',
};

class AdminFixture {
  final requests = <http.Request>[];
  final Future<http.Response?> Function(http.Request)? override;
  late final http.Client client;
  late final Session session;
  AdminFixture({this.override, String role = 'ADMIN'}) {
    client = MockClient((r) async {
      requests.add(r);
      final custom = await override?.call(r);
      if (custom != null) return custom;
      final path = r.url.path;
      if (path == '/auth/user-info') {
        return adminResponse({
          'loginId': 'SAMPLE',
          'nickname': 'SAMPLE 관리자',
          'email': 'sample@example.invalid',
          'majorType': 'RELATED',
          'majorTypeLabel': '유사전공',
        });
      }
      if (path == '/users/me/goal') {
        return adminResponse({'goal': {}, 'subjects': [], 'examRounds': []});
      }
      if (path == '$plannerPath/saved') return adminResponse({'plan': null});
      if (path == '/admin/collect/db-status') {
        return adminResponse({
          'connected': true,
          'database': 'SAMPLE',
          'version': 'SAMPLE',
          'elapsedMs': 2,
          'tableCount': 1,
          'tables': [
            {'table': 'PASS_REVIEWS', 'rows': 21},
          ],
          'emptyTables': [],
        });
      }
      if (path == '/admin/collect/data/summary') {
        return adminResponse({
          'total': 21,
          'bySource': [
            {'key': 'VELOG', 'status': 'VALID', 'count': 21},
          ],
          'byCert': [
            {'key': '정보처리기사', 'status': 'VALID', 'count': 21},
          ],
          'lastCollectedAt': '2026-11-15T10:00:00',
        });
      }
      if (path == '/admin/collect/data/reviews') {
        final page = int.parse(r.url.queryParameters['page'] ?? '0');
        return adminResponse({
          'total': 21,
          'page': page,
          'size': 20,
          'rows': [
            {...sampleReview, 'reviewId': page == 0 ? 1 : 21},
          ],
        });
      }
      if (path == '/admin/collect/reviews/status' ||
          path == '/admin/collect/reviews/cancel') {
        return adminResponse(sampleJob);
      }
      if (path == '/admin/collect/reviews/start') {
        return adminResponse({
          ...sampleJob,
          'state': 'RUNNING',
          'processed': 2,
          'candidates': 100,
        });
      }
      if (path.startsWith('/admin/collect/naver/')) {
        return adminResponse({
          'job': sampleJob,
          'keyReady': false,
          'usedToday': 0,
          'dailyLimit': 20000,
          'recentNews': [],
        });
      }
      if (path == '/admin/collect/status/by-cert') {
        return adminResponse({
          'crawl': {'byCert': {}},
          'naver': {'byCert': {}},
        });
      }
      if (path == '/admin/collect/sources') {
        return adminResponse({
          'listings': ['https://velog.io/search?q=SAMPLE'],
          'seeds': [],
          'tistoryKeywords': [],
          'naverKeywords': [],
          'seedCount': 0,
        });
      }
      if (path == '/admin/collect/reviews/recovery-report') {
        return adminResponse({
          'report': {'snapshotAt': null, 'message': 'SAMPLE 복구 기준 없음'},
          'ledgerUrls': 0,
          'ledgerEverSaved': 0,
        });
      }
      if (path == '/admin/collect/reviews/reset') {
        return adminResponse({
          'executed': r.method == 'POST',
          'velog': 2,
          'tistory': 1,
          'message': 'SAMPLE 초기화 결과',
        });
      }
      if (path == '/admin/collect/sources/remove') {
        return adminResponse({'removed': true});
      }
      if (path.startsWith('/admin/collect/sources/')) {
        return adminResponse({
          'addedListings': 1,
          'addedSeeds': 0,
          'duplicates': 0,
          'invalid': [],
          'message': 'SAMPLE 추가 완료',
        });
      }
      if (path == '/admin/collect/reviews/preview') {
        return adminResponse({
          'verdict': 'SAVE_VALID',
          'message': 'SAMPLE 저장 없는 미리보기',
          'review': {'totalHours': 45},
        });
      }
      if (path == '/admin/collect/reference-stats') {
        return adminResponse([
          {'certificate': 'SAMPLE', 'count': 10},
        ]);
      }
      if (path == '/admin/collect/reviews/discover') {
        return adminResponse({
          'messages': ['SAMPLE 후보 없음'],
          'candidates': [],
        });
      }
      if (path.startsWith('/admin/collect/')) {
        return adminResponse({
          'mode': 'SAMPLE',
          'status': 'SUCCESS',
          'message': 'SAMPLE 수집 결과',
        });
      }
      throw StateError('Unexpected ${r.method} ${r.url.path}');
    });
    session = Session(
      AdminMemoryStore(role),
      client,
      drafts: MemoryDraftStorage(),
    );
  }
  Future<void> restore() => session.restore();
  void dispose() {
    session.dispose();
    client.close();
  }
}
