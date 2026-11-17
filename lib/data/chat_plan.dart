import 'package:flutter/foundation.dart';

import 'api.dart';
import 'models.dart';
import 'plan_draft.dart';

/// 서버가 "채팅 안에서 계획 입력을 열어라"는 뜻으로 보내는 notice 값.
const autoPlanNotice = 'AUTO_PLAN_SETUP';

/// 하루 시간·요일·시험별 기간과 이해도. 같은 상담 화면의 모든 계획 카드가 함께 쓴다.
class ChatPlanInputs extends ChangeNotifier {
  int? minutes;

  /// 자격증별로 하루 시간을 따로 정하는가, 그리고 시험 key별 하루 상한(분).
  bool split = false;
  final examMinutes = <String, int>{};
  final weekdays = <int>{1, 2, 3, 4, 5, 6, 7};
  final goals = <String, ExamDraft>{};
  void update(VoidCallback change) {
    change();
    notifyListeners();
  }
}

bool validDailyMinutes(int? n) => n != null && n >= 30 && n <= 960;

/// 질문 속 공부 기간: "11월 20일부터", "2027-01-10까지", "3월 20일 시험".
/// 연도가 없으면 올해, 이미 지난 날짜면 내년으로 본다.
({DateTime? start, DateTime? end}) datesInMessage(
  String message,
  DateTime today,
) {
  DateTime? start, end;
  final pattern = RegExp(
    r'(?:(20\d{2})\s*[년.\-/]\s*)?(\d{1,2})\s*(?:월|[.\-/])\s*(\d{1,2})\s*일?\s*(부터|까지|시험)',
  );
  for (final m in pattern.allMatches(message)) {
    final month = int.parse(m[2]!), day = int.parse(m[3]!);
    if (month < 1 || month > 12 || day < 1 || day > 31) continue;
    var date = DateTime(
      m[1] == null ? today.year : int.parse(m[1]!),
      month,
      day,
    );
    if (m[1] == null && date.isBefore(today)) {
      date = DateTime(today.year + 1, month, day);
    }
    if (date.month != month || date.day != day) continue; // 2월 30일 같은 날짜
    if (m[4] == '부터') {
      start = date;
    } else {
      end = date;
    }
  }
  if (start != null && end != null && !start.isBefore(end)) {
    return (start: null, end: null);
  }
  return (start: start, end: end);
}

/// 질문 속 하루 공부시간(분): "하루 2시간", "매일 1시간 30분", "90분씩", "하루 2시간 반".
/// "총 100시간" 같은 전체 예산은 읽지 않고, 30~960분을 벗어나면 null.
int? dailyMinutesInMessage(String message) {
  for (final pattern in [
    RegExp(r'(?:하루|매일|일일)\s*(?:에|당|평균)?\s*(?:약\s*)?' + _amount),
    RegExp(_amount + r'\s*씩'),
  ]) {
    for (final m in pattern.allMatches(message)) {
      final minutes = _minutesOf(m);
      if (validDailyMinutes(minutes)) return minutes;
    }
  }
  return null;
}

// "2시간", "1시간 30분", "2시간 반", "1.5시간", "90분". 그룹: 시간, 반, 분, 분만.
const _amount =
    r'(?:(\d{1,2}(?:\.\d)?)\s*시간\s*(?:(반)(?!복)|(\d{1,3})\s*분)?|(\d{1,3})\s*분)';
int _minutesOf(RegExpMatch m) =>
    ((double.tryParse(m[1] ?? '') ?? 0) * 60).round() +
    (m[2] == null ? 0 : 30) +
    (int.tryParse(m[3] ?? m[4] ?? '') ?? 0);

/// 채팅 계획이 알아듣는 자격증. 이름 규칙은 웹 chatbot.js 의 CERT_WORDS 와 같다.
class _Cert {
  final String id;
  final RegExp word;
  final bool Function(String name) written;
  final bool Function(String name)? practical;
  const _Cert(this.id, this.word, this.written, [this.practical]);
}

final _certs = [
  _Cert(
    'IPE',
    RegExp(r'정처기|정보\s*처리\s*기사'),
    (n) => n.startsWith('정보처리기사 필기'),
    (n) => n == '정보처리기사 실기',
  ),
  _Cert(
    'SQLD',
    RegExp(r'SQLD|SQL\s*개발자', caseSensitive: false),
    (n) => n == 'SQLD',
  ),
  _Cert(
    'ADSP',
    RegExp(r'ADsP|데이터\s*분석\s*준\s*전문가', caseSensitive: false),
    (n) => n == 'ADsP',
  ),
  // "컴활 2급"만 말한 경우는 제외. 급수를 말하지 않으면 1급으로 본다.
  _Cert(
    'CA1',
    RegExp(r'(?:컴활|컴퓨터\s*활용\s*능력)(?!\s*2\s*급)'),
    (n) => n == '컴퓨터활용능력 1급 필기',
    (n) => n == '컴퓨터활용능력 1급 실기',
  ),
];

/// 한 번에 묶을 수 있는 자격증 수 (같은 자격증의 필기·실기는 1개).
const maxChatPlanCerts = 3;

// 질문에 자격증 이름이 나온 자리 (나온 순서).
List<({_Cert cert, int start, int end})> _mentions(String message) => [
  for (final cert in _certs)
    for (final m in cert.word.allMatches(message))
      (cert: cert, start: m.start, end: m.end),
]..sort((a, b) => a.start.compareTo(b.start));

/// 질문에 나온 자격증과 시험구분 (나온 순서).
/// 시험구분은 그 자격증 이름부터 다음 자격증 이름 전까지의 글에서 찾는다.
/// 붙여 말하지 않은 자격증은 질문 전체에 "실기"만 있으면 실기, 아니면 필기.
List<({String id, bool written, bool practical})> certsInMessage(
  String message,
) {
  final found = _mentions(message);
  final onlyPractical = message.contains('실기') && !message.contains('필기');
  final wanted = <String, ({bool written, bool practical})>{};
  for (final (i, mention) in found.indexed) {
    final part = message.substring(
      i == 0 ? 0 : mention.start,
      i + 1 < found.length ? found[i + 1].start : message.length,
    );
    final before = wanted[mention.cert.id];
    wanted[mention.cert.id] = (
      written: (before?.written ?? false) || part.contains('필기'),
      practical:
          (before?.practical ?? false) ||
          (part.contains('실기') && mention.cert.practical != null),
    );
  }
  return [
    for (final e in wanted.entries)
      if (e.value.written || e.value.practical)
        (id: e.key, written: e.value.written, practical: e.value.practical)
      else if (onlyPractical &&
          _certs.firstWhere((c) => c.id == e.key).practical != null)
        (id: e.key, written: false, practical: true)
      else
        (id: e.key, written: true, practical: false),
  ];
}

/// 질문 속 자격증별 하루 시간(자격증 id → 분): "SQLD 1시간, 정처기는 하루 2시간".
/// 자격증 이름 바로 뒤(다음 자격증 이름 전)에 적힌 시간만 그 자격증의 것으로 본다.
Map<String, int> examMinutesInMessage(String message) {
  final found = _mentions(message);
  final time = RegExp(r'^\s*(?:1\s*급)?[^\d,.·/]{0,12}?' + _amount);
  final minutes = <String, int>{};
  for (final (i, mention) in found.indexed) {
    final end = i + 1 < found.length ? found[i + 1].start : message.length;
    final m = time.firstMatch(message.substring(mention.end, end));
    if (m == null) continue;
    final n = _minutesOf(m);
    if (validDailyMinutes(n)) minutes.putIfAbsent(mention.cert.id, () => n);
  }
  return minutes;
}

/// 질문 한 건에서 열린 계획 카드의 상태. 목록에서 스크롤로 사라져도 유지된다.
class ChatPlanSetup {
  final List<CatalogExam> exams;
  final bool datesFromQuestion;
  final int? budgetHours;

  /// 질문에 적힌 하루 공부시간을 먼저 넣어 두었으면 그 값(분).
  final int? minutesFromQuestion;

  /// 질문에 자격증별 시간이 적혀 있어 나눠서 넣어 두었는가.
  final bool splitFromQuestion;
  Json? request;
  ChatPlanReply? result;
  bool busy = false, saving = false, saved = false;
  String? error, saveNote;
  ChatPlanSetup._(
    this.exams,
    this.datesFromQuestion,
    this.budgetHours,
    this.minutesFromQuestion,
    this.splitFromQuestion,
  );

  /// 질문에서 종목을 고르고, 날짜가 적혀 있으면 공부 기간에 먼저 넣는다.
  factory ChatPlanSetup.from(
    String message,
    Catalog catalog,
    ChatPlanInputs inputs,
    DateTime today,
  ) {
    final asking = certsInMessage(message);
    if (asking.length > maxChatPlanCerts) {
      throw const ApiError(
        '자격증은 한 번에 $maxChatPlanCerts개까지 묶을 수 있어요 (같은 자격증의 필기·실기는 1개로 셉니다). '
        '질문의 자격증을 줄여 다시 말씀해 주세요.',
      );
    }
    // 이 시험이 질문의 어느 자격증에 해당하는가 (해당 없으면 null).
    String? certOf(CatalogExam e) {
      for (final entry in asking) {
        final cert = _certs.firstWhere((c) => c.id == entry.id);
        if (entry.written && cert.written(e.name) ||
            entry.practical && (cert.practical?.call(e.name) ?? false)) {
          return entry.id;
        }
      }
      return null;
    }

    final active = catalog.exams.where((e) => certOf(e) != null).toList();
    if (active.isEmpty) {
      throw const ApiError(
        '현재 지원하는 자격증(정처기 필기·실기, SQLD, ADsP, 컴활 1급 필기·실기)을 찾지 못했어요.',
      );
    }
    final limit = plusDays(today, 540);
    final asked = datesInMessage(message, today);
    for (final exam in active) {
      final goal = inputs.goals.putIfAbsent(
        exam.key,
        () => ExamDraft(today, null),
      );
      final suggested = exam.suggested;
      if (goal.end == null &&
          suggested != null &&
          suggested.isAfter(today) &&
          !suggested.isAfter(limit)) {
        goal.end = suggested;
      }
      if (asked.start != null) goal.start = asked.start!;
      if (asked.end != null) goal.end = asked.end;
    }
    // 자격증마다 시간이 적혀 있으면 나눠 넣고, 아니면 하루 총 시간으로 읽는다.
    // 한 자격증의 필기·실기를 함께 고르면 어느 쪽 시간인지 알 수 없어 나누지 않는다.
    final each = examMinutesInMessage(message);
    final own = [for (final e in active) each[certOf(e)]];
    final ownTotal = own.fold(0, (sum, n) => sum + (n ?? 0));
    final divided =
        active.length >= 2 &&
        active.map(certOf).toSet().length == active.length &&
        !own.contains(null) &&
        ownTotal <= 960;
    final daily = divided ? ownTotal : dailyMinutesInMessage(message);
    if (divided) {
      inputs.update(() {
        inputs.split = true;
        for (final (i, e) in active.indexed) {
          inputs.examMinutes[e.key] = own[i]!;
        }
      });
    } else if (daily != null) {
      inputs.update(() {
        inputs.split = false;
        inputs.minutes = daily;
      });
    }
    final budget = RegExp(r'총\s*(\d{1,4})\s*시간').firstMatch(message);
    return ChatPlanSetup._(
      active,
      asked.start != null || asked.end != null,
      budget == null ? null : int.parse(budget[1]!),
      daily,
      divided,
    );
  }

  /// 모든 시험의 끝낼 날짜가 정해졌는가 (상시시험은 처음에 비어 있다).
  bool datesChosen(ChatPlanInputs inputs) =>
      exams.every((e) => inputs.goals[e.key]?.end != null);

  /// 이 카드에서 자격증별 시간을 쓰는가 (자격증이 둘 이상일 때만 의미가 있다).
  bool splits(ChatPlanInputs inputs) => exams.length >= 2 && inputs.split;

  /// 서버에 보낼 하루 총 시간. 나눠 쓰면 자격증별 시간의 합. 아직 못 정하면 null.
  int? dailyTotal(ChatPlanInputs inputs) {
    if (!splits(inputs)) {
      return validDailyMinutes(inputs.minutes) ? inputs.minutes : null;
    }
    var sum = 0;
    for (final e in exams) {
      final n = inputs.examMinutes[e.key];
      if (!validDailyMinutes(n)) return null;
      sum += n!;
    }
    return sum <= 960 ? sum : null;
  }

  bool familiarityChosen(ChatPlanInputs inputs) => exams.every(
    (e) => e.subjects.every(
      (s) => inputs.goals[e.key]?.familiarity[s['name']] != null,
    ),
  );

  /// 서버에 보낼 계획 요청 (학습계획 만들기 화면과 같은 모양).
  Json buildRequest(ChatPlanInputs inputs) {
    final total = dailyTotal(inputs), each = splits(inputs);
    if (total == null) {
      throw ApiError(
        each
            ? '자격증별 하루 시간을 각각 30분 이상, 합계 960분 이하로 입력해 주세요.'
            : '하루 공부 가능시간을 먼저 선택하거나 30~960분으로 입력해 주세요.',
      );
    }
    if (inputs.weekdays.isEmpty) {
      throw const ApiError('공부할 요일을 하나 이상 선택해 주세요.');
    }
    final goals = <Json>[];
    for (final exam in exams) {
      final g = inputs.goals[exam.key]!;
      if (g.end == null) throw ApiError('${exam.name}: 끝낼 날짜를 선택해 주세요.');
      if (!g.start.isBefore(g.end!)) {
        throw ApiError('${exam.name}: 공부 시작일은 끝낼 날짜 이전이어야 해요.');
      }
      final subjects = <Json>[];
      for (final s in exam.subjects) {
        final name = s['name'] as String,
            level = g.familiarity[name],
            hours = s['baseHours'] as num?;
        if (level == null) {
          throw ApiError('${exam.name} / $name: 이해도를 선택해 주세요.');
        }
        if (hours == null || hours <= 0) {
          throw ApiError('$name 과목의 기준시간이 아직 준비되지 않았어요.');
        }
        subjects.add({
          'name': name,
          'baseHours': hours,
          'familiarity': level,
          'progressPercent': 0,
          'actualMinutes': 0,
        });
      }
      goals.add({
        'key': exam.key,
        'certificationName': exam.name,
        'startDate': isoDay(g.start),
        'examDate': isoDay(g.end!),
        if (each) 'dailyMinutes': inputs.examMinutes[exam.key],
        'subjects': subjects,
      });
    }
    return {
      'dailyMinutes': total,
      'studyWeekdays': inputs.weekdays.toList()..sort(),
      'goals': goals,
    };
  }
}
