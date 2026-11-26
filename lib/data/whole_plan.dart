import 'models.dart';

class WholePlanSubject {
  final int key, minutes;
  final String name, exam;

  WholePlanSubject.from(Json json)
    : key = json['key'] as int,
      name = json['name'] as String,
      exam = json['exam'] as String? ?? '',
      minutes = json['minutes'] as int;
}

class WholePlanInput {
  final int id, version, protectedTasks;
  final String name;
  final DateTime today, start, end;
  final Map<int, int> weekdayMinutes;
  final List<WholePlanSubject> subjects;

  WholePlanInput.from(Json json)
    : id = json['planId'] as int,
      version = json['planVersion'] as int,
      protectedTasks = json['protectedTasks'] as int,
      name = json['planName'] as String? ?? '학습계획',
      today = DateTime.parse(json['today'] as String),
      start = DateTime.parse(json['startDate'] as String),
      end = DateTime.parse(json['endDate'] as String),
      weekdayMinutes = object(json['weekdayMinutes'])
          .map((day, minutes) => MapEntry(int.parse(day), minutes as int)),
      subjects = rows(json['subjects']).map(WholePlanSubject.from).toList();
}

class WholePlanAllocation {
  final String exam, subject;
  final DateTime date;
  final int minutes;

  WholePlanAllocation.from(Json json)
    : subject = json['subject'] as String,
      exam = json['exam'] as String? ?? '',
      minutes = json['minutes'] as int,
      date = DateTime.parse(json['date'] as String);
}

class WholePlanPreview {
  final String approval;
  final bool changed;
  final int protectedTasks;
  final List<WholePlanAllocation> removed, added;

  WholePlanPreview.from(Json json)
    : approval = json['approval'] as String,
      changed = json['changed'] == true,
      protectedTasks = json['protectedTasks'] as int,
      removed = rows(json['removed']).map(WholePlanAllocation.from).toList(),
      added = rows(json['added']).map(WholePlanAllocation.from).toList();
}
