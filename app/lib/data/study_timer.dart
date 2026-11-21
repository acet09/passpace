import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'plan_draft.dart';
import 'study_models.dart';

enum StudyTimerPhase { idle, running, paused, saving, uncertain, saved }

/// Device-local measurement. The existing record API remains authoritative.
class StudyTimer extends ChangeNotifier {
  final PlanDraftStorage storage;
  final String key;
  final DateTime Function() now;
  final Stopwatch _watch = Stopwatch()..start();
  late final int Function() ticks;
  StudyTimer(
    this.storage,
    String origin,
    String userId, {
    DateTime Function()? now,
    int Function()? ticks,
  }) : now = now ?? DateTime.now,
       key =
           'passpace.study-timer.v1.${base64Url.encode(utf8.encode('${Uri.parse(origin).origin}\n$userId'))}' {
    this.ticks = ticks ?? () => _watch.elapsedMilliseconds;
  }

  StudyTimerPhase phase = StudyTimerPhase.idle;
  DateTime? date;
  StudyTaskChoice? task;
  bool restoring = true, loadFailed = false, dayEnded = false;
  String? error, notice;
  int _milliseconds = 0, _anchorTicks = 0, _writes = 0;
  DateTime? _anchor;
  bool _alive = true, _reading = false;
  Future<void> _pending = Future.value();
  bool get storing => _writes > 0;
  bool get locked =>
      phase == StudyTimerPhase.saving ||
      phase == StudyTimerPhase.uncertain ||
      phase == StudyTimerPhase.saved;
  bool get available => _alive && !restoring && !loadFailed && !storing;
  DateTime _day(DateTime instant) {
    final seoul = instant.toUtc().add(const Duration(hours: 9));
    return DateTime(seoul.year, seoul.month, seoul.day);
  }

  DateTime get _boundary => DateTime.utc(
    date!.year,
    date!.month,
    date!.day + 1,
  ).subtract(const Duration(hours: 9));
  DateTime? get endOfDayUtc => date == null ? null : _boundary;

  Future<void> alignElapsed(int milliseconds) async {
    if (!_alive ||
        loadFailed ||
        restoring ||
        date == null ||
        locked ||
        !(phase == StudyTimerPhase.running ||
            phase == StudyTimerPhase.paused && dayEnded) ||
        milliseconds <= _measured ||
        milliseconds > 86400000) {
      return;
    }
    _milliseconds = milliseconds;
    if (now().toUtc().isBefore(_boundary) && phase == StudyTimerPhase.running) {
      _anchor = now().toUtc();
      _anchorTicks = ticks();
    } else {
      phase = StudyTimerPhase.paused;
      _anchor = null;
      dayEnded = true;
    }
    await _write();
  }

  int get _measured {
    final anchor = _anchor;
    if (phase != StudyTimerPhase.running || anchor == null) {
      return _milliseconds;
    }
    final passed = math.max(0, ticks() - _anchorTicks);
    final remaining = math.max(0, _boundary.difference(anchor).inMilliseconds);
    return math.min(86400000, _milliseconds + math.min(passed, remaining));
  }

  Duration get elapsed => Duration(milliseconds: _measured);
  int get minutes => elapsed.inMinutes;
  String get label {
    final seconds = elapsed.inSeconds;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(seconds ~/ 3600)}:${two(seconds ~/ 60 % 60)}:${two(seconds % 60)}';
  }

  void _notify() {
    if (_alive) notifyListeners();
  }

  Future<void> restore() async {
    if (_reading || !_alive) return;
    _reading = true;
    restoring = true;
    loadFailed = false;
    error = null;
    _notify();
    try {
      final raw = await storage.read(key);
      if (!_alive) return;
      phase = StudyTimerPhase.idle;
      date = null;
      task = null;
      _anchor = null;
      _milliseconds = 0;
      dayEnded = false;
      notice = null;
      if (raw != null) {
        final data = object(jsonDecode(raw));
        if (data['schema'] != 1) throw const FormatException('Timer schema');
        phase = StudyTimerPhase.values.byName(data['phase'] as String);
        date = data['date'] == null ? null : studyDate(data['date']);
        final amount = data['milliseconds'];
        if (amount is! int ||
            amount < 0 ||
            amount > 86400000 ||
            phase != StudyTimerPhase.idle && date == null) {
          throw const FormatException('Timer data');
        }
        _milliseconds = amount;
        task = data['task'] == null
            ? null
            : StudyTaskChoice.from(object(data['task']));
        dayEnded = data['dayEnded'] == true;
        if (phase == StudyTimerPhase.saving) phase = StudyTimerPhase.uncertain;
        if (phase == StudyTimerPhase.running) {
          final anchorText = data['anchor'] as String;
          final anchor = DateTime.parse(anchorText);
          if (!anchorText.endsWith('Z') || _day(anchor) != date) {
            throw const FormatException('Timer anchor');
          }
          final current = now().toUtc();
          final delta = current.difference(anchor).inMilliseconds;
          if (delta < 0) {
            phase = StudyTimerPhase.paused;
            notice = '기기 시간이 바뀌어 측정을 멈췄어요. 시간을 확인해 주세요.';
          } else {
            final remaining = math.max(
              0,
              _boundary.difference(anchor).inMilliseconds,
            );
            _milliseconds = math.min(
              86400000,
              amount + math.min(delta, remaining),
            );
            if (delta >= remaining || _day(current) != date) {
              phase = StudyTimerPhase.paused;
              dayEnded = true;
            } else {
              _anchor = current;
              _anchorTicks = ticks();
            }
          }
        }
      }
    } catch (_) {
      loadFailed = true;
      error = '저장한 타이머를 불러오지 못했어요. 다시 불러오거나 초기화해 주세요.';
    } finally {
      _reading = false;
      restoring = false;
      _notify();
    }
  }

  Future<bool> _write({bool clear = false}) async {
    if (!_alive) return false;
    final value = clear
        ? null
        : jsonEncode({
            'schema': 1,
            'phase': phase.name,
            'date': date == null ? null : isoDay(date!),
            'milliseconds': _milliseconds,
            'anchor': _anchor?.toUtc().toIso8601String(),
            'task': task?.toJson(),
            'dayEnded': dayEnded,
          });
    _writes++;
    error = null;
    _notify();
    final operation = _pending.then((_) => storage.write(key, value));
    _pending = operation.catchError((Object _) {});
    try {
      await operation;
      return true;
    } catch (_) {
      error = '기기에 타이머 상태를 저장하지 못했어요. 다시 시도해 주세요.';
      return false;
    } finally {
      _writes--;
      _notify();
    }
  }

  Future<bool> start() async {
    if (!available || locked || phase == StudyTimerPhase.running || dayEnded) {
      return false;
    }
    final current = now().toUtc();
    if (date != null && date != _day(current)) {
      dayEnded = true;
      await _write();
      return false;
    }
    date ??= _day(current);
    _anchor = current;
    _anchorTicks = ticks();
    phase = StudyTimerPhase.running;
    notice = null;
    if (!await _write()) {
      _capture();
      _notify();
      return false;
    }
    return true;
  }

  void _capture() {
    _milliseconds = _measured;
    _anchor = null;
    phase = StudyTimerPhase.paused;
  }

  Future<bool> pause() async {
    if (phase != StudyTimerPhase.running) return true;
    _capture();
    return _write();
  }

  void tick() {
    if (restoring || loadFailed || phase != StudyTimerPhase.running) return;
    if (now().toUtc().isAfter(_boundary) ||
        _measured - _milliseconds >=
            _boundary.difference(_anchor!).inMilliseconds) {
      _capture();
      dayEnded = true;
      unawaited(_write());
    }
    _notify();
  }

  Future<bool> choose(StudyTaskChoice? value) async {
    if (!available || locked || phase == StudyTimerPhase.running) return false;
    task = value;
    return _write();
  }

  Future<bool> beginSave() async {
    if (!available || phase != StudyTimerPhase.paused || minutes < 1) {
      return false;
    }
    phase = StudyTimerPhase.saving;
    if (!await _write()) {
      phase = StudyTimerPhase.paused;
      _notify();
      return false;
    }
    return true;
  }

  Future<void> rejected() async {
    if (!_alive) return;
    phase = StudyTimerPhase.paused;
    await _write();
  }

  Future<void> uncertain() async {
    if (!_alive) return;
    phase = StudyTimerPhase.uncertain;
    await _write();
  }

  Future<void> complete() async {
    if (!_alive) return;
    phase = StudyTimerPhase.saved;
    if (await _write()) await reset();
  }

  Future<bool> retainAfterInspection() async {
    if (!available || phase != StudyTimerPhase.uncertain) return false;
    phase = StudyTimerPhase.paused;
    notice = '아직 저장하지 않은 측정 시간이 남아 있어요. 목록을 확인했다면 직접 저장해 주세요.';
    if (await _write()) return true;
    phase = StudyTimerPhase.uncertain;
    _notify();
    return false;
  }

  Future<bool> reset({bool verified = false}) async {
    if (storing ||
        phase == StudyTimerPhase.saving ||
        phase == StudyTimerPhase.uncertain && !verified) {
      return false;
    }
    if (!await _write(clear: true)) return false;
    phase = StudyTimerPhase.idle;
    date = null;
    task = null;
    _anchor = null;
    _milliseconds = 0;
    dayEnded = false;
    loadFailed = false;
    notice = null;
    _notify();
    return true;
  }

  @override
  void dispose() {
    _alive = false;
    _watch.stop();
    super.dispose();
  }
}
