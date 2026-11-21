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
      _retired.remove(owner);
      await channel.invokeMethod<void>('stop', {'owner': owner});
    }
  }

  Future<void> sync(StudyTimer timer, {bool refresh = false}) {
    if (!enabled || _disposed || timer.restoring || timer.storing) {
      return Future.value();
    }
    final running = timer.phase == StudyTimerPhase.running && !timer.loadFailed;
    final signature =
        '${timer.phase.name}:${timer.task?.id}:${timer.task?.name}';
    final changedOwner =
        !identical(timer, _timer) ||
        running && !(_signature?.startsWith('running:') ?? false);
    if (!refresh && !changedOwner && signature == _signature) return _pending;
    if (changedOwner) {
      if (_owner != null) _retired.add(_owner!);
      _owner = 'study-${DateTime.now().microsecondsSinceEpoch}-${++serial}';
    }
    _timer = timer;
    _signature = signature;
    final turn = ++_turn, owner = _owner!;
    _pending = _pending
        .then((_) async {
          await _stops();
          if (_disposed || turn != _turn) return;
          if (!running) {
            await channel.invokeMethod<void>('stop', {'owner': owner});
            return;
          }
          final allowed = !_asked
              ? await channel.invokeMethod<bool>('requestPermission')
              : await channel.invokeMethod<bool>('notificationAllowed');
          _asked = true;
          if (_disposed ||
              turn != _turn ||
              timer.phase != StudyTimerPhase.running) {
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
    _turn++;
    if (_owner != null) _retired.add(_owner!);
    _pending = _pending.then((_) => _stops()).catchError((Object _) {});
    if (handlerOwner == instance) channel.setMethodCallHandler(null);
    super.dispose();
  }
}
