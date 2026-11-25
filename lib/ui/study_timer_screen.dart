import 'dart:async';

import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/models.dart';
import '../data/session.dart';
import '../data/study_timer.dart';
import '../data/study_models.dart';
import 'design.dart';
import 'study_task_picker.dart';
import 'subject_color_picker.dart';
import 'study_timer_progress.dart';

String studyTimerStatus(StudyTimer timer) => switch (timer.phase) {
  StudyTimerPhase.idle => '시작할 준비가 됐어요',
  StudyTimerPhase.running => '측정 중',
  StudyTimerPhase.paused => '일시정지',
  StudyTimerPhase.saving => '저장 중',
  StudyTimerPhase.uncertain => '저장 결과 확인 필요',
  StudyTimerPhase.saved => '저장 완료',
};

/// Reuses the confirmed save's choice without changing explicit reset behavior.
Future<void> restoreSavedTimerSubject(
  StudyTimer clock,
  StudyTaskChoice? subject,
  Session session,
  PassApi? owner,
) async {
  if (subject != null &&
      owner != null &&
      identical(owner, session.account) &&
      clock.available &&
      clock.phase == StudyTimerPhase.idle &&
      clock.elapsed == Duration.zero &&
      clock.task == null) {
    await clock.choose(subject);
  }
}

class StudyTimerScreen extends StatefulWidget {
  final Session session;
  final StudyTimer timer;
  final VoidCallback onForbidden;
  final void Function(DateTime, int) onUncertain;
  final bool embedded;
  final VoidCallback? onHistory;
  final ValueChanged<StudyRecord>? onSaved;
  final String? notificationNotice;
  final VoidCallback? onNotificationSettings;
  final bool active;
  final bool Function()? canSave;
  final StudySubjectColor? colorForSubject;
  const StudyTimerScreen(
    this.session,
    this.timer, {
    super.key,
    required this.onForbidden,
    required this.onUncertain,
    this.embedded = false,
    this.onHistory,
    this.onSaved,
    this.notificationNotice,
    this.onNotificationSettings,
    this.active = true,
    this.canSave,
    this.colorForSubject,
  });
  @override
  State<StudyTimerScreen> createState() => _StudyTimerScreenState();
}

class _StudyTimerScreenState extends State<StudyTimerScreen> {
  late final PassApi account;
  bool blocked = false;
  String? error;
  StudyTimer get timer => widget.timer;
  Color? get taskColor {
    final task = timer.task;
    return task == null ? null : widget.colorForSubject?.call(task);
  }

  @override
  void initState() {
    super.initState();
    account = widget.session.account!;
    widget.session.addListener(accountChanged);
  }

  void accountChanged() {
    if (mounted && !identical(account, widget.session.account)) {
      unawaited(timer.pause());
      setState(() => blocked = true);
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(accountChanged);
    super.dispose();
  }

  bool get current =>
      mounted && !blocked && identical(account, widget.session.account);

  Future<void> choose() async {
    if (!await timer.pause() ||
        !mounted ||
        !current ||
        !timer.available ||
        timer.locked) {
      return;
    }
    final result = await Navigator.push<StudyTaskSelection>(
      context,
      MaterialPageRoute(
        builder: (_) => StudyTaskPicker(
          widget.session,
          date: timer.date ?? dayInSeoul(),
          selectedId: timer.task?.id,
          colorForSubject: widget.colorForSubject,
          onForbidden: () {
            widget.onForbidden();
            if (mounted) setState(() => blocked = true);
          },
        ),
      ),
    );
    if (current && result != null) await timer.choose(result.task);
  }

  Future<void> save() async {
    final clock = timer,
        session = widget.session,
        owner = account,
        onSaved = widget.onSaved;
    if (widget.canSave?.call() == false) {
      setState(() => error = '열려 있는 기록 입력을 마친 뒤 저장해 주세요.');
      return;
    }
    if (!current || !await clock.beginSave()) return;
    if (!current) {
      await clock.rejected();
      return;
    }
    final date = clock.date!, minutes = clock.minutes, task = clock.task;
    try {
      final record = await account.saveStudySession(date, minutes, task: task);
      if (record.date != date ||
          record.minutes != minutes ||
          record.taskId != task?.id) {
        throw const StudySaveUncertain();
      }
      await clock.complete();
      await restoreSavedTimerSubject(clock, task, session, owner);
      if (identical(owner, session.account)) {
        if (onSaved != null) {
          onSaved(record);
        } else if (mounted && current) {
          Navigator.pop(context, record);
        }
      }
    } catch (e) {
      if (e is ApiError &&
          e.status != null &&
          e.status! >= 400 &&
          e.status! < 500) {
        await clock.rejected();
        if (current) {
          if (e.status == 401 || e.status == 403) {
            widget.onForbidden();
            setState(() => blocked = true);
          } else {
            setState(() => error = friendly(e));
          }
        }
      } else {
        await clock.uncertain();
        if (current) widget.onUncertain(date, minutes);
      }
    }
  }

  Future<void> prepareNext() async {
    if (!current) return;
    final clock = timer,
        subject = timer.task,
        session = widget.session,
        owner = account;
    if (await clock.reset()) {
      await restoreSavedTimerSubject(clock, subject, session, owner);
    }
  }

  Future<void> reset() async {
    if (timer.elapsed > Duration.zero || timer.loadFailed) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('측정을 초기화할까요?'),
          content: const Text('아직 저장하지 않은 측정 시간이 지워져요. 이미 저장한 학습기록은 그대로 유지돼요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('초기화'),
            ),
          ],
        ),
      );
      if (ok != true || !current) return;
    }
    await timer.pause();
    if (current) await timer.reset();
  }

  Future<void> toggleMeasurement() async {
    setState(() => error = null);
    if (timer.phase == StudyTimerPhase.running) {
      await timer.pause();
    } else {
      await timer.start();
    }
  }

  List<Widget> measurementActions() {
    final phase = timer.phase;
    final paused = phase == StudyTimerPhase.paused;
    final saving = phase == StudyTimerPhase.saving;
    final readyToSave = paused && timer.available && timer.minutes > 0;
    final showMeasurementAction = !readyToSave && !saving && !timer.dayEnded;
    final remainingSeconds = timer.elapsed.inSeconds % 60;

    return [
      if (showMeasurementAction)
        PrimaryAction(switch (phase) {
          StudyTimerPhase.running => '일시정지',
          StudyTimerPhase.idle => '측정 시작',
          _ => '계속 측정',
        }, timer.available ? toggleMeasurement : null),
      if (paused || saving) ...[
        if (showMeasurementAction) const SizedBox(height: 8),
        OutlinedButton(
          onPressed: readyToSave ? save : null,
          style: readyToSave
              ? OutlinedButton.styleFrom(
                  backgroundColor: blue,
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: blue),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : null,
          child: Text(saving ? '저장 중…' : '기록 저장'),
        ),
        if (paused && (timer.minutes == 0 || remainingSeconds != 0)) ...[
          const SizedBox(height: 8),
          HelpText(
            timer.minutes == 0
                ? '1분 이상 측정하면 기록을 저장할 수 있어요.'
                : '${durationLabel(timer.minutes)}을 저장해요. 남은 $remainingSeconds초는 제외돼요.',
          ),
        ],
      ],
      if (!saving)
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            if (readyToSave && !timer.dayEnded)
              TextButton(
                onPressed: toggleMeasurement,
                child: const Text('계속 측정'),
              ),
            if (phase != StudyTimerPhase.idle || timer.task != null)
              TextButton(
                onPressed: timer.available ? reset : null,
                child: Text(
                  phase == StudyTimerPhase.idle ? '과목 연결 해제' : '측정 초기화',
                ),
              ),
          ],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: timer,
    builder: (context, _) => PopScope(
      canPop:
          !widget.active ||
          timer.phase != StudyTimerPhase.saving && !timer.storing,
      child: Scaffold(
        appBar: widget.embedded ? null : AppBar(title: const Text('집중 타이머')),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => blocked
                ? const ScrollBody(
                    children: [
                      AlertText('로그인 상태가 바뀌었어요. 이전 화면으로 돌아가 다시 확인해 주세요.'),
                    ],
                  )
                : ScrollBody(
                    children: [
                      TextButton(
                        onPressed: timer.available && !timer.locked
                            ? choose
                            : null,
                        style: TextButton.styleFrom(
                          alignment: AlignmentDirectional.centerStart,
                          foregroundColor: ink,
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: line),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.menu_book_outlined, color: blue),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '과목 선택',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: muted,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        if (taskColor case final color?) ...[
                                          SubjectColorDot(color),
                                          const SizedBox(width: 8),
                                        ],
                                        Expanded(
                                          child: Text(
                                            timer.task?.name ?? '과목 연결 없음',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (timer.phase == StudyTimerPhase.running ||
                          timer.phase == StudyTimerPhase.paused)
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            studyTimerStatus(timer),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: muted),
                          ),
                        ),
                      if (timer.phase == StudyTimerPhase.saved) ...[
                        const HelpText('학습기록을 저장했어요.'),
                        const SizedBox(height: 8),
                        PrimaryAction(
                          '새 측정 준비',
                          timer.storing ? null : prepareNext,
                        ),
                        const SizedBox(height: 14),
                      ],
                      StudyTimerProgress(
                        api: account,
                        task: timer.task,
                        subjectColor: taskColor,
                        date: timer.date ?? dayInSeoul(),
                        elapsed: timer.elapsed,
                        label: timer.label,
                        active: widget.active,
                        maxDiameter: (constraints.maxHeight * .43).clamp(
                          200.0,
                          288.0,
                        ),
                        phase: timer.phase,
                        canRead: () =>
                            current &&
                            timer.phase != StudyTimerPhase.saving &&
                            timer.phase != StudyTimerPhase.uncertain,
                        onForbidden: () {
                          if (!current) return;
                          widget.onForbidden();
                          setState(() => blocked = true);
                        },
                      ),
                      const SizedBox(height: 16),
                      if (timer.error != null) AlertText(timer.error!),
                      if (error != null) AlertText(error!),
                      if (timer.notice != null) AlertText(timer.notice!),
                      if (timer.dayEnded)
                        const AlertText(
                          '날짜가 바뀌어 측정을 멈췄어요. 저장하거나 초기화한 뒤 새로 시작해 주세요.',
                        ),
                      if (timer.restoring)
                        const Center(
                          child: CircularProgressIndicator(
                            semanticsLabel: '타이머 불러오는 중',
                          ),
                        )
                      else if (timer.loadFailed) ...[
                        PrimaryAction('다시 불러오기', timer.restore),
                        TextButton(
                          onPressed: reset,
                          child: const Text('타이머 초기화'),
                        ),
                      ] else if (timer.phase == StudyTimerPhase.uncertain) ...[
                        const AlertText(
                          '저장 결과를 확인하지 못했어요. 같은 기록이 있는지 목록을 확인해 주세요. 확인 전에는 다시 저장하지 않아요.',
                        ),
                        PrimaryAction(
                          '기록 목록에서 확인',
                          widget.onHistory ?? () => Navigator.pop(context),
                        ),
                      ] else if (timer.phase != StudyTimerPhase.saved)
                        ...measurementActions(),
                      if (widget.notificationNotice != null) ...[
                        AlertText(widget.notificationNotice!),
                        TextButton(
                          onPressed: widget.onNotificationSettings,
                          child: const Text('알림 설정'),
                        ),
                      ],
                      if (timer.phase == StudyTimerPhase.idle &&
                          timer.available &&
                          !timer.locked)
                        const HelpText(
                          '다른 앱을 열어도 측정이 이어지며 자정에 멈춰요. 일시정지 시간은 공부시간에서 빼요.',
                        ),
                    ],
                  ),
          ),
        ),
      ),
    ),
  );
}
