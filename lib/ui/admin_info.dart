import 'package:flutter/material.dart';

import 'design.dart';

/// [용성·11-21] 관리자 "수집자료정보" 설명 페이지.
/// 각 수집 영역 제목 옆의 "수집자료정보"를 누르면 그 영역의 자료 설명으로 이동한다.
/// 서버를 부르지 않는 읽기 전용 화면이다 (내용은 서버 수집 코드 기준으로 작성).
class AdminInfoTopic {
  final String title;
  final String source;
  final String summary;
  final List<(String, String)> items;
  final String storedIn;
  final String? note;
  const AdminInfoTopic({
    required this.title,
    required this.source,
    required this.summary,
    required this.items,
    required this.storedIn,
    this.note,
  });
}

const adminInfoTopics = <String, AdminInfoTopic>{
  'crawl': AdminInfoTopic(
    title: 'velog·티스토리 크롤링',
    source: 'velog·티스토리 합격 후기 글 본문',
    summary: '후기 글을 읽어 학습시간 통계에 쓰는 값을 뽑아요. 본문 원문은 저장하지 않아요.',
    items: [
      ('자격증 · 시험 구분', '정보처리기사 · SQLD · 컴활 1급 · ADsP / 필기 · 실기'),
      ('합격 여부', '합격 후기만 통계에 써요'),
      ('총 공부시간', '"총 30시간", "합계 23시간 56분", 날짜별 일지 합산'),
      ('준비 일수 · 하루 공부시간', '총 시간이 없으면 일수 × 하루 시간으로 계산해요'),
      ('전공 여부', '전공 · 관련 · 비전공'),
      ('공부 과목 · 공부 방법', '언급된 과목 이름, 독학 · 강의 등'),
      ('과목별 언급', '과목별 시간 · 비율 · 어려움 · 쉬움 (과목 언급 테이블에 따로 저장)'),
      ('작성일 · 작성자', '작성자는 익명 처리한 값(해시)만 저장해요'),
      ('근거 요약문 · 검증 상태', '뽑은 값으로 만든 요약문, VALID · PENDING · EXCLUDED'),
    ],
    storedIn: 'PASS_REVIEWS, REVIEW_SUBJECT_MENTIONS',
  ),
  'naver': AdminInfoTopic(
    title: '네이버 검색 API',
    source: '네이버 블로그 · 카페 · 뉴스 검색 결과',
    summary: '검색 API가 주는 제목과 요약문만 받아요. 본문이 없어서 통계에는 쓰지 않아요.',
    items: [
      ('블로그 · 카페 후기', '제목, 요약문, 주소, 작성일(블로그만), 블로거 아이디(익명 처리)'),
      ('검증 상태', '요약문뿐이라 모두 검토 대기(PENDING) 또는 제외(EXCLUDED)로 저장해요. 상태는 바꾸지 않아요'),
      ('통계 사용 조건', '합격 · 시험 구분 · 공부시간 계산 가능 · 최근 3년(오래된 시험 연도 언급 제외) · 준비 90일 이하 · 하루 3시간 이하 · 작성자당 1건 · 박스플롯 이상치 제외'),
      ('통계 사용 방식', '크롤링 후기가 10건 미만인 그룹에만 보충해요. 그래도 부족할 때만 하루시간 추정값을 써요'),
      ('뉴스', '최신 뉴스 제목과 링크. 화면 참고용이며 DB에는 저장하지 않아요'),
    ],
    storedIn: 'PASS_REVIEWS (뉴스는 저장 안 함)',
    note: '조건을 통과한 네이버 후기는 크롤링 표본이 부족할 때만 참고 학습시간에 보충돼요. 재집계 결과 표에 네이버 단독 중앙값도 비교용으로 보여요.',
  ),
  'schedule': AdminInfoTopic(
    title: '시험일정 가져오기',
    source: '공공데이터 API · dataq 페이지',
    summary: '자격증별 시험 회차와 날짜를 가져와요. 날짜가 바뀌면 변경 이력을 남겨요.',
    items: [
      ('정보처리기사', '공공데이터포털 (한국산업인력공단 시험일정 API): 회차, 접수 기간, 시험일, 합격 발표일'),
      ('SQLD · ADsP', '공공데이터포털 (한국데이터산업진흥원 데이터 자격검정 시험 정보): 회차, 시험일, 접수 시작 · 마감일, 합격 발표일 (최근 2년, 일반검정)'),
      ('dataq 수동 수집', '공공 API가 안 될 때 dataq 페이지에서 같은 일정을 보조로 가져와요'),
      ('컴활 1급', '상시시험이라 정해진 시험일이 없어 가져오지 않아요'),
    ],
    storedIn: 'EXAM_ROUNDS, EXAM_SCHEDULE_CHANGE_LOGS',
  ),
  'reference': AdminInfoTopic(
    title: '후기 기반 참고시간',
    source: '수집된 합격 후기 (VALID)',
    summary: '합격 후기로 자격증별 총 공부시간을 계산해요. 학습계획(플래너)의 기준값이에요.',
    items: [
      ('쓰는 자료', '합격 · VALID 후기, 작성자당 1건, 최근 3년'),
      ('만드는 값', '자격증 · 시험 · 전공별 총 공부시간 중앙값, 표본 수, 최소 · 최대'),
      ('실측 기준', '후기 10건 이상이면 실측값(VERIFIED)으로 저장해요'),
      ('표본 순서', '크롤링 실측 → 부족하면 네이버 요약 후기 보충 → 그래도 부족하면 하루시간 추정값'),
      ('네이버 비교', '그룹마다 네이버 단독 중앙값을 함께 계산해 결과 표에 보여 줘요'),
      ('그룹', '같은 전공 / 전공 구분 없는 전체 (실기가 없는 SQLD · ADsP는 필기만)'),
      ('쓰이는 곳', '플래너가 총 공부시간 × 과목 비율로 과목별 시간을 만들어요'),
    ],
    storedIn: 'STUDY_REFERENCE_STATS',
    note: '후기를 새로 수집한 뒤 재집계해야 새 후기가 계획에 반영돼요.',
  ),
  'subject': AdminInfoTopic(
    title: '과목 언급 채우기',
    source: '이미 저장한 velog · 티스토리 후기 본문 (다시 읽기)',
    summary: '후기에서 과목별 언급을 모아요. 과목별 학습량의 재료이며, 아직 계산에는 쓰지 않아요.',
    items: [
      ('과목별 시간', '"DB 4시간", 날짜별 일지 합산'),
      ('과목별 비율', '"SQL에 60%"'),
      ('건너뜀', '"과목 하나는 안 봄" (0시간)'),
      ('난이도', '어려움 · 쉬움 언급'),
      ('근거 요약문', '뽑은 값으로 만든 요약문 (원문 아님)'),
    ],
    storedIn: 'REVIEW_SUBJECT_MENTIONS',
    note: '새로 수집하는 후기는 수집할 때 자동으로 채워져요. 과목별 10건 이상 쌓이면 과목별 실측 평균에 쓸 예정이에요.',
  ),
};

/// 제목 옆에 붙는 "수집자료정보" 글자 링크
class AdminInfoLink extends StatelessWidget {
  final String topic;
  const AdminInfoLink(this.topic, {super.key});
  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      minimumSize: const Size(48, 36),
      foregroundColor: blue,
    ),
    onPressed: () => Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => AdminInfoScreen(topic)),
    ),
    child: const Text(
      '수집자료정보',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        decoration: TextDecoration.underline,
      ),
    ),
  );
}

class AdminInfoScreen extends StatelessWidget {
  final String topic;
  const AdminInfoScreen(this.topic, {super.key});
  @override
  Widget build(BuildContext context) {
    final t = adminInfoTopics[topic];
    return Scaffold(
      appBar: AppBar(title: const Text('수집자료정보')),
      body: SafeArea(
        child: t == null
            ? const Center(child: Text('설명이 없는 항목이에요.'))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  Text(
                    t.title,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: ink),
                  ),
                  const SizedBox(height: 8),
                  Text(t.summary, style: const TextStyle(height: 1.6, color: ink)),
                  const SizedBox(height: 16),
                  _row('가져오는 곳', t.source),
                  _row('저장 위치', t.storedIn),
                  const SizedBox(height: 16),
                  const Text(
                    '수집 · 생성 자료',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ink),
                  ),
                  const SizedBox(height: 8),
                  for (final (label, desc) in t.items)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: paper,
                        border: Border.all(color: line),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: ink)),
                          const SizedBox(height: 4),
                          Text(desc, style: const TextStyle(color: muted, height: 1.5)),
                        ],
                      ),
                    ),
                  if (t.note != null) ...[
                    const SizedBox(height: 8),
                    Text(t.note!, style: const TextStyle(color: amber, height: 1.6)),
                  ],
                ],
              ),
      ),
    );
  }

  static Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(label, style: const TextStyle(color: muted, fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Text(value, style: const TextStyle(color: ink, height: 1.5))),
      ],
    ),
  );
}
