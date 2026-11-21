import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:passpace_mobile/data/api.dart';
import 'package:passpace_mobile/data/models.dart';
import 'package:passpace_mobile/data/study_timer.dart';
import 'package:passpace_mobile/ui/study_records.dart';

import 'study_records_test.dart' show openStudy, tapStudy;
import 'study_timer_screen_test.dart' show seedTimer;
import 'study_timer_progress_test.dart' show planFor, progress, showProgress;
import 'study_timer_cumulative_test.dart' show saved;
import 'support/study_fixture.dart';
import 'support/draft_storage.dart';

StudyFixture subjectFixture({
  Future<http.Response?> Function(http.Request, StudyFixture)? onRequest,
}) {
  late StudyFixture f;
  f = StudyFixture(
    empty: true,
    override: (r) async {
      if (r.url.path == '$plannerPath/saved') {
        return studyEnvelope({'plan': planFor(f)});
      }
      return onRequest?.call(r, f);
    },
  );
  return f;
}

Future<void> openSubject(WidgetTester t, StudyFixture f) async {
  await seedTimer(f, seconds: 900);
  await openStudy(t, f);
  await tapStudy(t, find.byKey(const ValueKey('study-timer-open')));
  await tapStudy(t, find.text('과목 선택'));
  await tapStudy(t, find.text('SAMPLE 데이터베이스'));
}

StudyTimer clockOf(WidgetTester t) =>
    t.state<StudyRecordsScreenState>(find.byType(StudyRecordsScreen)).timer!;

void main() {
  testWidgets('저장 후 같은 화면에 과목을 유지하고 바로 다음 측정을 시작한다', (t) async {
    final f = subjectFixture();
    addTearDown(f.dispose);
    await openSubject(t, f);
    await tapStudy(t, find.text('기록 저장'));
    expect(find.byKey(const ValueKey('study-timer-clock')), findsOneWidget);
    expect(clockOf(t).task?.id, 502);
    expect(clockOf(t).phase, StudyTimerPhase.idle);
    expect(find.text('00:00:00'), findsOneWidget);
    expect(progress(t), .5);
    final restored = StudyTimer(
      f.session.drafts,
      f.session.origin,
      f.session.user!.id,
    );
    await restored.restore();
    expect(restored.task?.id, 502);
    expect(restored.elapsed, Duration.zero);
    restored.dispose();
    await tapStudy(t, find.text('측정 시작'));
    expect(clockOf(t).phase, StudyTimerPhase.running);
    expect(clockOf(t).task?.id, 502);
    await clockOf(t).alignElapsed(300000);
    await clockOf(t).pause();
    await t.pumpAndSettle();
    await tapStudy(t, find.text('기록 저장'));
    expect(clockOf(t).task?.id, 502);
    expect(clockOf(t).elapsed, Duration.zero);
    expect(f.history.map((r) => r['durationMinutes']).toList(), [15, 5]);
    expect(progress(t), closeTo(2 / 3, .005));
    expect(f.requests.where((r) => r.method == 'POST'), hasLength(2));
  });

  testWidgets('다른 보기로 이동한 뒤 저장 응답이 와도 과목을 보존한다', (t) async {
    final pending = Completer<http.Response>();
    final f = subjectFixture(
      onRequest: (r, f) async => r.method == 'POST' ? pending.future : null,
    );
    addTearDown(f.dispose);
    await openSubject(t, f);
    await tapStudy(t, find.text('기록 저장'));
    final body = object(
      jsonDecode(f.requests.singleWhere((r) => r.method == 'POST').body),
    );
    await tapStudy(t, find.byKey(const ValueKey('open-study-history')));
    pending.complete(studyEnvelope(f.storeRecord(body)));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('study-timer-clock')), findsNothing);
    await tapStudy(t, find.byKey(const ValueKey('study-timer-open')));
    expect(clockOf(t).task?.id, 502);
    expect(find.text('00:00:00'), findsOneWidget);
    expect(progress(t), .5);
  });

  testWidgets('로그아웃 뒤 이전 저장 응답은 과목을 다시 쓰지 않는다', (t) async {
    final pending = Completer<http.Response>();
    final f = subjectFixture(
      onRequest: (r, f) async => r.method == 'POST' ? pending.future : null,
    );
    addTearDown(f.dispose);
    await openSubject(t, f);
    await tapStudy(t, find.text('기록 저장'));
    final before = Map<String, String>.from(
      (f.session.drafts as MemoryDraftStorage).values,
    );
    final body = object(
      jsonDecode(f.requests.singleWhere((r) => r.method == 'POST').body),
    );
    await f.session.logout();
    await t.pumpAndSettle();
    pending.complete(studyEnvelope(f.storeRecord(body)));
    await t.pumpAndSettle();
    expect((f.session.drafts as MemoryDraftStorage).values, before);
    expect(find.byType(NavigationBar), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('서버 저장 후 기기 정리가 실패해도 재시도 때 과목을 유지한다', (t) async {
    final f = subjectFixture(
      onRequest: (r, f) async {
        if (r.method != 'POST') return null;
        final result = f.storeRecord(object(jsonDecode(r.body)));
        (f.session.drafts as MemoryDraftStorage).failWrites = true;
        return studyEnvelope(result);
      },
    );
    addTearDown(f.dispose);
    await openSubject(t, f);
    await tapStudy(t, find.text('기록 저장'));
    expect(clockOf(t).phase, StudyTimerPhase.saved);
    expect(clockOf(t).task?.id, 502);
    (f.session.drafts as MemoryDraftStorage).failWrites = false;
    await tapStudy(t, find.text('새 측정 준비'));
    expect(clockOf(t).phase, StudyTimerPhase.idle);
    expect(clockOf(t).task?.id, 502);
    expect(clockOf(t).elapsed, Duration.zero);
    expect(progress(t), .5);
    expect(f.requests.where((r) => r.method == 'POST'), hasLength(1));
  });

  testWidgets('응답 유실 뒤 저장됨을 확인한 경우에도 같은 과목으로 돌아온다', (t) async {
    final f = subjectFixture(
      onRequest: (r, f) async {
        if (r.method != 'POST') return null;
        f.storeRecord(object(jsonDecode(r.body)));
        throw http.ClientException('SAMPLE acknowledgement lost');
      },
    );
    addTearDown(f.dispose);
    await openSubject(t, f);
    await tapStudy(t, find.text('기록 저장'));
    await tapStudy(t, find.text('기록 목록에서 확인'));
    await tapStudy(t, find.text('기록 확인 완료'));
    await tapStudy(t, find.text('저장된 기록 확인'));
    await tapStudy(t, find.byKey(const ValueKey('study-timer-open')));
    expect(clockOf(t).task?.id, 502);
    expect(clockOf(t).elapsed, Duration.zero);
    expect(progress(t), .5);
    expect(f.requests.where((r) => r.method == 'POST'), hasLength(1));
  });

  testWidgets('사용자가 명시적으로 측정을 초기화하면 기존대로 과목을 해제한다', (t) async {
    final f = subjectFixture();
    addTearDown(f.dispose);
    await openSubject(t, f);
    await tapStudy(t, find.text('기록 저장'));
    await tapStudy(t, find.text('측정 초기화'));
    expect(clockOf(t).task, isNull);
    expect(find.text('과목 연결 없음'), findsOneWidget);
    expect(f.history.single['durationMinutes'], 15);
  });

  testWidgets('입력 화면 위 알림 타이머도 저장 후 유지되고 원래 입력은 보존한다', (t) async {
    final f = subjectFixture();
    addTearDown(f.dispose);
    await openSubject(t, f);
    final records = t.state<StudyRecordsScreenState>(
      find.byType(StudyRecordsScreen),
    );
    final input = TextEditingController(text: 'SAMPLE 보존할 입력');
    addTearDown(input.dispose);
    unawaited(
      Navigator.of(t.element(find.byType(NavigationBar))).push<void>(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('SAMPLE 입력')),
            body: TextField(controller: input),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    unawaited(records.openNotificationTimer());
    await t.pumpAndSettle();
    await tapStudy(t, find.text('기록 저장'));
    expect(find.text('00:00:00'), findsOneWidget);
    expect(find.text('SAMPLE 데이터베이스'), findsOneWidget);
    expect(progress(t), .5);
    await tapStudy(t, find.byType(BackButton));
    expect(find.text('SAMPLE 입력'), findsOneWidget);
    expect(input.text, 'SAMPLE 보존할 입력');
    expect(f.history.single['durationMinutes'], 15);
    expect(t.takeException(), isNull);
  });

  testWidgets('저장 단계가 프레임 사이에 끝나도 같은 과목의 누적 원을 갱신한다', (t) async {
    final f = subjectFixture();
    addTearDown(f.dispose);
    await showProgress(t, f);
    expect(progress(t), .5);
    f.history.add(saved(f, 1, 15));
    await showProgress(
      t,
      f,
      elapsed: Duration.zero,
      phase: StudyTimerPhase.idle,
    );
    expect(progress(t), .5);
    expect(find.text('저장 15분 + 이번 측정 0초'), findsOneWidget);
  });
}
