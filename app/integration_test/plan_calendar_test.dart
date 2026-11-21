import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/main.dart';

import '../test/learning_plan_hub_test.dart' as fixture;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('SAMPLE: Android 월간 일정의 선택·빈 날짜·목록 전환', (t) async {
    // HubFixture uses MockClient and memory stores, never the user's saved account.
    final f = fixture.HubFixture()..taskDays = 10;
    addTearDown(f.client.close);
    await f.session.restore();
    await t.pumpWidget(PassPaceApp(f.session));
    await t.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    Future<void> tap(Finder finder) async {
      await t.ensureVisible(finder);
      await t.pumpAndSettle();
      await t.tap(finder);
      await t.pumpAndSettle();
    }

    Future<void> capture(String name) async {
      await t.pumpAndSettle();
      final bytes = await binding.takeScreenshot(name);
      await File('${Directory.systemTemp.path}/calendar-$name.png')
          .writeAsBytes(bytes);
    }

    await tap(fixture.tab('학습계획'));
    await tap(find.byTooltip('목표와 기본 설정 접기'));
    await tap(find.text('전체 일정'));
    final calendar = find.byKey(const ValueKey('plan-month-calendar'));
    await t.ensureVisible(calendar);
    await t.pumpAndSettle();
    await capture('month');
    await tap(find.byTooltip('다음 달'));
    await capture('next-month');
    await tap(find.widgetWithText(TextButton, '오늘'));
    final empty = plusDays(f.today, 12);
    if (empty.month != f.today.month) await tap(find.byTooltip('다음 달'));
    await tap(find.byKey(ValueKey('calendar-day-${isoDay(empty)}')));
    final emptyPanel = find.text('계획된 학습 없음');
    expect(emptyPanel, findsOneWidget);
    await t.ensureVisible(emptyPanel);
    await t.pumpAndSettle();
    await capture('empty-day');
    await tap(find.byTooltip('목록으로 보기'));
    expect(find.byKey(const ValueKey('plan-month-calendar')), findsNothing);
    await capture('list');
    expect(f.goalWrites, isEmpty);
    expect(f.planWrites, 0);
    expect(t.takeException(), isNull);
  });
}
