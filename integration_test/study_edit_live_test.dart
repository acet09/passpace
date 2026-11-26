import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/data/session.dart';
import 'package:passpace_mobile/main.dart';

import '../test/support/draft_storage.dart';

class _EditStore implements SessionStore {
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
  testWidgets('격리 실제 API: 기존 기록 날짜·시간 수정·취소·통계·재진입', (t) async {
    final uri = Uri.tryParse(origin);
    if (!isolated ||
        uri?.host != '10.0.2.2' ||
        uri?.scheme != 'http' ||
        [8080, 8082, 18080, 3306, 3308].contains(uri?.port) ||
        !id.startsWith('app_verify_') ||
        password.isEmpty) {
      throw StateError('합성 계정이 있는 격리 API만 사용할 수 있습니다.');
    }
    final client = http.Client();
    addTearDown(client.close);
    final session = Session(_EditStore(), client, drafts: MemoryDraftStorage());
    addTearDown(session.dispose);
    await session.changeOrigin(origin);
    await session.signIn(id, password);
    final today = dayInSeoul(), target = plusDays(dayInSeoul(), -1);
    final start = plusDays(today, -6);
    final original = (await session.account!.studySessions(
      today,
      today,
    )).items.single;
    final before = await session.account!.studyStats(start, today);
    expect(original.minutes, 60);
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
    await capture('live-edit-before');
    final edit = find.byKey(ValueKey('study-edit-${original.id}'));
    await tap(find.byKey(ValueKey('study-actions-${original.id}')));
    await tap(edit);
    expect(
      t
          .widget<TextFormField>(find.byKey(const ValueKey('study-minutes')))
          .controller!
          .text,
      '60',
    );
    await t.enterText(find.byKey(const ValueKey('study-minutes')), '90');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    await tap(find.byType(BackButton));
    expect(
      (await session.account!.studySessions(today, today)).items.single.minutes,
      60,
    );
    await tap(find.byKey(ValueKey('study-actions-${original.id}')));
    await tap(edit);
    await tap(find.text('공부한 날짜'));
    if (today.month != target.month) {
      final previous = MaterialLocalizations.of(
        t.element(find.byType(CalendarDatePicker)),
      ).previousMonthTooltip;
      await tap(find.byTooltip(previous));
    }
    await tap(
      find.descendant(
        of: find.byType(CalendarDatePicker),
        matching: find.text('${target.day}'),
      ),
    );
    await tap(find.text('확인'));
    await t.enterText(find.byKey(const ValueKey('study-minutes')), '75');
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pumpAndSettle();
    await capture('live-edit-input');
    await tap(find.text('수정 내용 저장'));
    expect(find.text('1시간 15분'), findsOneWidget);
    ScaffoldMessenger.of(t.element(find.byKey(const ValueKey('study-view-0'))))
        .hideCurrentSnackBar();
    await t.pumpAndSettle();
    await capture('live-edit-after');
    final oldDay = await session.account!.studySessions(today, today);
    expect(oldDay.items.any((r) => r.id == original.id), false);
    final newDay = await session.account!.studySessions(target, target);
    final updated = newDay.items.singleWhere((r) => r.id == original.id);
    expect(updated.minutes, 75);
    expect(updated.date, target);
    expect(updated.taskId, original.taskId);
    final after = await session.account!.studyStats(start, today);
    expect(after.totalMinutes, before.totalMinutes + 15);
    expect(after.days.singleWhere((d) => d.date == today).minutes, 0);
    expect(after.days.singleWhere((d) => d.date == target).minutes, 105);
    await tap(find.text('개인 통계'));
    expect(
      t.widget<Text>(find.byKey(const ValueKey('study-total'))).data,
      durationLabel(after.totalMinutes),
    );
    await t.ensureVisible(find.byKey(const ValueKey('study-selected-day')));
    await capture('live-edit-statistics');
    await tap(find.descendant(of: nav, matching: find.text('오늘')));
    await tap(find.descendant(of: nav, matching: find.text('기록')));
    expect(
      t.widget<Text>(find.byKey(const ValueKey('study-total'))).data,
      durationLabel(after.totalMinutes),
    );
    expect(t.takeException(), isNull);
    binding.reportData = {
      ...?binding.reportData,
      'mode': 'isolated real Spring Boot and MariaDB',
      'checks': [
        'original-values',
        'cancel-without-update',
        'change-date-and-minutes',
        'same-session-id',
        'original-date-removed',
        'new-date-total',
        'statistics-refresh',
        'tab-reentry',
      ],
      'productionWrites': false,
    };
  });
}
