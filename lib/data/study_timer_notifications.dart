import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'study_timer.dart';

class StudyTimerNotifications extends ChangeNotifier {
  static const platform = MethodChannel('kr.passpace.mobile/study-timer');
  static int serial = 0, handlerOwner = 0;
  final MethodChannel channel;
  final int instance = ++serial;
  bool enabled, _disposed = false, _asked = false;
  int _turn = 0;
  String? _owner, _signature, notice;
  int? _taskId;
  StudyTimer? _timer;
  Future<void> _pending = Future.value();
  final _retired = <String>{};
  StudyTimerNotifications({MethodChannel? channel})
    : channel = channel ?? platform,
      enabled =
          channel != null ||
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<void> get settled => _pending;
  void _notice(String? value) {
    if (!_disposed && notice != value) {
      notice = value;
      notifyListeners();
    }
  }

  Future<void> attach(VoidCallback onOpen) async {
    if (!enabled || _disposed) return;
    handlerOwner = instance;
    Future<void> consume() async {
      final pending = await channel.invokeMethod<bool>('takePendingOpen');
      if (!_disposed && handlerOwner == instance && pending == true) onOpen();
    }

    channel.setMethodCallHandler((call) async {
      if (call.method == 'openTimer') await consume();
      if (call.method == 'timerAction') {
        final args = call.arguments;
        final timer = _timer;
        if (_disposed ||
            handlerOwner != instance ||
            args is! Map ||
            _owner == null ||
            args['owner'] != _owner ||
            timer == null ||
            !timer.available ||
            timer.locked ||
            timer.dayEnded) {
          return;
        }
        if (args['running'] == false &&
            timer.phase == StudyTimerPhase.running) {
          await timer.pause();
        } else if (args['running'] == true &&
            timer.phase == StudyTimerPhase.paused) {
          await timer.start();
        }
        if (identical(_timer, timer)) await sync(timer);
      }
    });
    try {
      await channel.invokeMethod<void>('attach');
      await consume();
    } on MissingPluginException {
      enabled = false;
    } on PlatformException {
      /* Retry on resume. */
    }
  }

  Future<void> _stops() async {
    while (_retired.isNotEmpty) {
      final owner = _retired.first;
      await channel.invokeMethod<void>('stop', {'owner': owner});
      _retired.remove(owner);
    }
  }

  Future<void> sync(StudyTimer timer, {bool refresh = false}) {
    if (!enabled || _disposed || timer.restoring || timer.storing) {
      return Future.value();
    }
    final running = timer.phase == StudyTimerPhase.running && !timer.loadFailed;
    final visible =
        !timer.loadFailed &&
        !timer.dayEnded &&
        (running || timer.phase == StudyTimerPhase.paused && _owner != null);
    final signature =
        '${timer.phase.name}:${timer.task?.id}:${timer.task?.name}';
    final sameTimer = identical(timer, _timer);
    final changedTask = sameTimer && timer.task?.id != _taskId;
    if (!sameTimer || !visible || changedTask) {
      if (_owner case final owner?) _retired.add(owner);
      _owner = null;
    }
    if (!refresh && sameTimer && signature == _signature && _retired.isEmpty) {
      return _pending;
    }
    if (visible && (running || sameTimer)) {
      _owner ??= 'study-${DateTime.now().microsecondsSinceEpoch}-${++serial}';
    }
    _timer = timer;
    _taskId = timer.task?.id;
    _signature = signature;
    final turn = ++_turn, owner = _owner;
    _pending = _pending
        .then((_) async {
          await _stops();
          if (_disposed || turn != _turn || owner == null) return;
          final allowed = !_asked
              ? await channel.invokeMethod<bool>('requestPermission')
              : await channel.invokeMethod<bool>('notificationAllowed');
          _asked = true;
          if (_disposed ||
              turn != _turn ||
              timer.phase !=
                  (running
                      ? StudyTimerPhase.running
                      : StudyTimerPhase.paused)) {
            return;
          }
          _notice(
            allowed == true
                ? null
                : '알림 권한이 꺼져 있어요. 알림 설정에서 허용하면 진행 시간을 알림창에서도 볼 수 있어요.',
          );
          await channel.invokeMethod<void>('start', {
            'owner': owner,
            'subject': timer.task?.name ?? '과목 연결 없음',
            'elapsedMs': timer.elapsed.inMilliseconds,
            'endUtcMs': timer.endOfDayUtc!.millisecondsSinceEpoch,
            'running': running,
          });
        })
        .catchError((Object e) {
          if (e is MissingPluginException) {
            enabled = false;
          } else {
            _notice('진행 알림을 표시하지 못했어요. 앱 안에서 측정은 계속할 수 있어요.');
          }
        });
    return _pending;
  }

  void _retireActive() {
    _turn++;
    if (_owner case final owner?) _retired.add(owner);
    _owner = null;
    _timer = null;
    _taskId = null;
    _signature = null;
  }

  void clear() {
    _retireActive();
    _pending = _pending.then((_) => _stops()).catchError((Object _) {});
  }

  Future<bool> stopForWithdrawal() async {
    _retireActive();
    if (!enabled) return true;
    final turn = _turn;
    final stopping = _pending.then((_) => _stops());
    _pending = stopping.catchError((Object _) {});
    try {
      await stopping;
      return !_disposed && turn == _turn;
    } on MissingPluginException {
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int?> elapsed() async {
    if (!enabled || _disposed || _owner == null) return null;
    try {
      return await channel.invokeMethod<int>('elapsed', {'owner': _owner});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> openSettings() async {
    if (!enabled || _disposed) return;
    try {
      await channel.invokeMethod<void>('openSettings');
    } on PlatformException {
      _notice('기기의 설정에서 PASS PACE 알림을 허용해 주세요.');
    } on MissingPluginException {
      enabled = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    clear();
    if (handlerOwner == instance) channel.setMethodCallHandler(null);
    super.dispose();
  }
}
