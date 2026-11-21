import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/data/study_models.dart';
import 'package:passpace_mobile/data/study_timer.dart';
import 'package:passpace_mobile/main.dart';
import 'package:passpace_mobile/ui/study_records.dart';
import 'package:passpace_mobile/ui/study_timer_progress.dart';

import '../test/study_records_test.dart' show tapStudy;
import '../test/study_timer_progress_test.dart' show planFor;
import '../test/support/study_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('SAMPLE_TIMER_RING_PREVIEW · 실제 Android의 모의 배정 원형 표시', (t) async {
    late StudyFixture f;
    f = StudyFixture(
      override: (r) async {
        if (r.url.path != '$plannerPath/saved') return null;
        final plan = planFor(f);
        plan['tasks'] = <Json>[
          ...rows(plan['tasks']),
          {
            'date': isoDay(plusDays(f.today, 1)),
            'certificationName': 'SAMPLE 기사',
            'subjectName': f.planTasks.first['subjectName'],
            'minutes': 30,
          },
        ];
        return studyEnvelope({'plan': plan});
      },
    );
    addTearDown(f.dispose);
    f.planTasks.add({
      ...f.planTasks[1],
      'taskId': 999,
      'subjectName': 'SAMPLE 이전 과목',
      'planStatus': 'REPLACED',
    });
    await f.session.restore();
    expect((await f.session.account!.saved())?.id, 5);
    var ticks = 0;
    var now = DateTime.utc(f.today.year, f.today.month, f.today.day, 1);
    final clock = StudyTimer(
      f.session.drafts,
      f.session.origin,
      f.session.user!.id,
      now: () => now,
      ticks: () => ticks,
    );
    await clock.restore();
    expect(await clock.choose(StudyTaskChoice.from(f.planTasks[1])), true);
    expect(await clock.start(), true);
    ticks = 900000;
    now = now.add(const Duration(minutes: 15));
    expect(await clock.pause(), true);
    expect(clock.minutes, 15);
    clock.dispose();
    await t.pumpWidget(PassPaceApp(f.session));
    await t.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await tapStudy(
      t,
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('기록'),
      ),
    );
    for (var attempt = 0; attempt < 50; attempt++) {
      final value = t
          .widget<CircularProgressIndicator>(
            find.byKey(const ValueKey('study-timer-progress')),
          )
          .value;
      if (value == .5) break;
      await t.pump(const Duration(milliseconds: 100));
    }
    final restored = t
        .state<StudyRecordsScreenState>(find.byType(StudyRecordsScreen))
        .timer!;
    final view = t.widget<StudyTimerProgress>(find.byType(StudyTimerProgress));
    debugPrint(
      'SAMPLE_RING_DIAGNOSTIC phase=${restored.phase.name},minutes=${restored.minutes},task=${restored.task?.id},date=${restored.date},active=${view.active},canRead=${view.canRead()},messages=${find.byType(Text).evaluate().map((e) => (e.widget as Text).data ?? '').where((s) => s.contains('배정') || s.contains('선택') || s.contains('계획')).join('|')},reads=${f.requests.map((r) => r.url.path).join('|')}',
    );
    expect(
      t
          .widget<CircularProgressIndicator>(
            find.byKey(const ValueKey('study-timer-progress')),
          )
          .value,
      .5,
    );
    expect(find.text('00:15:00'), findsOneWidget);
    expect(find.text('배정 30분'), findsOneWidget);
    await binding.takeScreenshot('sample-timer-half');
    await tapStudy(t, find.text('과목 선택'));
    expect(find.text('이전 계획 포함'), findsNothing);
    expect(find.text('SAMPLE 이전 과목'), findsNothing);
    expect(find.text('2개 과목'), findsOneWidget);
    await binding.takeScreenshot('sample-current-subjects');
    expect(f.requests.where((r) => r.method != 'GET'), isEmpty);
    binding.reportData ??= {};
    binding.reportData!.addAll({
      'mode': 'SAMPLE mock API on actual Android emulator',
      'checks': [
        '15-of-30-minutes-half-circle',
        'paused-clock-preserved',
        'active-subjects-only',
        'previous-plan-option-absent',
      ],
      'realApiWrites': false,
      'measurementIsSynthetic': true,
    });
  });
}
