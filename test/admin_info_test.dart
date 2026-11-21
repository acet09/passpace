import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passpace_mobile/ui/admin_info.dart';
import 'package:passpace_mobile/ui/admin_widgets.dart';

/// [용성·11-21] 수집 영역 제목 옆 "수집자료정보" 링크와 설명 페이지
void main() {
  test('모든 수집 영역에 설명이 있다', () {
    for (final key in ['crawl', 'naver', 'schedule', 'reference', 'subject']) {
      final t = adminInfoTopics[key];
      expect(t, isNotNull, reason: key);
      expect(t!.items, isNotEmpty, reason: key);
    }
  });

  testWidgets('제목 옆 수집자료정보를 누르면 그 영역의 설명 페이지로 이동한다', (t) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AdminSection('네이버 검색 API', [Text('본문')], info: 'naver'),
        ),
      ),
    );
    expect(find.text('네이버 검색 API'), findsOneWidget);
    await t.tap(find.text('수집자료정보'));
    await t.pumpAndSettle();
    expect(find.byType(AdminInfoScreen), findsOneWidget);
    expect(find.textContaining('PENDING'), findsWidgets);
    expect(find.textContaining('하루 3시간 이하'), findsOneWidget);
  });

  testWidgets('info 가 없으면 링크를 보여 주지 않는다', (t) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AdminSection('관리 메뉴', [Text('본문')])),
      ),
    );
    expect(find.text('수집자료정보'), findsNothing);
  });
}
