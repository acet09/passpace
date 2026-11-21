import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passpace_mobile/data/study_timer.dart';
import 'package:passpace_mobile/data/study_timer_notifications.dart';

import 'support/draft_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('SAMPLE/study-notification');
  final calls = <MethodCall>[];
  setUp(() => calls.clear());
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  Future<StudyTimer> running() async {
    final t = StudyTimer(
      MemoryDraftStorage(),
      'http://10.0.2.2:8080',
      'SAMPLE',
    );
    await t.restore();
    await t.start();
    return t;
  }

  test('시작 알림은 실제 측정값·과목만 보내고 일시정지하면 해당 소유자만 종료한다', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
          calls.add(c);
          return c.method == 'requestPermission' ||
                  c.method == 'notificationAllowed'
              ? true
              : false;
        });
    final timer = await running();
    final n = StudyTimerNotifications(channel: channel);
    await n.sync(timer);
    final start = calls.singleWhere((c) => c.method == 'start');
    expect((start.arguments as Map)['elapsedMs'], isNonNegative);
    expect(
      (start.arguments as Map).keys,
      containsAll(['owner', 'subject', 'elapsedMs', 'endUtcMs']),
    );
    await timer.pause();
    await n.sync(timer);
    expect(calls.where((c) => c.method == 'stop'), isNotEmpty);
    expect(
      (calls.last.arguments as Map)['owner'],
      (start.arguments as Map)['owner'],
    );
    n.dispose();
    await n.settled;
    timer.dispose();
  });
  test('알림 권한 거부는 측정을 유지하고 설정 안내를 제공한다', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
          calls.add(c);
          return false;
        });
    final timer = await running();
    final n = StudyTimerNotifications(channel: channel);
    await n.sync(timer);
    expect(n.notice, isNotNull);
    expect(timer.phase, StudyTimerPhase.running);
    await n.openSettings();
    expect(calls.last.method, 'openSettings');
    n.dispose();
    await n.settled;
    timer.dispose();
  });
  test('권한 응답을 기다리는 사이 계정이 바뀌면 이전 타이머 알림을 시작하지 않는다', () async {
    final permission = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (c) async {
          calls.add(c);
          if (c.method == 'requestPermission') return permission.future;
          return true;
        });
    final old = await running(),
        next = StudyTimer(
          MemoryDraftStorage(),
          'http://10.0.2.2:8080',
          'OTHER',
        );
    await next.restore();
    final n = StudyTimerNotifications(channel: channel);
    final first = n.sync(old);
    await Future<void>.delayed(Duration.zero);
    final second = n.sync(next);
    permission.complete(true);
    await first;
    await second;
    expect(calls.where((c) => c.method == 'start'), isEmpty);
    n.dispose();
    await n.settled;
    old.dispose();
    next.dispose();
  });
}
