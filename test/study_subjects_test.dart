import 'package:flutter_test/flutter_test.dart';
import 'package:passpace_mobile/data/study_models.dart';

StudyTaskChoice choice(
  int id,
  String subject,
  String date, {
  String exam = 'SAMPLE 자격증',
  int? subjectId,
  String status = 'ACTIVE',
}) => StudyTaskChoice.from({
  'taskId': id,
  'planId': 5,
  'planVersion': 3,
  'subjectId': subjectId,
  'subjectName': subject,
  'certificationName': exam,
  'scheduledDate': date,
  'planStatus': status,
});

void main() {
  final day = DateTime(2026, 11, 16);
  test('날짜별 반복4과목은 과목4개만 남기고 가까운 실제 항목에 연결한다', () {
    final tasks = [
      for (var d = 10; d <= 20; d++)
        for (var s = 0; s < 4; s++) choice(d * 10 + s, '과목$s', '2026-11-$d'),
    ];
    final result = distinctStudySubjects(tasks, day);
    expect(result.map((s) => s.name), ['과목0', '과목1', '과목2', '과목3']);
    expect(result.map((s) => s.id), [160, 161, 162, 163]);
  });
  test('기존 연결은 같은 과목의 날짜가 더 가까워도 그대로 유지한다', () {
    final result = distinctStudySubjects(
      [choice(1, '과목', '2026-11-10'), choice(2, '과목', '2026-11-16')],
      day,
      selectedId: 1,
    );
    expect(result.single.id, 1);
  });
  test('다른 자격증의 같은 과목명과 서로 다른 과목 ID는 합치지 않는다', () {
    final result = distinctStudySubjects([
      choice(1, '과목', '2026-11-16', exam: '시험A'),
      choice(2, '과목', '2026-11-16', exam: '시험B'),
      choice(3, '과목', '2026-11-16', exam: '시험B', subjectId: 30),
      choice(4, '과목', '2026-11-16', exam: '시험B', subjectId: 40),
    ], day);
    expect(result, hasLength(4));
  });
  test('현재 계획을 이전 계획보다 우선하고 이름 없는 항목을 임의로 합치지 않는다', () {
    final result = distinctStudySubjects([
      choice(1, '과목', '2026-11-16', status: 'REPLACED'),
      choice(2, '과목', '2026-11-15'),
      choice(3, '', '2026-11-16'),
      choice(4, '', '2026-11-16'),
    ], day);
    expect(result.map((s) => s.id), [2, 3, 4]);
  });
}
