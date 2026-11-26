import 'dart:convert';

import 'models.dart';
import 'plan_draft.dart';

class SubjectColorPreferences {
  static const storageKind = 'subject-colors';
  final PlanDraftStorage storage;
  final String key;

  SubjectColorPreferences(this.storage, String origin, String loginId)
    : key = accountStorageKey(storageKind, origin, loginId);

  // The saved plan sends names, but no reusable subject ID. Task IDs identify
  // individual allocations and may change when the plan is rebuilt.
  static String subjectKey(StudyTask task) =>
      keyForNames(task.exam, task.subject);

  static String keyForNames(String? exam, String subject) =>
      jsonEncode([exam?.trim() ?? '', subject.trim()]);

  Future<Map<String, String>> read() async {
    final stored = await storage.read(key);
    if (stored == null) return {};
    try {
      final colors = jsonDecode(stored);
      if (colors is! Map<String, dynamic>) return {};
      return {
        for (final entry in colors.entries)
          if (entry.value case final String value) entry.key: value,
      };
    } on FormatException {
      return {};
    }
  }

  Future<void> save(Map<String, String> colors) =>
      storage.write(key, colors.isEmpty ? null : jsonEncode(colors));
}
