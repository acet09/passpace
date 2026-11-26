import 'api.dart';
import 'study_models.dart';

Future<List<StudyTaskChoice>?> readStudyTaskChoices(
  PassApi api, {
  DateTime? date,
  bool includeReplaced = false,
  Set<int>? taskIds,
  required bool Function() isCurrent,
}) async {
  final choices = <int, StudyTaskChoice>{};
  for (var page = 0; page <= 10000; page++) {
    final result = await api.studyPlanTasks(
      date: date,
      includeReplaced: includeReplaced,
      page: page,
    );
    if (!isCurrent()) return null;
    if (result.page != page) {
      throw const FormatException('Unexpected study task page');
    }
    for (final choice in result.items) {
      if (taskIds == null || taskIds.contains(choice.id)) {
        choices[choice.id] = choice;
      }
    }
    if (!result.hasNext ||
        (taskIds != null && choices.length == taskIds.length)) {
      return choices.values.toList();
    }
    if (result.items.isEmpty) break;
  }
  throw const FormatException('Incomplete study task list');
}

/// Reads a complete range without using stale results after a date or account change.
Future<List<StudyRecord>?> readStudyHistory(
  PassApi api,
  DateTime start,
  DateTime end, {
  required bool Function() isCurrent,
  int pageSize = 20,
}) async {
  final records = <int, StudyRecord>{};
  for (var page = 0; page <= 10000; page++) {
    final result = await api.studySessions(
      start,
      end,
      page: page,
      pageSize: pageSize,
    );
    if (!isCurrent()) return null;
    if (result.page != page ||
        result.items.any(
          (r) => r.date.isBefore(start) || r.date.isAfter(end),
        )) {
      throw const FormatException('Unexpected study history page');
    }
    for (final record in result.items) {
      final old = records[record.id];
      if (old != null &&
          (
                old.date,
                old.minutes,
                old.taskId,
                old.planId,
                old.subjectId,
                old.subjectName,
              ) !=
              (
                record.date,
                record.minutes,
                record.taskId,
                record.planId,
                record.subjectId,
                record.subjectName,
              )) {
        throw const FormatException('Study record changed between pages');
      }
      records[record.id] = record;
    }
    if (!result.hasNext) return records.values.toList();
    if (page == 10000 || result.items.isEmpty) {
      throw const FormatException('Incomplete study history');
    }
  }
  throw const FormatException('Incomplete study history');
}
