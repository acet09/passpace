import 'models.dart';

typedef ScheduleKey = ({String date, String exam, String subject});

class ScheduleChange {
  final ScheduleKey key;
  final int before, after;
  const ScheduleChange(this.key, this.before, this.after);
  String get label => before == 0
      ? '추가'
      : after == 0
      ? '제외'
      : '시간 변경';
}

class PlanComparison {
  final SavedPlan? previous;
  final Map<ScheduleKey, int> before, after;
  late final List<ScheduleChange> changes = _changes();
  PlanComparison(this.previous, Preview preview)
    : before = savedSchedule(previous),
      after = previewSchedule(preview);
  int get beforeMinutes => before.values.fold(0, (a, b) => a + b);
  int get afterMinutes => after.values.fold(0, (a, b) => a + b);
  int get added => changes.where((c) => c.before == 0).length;
  int get removed => changes.where((c) => c.after == 0).length;
  int get adjusted => changes.length - added - removed;
  List<ScheduleChange> _changes() {
    final keys = {...before.keys, ...after.keys}.toList()
      ..sort((a, b) {
        final date = a.date.compareTo(b.date);
        if (date != 0) return date;
        final exam = a.exam.compareTo(b.exam);
        return exam != 0 ? exam : a.subject.compareTo(b.subject);
      });
    return [
      for (final key in keys)
        if ((before[key] ?? 0) != (after[key] ?? 0))
          ScheduleChange(key, before[key] ?? 0, after[key] ?? 0),
    ];
  }

  static Map<ScheduleKey, int> savedSchedule(SavedPlan? plan) {
    final result = <ScheduleKey, int>{};
    for (final task in plan?.byDay.values.expand((v) => v) ?? <StudyTask>[]) {
      final key = (
        date: isoDay(task.date),
        exam: task.exam,
        subject: task.subject,
      );
      result.update(key, (n) => n + task.minutes, ifAbsent: () => task.minutes);
    }
    return result;
  }

  static Map<ScheduleKey, int> previewSchedule(Preview preview) {
    final result = <ScheduleKey, int>{};
    for (final day in preview.days) {
      for (final a in rows(day['allocations'])) {
        final key = (
          date: day['date'] as String,
          exam: a['certificationName'] as String? ?? '',
          subject: a['subjectName'] as String,
        );
        final minutes = a['minutes'] as int;
        result.update(key, (n) => n + minutes, ifAbsent: () => minutes);
      }
    }
    return result;
  }

  static bool samePlan(SavedPlan? a, SavedPlan? b) {
    if (a == null || b == null) return a == null && b == null;
    if (a.id != b.id ||
        a.version != b.version ||
        a.name != b.name ||
        a.start != b.start ||
        a.end != b.end) {
      return false;
    }
    final left = savedSchedule(a), right = savedSchedule(b);
    return left.length == right.length &&
        left.entries.every((e) => right[e.key] == e.value);
  }
}
