import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/data/plan_draft.dart';
import 'package:passpace_mobile/data/plan_comparison.dart';

import 'support/draft_storage.dart';

void main() {
  test('초안은 재실행 후 복원되고 서버·계정별로 분리된다', () async {
    final storage = MemoryDraftStorage();
    final repo = PlanDraftRepository(
      storage,
      'https://team.example.com/',
      'first',
    );
    final draft = PlannerDraft(
      minutes: '9',
      weekdays: {1, 3, 5},
      step: 2,
      updatedAt: DateTime.utc(2026, 11, 15),
      exams: {
        'sqld': ExamDraft(
          DateTime(2026, 11, 15),
          DateTime(2026, 12, 15),
          selected: true,
          familiarity: {'SQL 활용': 2},
          progress: {'SQL 활용': 30},
          actual: {'SQL 활용': 87},
        ),
      },
    );
    await repo.save(draft);
    final reopened = PlanDraftRepository(
      storage,
      'https://team.example.com',
      'first',
    );
    final restored = (await reopened.read())!;
    expect(restored.minutes, '9');
    expect(restored.weekdays, {1, 3, 5});
    expect(restored.step, 2);
    expect(restored.exams['sqld']!.actual['SQL 활용'], 87);
    expect(
      await PlanDraftRepository(
        storage,
        'https://team.example.com',
        'second',
      ).read(),
      isNull,
    );
    expect(
      await PlanDraftRepository(
        storage,
        'https://other.example.com',
        'first',
      ).read(),
      isNull,
    );
    await reopened.clear();
    expect(await repo.read(), isNull);
  });
  test('이해도는 같은 과목 ID에 대해서만 불러온다', () {
    final e = CatalogExam.from({
      'key': 'a',
      'certificationName': 'SQLD',
      'subjects': [
        {'subjectId': 11, 'name': 'SQL 활용', 'baseHours': 10},
        {'subjectId': 99, 'name': '다른 과목', 'baseHours': 10},
      ],
    });
    final goal = GoalData.from({
      'goal': {
        'familiarity': {'11': 3, '12': 1},
      },
      'examRounds': [],
      'subjects': [],
    });
    expect(savedFamiliarity(e, goal), {'SQL 활용': 3});
  });
  test('손상되거나 호환되지 않는 초안을 조용히 덮어쓰지 않는다', () async {
    final storage = MemoryDraftStorage();
    final repo = PlanDraftRepository(
      storage,
      'https://team.example.com',
      'first',
    );
    storage.values[repo.key] = jsonEncode({'schema': 99});
    await expectLater(repo.read(), throwsFormatException);
    expect(storage.values, contains(repo.key));
  });
  test('계획 비교는 중복 과목 합산과 날짜별 추가·제외·시간 변경을 구분한다', () {
    final old = SavedPlan.from({
      'planId': 1,
      'planName': '기존',
      'versionNo': 1,
      'startDate': '2026-11-15',
      'endDate': '2026-11-20',
      'tasks': [
        {
          'date': '2026-11-15',
          'certificationName': 'SQLD',
          'subjectName': '모델링',
          'minutes': 20,
        },
        {
          'date': '2026-11-15',
          'certificationName': 'SQLD',
          'subjectName': '모델링',
          'minutes': 40,
        },
        {
          'date': '2026-11-15',
          'certificationName': 'SQLD',
          'subjectName': 'SQL 활용',
          'minutes': 30,
        },
        {
          'date': '2026-11-16',
          'certificationName': '정보처리기사',
          'subjectName': '소프트웨어',
          'minutes': 45,
        },
      ],
    });
    final next = Preview.from({
      'totalRemainingMinutes': 200,
      'totalShortfallMinutes': 10,
      'feasible': false,
      'notices': [],
      'days': [
        {
          'date': '2026-11-15',
          'allocations': [
            {'certificationName': 'SQLD', 'subjectName': '모델링', 'minutes': 60},
            {
              'certificationName': 'SQLD',
              'subjectName': 'SQL 활용',
              'minutes': 50,
            },
          ],
        },
        {
          'date': '2026-11-17',
          'allocations': [
            {
              'certificationName': '정보처리기사',
              'subjectName': '소프트웨어',
              'minutes': 45,
            },
          ],
        },
      ],
    });
    final diff = PlanComparison(old, next);
    expect(diff.beforeMinutes, 135);
    expect(diff.afterMinutes, 155);
    expect(diff.added, 1);
    expect(diff.removed, 1);
    expect(diff.adjusted, 1);
    expect(diff.changes.map((v) => v.key.date), [
      '2026-11-15',
      '2026-11-16',
      '2026-11-17',
    ]);
    expect(diff.changes.first.before, 30);
    expect(PlanComparison.samePlan(old, old), true);
    final another = SavedPlan.from({
      'planId': 2,
      'planName': '기존',
      'versionNo': 2,
      'startDate': '2026-11-15',
      'endDate': '2026-11-20',
      'tasks': [],
    });
    expect(PlanComparison.samePlan(old, another), false);
    expect(PlanComparison(null, next).afterMinutes, 155);
  });
}
