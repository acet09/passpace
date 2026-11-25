import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/data/session.dart';
import 'package:passpace_mobile/main.dart';
import 'package:passpace_mobile/ui/plan_month_calendar.dart';
import 'package:passpace_mobile/ui/study_timer_screen.dart';

import '../test/support/draft_storage.dart';

class _Store implements SessionStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
}

class _Client extends http.BaseClient {
  final delegate = http.Client();
  int recordsPosted = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) {
    if (r.method == 'POST' && r.url.path == '/study/sessions') recordsPosted++;
    return delegate.send(r);
  }

  @override
  void close() => delegate.close();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const origin = String.fromEnvironment('STUDY_TEST_ORIGIN');
  const id = String.fromEnvironment('STUDY_TEST_ID');
  const password = String.fromEnvironment('STUDY_TEST_PASSWORD');
  const isolated = bool.fromEnvironment('STUDY_TEST_ISOLATED');
  testWidgets('격리 실제 API:직접 타이머·알림·홈 월간·계획 월간', (t) async {
    final uri = Uri.tryParse(origin);
    if (!isolated ||
        uri?.host != '10.0.2.2' ||
        uri?.scheme != 'http' ||
        [8080, 18080, 3306, 3308].contains(uri?.port) ||
        !id.startsWith('app_verify_') ||
        password.isEmpty) {
      throw StateError('합성 계정이 있는 격리 API만 사용할 수 있습니다.');
    }
    final client = _Client();
    addTearDown(client.close);
    final session = Session(_Store(), client, drafts: MemoryDraftStorage());
    addTearDown(session.dispose);
    await session.changeOrigin(origin);
    await session.signIn(id, password);
    final api = session.account!,
        today = dayInSeoul(),
        start = plusDays(dayInSeoul(), -6);
    final original = (await api.studySessions(today, today)).items.single;
    final before = await api.studyStats(start, today);
    final page0 = await api.studyPlanTasks(),
        page1 = await api.studyPlanTasks(page: 1);
    expect(page0.items.length + page1.items.length, 64);
    expect(page0.hasNext, true);
    expect(page1.hasNext, false);
    await t.pumpWidget(PassPaceApp(session));
    await t.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    Future<void> tap(Finder finder) async {
      if (finder.evaluate().isEmpty) {
        await t.scrollUntilVisible(
          finder,
          250,
          scrollable: find.byType(Scrollable).hitTestable().first,
        );
      }
      await t.ensureVisible(finder);
      await t.pumpAndSettle();
      await t.tap(finder);
      await t.pumpAndSettle();
    }

    Future<void> capture(String name) async {
      await t.pumpAndSettle();
      await binding.takeScreenshot(name);
    }

    await tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('기록'),
      ),
    );
    await capture('live-navigation-records');
    await tap(find.text('과목 선택'));
    expect(find.text('4개 과목'), findsOneWidget);
    expect(find.text('전체 일정'), findsNothing);
    for (final subject in [
      'SAMPLE 소프트웨어 설계',
      'SAMPLE 데이터베이스',
      'SAMPLE 프로그래밍',
      'SAMPLE 정보시스템',
    ]) {
      expect(find.text(subject), findsOneWidget);
    }
    await capture('live-navigation-subjects');
    await tap(find.text('SAMPLE 데이터베이스'));
    await tap(find.text('측정 시작'));
    await capture('live-navigation-running');
    await tap(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('홈')),
    );
    debugPrint('SAMPLE_NOTIFICATION_READY');
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 31)));
    await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 31)));
    await t.pumpAndSettle();
    final clock = t
        .widget<StudyTimerScreen>(find.byType(StudyTimerScreen))
        .timer;
    expect(clock.elapsed.inSeconds, greaterThanOrEqualTo(60));
    expect(
      t.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    await tap(find.text('일시정지'));
    final measured = clock.minutes, task = clock.task;
    expect(task, isNotNull);
    expect(measured, greaterThanOrEqualTo(1));
    await capture('live-navigation-paused');
    debugPrint('SAMPLE_NOTIFICATION_PAUSED');
    await tap(find.text('기록 저장'));
    final added = (await api.studySessions(
      today,
      today,
    )).items.singleWhere((r) => r.id != original.id);
    expect(added.minutes, measured);
    expect(added.taskId, task!.id);
    expect(added.subjectName, 'SAMPLE 데이터베이스');
    expect(client.recordsPosted, 1);
    final after = await api.studyStats(start, today);
    expect(after.totalMinutes, before.totalMinutes + measured);
    ScaffoldMessenger.of(t.element(find.byKey(const ValueKey('study-view-0'))))
        .hideCurrentSnackBar();
    await capture('live-navigation-saved');
    final scroll = find
        .descendant(
          of: find.byKey(const ValueKey('study-view-0')),
          matching: find.byType(Scrollable),
        )
        .first;
    t.state<ScrollableState>(scroll).position.jumpTo(0);
    await t.pumpAndSettle();
    await tap(find.text('개인 통계'));
    expect(find.textContaining('한국 시간'), findsNothing);
    expect(
      t.widget<Text>(find.byKey(const ValueKey('study-total'))).data,
      durationLabel(after.totalMinutes),
    );
    await t.ensureVisible(find.byKey(ValueKey('study-day-${isoDay(today)}')));
    await t.pumpAndSettle();
    await capture('live-navigation-daily');
    expect(find.text('일별 공부시간'), findsOneWidget);
    expect(t.takeException(), isNull);
    await tap(
      find.descendant(of: find.byType(NavigationBar), matching: find.text('홈')),
    );
    expect(find.byType(PlanMonthCalendar), findsNothing);
    await capture('live-navigation-home-today');
    await tap(find.text('학습 일정 보기'));
    await tap(find.text('전체 일정'));
    await t.ensureVisible(find.byKey(const ValueKey('plan-month-calendar')));
    await t.pumpAndSettle();
    await capture('live-navigation-plan-month');
    await tap(find.byTooltip('다음 달'));
    await capture('live-navigation-plan-next-month');
    await tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('기록'),
      ),
    );
    expect(find.byKey(const ValueKey('study-timer-clock')), findsOneWidget);
    expect(find.byKey(const ValueKey('study-total')), findsNothing);
    expect(t.takeException(), isNull);
    binding.reportData = {
      ...?binding.reportData,
      'mode': 'isolated actual API and Android notification',
      'checks': [
        'record-tab-direct-timer',
        '64-tasks-four-subjects',
        'notification-tap-returns-from-home',
        'actual-one-minute-and-one-POST',
        'separate-history-and-statistics',
        'home-today-and-plan-link',
        'plan-month',
        'plan-next-month',
        'record-tab-reentry-direct-timer',
      ],
      'measuredMinutes': measured,
      'productionWrites': false,
    };
  });
}
