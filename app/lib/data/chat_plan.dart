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

  /// 요일마다 시간을 다르게 정하는가, 그리고 요일(1=월 … 7=일)별 시간(분). 없는 요일은 쉬는 날.
  bool byWeekday = false;
  final dayMinutes = <int, int>{};
  final weekdays = <int>{1, 2, 3, 4, 5, 6, 7};

  /// 요일별 시간을 정하고, 공부 요일을 시간이 있는 요일로 맞춘다.
  void setDayMinutes(Map<int, int> minutes) {
    dayMinutes
      ..clear()
      ..addAll(minutes);
    if (minutes.isNotEmpty) {
      weekdays
        ..clear()
        ..addAll(minutes.keys);
    }
  }
  final goals = <String, ExamDraft>{};
  void update(VoidCallback change) {
    change();
    notifyListeners();
  }
}

bool validDailyMinutes(int? n) => n != null && n >= 30 && n <= 960;

/// 요일 묶음을 "월·수·금"처럼 적는다.
String weekdayNames(Iterable<int> days) =>
    (days.toList()..sort()).map((d) => weekdays[d - 1]).join('·');

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

const _dayLetters = '월화수목금토일';
const _dayJoin = ',|·|/|이랑|랑|하고|과|와|및';
// "화요일", 또는 요일 한 글자. 한 글자는 뒤에 다른 요일·조사·띄어쓰기가 올 때만 요일로 본다
// ("수목원", "월수입", "일정"의 글자는 요일이 아니다).
const _day =
    '(?:[$_dayLetters]요일|[$_dayLetters](?=[$_dayLetters]|\\s|\$|[.!?~\\-]|$_dayJoin'
    '|은|는|이|가|에|엔|만|도|마다|밖에|빼|제외|말고|까지|부터))';

// 요일을 말한 자리: "주말", "월~금", "월수금", "화요일이랑 목요일". 그룹 1·2는 범위의 처음·끝.
final _dayGroups = RegExp(
  '주말|평일|주중|매일|날마다'
  '|(?<![가-힣0-9])([$_dayLetters])(?:요일)?\\s*(?:~|-|부터|에서)\\s*(?=$_day)([$_dayLetters])(?:요일)?(?:\\s*까지)?'
  '|(?<![가-힣0-9])$_day(?:(?:\\s*(?:$_dayJoin)\\s*|\\s+)?$_day)*',
);
// 요일 뒤에 온 말로 되는 날인지 안 되는 날인지 가린다.
final _dayOff = RegExp(
  r'안\s*(?:돼|되|됨|됩|될|된|해|함|할|합)|못\s*(?:해|하|함|합|할)|불가|빼|제외|말고|쉬|쉴|쉽|힘들|어렵|어려|없|바쁘|바빠',
);
final _dayOn = RegExp(r'만(?!큼)|가능|돼|되|됨|됩|할\s*수|공부|괜찮|비어|한가|\d\s*(?:시간|분)');
final _clauseEnd = RegExp(r'는데|지만|고\s|[,.!?\n]');

/// 질문 속 공부 요일(1=월 … 7=일): "월수금만 가능", "주말은 안 돼", "화요일이랑 목요일 빼고".
/// 되는 요일을 말하면 그 요일만, 안 되는 요일만 말하면 나머지 요일을 돌려준다.
/// 요일 이야기가 없거나 되는지 안 되는지 알 수 없으면 null.
Set<int>? weekdaysInMessage(String message) {
  const all = {1, 2, 3, 4, 5, 6, 7};
  final on = <int>{}, off = <int>{};
  var also = false;
  for (final mention in _dayMentions(message)) {
    if (_dayOff.hasMatch(mention.tail)) {
      off.addAll(mention.days);
    } else if (_dayOn.hasMatch(mention.tail)) {
      on.addAll(mention.days);
      // "주말에도 가능"은 주말만 된다는 뜻이 아니다.
      if (RegExp(r'^\s*에?도').hasMatch(mention.tail)) also = true;
    }
  }
  if (on.isEmpty && off.isEmpty) return null;
  final days = (on.isEmpty || also ? all : on).difference(off);
  return days.isEmpty ? null : days;
}

/// 질문 속 요일별 공부시간(요일 → 분): "평일엔 2시간, 주말엔 4시간", "월수금 1시간 토요일 3시간".
/// 요일마다 다른 시간을 둘 이상 말했을 때만 읽는다. "월수금 하루 2시간"처럼 시간이 하나면
/// 요일과 하루 시간으로 따로 읽으므로 null.
Map<int, int>? weekdayMinutesInMessage(String message) {
  final minutes = <int, int>{}, off = <int>{}, amounts = <int>{};
  var told = 0;
  for (final mention in _dayMentions(message)) {
    if (_dayOff.hasMatch(mention.tail)) {
      off.addAll(mention.days);
      continue;
    }
    final time = RegExp(_amount).firstMatch(mention.tail);
    if (time == null) continue;
    final n = _minutesOf(time);
    if (!validDailyMinutes(n)) continue;
    told++;
    amounts.add(n);
    for (final day in mention.days) {
      minutes[day] = n;
    }
  }
  if (told < 2 || amounts.length < 2) return null;
  minutes.removeWhere((day, _) => off.contains(day));
  return minutes.isEmpty ? null : minutes;
}

// 요일을 말한 자리마다: 어느 요일인지, 그리고 그 요일에 대해 이어서 한 말(다음 요일 이야기 전, 같은 절 안).
List<({Set<int> days, String tail})> _dayMentions(String message) {
  const all = {1, 2, 3, 4, 5, 6, 7};
  final groups = <({Set<int> days, int end})>[];
  final starts = <int>[];
  for (final m in _dayGroups.allMatches(message)) {
    final text = m[0]!;
    final Set<int> days;
    if (text == '주말') {
      days = {6, 7};
    } else if (text == '평일' || text == '주중') {
      days = {1, 2, 3, 4, 5};
    } else if (text == '매일' || text == '날마다') {
      days = all;
    } else if (m[1] != null) {
      final from = _dayLetters.indexOf(m[1]!), to = _dayLetters.indexOf(m[2]!);
      if (from == to) continue;
      // "금~월"처럼 주를 넘어가는 범위도 읽는다.
      days = {from + 1};
      for (var i = from; i != to;) {
        i = (i + 1) % 7;
        days.add(i + 1);
      }
    } else {
      final letters = text
          .replaceAll('요일', '')
          .split('')
          .where(_dayLetters.contains)
          .toList();
      // "일일 2시간", "금일"은 요일이 아니고, 한 글자만 쓴 "일"·"수"는 다른 말일 수 있다.
      if (!text.contains('요일') &&
          (letters.length < 2 || text == '일일' || text == '금일')) {
        continue;
      }
      days = {for (final c in letters) _dayLetters.indexOf(c) + 1};
    }
    groups.add((days: days, end: m.end));
    starts.add(m.start);
  }
  return [
    for (final (i, group) in groups.indexed)
      (
        days: group.days,
        tail: () {
          var end = i + 1 < groups.length ? starts[i + 1] : message.length;
          if (end > group.end + 18) end = group.end + 18;
          final tail = message.substring(group.end, end);
          final cut = _clauseEnd.firstMatch(tail);
          return cut == null ? tail : tail.substring(0, cut.start);
        }(),
      ),
  ];
}

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

  /// 질문에 적힌 공부 요일을 먼저 넣어 두었으면 그 요일(1=월 … 7=일).
  final Set<int>? weekdaysFromQuestion;

  /// 질문에 요일마다 다른 시간이 적혀 있어 요일별 시간으로 넣어 두었는가.
  final bool dayMinutesFromQuestion;

  /// 카드는 한 번에 한 가지씩 묻는다. 답을 마친 단계와, 다시 고치려고 연 단계.
  final confirmed = <String>{};
  String? editing;
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
    this.weekdaysFromQuestion,
    this.dayMinutesFromQuestion,
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
    // "평일 2시간, 주말 4시간"처럼 요일마다 다른 시간을 말했으면 요일별 시간으로 넣는다.
    final perDay = divided ? null : weekdayMinutesInMessage(message);
    final daily = divided
        ? ownTotal
        : perDay != null
        ? perDay.values.reduce((a, b) => a > b ? a : b)
        : dailyMinutesInMessage(message);
    if (divided) {
      inputs.update(() {
        inputs.split = true;
        inputs.byWeekday = false;
        for (final (i, e) in active.indexed) {
          inputs.examMinutes[e.key] = own[i]!;
        }
      });
    } else if (perDay != null) {
      inputs.update(() {
        inputs.split = false;
        inputs.byWeekday = true;
        inputs.setDayMinutes(perDay);
      });
    } else if (daily != null) {
      inputs.update(() {
        inputs.split = false;
        inputs.byWeekday = false;
        inputs.minutes = daily;
      });
    }
    // "월수금만 가능", "주말은 안 돼"처럼 요일을 말했으면 공부할 요일에 먼저 넣는다.
    final days = perDay?.keys.toSet() ?? weekdaysInMessage(message);
    if (days != null && perDay == null) {
      inputs.update(() {
        inputs.weekdays
          ..clear()
          ..addAll(days);
        // 요일별 시간을 쓰던 중이면 안 되는 요일의 시간을 지운다.
        inputs.dayMinutes.removeWhere((day, _) => !days.contains(day));
      });
    }
    final budget = RegExp(r'총\s*(\d{1,4})\s*시간').firstMatch(message);
    final setup = ChatPlanSetup._(
      active,
      asked.start != null || asked.end != null,
      budget == null ? null : int.parse(budget[1]!),
      daily,
      divided,
      days,
      perDay != null,
    );
    // 질문에서 이미 읽은 것은 다시 묻지 않는다 (카드에서 눌러 고칠 수는 있다).
    if (daily != null && setup.dailyTotal(inputs) != null) {
      setup.confirmed.add(stepTime);
    }
    if (days != null) setup.confirmed.add(stepDays);
    if (setup.datesFromQuestion && setup.datesChosen(inputs)) {
      setup.confirmed.add(stepPeriod);
    }
    return setup;
  }

  static const stepTime = 'time', stepDays = 'days', stepPeriod = 'period';
  static String stepLevel(CatalogExam exam) => 'level:${exam.key}';

  /// 이 카드가 차례로 묻는 단계. 요일별 시간을 쓰면 요일은 시간 단계에서 함께 정한다.
  List<String> steps(ChatPlanInputs inputs) => [
    stepTime,
    if (!inputs.byWeekday) stepDays,
    stepPeriod,
    for (final exam in exams) stepLevel(exam),
  ];

  /// 지금 물어볼 단계. 모두 답했으면 null (계산할 차례).
  String? current(ChatPlanInputs inputs) {
    final all = steps(inputs);
    if (editing != null && all.contains(editing)) return editing;
    for (final step in all) {
      // 답했더라도 값이 비게 됐으면(다른 카드에서 바뀐 경우) 다시 묻는다.
      if (!confirmed.contains(step) || !answered(step, inputs)) return step;
    }
    return null;
  }

  /// 그 단계의 답이 채워졌는가.
  bool answered(String step, ChatPlanInputs inputs) {
    if (step == stepTime) return dailyTotal(inputs) != null;
    if (step == stepDays) return inputs.weekdays.isNotEmpty;
    if (step == stepPeriod) return datesChosen(inputs);
    final exam = exams.firstWhere((e) => stepLevel(e) == step);
    return exam.subjects.every(
      (s) => inputs.goals[exam.key]?.familiarity[s['name']] != null,
    );
  }

  /// 모든 시험의 끝낼 날짜가 정해졌는가 (상시시험은 처음에 비어 있다).
  bool datesChosen(ChatPlanInputs inputs) =>
      exams.every((e) => inputs.goals[e.key]?.end != null);

  /// 이 카드에서 자격증별 시간을 쓰는가 (자격증이 둘 이상일 때만 의미가 있다).
  bool splits(ChatPlanInputs inputs) =>
      exams.length >= 2 && inputs.split && !inputs.byWeekday;

  /// 서버에 보낼 하루 총 시간. 나눠 쓰면 자격증별 시간의 합, 요일별 시간이면 가장 긴 요일의 시간.
  /// 아직 못 정하면 null.
  int? dailyTotal(ChatPlanInputs inputs) {
    if (inputs.byWeekday) {
      final times = inputs.dayMinutes.values;
      return times.isNotEmpty && times.every(validDailyMinutes)
          ? times.reduce((a, b) => a > b ? a : b)
          : null;
    }
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
        inputs.byWeekday
            ? '공부할 요일의 시간을 하나 이상, 각각 30~960분으로 정해 주세요.'
            : each
            ? '자격증별 하루 시간을 각각 30분 이상, 합계 960분 이하로 입력해 주세요.'
            : '하루 공부 가능시간을 먼저 선택하거나 30~960분으로 입력해 주세요.',
      );
    }
    if (!inputs.byWeekday && inputs.weekdays.isEmpty) {
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
    final days =
        (inputs.byWeekday ? inputs.dayMinutes.keys : inputs.weekdays).toList()
          ..sort();
    return {
      'dailyMinutes': total,
      'studyWeekdays': days,
      // 요일마다 시간이 다르면 요일 → 분. 서버는 이 요일에만, 그날의 시간까지만 배정한다.
      if (inputs.byWeekday)
        'weekdayMinutes': {
          for (final day in days) '$day': inputs.dayMinutes[day],
        },
      'goals': goals,
    };
  }
}
