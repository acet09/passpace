import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/data/session.dart';
import 'package:passpace_mobile/main.dart';

import '../test/support/draft_storage.dart';

class _ActionsStore implements SessionStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const origin = String.fromEnvironment('STUDY_TEST_ORIGIN');
  const id = String.fromEnvironment('STUDY_TEST_ID');
  const password = String.fromEnvironment('STUDY_TEST_PASSWORD');
  const isolated = bool.fromEnvironment('STUDY_TEST_ISOLATED');
  testWidgets('격리 실제 API: 기존·신규 과목 연결·삭제 취소·삭제·통계', (t) async {
    final uri = Uri.tryParse(origin);
    if (!isolated ||
        uri?.host != '10.0.2.2' ||
        uri?.scheme != 'http' ||
        [8080, 18080, 3306, 3308].contains(uri?.port) ||
        !id.startsWith('app_verify_') ||
        password.isEmpty) {
      throw StateError('합성 계정이 있는 격리 API만 사용할 수 있습니다.');
    }
    final client = http.Client();
    addTearDown(client.close);
    final session = Session(
      _ActionsStore(),
      client,
      drafts: MemoryDraftStorage(),
    );
    addTearDown(session.dispose);
    await session.changeOrigin(origin);
    await session.signIn(id, password);
    final api = session.account!, today = dayInSeoul();
    final start = plusDays(today, -6);
    final original = (await api.studySessions(today, today)).items.single;
    final choice = (await api.studyPlanTasks(date: today)).items.single;
    final before = await api.studyStats(start, today);
    expect(original.minutes, 60);
    expect(original.taskId, isNull);
    expect(choice.subjectId, isNull);
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

    void dismissNotice() {
      ScaffoldMessenger.of(
        t.element(find.byKey(const ValueKey('study-view-0'))),
      ).hideCurrentSnackBar();
    }

    final nav = find.byType(NavigationBar);
    await tap(find.descendant(of: nav, matching: find.text('기록')));
    await tap(find.byKey(const ValueKey('open-study-history')));
    final day = find.byKey(ValueKey('history-day-${isoDay(original.date)}'));
    if (find
        .descendant(of: day, matching: find.byIcon(Icons.expand_more))
        .evaluate()
        .isNotEmpty) {
      await tap(day);
    }
    await capture('live-actions-before');
    await tap(find.byKey(ValueKey('study-actions-${original.id}')));
    await tap(find.byKey(ValueKey('study-edit-${original.id}')));
    await tap(find.byKey(const ValueKey('study-task-picker')));
    await capture('live-actions-choices');
    await tap(find.byKey(ValueKey('study-task-${choice.id}')));
    expect(
      t
          .widget<TextFormField>(find.byKey(const ValueKey('study-minutes')))
          .controller!
          .text,
      '60',
    );
    await tap(find.text('수정 내용 저장'));
    final linked = (await api.studySessions(today, today)).items.single;
    expect(linked.id, original.id);
    expect(linked.taskId, choice.id);
    expect(linked.subjectName, choice.subjectName);
    expect(linked.minutes, 60);
    dismissNotice();
    await capture('live-actions-linked');
    await tap(find.byKey(const ValueKey('history-add')));
    await t.enterText(find.byKey(const ValueKey('study-minutes')), '25');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    await tap(find.byKey(const ValueKey('study-task-picker')));
    await tap(find.byKey(ValueKey('study-task-${choice.id}')));
    expect(
      t
          .widget<TextFormField>(find.byKey(const ValueKey('study-minutes')))
          .controller!
          .text,
      '25',
    );
    await tap(find.text('공부시간 저장'));
    final added = (await api.studySessions(
      today,
      today,
    )).items.singleWhere((r) => r.id != original.id);
    expect(added.minutes, 25);
    expect(added.taskId, choice.id);
    expect(
      (await api.studyStats(start, today)).totalMinutes,
      before.totalMinutes + 25,
    );
    dismissNotice();
    final delete = find.byKey(ValueKey('study-delete-${added.id}'));
    await tap(find.byKey(ValueKey('study-actions-${added.id}')));
    await tap(delete);
    await capture('live-actions-delete-confirm');
    await tap(find.widgetWithText(TextButton, '취소'));
    expect(
      (await api.studySessions(
        today,
        today,
      )).items.any((r) => r.id == added.id),
      true,
    );
    await tap(find.byKey(ValueKey('study-actions-${added.id}')));
    await tap(delete);
    await tap(find.widgetWithText(FilledButton, '삭제'));
    final remaining = (await api.studySessions(today, today)).items.single;
    expect(remaining.id, original.id);
    expect(remaining.taskId, choice.id);
    final after = await api.studyStats(start, today);
    expect(after.totalMinutes, before.totalMinutes);
    dismissNotice();
    await capture('live-actions-after');
    final recordsScroll = find
        .descendant(
          of: find.byKey(const ValueKey('study-view-0')),
          matching: find.byType(Scrollable),
        )
        .first;
    t.state<ScrollableState>(recordsScroll).position.jumpTo(0);
    await t.pumpAndSettle();
    await tap(find.text('개인 통계'));
    expect(
      t.widget<Text>(find.byKey(const ValueKey('study-total'))).data,
      durationLabel(after.totalMinutes),
    );
    await t.ensureVisible(find.byKey(const ValueKey('study-selected-day')));
    await capture('live-actions-statistics');
    expect(t.takeException(), isNull);
    binding.reportData = {
      ...?binding.reportData,
      'mode': 'isolated real Spring Boot and MariaDB',
      'checks': [
        'real-owned-task-choice',
        'null-subject-registry-id-supported',
        'existing-record-linked-same-id-and-minutes',
        'new-record-linked-with-manual-minutes',
        'delete-cancel-preserves-record',
        'confirmed-delete-removes-only-target',
        'statistics-recalculated',
      ],
      'productionWrites': false,
    };
  });
}
