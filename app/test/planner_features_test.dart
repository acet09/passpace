import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/data/plan_draft.dart';
import 'package:passpace_mobile/ui/design.dart';
import 'package:passpace_mobile/ui/planner.dart';

import 'support/draft_storage.dart';

http.Response success(Object? data) => http.Response.bytes(
  utf8.encode(jsonEncode({'status': 'SUCCESS', 'code': 200, 'data': data})),
  200,
);

class Fixture {
  final today = dayInSeoul();
  final storage = MemoryDraftStorage();
  late final repository = PlanDraftRepository(
    storage,
    emulatorOrigin,
    'fixture-user',
  );
  Json? active;
  int saves = 0;
  Json? request;
  PlanSaveResult? result;
  late final api = PassApi(
    MockClient((r) async {
      if (r.url.path == '/users/me/goal') {
        return success({
          'goal': {
            'dailyMinutes': 90,
            'targetExamDate': isoDay(plusDays(today, 35)),
            'familiarity': {'11': 3, '999': 1},
          },
          'examRounds': [],
          'subjects': [
            {'subjectId': 11, 'subjectName': 'SQL 활용'},
          ],
        });
      }
      if (r.url.path == '$plannerPath/catalog') {
        return success({
          'profileDailyMinutes': 150,
          'notices': ['SAMPLE 검증용 계산 설명'],
          'goals': [
            {
              'key': 'sqld',
              'certificationName': 'SQLD',
              'evidence': {'warning': 'SAMPLE 검증용 학습량 근거'},
              'suggestedExamDate': isoDay(plusDays(today, 60)),
              'subjects': [
                {'subjectId': 11, 'name': 'SQL 활용', 'baseHours': 10},
                {'subjectId': 22, 'name': '모델링', 'baseHours': 10},
              ],
            },
          ],
        });
      }
      if (r.url.path == '$plannerPath/saved') return success({'plan': active});
      if (r.url.path == '$plannerPath/preview') {
        request = object(jsonDecode(r.body));
        return success({
          'totalRemainingMinutes': 60,
          'totalShortfallMinutes': 0,
          'feasible': true,
          'notices': ['SAMPLE 검증용 계산 설명'],
          'days': [
            {
              'date': isoDay(today),
              'allocatedMinutes': 60,
              'allocations': [
                {
                  'certificationName': 'SQLD',
                  'subjectName': 'SQL 활용',
                  'minutes': 60,
                },
              ],
            },
          ],
        });
      }
      if (r.url.path == '$plannerPath/save') {
        saves++;
        return success({'planId': 3});
      }
      throw StateError(r.url.path);
    }),
    emulatorOrigin,
    token: 'fixture',
  );
  Json plan(int id, int version, int minutes) => {
    'planId': id,
    'versionNo': version,
    'planName': 'SQLD',
    'startDate': isoDay(today),
    'endDate': isoDay(today),
    'tasks': [
      {
        'date': isoDay(today),
        'certificationName': 'SQLD',
        'subjectName': 'SQL 활용',
        'minutes': minutes,
      },
    ],
  };
}

Future<void> tap(WidgetTester t, Finder finder) async {
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  await t.tap(finder);
  await t.pumpAndSettle();
}

Future<void> open(WidgetTester t, Fixture f) async {
  await t.pumpWidget(
    MaterialApp(
      theme: paceTheme(),
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                f.result = await Navigator.push<PlanSaveResult>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        PlannerScreen(f.api, draftRepository: f.repository),
                  ),
                );
              },
              child: const Text('계획 열기'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  await tap(t, find.text('계획 열기'));
}

Future<void> next(WidgetTester t) =>
    tap(t, find.widgetWithText(FilledButton, '다음'));
Future<void> toSubjects(WidgetTester t) async {
  await next(t);
  await tap(t, find.byType(CheckboxListTile));
  await next(t);
}

Future<void> toPreview(WidgetTester t) async {
  await toSubjects(t);
  await tap(t, find.widgetWithText(ChoiceChip, '보통').last);
  await tap(t, find.widgetWithText(FilledButton, '계획 미리보기'));
}

void main() {
  testWidgets('이전 초안의 기학습 값은 제거하고 시간·요일·이해도만 계산에 보낸다', (t) async {
    final f = Fixture();
    await f.repository.save(
      PlannerDraft(
        minutes: '180',
        weekdays: {1, 3, 5, 7},
        step: 2,
        updatedAt: DateTime.now().toUtc(),
        exams: {
          'sqld': ExamDraft(
            f.today,
            plusDays(f.today, 60),
            selected: true,
            familiarity: {'SQL 활용': 3, '모델링': 2},
            progress: {'SQL 활용': 50},
            actual: {'SQL 활용': 90},
          ),
        },
      ),
    );
    await open(t, f);
    await tap(t, find.text('이어서 작성'));
    await tap(t, find.text('계획 미리보기'));
    expect(f.request!['dailyMinutes'], 180);
    expect(find.text('계산 안내'), findsNothing);
    expect(f.request!['studyWeekdays'], [1, 3, 5, 7]);
    final subjects = f.request!['goals'][0]['subjects'] as List;
    expect(subjects[0]['familiarity'], 3);
    for (final subject in subjects) {
      expect(subject['progressPercent'], 0);
      expect(subject['actualMinutes'], 0);
    }
    expect(f.saves, 0);
    await tap(t, find.byType(BackButton));
    expect(find.text('이미 공부한 과목이 있나요?'), findsNothing);
    expect(find.text('학습량 산정 근거'), findsNothing);
    expect(find.text('계획 계산 기준'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('기존 값은 과목 ID로 불러오고 초안은 화면 재생성 후 복원된다', (t) async {
    final f = Fixture();
    await open(t, f);
    expect(
      t.widget<TextField>(find.byType(TextField).first).controller!.text,
      '90',
    );
    await t.enterText(find.byType(TextField).first, '75');
    await tap(t, find.widgetWithText(FilterChip, '월'));
    await toSubjects(t);
    expect(
      t
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '익숙함').first)
          .selected,
      true,
    );
    expect(
      t
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '익숙함').last)
          .selected,
      false,
    );
    await tap(t, find.widgetWithText(ChoiceChip, '보통').last);
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    final restored = (await f.repository.read())!;
    expect(restored.minutes, '75');
    expect(restored.weekdays.contains(1), false);
    expect(restored.step, 2);
    await open(t, f);
    expect(find.text('이어서 작성할 계획이 있어요'), findsOneWidget);
    await tap(t, find.text('이어서 작성'));
    expect(find.text('나에게 맞는 학습량'), findsOneWidget);
    expect(
      t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '보통').last).selected,
      true,
    );
    await tap(t, find.byType(BackButton));
    expect(find.text('준비할 시험'), findsOneWidget);
    await tap(t, find.byType(BackButton));
    expect(
      t.widget<TextField>(find.byType(TextField).first).controller!.text,
      '75',
    );
    expect(
      t.widget<FilterChip>(find.widgetWithText(FilterChip, '월')).selected,
      false,
    );
    await tap(t, find.byType(BackButton));
    expect(find.text('계획 열기'), findsOneWidget);
    await tap(t, find.text('계획 열기'));
    await tap(t, find.text('새로 작성'));
    expect(await f.repository.read(), isNull);
    expect(
      t.widget<TextField>(find.byType(TextField).first).controller!.text,
      '90',
    );
    expect(t.takeException(), isNull);
  });
  testWidgets('기본 목표일은 직접 적용하고 기존 값 재적용은 확인 후 반영한다', (t) async {
    final f = Fixture();
    await open(t, f);
    await t.enterText(find.byType(TextField).first, '120');
    await tap(t, find.text('기존 값 불러오기'));
    await tap(t, find.text('불러오기'));
    expect(
      t.widget<TextField>(find.byType(TextField).first).controller!.text,
      '90',
    );
    await next(t);
    await tap(t, find.byType(CheckboxListTile));
    expect(find.text(isoDay(plusDays(f.today, 60))), findsOneWidget);
    await tap(t, find.textContaining('저장한 목표일 사용'));
    expect(find.text(isoDay(plusDays(f.today, 35))), findsOneWidget);
    await next(t);
    await tap(t, find.widgetWithText(ChoiceChip, '보통').last);
    await tap(t, find.text('계획 미리보기'));
    expect(f.request!['goals'][0]['examDate'], isoDay(plusDays(f.today, 35)));
    expect(f.request!['goals'][0]['subjects'][0]['familiarity'], 3);
    expect(f.saves, 0);
  });
  testWidgets('변경 상세를 비교하고 외부에서 바뀐 계획은 재확인 후 저장한다', (t) async {
    final f = Fixture()..active = null;
    f.active = f.plan(1, 1, 30);
    await open(t, f);
    await toPreview(t);
    expect(find.text('현재 계획과 변경 비교'), findsOneWidget);
    await tap(t, find.text('변경 상세 1건 보기'));
    expect(find.text('현재 30분'), findsOneWidget);
    expect(find.text('새 계획 1시간'), findsOneWidget);
    expect(f.saves, 0);
    await tap(t, find.byType(BackButton));
    f.active = f.plan(2, 2, 45);
    await tap(t, find.text('이 계획 저장'));
    await tap(t, find.text('바로 사용'));
    expect(find.textContaining('사용 중인 계획이 바뀌었어요'), findsOneWidget);
    expect(f.saves, 0);
    expect(find.text('버전 2 → 새 계획'), findsOneWidget);
    await tap(t, find.text('이 계획 저장'));
    await tap(t, find.text('바로 사용'));
    expect(f.saves, 1);
    expect(f.result!.draftCleared, true);
    expect(await f.repository.read(), isNull);
    expect(t.takeException(), isNull);
  });
  testWidgets('서버 저장 성공 뒤 초안 정리가 실패해도 저장 요청을 반복하지 않는다', (t) async {
    final f = Fixture();
    await open(t, f);
    await toPreview(t);
    f.storage.failWrites = true;
    await tap(t, find.text('이 계획 저장'));
    await tap(t, find.text('바로 사용'));
    expect(f.saves, 1);
    expect(f.result!.draftCleared, false);
    expect(find.text('계획 열기'), findsOneWidget);
    expect(f.storage.values, contains(f.repository.key));
    expect(t.takeException(), isNull);
  });
}
