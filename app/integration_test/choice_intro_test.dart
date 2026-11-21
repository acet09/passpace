import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:passpace_mobile/main.dart';
import 'package:passpace_mobile/ui/admin_widgets.dart';

import '../test/admin_choice_visibility_test.dart'
    show expectSelectedLabelVisible;
import '../test/admin_native_test.dart' show tapVisible, choose;
import '../test/support/admin_fixture.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('SAMPLE: 수집 선택 목록·선택값 표시와 소개 단계 제거', (t) async {
    final f = AdminFixture();
    addTearDown(f.dispose);
    await f.restore();
    await t.pumpWidget(PassPaceApp(f.session));
    await t.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await tapVisible(
      t,
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('내 정보'),
      ),
    );
    await tapVisible(t, find.text('관리자 페이지'));
    await tapVisible(t, find.text('후기 수집'));
    final site = find.byWidgetPredicate(
      (w) => w is AdminChoice && w.label == '수집 사이트',
    );
    await Scrollable.ensureVisible(t.element(site), alignment: .15);
    await t.pumpAndSettle();
    expectSelectedLabelVisible(t, '전체');
    expectSelectedLabelVisible(t, '일반 수집');
    await t.tap(
      find.descendant(of: site, matching: find.byType(DropdownButton<String>)),
    );
    await t.pumpAndSettle();
    await binding.takeScreenshot('after-site-menu');
    await t.tap(find.text('티스토리').last);
    await t.pumpAndSettle();
    await choose(t, '수집 방식', '복구 수집');
    await Scrollable.ensureVisible(t.element(site), alignment: .15);
    await t.pumpAndSettle();
    expectSelectedLabelVisible(t, '티스토리');
    expectSelectedLabelVisible(t, '복구 수집');
    await binding.takeScreenshot('after-selected-values');
    expect(f.requests.every((r) => r.method == 'GET'), true);
    await f.session.logout();
    await t.pumpAndSettle();
    for (final label in ['목표 설정', '학습계획', '오늘의 학습']) {
      expect(find.text(label), findsNothing);
    }
    expect(find.widgetWithText(FilledButton, '로그인'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    await binding.takeScreenshot('after-login-intro');
    expect(t.takeException(), isNull);
  });
}
