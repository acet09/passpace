import '../data/api.dart';
import '../data/study_history.dart';
import '../data/study_models.dart';

class StudyHistoryLinkError implements Exception {
  const StudyHistoryLinkError();
}

/// Reads saved minutes for the displayed day without changing stored records.
Future<int?> savedSubjectMinutes(
  PassApi api,
  DateTime date,
  StudyTaskChoice selected,
  List<StudyTaskChoice> active, {
  required bool Function() isCurrent,
}) async {
  final records = await readStudyHistory(api, date, date, isCurrent: isCurrent);
  if (records == null) return null;
  final tasks = {for (final task in active) task.id: task};
  final needsHistory = records.any(
    (r) =>
        r.taskId != null &&
        !(selected.subjectId != null && r.subjectId != null) &&
        !tasks.containsKey(r.taskId),
  );
  if (needsHistory) {
    // Historical links resolve saved records only; the picker remains ACTIVE-only.
    final history = await readStudyTaskChoices(
      api,
      includeReplaced: true,
      isCurrent: isCurrent,
    );
    if (history == null) return null;
    for (final task in history) {
      tasks[task.id] = task;
    }
    final current = tasks[selected.id];
    if (current == null ||
        current.status != 'ACTIVE' ||
        current.planId != selected.planId ||
        current.planVersion != selected.planVersion) {
      throw const StudyHistoryLinkError();
    }
  }
  bool sameSubject(StudyRecord record) {
    if (selected.subjectId != null && record.subjectId != null) {
      return selected.subjectId == record.subjectId;
    }
    if (record.taskId == null) return false;
    final linked = tasks[record.taskId];
    if (linked == null ||
        record.planId != null && record.planId != linked.planId ||
        record.subjectId != null &&
            linked.subjectId != null &&
            record.subjectId != linked.subjectId) {
      throw const StudyHistoryLinkError();
    }
    if (selected.subjectId != null && linked.subjectId != null) {
      return selected.subjectId == linked.subjectId;
    }
    final subject = selected.subjectName?.trim() ?? '',
        exam = selected.certificationName?.trim() ?? '';
    if (subject.isEmpty ||
        exam.isEmpty ||
        linked.subjectName?.trim().isNotEmpty != true ||
        linked.certificationName?.trim().isNotEmpty != true) {
      throw const StudyHistoryLinkError();
    }
    if (linked.subjectName!.trim() != subject ||
        linked.certificationName!.trim() != exam) {
      return false;
    }
    final knownIds = tasks.values
        .where(
          (t) =>
              t.subjectName?.trim() == subject &&
              t.certificationName?.trim() == exam,
        )
        .map((t) => t.subjectId)
        .whereType<int>()
        .toSet();
    if (knownIds.length > 1 ||
        selected.subjectId != null &&
            knownIds.any((id) => id != selected.subjectId)) {
      throw const StudyHistoryLinkError();
    }
    return true;
  }

  return records.where(sameSubject).fold<int>(0, (n, r) => n + r.minutes);
}
