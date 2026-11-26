import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

String accountStorageKey(String kind, String origin, String loginId) =>
    'passpace.$kind.v1.${base64Url.encode(utf8.encode('${Uri.parse(origin).origin}\n$loginId'))}';

abstract interface class PlanDraftStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class SecurePlanDraftStorage implements PlanDraftStorage {
  final _storage = const FlutterSecureStorage();
  Future<void> _pending = Future.value();
  @override
  Future<String?> read(String key) async {
    await _pending;
    return _storage.read(key: key);
  }

  @override
  Future<void> write(String key, String? value) {
    final operation = _pending.then(
      (_) => value == null
          ? _storage.delete(key: key)
          : _storage.write(key: key, value: value),
    );
    _pending = operation.catchError((Object _) {});
    return operation;
  }
}

class PlanDraftRepository {
  final PlanDraftStorage storage;
  final String key;
  PlanDraftRepository(this.storage, String origin, String userId)
    : key = accountStorageKey('plan-draft', origin, userId);
  Future<PlannerDraft?> read() async {
    final value = await storage.read(key);
    return value == null
        ? null
        : PlannerDraft.fromJson(object(jsonDecode(value)));
  }

  Future<void> save(PlannerDraft value) =>
      storage.write(key, jsonEncode(value.toJson()));
  Future<void> clear() => storage.write(key, null);
}

class ExamDraft {
  DateTime start;
  DateTime? end;
  bool selected;
  final Map<String, int> familiarity, progress, actual;
  ExamDraft(
    this.start,
    this.end, {
    this.selected = false,
    Map<String, int>? familiarity,
    Map<String, int>? progress,
    Map<String, int>? actual,
  }) : familiarity = familiarity ?? {},
       progress = progress ?? {},
       actual = actual ?? {};
  factory ExamDraft.fromJson(Json j) => ExamDraft(
    DateTime.parse(j['start'] as String),
    DateTime.tryParse(j['end'] as String? ?? ''),
    selected: j['selected'] as bool,
    familiarity: Map<String, int>.from(j['familiarity'] as Map),
    progress: Map<String, int>.from(j['progress'] as Map),
    actual: Map<String, int>.from(j['actual'] as Map),
  );
  Json toJson() => {
    'start': isoDay(start),
    'end': end == null ? null : isoDay(end!),
    'selected': selected,
    'familiarity': Map<String, int>.of(familiarity),
    'progress': Map<String, int>.of(progress),
    'actual': Map<String, int>.of(actual),
  };
}

class PlannerDraft {
  final String minutes;
  final Set<int> weekdays;
  final Map<int, String>? weekdayInputs;
  final Map<String, ExamDraft> exams;
  final int step;
  final DateTime updatedAt;
  PlannerDraft({
    required this.minutes,
    required this.weekdays,
    this.weekdayInputs,
    required this.exams,
    required this.step,
    required this.updatedAt,
  });
  factory PlannerDraft.fromJson(Json j) {
    if (j['schema'] != 1) throw const FormatException('Unsupported plan draft');
    final step = j['step'] as int;
    final weekdays = (j['weekdays'] as List).cast<int>().toSet();
    if (step < 0 || step > 2 || weekdays.any((d) => d < 1 || d > 7)) {
      throw const FormatException('Invalid plan draft');
    }
    return PlannerDraft(
      minutes: j['minutes'] as String,
      weekdays: weekdays,
      weekdayInputs: j['weekdayInputs'] == null
          ? null
          : object(j['weekdayInputs']).map((key, value) {
              final day = int.tryParse(key);
              if (day == null ||
                  day < 1 ||
                  day > 7 ||
                  value is! String ||
                  !RegExp(r'^\d{0,3}$').hasMatch(value)) {
                throw const FormatException('Invalid weekday draft');
              }
              return MapEntry(day, value);
            }),
      exams: object(
        j['exams'],
      ).map((key, value) => MapEntry(key, ExamDraft.fromJson(object(value)))),
      step: step,
      updatedAt: DateTime.parse(j['updatedAt'] as String),
    );
  }
  Json toJson() => {
    'schema': 1,
    'minutes': minutes,
    'weekdays': weekdays.toList()..sort(),
    if (weekdayInputs case final inputs?)
      'weekdayInputs': inputs.map((day, text) => MapEntry('$day', text)),
    'exams': exams.map((k, v) => MapEntry(k, v.toJson())),
    'step': step,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

/// Reuses only subject IDs returned by both existing server endpoints.
Map<String, int> savedFamiliarity(CatalogExam exam, GoalData goal) => {
  for (final subject in exam.subjects)
    if (goal.familiarity[subject['subjectId']?.toString()] case final int level
        when level >= 1 && level <= 3)
      subject['name'] as String: level,
};
