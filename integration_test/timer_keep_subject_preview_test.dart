import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/data/study_models.dart';
import 'package:passpace_mobile/data/study_timer.dart';
import 'package:passpace_mobile/main.dart';
import 'package:passpace_mobile/ui/study_records.dart';

import '../test/study_records_test.dart' show tapStudy;
import '../test/study_timer_progress_test.dart' show planFor, progress;
import '../test/support/study_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('SAMPLE_KEEP_SUBJECT_PREVIEW · 선택 유지·바로 재측정', (t) async {
    late StudyFixture f;
    f = StudyFixture(
      empty: true,
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
    await f.session.restore();
    expect((await f.session.account!.saved())?.id, 5);
    var ticks = 0;
    var now = DateTime.utc(f.today.year, f.today.month, f.today.day, 1);
    final seed = StudyTimer(
      f.session.drafts,
      f.session.origin,
      f.session.user!.id,
      now: () => now,
      ticks: () => ticks,
    );
    await seed.restore();
    expect(await seed.choose(StudyTaskChoice.from(f.planTasks[1])), true);
    expect(await seed.start(), true);
    ticks = 900000;
    now = now.add(const Duration(minutes: 15));
    await seed.pause();
    expect(seed.minutes, 15);
    seed.dispose();
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
    Future<void> waitProgress(double expected) async {
      for (var i = 0; i < 50; i++) {
        if (((progress(t) ?? -1) - expected).abs() < .005) return;
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(progress(t), closeTo(expected, .005));
    }

    await waitProgress(.5);
    await tapStudy(t, find.text('기록 저장'));
    expect(f.history.single['durationMinutes'], 15);
    expect(find.byKey(const ValueKey('study-timer-clock')), findsOneWidget);
    expect(
      t
          .state<StudyRecordsScreenState>(find.byType(StudyRecordsScreen))
          .timer!
          .task
          ?.id,
      502,
    );
    expect(find.text('SAMPLE 데이터베이스'), findsOneWidget);
    await waitProgress(.5);
    expect(find.text('00:00:00'), findsOneWidget);
    expect(find.text('저장 15분 + 이번 측정 0초'), findsOneWidget);
    await binding.takeScreenshot('sample-after-first-save');

    await tapStudy(t, find.text('측정 시작'));
    final clock = t
        .state<StudyRecordsScreenState>(find.byType(StudyRecordsScreen))
        .timer!;
    await clock.alignElapsed(300000);
    await clock.pause();
    await t.pumpAndSettle();
    expect(clock.minutes, 5);
    await waitProgress(2 / 3);
    expect(find.textContaining('저장 15분 + 이번 측정 5분'), findsOneWidget);
    await binding.takeScreenshot('sample-cumulative-round');
    await tapStudy(t, find.text('기록 저장'));
    expect(f.history.length, 2);
    expect(
      f.history.fold<int>(0, (n, r) => n + (r['durationMinutes'] as int)),
      20,
    );
    expect(find.byKey(const ValueKey('study-timer-clock')), findsOneWidget);
    expect(
      t
          .state<StudyRecordsScreenState>(find.byType(StudyRecordsScreen))
          .timer!
          .task
          ?.id,
      502,
    );
    expect(find.text('SAMPLE 데이터베이스'), findsOneWidget);
    await waitProgress(2 / 3);
    expect(find.text('00:00:00'), findsOneWidget);
    expect(find.text('저장 20분 + 이번 측정 0초'), findsOneWidget);
    await binding.takeScreenshot('sample-after-second-save');
    expect(f.requests.where((r) => r.method == 'POST'), hasLength(2));
    binding.reportData ??= {};
    binding.reportData!.addAll({
      'mode': 'SAMPLE mock API on actual Android emulator',
      'checks': [
        'save-fifteen-stays-on-timer',
        'subject-retained-without-picker',
        'saved-fifteen-plus-current-five',
        'second-save-keeps-subject-and-twenty',
      ],
      'mockPosts': 2,
      'savedSubjectMinutes': 20,
      'realApiWrites': false,
      'measurementIsSynthetic': true,
    });
  });
}
