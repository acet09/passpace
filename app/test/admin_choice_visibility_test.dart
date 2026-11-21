import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passpace_mobile/ui/admin_widgets.dart';
import 'package:passpace_mobile/ui/design.dart';

void expectSelectedLabelVisible(WidgetTester t, String label) {
  final finder = find.text(label);
  expect(finder, findsOneWidget);
  final paragraph = t.renderObject<RenderParagraph>(finder);
  final natural = TextPainter(
    text: paragraph.text,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    maxLines: paragraph.maxLines,
    locale: paragraph.locale,
  )..layout(maxWidth: paragraph.size.width);
  expect(
    paragraph.size.height,
    greaterThanOrEqualTo(natural.height - .1),
    reason: '선택된 $label 글자가 실제 글자 높이보다 작은 영역에 눌려 가려지면 안 됩니다.',
  );
  natural.dispose();
}

void main() {
  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('수집 사이트·방식의 선택값은 실제로 보이고 변경 후에도 유지된다: $scale', (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(320, 800);
      t.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      String site = 'ALL', mode = 'NEW';
      await t.pumpWidget(
        MaterialApp(
          theme: paceTheme(),
          home: Scaffold(
            body: ScrollBody(
              children: [
                StatefulBuilder(
                  builder: (context, update) => Column(
                    children: [
                      AdminChoice('수집 사이트', site, const {
                        'ALL': '전체',
                        'VELOG': 'velog',
                        'TISTORY': '티스토리',
                      }, (v) => update(() => site = v)),
                      AdminChoice('수집 방식', mode, const {
                        'NEW': '일반 수집',
                        'RECOVER': '복구 수집',
                        'RETRY': '실패분 다시 시도',
                      }, (v) => update(() => mode = v)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expectSelectedLabelVisible(t, '전체');
      expectSelectedLabelVisible(t, '일반 수집');
      for (final entry in [('수집 사이트', '티스토리'), ('수집 방식', '실패분 다시 시도')]) {
        final choice = find.byWidgetPredicate(
          (w) => w is AdminChoice && w.label == entry.$1,
        );
        await t.tap(
          find.descendant(
            of: choice,
            matching: find.byType(DropdownButton<String>),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.text(entry.$2).last);
        await t.pumpAndSettle();
        expectSelectedLabelVisible(t, entry.$2);
      }
      expect(site, 'TISTORY');
      expect(mode, 'RETRY');
      expect(t.takeException(), isNull);
    });
  }
}
