typedef Json = Map<String, dynamic>;

Json object(Object? value) {
  if (value is! Json) throw const FormatException('object expected');
  return value;
}

List<Json> rows(Object? value) => (value as List).map(object).toList();
List<String> strings(Object? value) => (value as List? ?? []).cast<String>();
const majors = {'MAJOR': '전공', 'RELATED': '유사전공', 'NON_MAJOR': '비전공'};
const levels = ['낯섦', '보통', '익숙함'];
const weekdays = ['월', '화', '수', '목', '금', '토', '일'];

DateTime dayInSeoul([DateTime? now]) {
  final kst = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 9));
  return DateTime(kst.year, kst.month, kst.day);
}

DateTime plusDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
String isoDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String shortDay(DateTime d) => '${d.month}월 ${d.day}일';
String durationLabel(int minutes) {
  if (minutes < 60) return '$minutes분';
  final rest = minutes % 60;
  return '${minutes ~/ 60}시간${rest == 0 ? '' : ' $rest분'}';
}

class Profile {
  final String id, name, email, major;
  final int? userId;
  Profile.from(Json j)
    : id = j['loginId'] as String,
      userId = j['userId'] as int?,
      name = j['nickname'] as String,
      email = j['email'] as String? ?? '',
      major = j['majorTypeLabel'] as String? ?? majors[j['majorType']] ?? '미설정';
}

class StudyTask {
  final DateTime date;
  final String exam, subject;
  final int minutes;
  final int? id;
  StudyTask.from(Json j)
    : date = DateTime.parse(j['date']),
      id = j['taskId'] as int?,
      exam = j['certificationName'] as String? ?? '',
      subject = j['subjectName'] as String,
      minutes = j['minutes'] as int;
}

class SavedPlan {
  final int? id;
  final String name;
  final DateTime start, end;
  final int version;
  final Map<String, List<StudyTask>> byDay = {};
  SavedPlan.from(Json j)
    : id = j['planId'] as int?,
      name = j['planName'] as String,
      start = DateTime.parse(j['startDate']),
      end = DateTime.parse(j['endDate']),
      version = j['versionNo'] as int {
    for (final item in rows(j['tasks']).map(StudyTask.from)) {
      byDay.putIfAbsent(isoDay(item.date), () => []).add(item);
    }
  }
  List<StudyTask> on(DateTime d) => byDay[isoDay(d)] ?? const [];
  bool get canEditSchedule =>
      id != null &&
      byDay.values.expand((tasks) => tasks).any((task) => task.id != null);
  List<String> get exams => byDay.values
      .expand((v) => v)
      .map((t) => t.exam)
      .where((e) => e.isNotEmpty)
      .toSet()
      .toList();
  int get totalMinutes =>
      byDay.values.expand((v) => v).fold(0, (n, t) => n + t.minutes);
}

/// 저장한 계획 목록의 한 줄. 지금 쓰는 계획 하나만 [active] 이고 나머지는 보관 중이다.
class PlanSummary {
  final int id, days, totalMinutes;
  final String name;
  final DateTime start, end;
  final bool active;
  PlanSummary.from(Json j)
    : id = j['planId'] as int,
      name = j['planName'] as String? ?? '학습계획',
      start = DateTime.parse(j['startDate']),
      end = DateTime.parse(j['endDate']),
      active = j['active'] == true,
      days = j['days'] as int? ?? 0,
      totalMinutes = j['totalMinutes'] as int? ?? 0;
}

class GoalData {
  final int? roundId, minutes;
  final DateTime? date;
  final Map<String, int> familiarity;
  final List<Json> rounds, subjects;
  GoalData.from(Json j)
    : this._(
        object(j['goal'] ?? <String, dynamic>{}),
        rows(j['examRounds']),
        rows(j['subjects']),
      );
  GoalData._(Json goal, this.rounds, this.subjects)
    : roundId = goal['examRoundId'] as int?,
      minutes = goal['dailyMinutes'] as int?,
      date = DateTime.tryParse(goal['targetExamDate'] as String? ?? ''),
      familiarity = Map<String, int>.from(goal['familiarity'] ?? {});
  Json? get selectedRound =>
      rounds.where((r) => r['examRoundId'] == roundId).firstOrNull;
  DateTime? get examDate =>
      date ??
      DateTime.tryParse(selectedRound?['examStartDate'] as String? ?? '');
  String get examLabel => selectedRound?['label'] as String? ?? '나의 목표 시험';
}

class CatalogExam {
  final String key, name;
  final DateTime? suggested;
  final String? scheduleNote, evidence;
  final bool temporary;
  final List<Json> subjects;

  /// 크롤링한 합격 후기의 실측 평균이 적용된 시험인가 (아니면 잠정 기준시간).
  final bool reviewBased;
  final int? reviewCount;
  final String? majorLabel, majorNote;
  final bool majorFallback;
  CatalogExam.from(Json j)
    : key = j['key'] as String,
      name = j['certificationName'] as String,
      suggested = DateTime.tryParse(j['suggestedExamDate'] as String? ?? ''),
      scheduleNote = j['scheduleNotice'] as String?,
      temporary = j['temporaryCatalog'] == true,
      evidence = (j['evidence'] as Json?)?['warning'] as String?,
      reviewBased = (j['evidence'] as Json?)?['status'] == 'REVIEW_VERIFIED',
      reviewCount = ((j['evidence'] as Json?)?['baselineAuthors'] as num?)
          ?.toInt(),
      majorLabel = (j['majorEvidence'] as Json?)?['userMajorLabel'] as String?,
      majorNote = (j['majorEvidence'] as Json?)?['warning'] as String?,
      majorFallback = (j['majorEvidence'] as Json?)?['fallback'] == true,
      subjects = rows(j['subjects']);
}

class Catalog {
  final List<CatalogExam> exams;
  final List<String> notices;
  final int? minutes;
  final String? majorLabel;
  Catalog.from(Json j)
    : exams = rows(j['goals']).map(CatalogExam.from).toList(),
      notices = strings(j['notices']),
      minutes = j['profileDailyMinutes'] as int?,
      majorLabel = j['loginMajorLabel'] as String?;
}

class Preview {
  final int requiredMinutes, missingMinutes;
  final bool feasible;
  final List<Json> days;
  final List<String> notices;
  final int? minimumDailyMinutes;
  final int additionalDailyMinutes;
  final List<Json> goals;
  late final List<Json> _orderedDays = [...days]
    ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
  int get calendarWeeks => _orderedDays.isEmpty
      ? 0
      : DateTime.parse(_orderedDays.last['date'])
                    .difference(DateTime.parse(_orderedDays.first['date']))
                    .inDays ~/
                7 +
            1;
  List<Json> weekAt(int index) {
    if (_orderedDays.isEmpty) return [];
    final start = plusDays(
      DateTime.parse(_orderedDays.first['date']),
      index * 7,
    );
    final byDate = {for (final day in _orderedDays) day['date'] as String: day};
    return List.generate(7, (i) {
      final date = isoDay(plusDays(start, i));
      return byDate[date] ??
          {'date': date, 'allocatedMinutes': 0, 'allocations': <Json>[]};
    });
  }

  Preview.from(Json j)
    : requiredMinutes = j['totalRemainingMinutes'] as int,
      missingMinutes = j['totalShortfallMinutes'] as int,
      feasible = j['feasible'] as bool,
      days = rows(j['days']),
      notices = strings(j['notices']),
      minimumDailyMinutes = j['minimumDailyMinutes'] as int?,
      additionalDailyMinutes = j['additionalDailyMinutes'] as int? ?? 0,
      goals = rows(j['goals'] ?? []);
}

/// 계획이 밀려 서버가 일정을 다시 짜 보라고 추천한 내용.
/// 밀린 시간이 계획 전체의 [threshold]% 이상일 때만 온다.
class ReplanAdvice {
  final String planName;
  final int totalMinutes, dueMinutes, doneMinutes, behindMinutes;
  final int percent, threshold;

  /// 남은 공부량을 오늘부터 다시 나눈 일정.
  final Preview proposal;
  ReplanAdvice.from(Json j)
    : this._(
        j['planName'] as String? ?? '학습계획',
        object(j['status']),
        Preview.from(object(j['proposal'])),
      );
  ReplanAdvice._(this.planName, Json status, this.proposal)
    : totalMinutes = status['totalMinutes'] as int,
      dueMinutes = status['dueMinutes'] as int,
      doneMinutes = status['doneMinutes'] as int,
      behindMinutes = status['behindMinutes'] as int,
      percent = status['behindPercent'] as int,
      threshold = status['thresholdPercent'] as int;
}

/// 채팅 안에서 계산한 계획과, 대화방에 남긴 요약 답변.
class ChatPlanReply {
  final Preview plan;
  final String answer;
  ChatPlanReply.from(Json j)
    : plan = Preview.from(object(j['plan'])),
      answer = j['answer'] as String? ?? '';
}

class Reply {
  final int conversation;
  final String answer;
  final bool llm;
  final List<String> sources;
  final String? notice;
  Reply.from(Json j)
    : conversation = j['conId'] as int,
      answer = j['answer'] as String,
      llm = j['llmUsed'] == true,
      notice = j['notice'] as String?,
      sources = strings(j['sources']);
}
