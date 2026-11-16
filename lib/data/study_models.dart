import 'models.dart';

DateTime studyDate(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw const FormatException('Invalid study date');
  }
  final date = DateTime.tryParse(value);
  if (date == null || isoDay(date) != value || date.year < 1000) {
    throw const FormatException('Invalid study date');
  }
  return date;
}

int _integer(Object? value, int min, int max) {
  if (value is! int || value < min || value > max) {
    throw const FormatException('Invalid study number');
  }
  return value;
}

int? _id(Object? value) =>
    value == null ? null : _integer(value, 1, 0x7fffffffffffffff);

class StudyRecord {
  final int id, minutes;
  final DateTime date;
  final int? taskId, planId, subjectId;
  final String? subjectName, inputMethod;

  StudyRecord.from(Json data)
    : id = _integer(data['sessionId'], 1, 0x7fffffffffffffff),
      date = studyDate(data['studyDate']),
      minutes = _integer(data['durationMinutes'], 1, 1440),
      taskId = _id(data['taskId']),
      planId = _id(data['planId']),
      subjectId = _id(data['subjectId']),
      subjectName = data['subjectName'] as String?,
      inputMethod = data['inputMethod'] as String?;
}

class StudyRecordPage {
  final List<StudyRecord> items;
  final int page, pageSize;
  final bool hasNext;

  StudyRecordPage.from(Json data)
    : items = List.unmodifiable(rows(data['items']).map(StudyRecord.from)),
      page = _integer(data['page'], 0, 10000),
      pageSize = _integer(data['pageSize'], 1, 100),
      hasNext = data['hasNext'] as bool;
}

class StudyTaskChoice {
  final int id, planId, planVersion;
  final int? subjectId;
  final String? planName, subjectName, certificationName;
  final String status;
  final DateTime? scheduledDate;
  StudyTaskChoice.from(Json data)
    : id = _integer(data['taskId'], 1, 0x7fffffffffffffff),
      planId = _integer(data['planId'], 1, 0x7fffffffffffffff),
      planVersion = _integer(data['planVersion'], 1, 0x7fffffff),
      subjectId = _id(data['subjectId']),
      planName = data['planName'] as String?,
      subjectName = data['subjectName'] as String?,
      certificationName = data['certificationName'] as String?,
      scheduledDate = data['scheduledDate'] == null
          ? null
          : studyDate(data['scheduledDate']),
      status = data['planStatus'] as String {
    if (status != 'ACTIVE' && status != 'REPLACED') {
      throw const FormatException('Invalid selectable plan');
    }
  }
  String get name =>
      subjectName?.trim().isNotEmpty == true ? subjectName! : '과목 이름 없음';
  Json toJson() => {
    'taskId': id,
    'planId': planId,
    'planVersion': planVersion,
    'subjectId': subjectId,
    'subjectName': subjectName,
    'planName': planName,
    'certificationName': certificationName,
    'scheduledDate': scheduledDate == null ? null : isoDay(scheduledDate!),
    'planStatus': status,
  };
}

class StudyTaskPage {
  final List<StudyTaskChoice> items;
  final int page, pageSize;
  final bool hasNext;
  StudyTaskPage.from(Json data)
    : items = List.unmodifiable(rows(data['items']).map(StudyTaskChoice.from)),
      page = _integer(data['page'], 0, 10000),
      pageSize = _integer(data['pageSize'], 1, 100),
      hasNext = data['hasNext'] as bool;
}

/// Shows each subject once while preserving an actual, owned task reference.
List<StudyTaskChoice> distinctStudySubjects(
  Iterable<StudyTaskChoice> tasks,
  DateTime date, {
  int? selectedId,
}) {
  final groups = <String, StudyTaskChoice>{};
  String identity(StudyTaskChoice task) {
    final name = task.subjectName?.trim() ?? '';
    final exam = task.certificationName?.trim() ?? '';
    if (task.subjectId != null) return 'id:${task.subjectId}';
    if (name.isEmpty) return 'task:${task.id}';
    final scope = exam.isEmpty ? 'plan:${task.planId}' : 'exam:$exam';
    return '$scope\u0000$name';
  }

  int compare(StudyTaskChoice a, StudyTaskChoice b) {
    if (a.id == selectedId) return -1;
    if (b.id == selectedId) return 1;
    if (a.status != b.status) return a.status == 'ACTIVE' ? -1 : 1;
    final ad = a.scheduledDate?.difference(date).inDays;
    final bd = b.scheduledDate?.difference(date).inDays;
    final distance = (ad?.abs() ?? 0x7fffffff).compareTo(
      bd?.abs() ?? 0x7fffffff,
    );
    if (distance != 0) return distance;
    if (ad != null && bd != null && ad != bd) return ad.compareTo(bd);
    return a.id.compareTo(b.id);
  }

  for (final task in tasks) {
    final key = identity(task), old = groups[identity(task)];
    if (old == null || compare(task, old) < 0) groups[key] = task;
  }
  return List.unmodifiable(groups.values);
}

class StudyDay {
  final DateTime date;
  final int minutes;
  StudyDay.from(Json data)
    : date = studyDate(data['studyDate']),
      minutes = _integer(data['durationMinutes'], 0, 1440);
}

class StudyStats {
  final DateTime start, end;
  final int totalMinutes;
  final List<StudyDay> days;

  StudyStats._(this.start, this.end, this.totalMinutes, this.days);

  factory StudyStats.from(Json data) {
    final start = studyDate(data['startDate']);
    final end = studyDate(data['endDate']);
    final total = _integer(data['totalMinutes'], 0, 1440 * 366);
    final days = rows(data['dailyStudyMinutes']).map(StudyDay.from).toList();
    if (data['timezone'] != 'Asia/Seoul' ||
        end.isBefore(start) ||
        days.isEmpty ||
        days.length > 366) {
      throw const FormatException('Invalid study statistics');
    }
    var date = start;
    var checkedTotal = 0;
    for (final day in days) {
      if (day.date != date) {
        throw const FormatException('Missing study statistics day');
      }
      checkedTotal += day.minutes;
      date = plusDays(date, 1);
    }
    // Validate the contract; the UI displays the server's total, not a new metric.
    if (days.last.date != end || checkedTotal != total) {
      throw const FormatException('Inconsistent study statistics');
    }
    return StudyStats._(start, end, total, List.unmodifiable(days));
  }
}
