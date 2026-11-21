import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:passpace_mobile/data/study_timer.dart';

import 'support/draft_storage.dart';

class _RetryStorage extends MemoryDraftStorage {
  bool failReads = true;
  @override
  Future<String?> read(String key) async {
    if (failReads) throw StateError('SAMPLE storage unavailable');
    return super.read(key);
  }
}

void main() {
  test('시스템 경과 시간은 실행 중인 타이머만 보정하고 멈춘 시간·한도는 유지한다', () async {
    final timer = StudyTimer(
      MemoryDraftStorage(),
      'http://10.0.2.2:8080',
      'SAMPLE',
    );
    await timer.restore();
    await timer.start();
    await timer.alignElapsed(90000);
    expect(timer.elapsed.inSeconds, greaterThanOrEqualTo(90));
    await timer.pause();
    final paused = timer.elapsed;
    await timer.alignElapsed(120000);
    expect(timer.elapsed, paused);
    await timer.start();
    await timer.alignElapsed(90000000);
    expect(timer.elapsed.inMinutes, lessThan(1440));
    await timer.pause();
    timer.dispose();
  });
  test('폐기된 타이머의 지연 성공·실패 응답은 새 측정의 저장값을 덮어쓰지 않는다', () async {
    for (final outcome in ['complete', 'uncertain', 'rejected']) {
      final storage = MemoryDraftStorage();
      var now = DateTime.utc(2026, 11, 16, 3);
      var ticks = 0;
      StudyTimer fresh() => StudyTimer(
        storage,
        'http://10.0.2.2:8080',
        'SAMPLE',
        now: () => now,
        ticks: () => ticks,
      );
      final old = fresh();
      await old.restore();
      await old.start();
      now = now.add(const Duration(seconds: 75));
      ticks += 75000;
      await old.pause();
      await old.beginSave();
      old.dispose();
      final next = fresh();
      await next.restore();
      await next.reset(verified: true);
      await next.start();
      final snapshot = storage.values[next.key];
      switch (outcome) {
        case 'complete':
          await old.complete();
        case 'uncertain':
          await old.uncertain();
        case 'rejected':
          await old.rejected();
      }
      expect(storage.values[next.key], snapshot, reason: outcome);
      next.dispose();
    }
  });
  test('일시적 읽기 오류 뒤 다시 불러오면 측정값을 보존하고 저장할 수 있다', () async {
    final storage = _RetryStorage();
    final timer = StudyTimer(storage, 'http://10.0.2.2:8080', 'SAMPLE');
    storage.values[timer.key] = jsonEncode({
      'schema': 1,
      'phase': 'paused',
      'date': '2026-11-16',
      'milliseconds': 85000,
      'anchor': null,
      'task': null,
    });
    await timer.restore();
    expect(timer.loadFailed, true);
    storage.failReads = false;
    await timer.restore();
    expect(timer.loadFailed, false);
    expect(timer.error, isNull);
    expect(timer.elapsed.inSeconds, 85);
    expect(await timer.beginSave(), true);
    timer.dispose();
  });
  test('손상된 실행 상태를 읽으면 타이머 틱이 예외 없이 멈춘다', () async {
    final store = MemoryDraftStorage();
    final timer = StudyTimer(store, 'http://10.0.2.2:8080', 'SAMPLE');
    store.values[timer.key] = jsonEncode({
      'schema': 1,
      'phase': 'running',
      'date': '2026-11-16',
      'milliseconds': 0,
      'anchor': 'INVALID',
      'task': null,
    });
    await timer.restore();
    expect(timer.loadFailed, true);
    expect(timer.tick, returnsNormally);
    expect(await timer.start(), false);
    timer.dispose();
  });
  late MemoryDraftStorage store;
  late DateTime now;
  late int ticks;
  StudyTimer create({
    String user = 'SAMPLE',
    String origin = 'http://10.0.2.2:8080',
  }) => StudyTimer(store, origin, user, now: () => now, ticks: () => ticks);
  void advance(int seconds) {
    now = now.add(Duration(seconds: seconds));
    ticks += seconds * 1000;
  }

  setUp(() {
    store = MemoryDraftStorage();
    now = DateTime.utc(2026, 11, 16, 3);
    ticks = 0;
  });
  test('측정 중 시간만 누적하고 일시정지 시간은 제외한다', () async {
    final timer = create();
    await timer.restore();
    await timer.start();
    advance(90);
    await timer.pause();
    expect(timer.elapsed.inSeconds, 90);
    advance(100);
    expect(timer.elapsed.inSeconds, 90);
    await timer.start();
    advance(20);
    await timer.pause();
    expect(timer.elapsed.inSeconds, 110);
    expect(timer.minutes, 1);
    timer.dispose();
  });
  test('앱을 다시 열면 동일 계정의 측정 중 시간을 복원한다', () async {
    final first = create();
    await first.restore();
    await first.start();
    advance(125);
    final restored = create();
    await restored.restore();
    expect(restored.phase, StudyTimerPhase.running);
    expect(restored.elapsed.inSeconds, 125);
    await restored.pause();
    first.dispose();
    restored.dispose();
  });
  test('날짜 경계에서 멈춰 다른 날의 시간을 이전 날에 합치지 않는다', () async {
    now = DateTime.utc(2026, 11, 16, 14, 59, 50);
    final timer = create();
    await timer.restore();
    await timer.start();
    advance(80);
    timer.tick();
    expect(timer.elapsed.inSeconds, 10);
    expect(timer.phase, StudyTimerPhase.paused);
    expect(timer.dayEnded, true);
    expect(await timer.start(), false);
    timer.dispose();
  });
  test('1분 미만은 저장하지 않고 저장 전 상태 기록이 실패하면 POST를 허용하지 않는다', () async {
    final timer = create();
    await timer.restore();
    await timer.start();
    advance(30);
    await timer.pause();
    expect(await timer.beginSave(), false);
    await timer.start();
    advance(50);
    await timer.pause();
    store.failWrites = true;
    expect(await timer.beginSave(), false);
    expect(timer.phase, StudyTimerPhase.paused);
    expect(timer.error, isNotNull);
    timer.dispose();
  });
  test('저장 중 종료된 타이머는 재전송 대신 확인을 요구한다', () async {
    final timer = create();
    await timer.restore();
    await timer.start();
    advance(75);
    await timer.pause();
    expect(await timer.beginSave(), true);
    final restored = create();
    await restored.restore();
    expect(restored.phase, StudyTimerPhase.uncertain);
    expect(await restored.beginSave(), false);
    expect(await restored.reset(), false);
    expect(await restored.reset(verified: true), true);
    timer.dispose();
    restored.dispose();
  });
  test('성공 후 기기 정리가 실패해도 저장을 반복하지 않는다', () async {
    final timer = create();
    await timer.restore();
    await timer.start();
    advance(75);
    await timer.pause();
    await timer.beginSave();
    store.failWrites = true;
    await timer.complete();
    expect(timer.phase, StudyTimerPhase.saved);
    expect(await timer.beginSave(), false);
    store.failWrites = false;
    expect(await timer.reset(), true);
    timer.dispose();
  });
  test('계정과 서버가 다르면 이전 타이머 상태를 읽지 않는다', () async {
    final timer = create();
    await timer.restore();
    await timer.start();
    final other = create(user: 'OTHER');
    await other.restore();
    final host = create(origin: 'http://127.0.0.1:8080');
    await host.restore();
    expect(other.phase, StudyTimerPhase.idle);
    expect(host.phase, StudyTimerPhase.idle);
    timer.dispose();
    other.dispose();
    host.dispose();
  });
  test('복원 시 기기 시각이 뒤로 바뀌면 시간을 만들지 않고 멈춘다', () async {
    final timer = create();
    await timer.restore();
    await timer.start();
    now = now.subtract(const Duration(hours: 1));
    final restored = create();
    await restored.restore();
    expect(restored.phase, StudyTimerPhase.paused);
    expect(restored.elapsed.inSeconds, 0);
    expect(restored.notice, isNotNull);
    timer.dispose();
    restored.dispose();
  });
}
