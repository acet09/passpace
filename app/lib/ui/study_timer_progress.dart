import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/models.dart';
import '../data/study_models.dart';
import '../data/study_timer.dart';
import 'design.dart';
import 'study_subject_history.dart';

/// Displays existing plan minutes; it never changes a plan or timer measurement.
class StudyTimerProgress extends StatefulWidget {
  final PassApi api;
  final StudyTaskChoice? task;
  final DateTime date;
  final Duration elapsed;
  final String label;
  final bool active;
  final StudyTimerPhase phase;
  final double maxDiameter;
  final bool Function() canRead;
  final VoidCallback onForbidden;
  const StudyTimerProgress({
    super.key,
    required this.api,
    required this.task,
    required this.date,
    required this.elapsed,
    required this.label,
    required this.canRead,
    required this.onForbidden,
    this.active = true,
    this.phase = StudyTimerPhase.paused,
    this.maxDiameter = 320,
  });

  Object get selection => (
    task?.id,
    task?.planId,
    task?.planVersion,
    task?.subjectId,
    task?.subjectName,
    task?.certificationName,
    task?.status,
    isoDay(date),
  );

  @override
  State<StudyTimerProgress> createState() => _StudyTimerProgressState();
}

class _StudyTimerProgressState extends State<StudyTimerProgress>
    with WidgetsBindingObserver {
  int epoch = 0;
  int? allocated, savedMinutes;
  bool loading = false, failed = false, refreshNeeded = false;
  String? message;
  bool get pendingSave =>
      widget.phase == StudyTimerPhase.saving ||
      widget.phase == StudyTimerPhase.uncertain;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(load());
  }

  @override
  void didUpdateWidget(covariant StudyTimerProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        !identical(oldWidget.api, widget.api) ||
        oldWidget.selection != widget.selection;
    if (changed) {
      allocated = null;
      savedMinutes = null;
      message = null;
      failed = false;
      refreshNeeded = false;
    }
    if (!widget.active || pendingSave) {
      epoch++;
    } else if (changed ||
        refreshNeeded ||
        widget.elapsed < oldWidget.elapsed ||
        !oldWidget.active ||
        oldWidget.phase != widget.phase &&
            ({
                  StudyTimerPhase.saving,
                  StudyTimerPhase.uncertain,
                  StudyTimerPhase.saved,
                }.contains(oldWidget.phase) ||
                widget.phase == StudyTimerPhase.saved)) {
      unawaited(load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) {
      unawaited(load());
    }
  }

  @override
  void dispose() {
    epoch++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool current(int turn, PassApi api) {
    if (!mounted ||
        epoch != turn ||
        !widget.active ||
        !identical(api, widget.api)) {
      return false;
    }
    if (pendingSave || !widget.canRead()) {
      refreshNeeded = true;
      return false;
    }
    return true;
  }

  void finish(String text, {int? minutes, int? saved}) => setState(() {
    message = text;
    allocated = minutes;
    savedMinutes = saved;
    loading = false;
  });

  Future<void> load() async {
    if (!widget.active) return;
    if (pendingSave || !widget.canRead()) {
      refreshNeeded = true;
      return;
    }
    final api = widget.api, task = widget.task, date = widget.date;
    final turn = ++epoch;
    setState(() {
      allocated = null;
      savedMinutes = null;
      failed = false;
      loading = true;
      refreshNeeded = false;
      message = null;
    });
    if (task == null) {
      finish('과목을 선택하면 배정 시간을 보여드려요.');
      return;
    }
    const chooseAgain = '현재 계획에서 과목을 다시 선택해 주세요.';
    if (task.status != 'ACTIVE') {
      finish(chooseAgain);
      return;
    }
    try {
      final plan = await api.saved();
      if (!current(turn, api)) return;
      if (plan == null) {
        finish('현재 학습계획이 없어요.');
        return;
      }
      if (plan.id != task.planId || plan.version != task.planVersion) {
        finish(chooseAgain);
        return;
      }
      final choices = <StudyTaskChoice>[];
      for (var page = 0; page <= 10000; page++) {
        final result = await api.studyPlanTasks(page: page);
        if (!current(turn, api)) return;
        if (result.page != page ||
            result.items.any((t) => t.status != 'ACTIVE')) {
          throw const FormatException('Unexpected current plan tasks');
        }
        choices.addAll(result.items);
        if (!result.hasNext) break;
        if (page == 10000 || result.items.isEmpty) {
          throw const FormatException('Incomplete current plan tasks');
        }
      }
      final linked = choices.where((t) => t.id == task.id).firstOrNull;
      if (linked == null ||
          linked.planId != task.planId ||
          linked.planVersion != task.planVersion ||
          linked.subjectId != task.subjectId ||
          linked.subjectName?.trim() != task.subjectName?.trim() ||
          linked.certificationName?.trim() != task.certificationName?.trim()) {
        finish(chooseAgain);
        return;
      }
      final subject = linked.subjectName?.trim() ?? '',
          exam = linked.certificationName?.trim() ?? '';
      final ids = choices
          .where(
            (t) =>
                t.planId == linked.planId &&
                t.subjectName?.trim() == subject &&
                t.certificationName?.trim() == exam,
          )
          .map((t) => t.subjectId)
          .toSet();
      if (subject.isEmpty || exam.isEmpty || ids.length != 1) {
        finish('이 과목의 배정 시간을 구분할 수 없어요.');
        return;
      }
      final tasks = plan
          .on(date)
          .where((t) => t.subject.trim() == subject && t.exam.trim() == exam);
      if (tasks.any((t) => t.minutes < 0)) {
        throw const FormatException('Invalid allocated minutes');
      }
      final minutes = tasks.fold(0, (n, t) => n + t.minutes);
      final saved = await savedSubjectMinutes(
        api,
        date,
        linked,
        choices,
        isCurrent: () => current(turn, api),
      );
      if (!current(turn, api) || saved == null) return;
      finish(
        minutes == 0 ? '이 날짜에 계획된 학습 없음' : '',
        minutes: minutes,
        saved: saved,
      );
    } catch (e) {
      if (!current(turn, api)) return;
      if (e is ApiError && (e.status == 401 || e.status == 403)) {
        widget.onForbidden();
        return;
      }
      setState(() {
        loading = false;
        failed = true;
        allocated = null;
        savedMinutes = null;
        message = e is StudyHistoryLinkError
            ? '기록의 과목 연결을 확인해 주세요.'
            : '학습 시간 정보를 불러오지 못했어요.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final minutes = allocated ?? 0;
    final elapsed = widget.phase == StudyTimerPhase.saved
        ? Duration.zero
        : widget.elapsed;
    final total = Duration(minutes: savedMinutes ?? 0) + elapsed;
    final value = minutes > 0
        ? (total.inMilliseconds / (minutes * 60000)).clamp(0.0, 1.0)
        : 0.0;
    final percent = (value * 100).floor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final size = math.min(constraints.maxWidth, widget.maxDiameter);
            return Center(
              child: SizedBox.square(
                dimension: size,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: value),
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 200),
                          builder: (_, progress, _) => Semantics(
                            excludeSemantics: minutes == 0,
                            label: minutes == 0 ? '배정 시간 없음' : null,
                            child: CircularProgressIndicator(
                              key: const ValueKey('study-timer-progress'),
                              value: progress,
                              strokeWidth: 14,
                              strokeCap: StrokeCap.round,
                              color: blue,
                              backgroundColor: const Color(0xffdce4f6),
                              semanticsLabel:
                                  '선택 과목 배정 시간 대비 저장 기록과 이번 측정의 누적 시간',
                              semanticsValue: '$percent%',
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(36),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            label:
                                '측정한 시간 ${widget.elapsed.inHours}시간 ${widget.elapsed.inMinutes % 60}분 ${widget.elapsed.inSeconds % 60}초',
                            child: ExcludeSemantics(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  widget.label,
                                  key: const ValueKey('study-timer-clock'),
                                  style: const TextStyle(
                                    fontSize: 46,
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (minutes > 0) ...[
                            const SizedBox(height: 12),
                            Text(
                              '배정 ${durationLabel(minutes)}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: muted,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Text(
          pendingSave
              ? widget.phase == StudyTimerPhase.uncertain
                    ? '저장 결과 확인 후 누적 시간을 갱신해요.'
                    : '기록 저장 중…'
              : loading
              ? '학습 시간 불러오는 중…'
              : minutes > 0
              ? value >= 1
                    ? '누적 ${timeLabel(total)} · 배정 시간 도달'
                    : '누적 ${timeLabel(total)} · 배정 시간의 $percent%'
              : message ?? '배정 시간 없음',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: minutes > 0 ? blue : muted,
            fontWeight: minutes > 0 ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        if (savedMinutes != null &&
            !pendingSave &&
            widget.phase != StudyTimerPhase.saved &&
            (minutes > 0 || savedMinutes! > 0)) ...[
          const SizedBox(height: 6),
          Text(
            '저장 ${durationLabel(savedMinutes!)} + 이번 측정 ${timeLabel(elapsed)}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 13),
          ),
        ],
        ...[
          const SizedBox(height: 6),
          Text(
            '${isoDay(widget.date)} · 배정 기준',
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 13),
          ),
        ],
        if (failed)
          TextButton(onPressed: load, child: const Text('학습 시간 다시 불러오기')),
      ],
    );
  }

  String timeLabel(Duration time) {
    final seconds = time.inSeconds % 60;
    if (time.inMinutes == 0) return '$seconds초';
    return '${durationLabel(time.inMinutes)}${seconds == 0 ? '' : ' $seconds초'}';
  }
}
