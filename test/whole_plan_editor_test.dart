import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/models.dart';

import 'study_records_test.dart' show tapStudy;
import 'support/study_fixture.dart';
import 'timer_navigation_test.dart' show boot, nav;

void main() {
  testWidgets('전체 계획을 단계별로 수정하고 입력을 유지한 뒤 같은 ID에 저장한다', (t) async {
    final today = dayInSeoul();
    final day = isoDay(today), end = isoDay(plusDays(today, 18));
    final path = '$plannerPath/plans/5/schedule';
    var version = 3, minutes = 45;
    Json? pending;
    final fixture = StudyFixture(
      override: (r) async {
        if (r.url.path == '$plannerPath/saved') {
          return studyEnvelope({
            'plan': {
              'planId': 5,
              'versionNo': version,
              'planName': 'SAMPLE 현재 계획',
              'startDate': day,
              'endDate': end,
              'tasks': [
                {
                  'taskId': 502,
                  'date': day,
                  'certificationName': 'SAMPLE 기사',
                  'subjectName': '데이터베이스',
                  'minutes': minutes,
                },
              ],
            },
          });
        }
        if (r.url.path == path && r.method == 'GET') {
          return studyEnvelope({
            'planId': 5,
            'planName': 'SAMPLE 현재 계획',
            'planVersion': version,
            'startDate': day,
            'endDate': end,
            'today': day,
            'weekdayMinutes': {'${today.weekday}': 75},
            'subjects': [
              {
                'key': 502,
                'exam': 'SAMPLE 기사',
                'name': '데이터베이스',
                'minutes': minutes,
              },
            ],
            'protectedTasks': 1,
          });
        }
        if (r.url.path == '$path/preview') {
          pending = object(jsonDecode(r.body));
          return studyEnvelope({
            'approval': 'sample-approved',
            'changed': true,
            'protectedTasks': 1,
            'removed': [
              {'date': day, 'subject': '데이터베이스', 'minutes': 45},
            ],
            'added': [
              {'date': day, 'subject': '데이터베이스', 'minutes': 60},
            ],
          });
        }
        if (r.url.path == path && r.method == 'PATCH') {
          expect(object(jsonDecode(r.body)), {
            ...pending!,
            'approval': 'sample-approved',
          });
          minutes = 60;
          return studyEnvelope({
            'planId': 5,
            'planVersion': ++version,
            'startDate': day,
            'endDate': end,
          });
        }
        return null;
      },
    );
    addTearDown(fixture.dispose);
    await boot(t, fixture);
    await nav(t, '학습계획');
    await tapStudy(t, find.byTooltip('계획 수정'));
    await tapStudy(t, find.text('전체 계획 수정'));
    Finder field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );
    final weekday = field('${weekdays[today.weekday - 1]}요일 최대 시간');
    final subject = field('데이터베이스');
    final next = find.text('다음');
    final start = find.text('시작일 · $day');
    final preview = find.text('변경안 미리보기');
    expect(find.textContaining('1 / 3'), findsOneWidget);
    expect(start, findsNothing);
    expect(subject, findsNothing);
    expect(preview, findsNothing);
    expect(t.widget<TextField>(weekday).controller!.text, '75');
    await t.enterText(weekday, '');
    await tapStudy(t, next);
    expect(find.textContaining('1~960분'), findsOneWidget);
    expect(find.textContaining('1 / 3'), findsOneWidget);
    await t.enterText(weekday, '90');
    await tapStudy(t, next);
    expect(find.textContaining('2 / 3'), findsOneWidget);
    expect(start, findsOneWidget);
    expect(subject, findsNothing);
    await tapStudy(t, next);
    expect(find.textContaining('3 / 3'), findsOneWidget);
    expect(weekday, findsNothing);
    await t.ensureVisible(subject);
    expect(t.widget<TextField>(subject).controller!.text, '45');
    await t.enterText(subject, '60');
    await tapStudy(t, find.text('이전'));
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(t.widget<TextField>(weekday).controller!.text, '90');
    await tapStudy(t, next);
    await tapStudy(t, next);
    expect(t.widget<TextField>(subject).controller!.text, '60');
    expect(pending, isNull);
    await tapStudy(t, preview);
    expect(find.text('전체 계획 변경 확인'), findsOneWidget);
    expect(find.textContaining('1개 보존'), findsOneWidget);
    expect(fixture.requests.where((r) => r.method == 'PATCH'), isEmpty);
    expect(pending!['weekdayMinutes'], {'${today.weekday}': 90});
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(t.widget<TextField>(subject).controller!.text, '60');
    await tapStudy(t, preview);
    await tapStudy(t, find.text('이 계획에 저장'));
    expect(version, 4);
    expect(find.text('전체 학습계획을 수정했어요.'), findsOneWidget);
    expect(
      fixture.requests.where((r) => r.url.path == '$plannerPath/save'),
      isEmpty,
    );
    expect(t.takeException(), isNull);
  });
}
