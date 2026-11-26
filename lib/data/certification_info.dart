// [11-26] 지원 자격증 정보 메뉴 모델 (GET /api/certifications, /api/certifications/{id}).
// 서버는 값이 없으면 null 을 보낸다. 화면은 null 항목을 숨기거나 "공식 사이트에서 확인" 으로 보여 준다.
import 'models.dart';

String? _s(Object? v) {
  final t = v as String?;
  return t == null || t.trim().isEmpty ? null : t;
}

int? _i(Object? v) => (v as num?)?.toInt();
DateTime? _d(Object? v) => DateTime.tryParse(v as String? ?? '');

class CertNextEvent {
  final String kind, label;
  final DateTime? date;
  final int dDay;
  final bool projected;
  CertNextEvent.from(Json j)
    : kind = j['kind'] as String? ?? '',
      label = j['label'] as String? ?? '',
      date = _d(j['date']),
      dDay = _i(j['dDay']) ?? 0,
      projected = j['projected'] == true;

  /// "D-3", 오늘이면 "D-day"
  String get dDayText => dDay == 0 ? 'D-day' : 'D-$dDay';

  /// 접수 마감·접수 시작이 일주일 안이면 강조
  bool get urgent => (kind == 'REG_OPEN' || kind == 'REG_START') && dDay <= 7;
}

class CertSummary {
  final int id;
  final String name;
  final String? certType, grade, category, issuingOrg, summary;
  final List<String> examTypes;
  final bool alwaysOpen;
  final CertNextEvent? next;
  CertSummary.from(Json j)
    : id = _i(j['certificationId'])!,
      name = j['name'] as String,
      certType = _s(j['certType']),
      grade = _s(j['grade']),
      category = _s(j['category']),
      issuingOrg = _s(j['issuingOrg']),
      summary = _s(j['summary']),
      examTypes = strings(j['examTypes']),
      alwaysOpen = j['alwaysOpen'] == true,
      next = j['nextEvent'] == null ? null : CertNextEvent.from(object(j['nextEvent']));

  /// "필기 · 실기" (필기만 있으면 "필기")
  String get partsText => examTypes
      .map((t) => t == 'PRACTICAL' ? '실기' : '필기')
      .join(' · ');

  /// 목록·카드에 쓰는 다음 일정 한 줄
  String get nextText {
    if (alwaysOpen) return '상시 시험';
    final n = next;
    if (n == null) return '일정 준비 중';
    return '${n.label} ${n.dDayText}${n.projected ? ' (예상)' : ''}';
  }
}

class CertExamInfo {
  final String examType, label;
  final int? fee, questionCount, durationMinutes, scopeYear;
  final String? method, passCriteria;
  final List<String> subjects;
  CertExamInfo.from(Json j)
    : examType = j['examType'] as String? ?? 'WRITTEN',
      label = j['examTypeLabel'] as String? ?? '필기',
      fee = _i(j['fee']),
      questionCount = _i(j['questionCount']),
      durationMinutes = _i(j['durationMinutes']),
      scopeYear = _i(j['scopeYear']),
      method = _s(j['method']),
      passCriteria = _s(j['passCriteria']),
      subjects = strings(j['subjects']);
}

class CertRound {
  final int? year, round;
  final String? label;
  final DateTime? regStart, regEnd, addRegStart, addRegEnd, examStart, examEnd, result;
  final bool past, projected;
  CertRound.from(Json j)
    : year = _i(j['examYear']),
      round = _i(j['roundNo']),
      label = _s(j['examTypeLabel']),
      regStart = _d(j['regStartAt']),
      regEnd = _d(j['regEndAt']),
      addRegStart = _d(j['addRegStartAt']),
      addRegEnd = _d(j['addRegEndAt']),
      examStart = _d(j['examStartDate']),
      examEnd = _d(j['examEndDate']),
      result = _d(j['resultDate']),
      past = j['past'] == true,
      projected = j['projected'] == true;

  String get title => '${year ?? ''}년 ${round == null ? '' : '제$round회 '}${label ?? ''}'.trim();
}

class CertPassRate {
  final int? year, round, applicants, passed;
  final String? label;
  final double? rate;
  CertPassRate.from(Json j)
    : year = _i(j['examYear']),
      round = _i(j['roundNo']),
      label = _s(j['examTypeLabel']),
      applicants = _i(j['applicantCount']),
      passed = _i(j['passCount']),
      rate = (j['passRate'] as num?)?.toDouble();
}

class CertDetail {
  final CertSummary basic;
  final String? eligibility, eligibilityCheckUrl, officialUrl, applyUrl;
  final DateTime? verifiedAt;
  final String? writtenExemption, requiredItems, validity, refundNote, refundUrl, resultNotice, relatedCerts;
  final List<CertExamInfo> exams;
  final CertRound? nextExam;
  final List<CertRound> schedule;
  final List<CertPassRate> passRates;
  CertDetail.from(Json j)
    : basic = CertSummary.from(object(j['basic'])),
      eligibility = _s(j['eligibility']),
      eligibilityCheckUrl = _s(j['eligibilityCheckUrl']),
      officialUrl = _s(j['officialUrl']),
      applyUrl = _s(j['applyUrl']),
      verifiedAt = _d(j['infoVerifiedAt']),
      writtenExemption = _s((j['notes'] as Json?)?['writtenExemption']),
      requiredItems = _s((j['notes'] as Json?)?['requiredItems']),
      validity = _s((j['notes'] as Json?)?['validity']),
      refundNote = _s((j['notes'] as Json?)?['refundNote']),
      refundUrl = _s((j['notes'] as Json?)?['refundUrl']),
      resultNotice = _s((j['notes'] as Json?)?['resultNotice']),
      relatedCerts = _s((j['notes'] as Json?)?['relatedCerts']),
      exams = rows(j['exams'] ?? []).map(CertExamInfo.from).toList(),
      nextExam = j['nextExam'] == null ? null : CertRound.from(object(j['nextExam'])),
      schedule = rows(j['schedule'] ?? []).map(CertRound.from).toList(),
      passRates = rows(j['passRates'] ?? []).map(CertPassRate.from).toList();

  /// 알아두면 좋은 정보 중 값이 있는 것만 (라벨, 내용)
  List<(String, String)> get notes => [
    if (writtenExemption != null) ('필기 면제', writtenExemption!),
    if (requiredItems != null) ('준비물', requiredItems!),
    if (validity != null) ('자격 유효기간', validity!),
    if (refundNote != null) ('취소 · 환불', refundNote!),
    if (resultNotice != null) ('발표 방법', resultNotice!),
  ];
}

/// 19400 → "19,400원"
String won(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '$b원';
}

/// 2026-12-01 → "2026.12.01"
String dot(DateTime? d) => d == null
    ? '-'
    : '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

/// 기간 "2026.12.01 ~ 12.05" (같은 날이면 하루만)
String span(DateTime? a, DateTime? b) {
  if (a == null) return '-';
  if (b == null || (a.year == b.year && a.month == b.month && a.day == b.day)) return dot(a);
  return '${dot(a)} ~ ${b.month.toString().padLeft(2, '0')}.${b.day.toString().padLeft(2, '0')}';
}

/// 플래너 카탈로그 key("db-3-WRITTEN") → 자격증 번호 3
int? certIdFromKey(String key) => int.tryParse(RegExp(r'^db-(\d+)-').firstMatch(key)?.group(1) ?? '');
