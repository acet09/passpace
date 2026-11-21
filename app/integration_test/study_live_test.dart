import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/data/session.dart';
import 'package:passpace_mobile/main.dart';

import '../test/support/draft_storage.dart';

class _LiveStudyStore implements SessionStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    value = next;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const origin = String.fromEnvironment('STUDY_TEST_ORIGIN');
  const id = String.fromEnvironment('STUDY_TEST_ID');
  const password = String.fromEnvironment('STUDY_TEST_PASSWORD');
  const isolated = bool.fromEnvironment('STUDY_TEST_ISOLATED');
  testWidgets('격리 실제 API: 앱에서 저장·조회·통계·재진입을 검증한다', (t) async {
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
      _LiveStudyStore(),
      client,
      drafts: MemoryDraftStorage(),
    );
    addTearDown(session.dispose);
    await session.changeOrigin(origin);
    await session.signIn(id, password);
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

    final today = dayInSeoul(), start = plusDays(dayInSeoul(), -6);
    final before = await session.account!.studyStats(start, today);
    await tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('기록'),
      ),
    );
    await capture('live-study-history-before');
    await tap(find.text('공부시간 추가'));
    await t.enterText(find.byKey(const ValueKey('study-minutes')), '45');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    await capture('live-study-input');
    await tap(find.text('공부시간 저장'));
    expect(find.text('45분'), findsOneWidget);
    await capture('live-study-history');
    ScaffoldMessenger.of(t.element(find.byKey(const ValueKey('study-view-0'))))
        .hideCurrentSnackBar();
    await t.pumpAndSettle();
    final after = await session.account!.studyStats(start, today);
    expect(after.totalMinutes, before.totalMinutes + 45);
    final records = await session.account!.studySessions(start, today);
    expect(
      records.items.any(
        (r) => r.minutes == 45 && r.date == today && r.taskId == null,
      ),
      true,
    );
    await tap(find.text('개인 통계'));
    expect(
      t.widget<Text>(find.byKey(const ValueKey('study-total'))).data,
      durationLabel(after.totalMinutes),
    );
    await tap(find.widgetWithText(ChoiceChip, '꺾은선'));
    expect(
      t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '꺾은선')).selected,
      true,
    );
    await t.ensureVisible(find.byKey(const ValueKey('study-selected-day')));
    await capture('live-study-line');
    await tap(find.widgetWithText(ChoiceChip, '막대'));
    expect(
      t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '막대')).selected,
      true,
    );
    await capture('live-study-bars');
    await tap(find.widgetWithText(ChoiceChip, '최근 30일'));
    final thirty = await session.account!.studyStats(
      plusDays(today, -29),
      today,
    );
    expect(
      t.widget<Text>(find.byKey(const ValueKey('study-total'))).data,
      durationLabel(thirty.totalMinutes),
    );
    await tap(find.widgetWithText(ChoiceChip, '꺾은선'));
    await t.ensureVisible(find.byKey(const ValueKey('study-selected-day')));
    await capture('live-study-month');
    await tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('오늘'),
      ),
    );
    await tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('기록'),
      ),
    );
    expect(
      t.widget<Text>(find.byKey(const ValueKey('study-total'))).data,
      durationLabel(thirty.totalMinutes),
    );
    expect(t.takeException(), isNull);
    binding.reportData = {
      ...?binding.reportData,
      'mode': 'isolated real Spring Boot and MariaDB',
      'checks': [
        'login',
        'manual-save',
        'history',
        'statistics-total',
        'line',
        'bars',
        '30-day-range',
        'tab-reentry',
      ],
      'productionWrites': false,
    };
  });
}
