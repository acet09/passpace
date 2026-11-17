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

/// 질문 속 자격증별 하루 시간: "SQLD 1시간, 정처기는 하루 2시간".
/// 자격증 이름 바로 뒤(다음 자격증 이름 전)에 적힌 시간만 그 자격증의 것으로 본다.
({int? sqld, int? ipe}) examMinutesInMessage(String message) {
  final names = RegExp(
    r'(SQLD|SQL\s*개발자)|(?:정처기|정보처리기사)(?:\s*(?:필기|실기))?',
    caseSensitive: false,
  ).allMatches(message).toList();
  final time = RegExp(r'^[^\d,.·/]{0,10}?' + _amount);
  int? sqld, ipe;
  for (final (i, name) in names.indexed) {
    final end = i + 1 < names.length ? names[i + 1].start : message.length;
    final m = time.firstMatch(message.substring(name.end, end));
    if (m == null) continue;
    final minutes = _minutesOf(m);
    if (!validDailyMinutes(minutes)) continue;
    if (name[1] != null) {
      sqld ??= minutes;
    } else {
      ipe ??= minutes;
    }
  }
  return (sqld: sqld, ipe: ipe);
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
    final sqld = RegExp(
      r'SQLD|SQL\s*개발자',
      caseSensitive: false,
    ).hasMatch(message);
    final ipe = RegExp('정처기|정보처리기사').hasMatch(message);
    final practical = ipe && message.contains('실기') && !message.contains('필기');
    final active = catalog.exams
        .where(
          (e) =>
              sqld && e.name == 'SQLD' ||
              ipe &&
                  (practical
                      ? e.name == '정보처리기사 실기'
                      : e.name.startsWith('정보처리기사 필기')),
        )
        .toList();
    if (active.isEmpty) {
      throw const ApiError('현재 지원하는 정처기 필기·실기 또는 SQLD를 찾지 못했어요.');
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
    final each = examMinutesInMessage(message);
    final own = [
      for (final e in active) e.name == 'SQLD' ? each.sqld : each.ipe,
    ];
    final ownTotal = own.fold(0, (sum, n) => sum + (n ?? 0));
    final divided =
        active.length >= 2 && !own.contains(null) && ownTotal <= 960;
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
