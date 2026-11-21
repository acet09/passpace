import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/models.dart';
import 'admin_api.dart';
import 'design.dart';

Json adminObject(Object? value) => object(value);
Json adminOptional(Object? value) => value is Json ? value : {};
int adminNumber(Object? value) => value is num ? value.toInt() : 0;
String adminText(Object? value) =>
    value == null || value == '' ? '—' : '$value';
const adminSources = {
  'ALL': '전체 출처',
  'VELOG': 'velog',
  'TISTORY': '티스토리',
  'NAVER_BLOG': '네이버 블로그',
  'NAVER_CAFE': '네이버 카페',
  'DUMMY': '더미',
  'OTHER': '기타',
};
const adminCertificates = {
  'ALL': '전체 자격증',
  '1320': '정보처리기사',
  'SQLD': 'SQLD',
  'CA1': '컴활 1급',
  'ADSP': 'ADsP',
};
const adminStatuses = {
  'ALL': '전체 상태',
  'VALID': '검증됨 · VALID',
  'PENDING': '검토 대기 · PENDING',
  'EXCLUDED': '제외됨 · EXCLUDED',
};
const adminStates = {
  'IDLE': '대기 중',
  'RUNNING': '수집 중',
  'DONE': '수집 완료',
  'STOPPED': '접근 거부·오류로 중단',
  'CANCELLED': '관리자가 중단함',
};

class AdminSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const AdminSection(this.title, this.children, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    ),
  );
}

class AdminChoice extends StatelessWidget {
  final String label, value;
  final Map<String, String> options;
  final ValueChanged<String>? onChanged;
  const AdminChoice(
    this.label,
    this.value,
    this.options,
    this.onChanged, {
    super.key,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      isDense: false,
      itemHeight: null,
      decoration: InputDecoration(labelText: label),
      selectedItemBuilder: (context) => options.values
          .map(
            (text) => Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      items: options.entries
          .map(
            (e) => DropdownMenuItem(
              value: e.key,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  e.value,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: onChanged == null
          ? null
          : (v) {
              if (v != null) onChanged!(v);
            },
    ),
  );
}

class AdminLoading extends StatelessWidget {
  const AdminLoading({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(28),
    child: Center(
      child: CircularProgressIndicator(semanticsLabel: '관리자 정보 불러오는 중'),
    ),
  );
}

class AdminFailure extends StatelessWidget {
  final Object error;
  final VoidCallback? retry;
  const AdminFailure(this.error, {this.retry, super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AlertText(friendly(error)),
      if (retry != null)
        OutlinedButton.icon(
          onPressed: retry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('다시 불러오기'),
        ),
    ],
  );
}

Future<bool> adminConfirm(
  BuildContext context,
  String title,
  String message, {
  String action = '실행',
  bool danger = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: Text(message, style: const TextStyle(height: 1.6)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(c).colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.pop(c, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

const _fieldLabels = <String, String>{
  'status': '상태',
  'mode': '실행 방식',
  'message': '안내',
  'target': '목표 건수',
  'success': '성공',
  'failed': '실패',
  'skipped': '건너뜀',
  'saved': '저장',
  'updated': '변경',
  'unchanged': '변경 없음',
  'unregistered': '미등록 자격증',
  'rounds': '확인한 시험일정',
  'connected': 'DB 연결',
  'database': '데이터베이스',
  'version': '서버 버전',
  'elapsedMs': '조회 시간(ms)',
  'tableCount': '테이블 수',
  'tables': '테이블별 행 수',
  'table': '테이블',
  'rows': '행 수',
  'emptyTables': '빈 테이블',
  'error': '오류 안내',
  'key': '구분',
  'count': '건수',
  'bySource': '출처별 건수',
  'byCert': '자격증별 건수',
  'lastCollectedAt': '마지막 수집 시각',
  'reviewId': '후기 번호',
  'source': '출처',
  'certName': '자격증',
  'certificateCode': '자격증 코드',
  'examType': '시험 종류',
  'reviewStatus': '검증 상태',
  'excludeReason': '제외 이유',
  'passYn': '합격 여부',
  'majorType': '전공 여부',
  'prepDays': '준비 기간(일)',
  'dailyMinutes': '후기 하루 학습량(분)',
  'totalHours': '후기 총 학습량(시간)',
  'studySubjects': '학습 과목',
  'studyMethod': '학습 방법',
  'evidenceText': '근거 요약',
  'postedAt': '작성일',
  'sourceUrl': '원문 주소',
  'collectedAt': '수집 시각',
  'url': '주소',
  'site': '사이트',
  'verdict': '검사 결과',
  'authorHashed': '작성자 해시 처리',
  'review': '추출한 후기',
  'quality': '품질 검사',
  'reviewSummary': '후기 요약',
  'candidates': '후기 후보',
  'messages': '탐색 안내',
  'label': '제목',
  'listedDate': '목록 작성일',
  'alreadySaved': '저장 여부',
  'linkCount': '발견한 주소 수',
  'invalid': '추가하지 못한 값',
  'addedListings': '추가한 목록',
  'addedSeeds': '추가한 글 주소',
  'duplicates': '중복',
  'removed': '삭제 여부',
  'executed': '초기화 실행 여부',
  'velog': 'velog 후기',
  'tistory': '티스토리 후기',
  'report': '복구 리포트',
  'snapshotAt': '복구 기준 시각',
  'before': '초기화 전 후기',
  'beforeValid': '초기화 전 검증된 후기',
  'restored': '복구한 후기',
  'restoredValid': '복구한 검증 후기',
  'restoreRate': '복구율(%)',
  'validRestoreRate': '검증 후기 복구율(%)',
  'sameValues': '동일한 값',
  'sameValueRate': '값 일치율(%)',
  'bySite': '사이트별 결과',
  'missing': '미복구 주소',
  'ledgerUrls': '수집 이력 건수',
  'ledgerEverSaved': '저장한 이력 건수',
  'title': '제목',
  'link': '주소',
  'date': '날짜',
  'sampleCount': '표본 수',
  'certificateId': '자격증 번호',
  'examCategory': '시험 구분',
  'referenceHours': '참고 학습시간',
};
String _displayValue(Object? v) {
  if (v == true) return '예';
  if (v == false) return '아니요';
  const labels = {
    'SAMPLE': 'SAMPLE · 샘플 자료',
    'RULE_BASED': 'RULE_BASED · 규칙 기반',
    'WRITTEN': '필기',
    'PRACTICAL': '실기',
    'MAJOR': '전공',
    'RELATED': '유사전공',
    'NON_MAJOR': '비전공',
    'Y': '합격',
    'N': '불합격',
    'SAVE_VALID': '검증 후기 저장 대상',
    'SAVE_PENDING': '검토 대기 저장 대상',
    'SAVE_EXCLUDED': '제외 후기 저장 대상',
    'SKIP': '저장 대상 아님',
  };
  return labels[v] ?? adminStatuses[v] ?? adminSources[v] ?? adminText(v);
}

class AdminValueTree extends StatelessWidget {
  final Object? value;
  const AdminValueTree(this.value, {super.key});
  @override
  Widget build(BuildContext context) {
    if (value is Map) {
      final entries = (value as Map).entries.where(
        (e) => !{'listingFile', 'seedFile', 'ledgerFile'}.contains(e.key),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: entries.map((e) {
          final label =
              _fieldLabels[e.key] ??
              adminCertificates[e.key] ??
              adminSources[e.key] ??
              '${e.key}';
          if (e.value is Map || e.value is List) {
            return ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 12),
                  child: AdminValueTree(e.value),
                ),
              ],
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: muted, fontSize: 12)),
                const SizedBox(height: 4),
                SelectableText(
                  _displayValue(e.value),
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
              ],
            ),
          );
        }).toList(),
      );
    }
    if (value is List) {
      final list = value as List;
      if (list.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: Text('표시할 항목이 없습니다.', style: TextStyle(color: muted)),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: list
            .map(
              (v) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AdminValueTree(v),
              ),
            )
            .toList(),
      );
    }
    return SelectableText(
      _displayValue(value),
      style: const TextStyle(height: 1.6),
    );
  }
}

class AdminDocumentScreen extends StatelessWidget {
  final String title;
  final Object? value;
  const AdminDocumentScreen(this.title, this.value, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(child: ScrollBody(children: [AdminValueTree(value)])),
  );
}

Future<void> showAdminDocument(
  BuildContext context,
  String title,
  Object? value, {
  required AdminApi api,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) =>
        AdminAccessGate(api, child: AdminDocumentScreen(title, value)),
  ),
);

/// Covers every admin route, including detail pages, when access is invalidated.
class AdminAccessGate extends StatefulWidget {
  final AdminApi api;
  final Widget child;
  final bool ownsApi;
  const AdminAccessGate(
    this.api, {
    required this.child,
    this.ownsApi = false,
    super.key,
  });
  @override
  State<AdminAccessGate> createState() => _AdminAccessGateState();
}

class _AdminAccessGateState extends State<AdminAccessGate> {
  @override
  void dispose() {
    if (widget.ownsApi) widget.api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.api, widget.api.session]),
    builder: (context, _) => widget.api.accessible
        ? widget.child
        : Scaffold(
            appBar: AppBar(title: const Text('관리자 접근 확인')),
            body: const SafeArea(
              child: ScrollBody(
                children: [
                  AlertText('관리자 권한이 없거나 로그인이 만료되었어요. 뒤로 돌아가 로그인 정보를 확인해 주세요.'),
                ],
              ),
            ),
          ),
  );
}
