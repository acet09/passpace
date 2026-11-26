import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/models.dart';
import '../data/study_history.dart';
import '../data/study_timer.dart';
import 'design.dart';

typedef TaskProgress = ({int taskId, Duration time});
typedef _RecordedStudy = ({
  int total,
  Map<int, int> byTask,
  Map<StudyTask, int> links,
});

class TodayStudyProgress extends StatefulWidget {
  final PassApi api;
  final SavedPlan? plan;
  final DateTime day;
  final int plannedMinutes;
  final Object refreshSignal;
  final StudyTimer? timer;
  final Widget Function(Map<StudyTask, TaskProgress>?, Widget?, Widget?)
  builder;

  const TodayStudyProgress({
    super.key,
    required this.api,
    required this.plan,
    required this.day,
    required this.plannedMinutes,
    required this.refreshSignal,
    required this.timer,
    required this.builder,
  });

  @override
  State<TodayStudyProgress> createState() => _TodayStudyProgressState();
}

class _TodayStudyProgressState extends State<TodayStudyProgress> {
  late Future<_RecordedStudy?> savedMinutes;
  int request = 0;
  late bool pending = pendingSave;

  bool get pendingSave =>
      widget.timer?.phase == StudyTimerPhase.saving ||
      widget.timer?.phase == StudyTimerPhase.uncertain;

  @override
  void initState() {
    super.initState();
    widget.timer?.addListener(timerChanged);
    savedMinutes = read();
  }

  @override
  void didUpdateWidget(TodayStudyProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timer != widget.timer) {
      oldWidget.timer?.removeListener(timerChanged);
      widget.timer?.addListener(timerChanged);
      pending = pendingSave;
    }
    if (oldWidget.api != widget.api ||
        oldWidget.day != widget.day ||
        oldWidget.plan?.id != widget.plan?.id ||
        oldWidget.plan?.version != widget.plan?.version ||
        oldWidget.refreshSignal != widget.refreshSignal) {
      savedMinutes = read();
    }
  }

  @override
  void dispose() {
    widget.timer?.removeListener(timerChanged);
    super.dispose();
  }

  Future<_RecordedStudy?> read() async {
    final turn = ++request;
    final api = widget.api, day = widget.day, plan = widget.plan;
    if (plan == null || plan.id == null) return null;
    bool current() => mounted && request == turn;
    final tasks = plan.on(day);
    final records = await readStudyHistory(api, day, day, isCurrent: current);
    if (records == null) return null;
    final links = {for (final task in tasks) task: ?task.id};
    if (links.length < tasks.length) {
      try {
        final choices = await readStudyTaskChoices(
          api,
          date: day,
          isCurrent: current,
        );
        if (choices == null) return null;
        for (final task in tasks.where((task) => task.id == null)) {
          if (tasks
                  .where(
                    (other) =>
                        other.exam.trim() == task.exam.trim() &&
                        other.subject.trim() == task.subject.trim(),
                  )
                  .length !=
              1) {
            continue;
          }
          final matches = choices
              .where(
                (choice) =>
                    choice.status == 'ACTIVE' &&
                    choice.planId == plan.id &&
                    choice.planVersion == plan.version &&
                    choice.scheduledDate == day &&
                    (choice.certificationName?.trim() ?? '') ==
                        task.exam.trim() &&
                    choice.subjectName?.trim() == task.subject.trim(),
              )
              .toList();
          if (matches.length == 1) links[task] = matches.single.id;
        }
      } on ApiError catch (error) {
        if (error.status == 401 || error.status == 403) rethrow;
        // Older servers can still supply the plan's total when task lookup fails.
      } on FormatException {
        // Leave unresolved rows without a numeric value.
      }
    }
    if (!current()) return null;
    final ids = links.length == tasks.length ? links.values.toSet() : null;
    final byTask = <int, int>{};
    var total = 0;
    for (final record in records) {
      if (record.planId != plan.id) continue;
      final id = record.taskId;
      if (ids != null && !ids.contains(id)) continue;
      total += record.minutes;
      if (id != null) {
        byTask.update(
          id,
          (n) => n + record.minutes,
          ifAbsent: () => record.minutes,
        );
      }
    }
    return (total: total, byTask: byTask, links: links);
  }

  void timerChanged() {
    if (!mounted) return;
    final saving = pendingSave;
    setState(() {
      if (pending && !saving) savedMinutes = read();
      pending = saving;
    });
  }

  Duration liveTime(Map<StudyTask, int> links) {
    final clock = widget.timer;
    final plan = widget.plan!;
    if (clock == null ||
        clock.date != widget.day ||
        clock.task?.planId != plan.id ||
        clock.task?.planVersion != plan.version ||
        (clock.phase != StudyTimerPhase.running &&
            clock.phase != StudyTimerPhase.paused)) {
      return Duration.zero;
    }
    if (links.length == plan.on(widget.day).length &&
        !links.containsValue(clock.task?.id)) {
      return Duration.zero;
    }
    return clock.elapsed;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_RecordedStudy?>(
    future: savedMinutes,
    builder: (context, snapshot) {
      if (widget.plan == null) return widget.builder(null, null, null);
      if (pendingSave) {
        return compose(status: const HelpText('저장 상태를 확인한 뒤 진행률을 표시해요.'));
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return compose(status: const HelpText('오늘 공부시간을 불러오는 중이에요.'));
      }
      final saved = snapshot.data;
      if (saved == null) {
        return compose(
          status: OutlinedButton(
            onPressed: () => setState(() => savedMinutes = read()),
            child: const Text('오늘 진행률 다시 불러오기'),
          ),
        );
      }
      final live = liveTime(saved.links);
      final total = Duration(minutes: saved.total) + live;
      final byTask = <StudyTask, TaskProgress>{
        for (final link in saved.links.entries)
          link.key: (
            taskId: link.value,
            time:
                Duration(minutes: saved.byTask[link.value] ?? 0) +
                (widget.timer?.task?.id == link.value ? live : Duration.zero),
          ),
      };
      return compose(
        studied: total,
        includesLiveTime: live > Duration.zero,
        byTask: byTask,
      );
    },
  );

  Widget compose({
    Duration? studied,
    bool includesLiveTime = false,
    Map<StudyTask, TaskProgress>? byTask,
    Widget? status,
  }) => widget.builder(
    byTask,
    TodayProgressSummary(
      plannedMinutes: widget.plannedMinutes,
      studied: studied,
      includesLiveTime: includesLiveTime,
    ),
    status ??
        (byTask != null && byTask.length < widget.plan!.on(widget.day).length
            ? TextButton(
                onPressed: () => setState(() => savedMinutes = read()),
                child: const Text('과목 연결 다시 확인'),
              )
            : null),
  );
}

class TodayProgressSummary extends StatelessWidget {
  final int plannedMinutes;
  final Duration? studied;
  final bool includesLiveTime;

  const TodayProgressSummary({
    super.key,
    required this.plannedMinutes,
    this.studied,
    this.includesLiveTime = false,
  });

  static const title = '오늘 전체 진행률';

  @override
  Widget build(BuildContext context) {
    final progressBar = StudyProgressBar(
      barKey: const ValueKey('today-study-progress'),
      label: title,
      studied: studied,
      plannedMinutes: plannedMinutes,
      detail: includesLiveTime ? '측정 시간 포함' : '',
      trackColor: const Color(0xffe2e7ee),
      header: (percent) {
        final progress = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HelpText(title),
            Text(
              percent,
              style: const TextStyle(
                fontSize: 38,
                height: 1.15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        );
        final times = Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            _timeRow(
              '공부',
              studied == null ? '—' : durationLabel(studied!.inMinutes),
            ),
            _timeRow('배정', durationLabel(plannedMinutes)),
          ],
        );
        return LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            if (constraints.maxWidth < 210 * scale) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [progress, const SizedBox(height: 6), times],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: progress),
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: 12,
                    bottom: 3,
                  ),
                  child: times,
                ),
              ],
            );
          },
        );
      },
    );
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xffdde4ee)),
      ),
      child: Stack(
        children: [
          Padding(padding: const EdgeInsets.all(14), child: progressBar),
          const PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: ColoredBox(
              key: ValueKey('today-progress-accent'),
              color: blue,
            ),
          ),
        ],
      ),
    );
  }

  TableRow _timeRow(String label, String value) => TableRow(
    children: [
      Padding(
        padding: const EdgeInsetsDirectional.only(end: 10, bottom: 2),
        child: HelpText(label),
      ),
      Text(
        value,
        textAlign: TextAlign.end,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    ],
  );
}

class StudyProgressBar extends StatelessWidget {
  final Key barKey;
  final String label, detail;
  final Duration? studied;
  final int plannedMinutes;
  final bool compact;
  final Color trackColor;
  final Color? fillColor;
  final Widget Function(String percent)? header;

  const StudyProgressBar({
    super.key,
    required this.barKey,
    required this.label,
    required this.detail,
    required this.studied,
    required this.plannedMinutes,
    this.compact = false,
    this.trackColor = pale,
    this.fillColor,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    final time = studied;
    final fraction = time == null || plannedMinutes <= 0
        ? null
        : (time.inMilliseconds /
                  Duration(minutes: plannedMinutes).inMilliseconds)
              .clamp(0.0, 1.0);
    final percent = fraction == null ? '—' : '${(fraction * 100).floor()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header?.call(percent) ??
            Row(
              children: [
                Expanded(child: HelpText(detail)),
                const SizedBox(width: 6),
                Text(
                  percent,
                  style: const TextStyle(
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
        SizedBox(height: compact ? 5 : 8),
        if (fraction == null)
          Semantics(
            label: '$label 확인 중',
            child: SizedBox(
              height: compact ? 5 : 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: trackColor,
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                ),
              ),
            ),
          )
        else
          LinearProgressIndicator(
            key: barKey,
            value: fraction,
            minHeight: compact ? 5 : 8,
            borderRadius: const BorderRadius.all(Radius.circular(8)),
            backgroundColor: trackColor,
            color: fillColor,
            semanticsLabel: label,
            semanticsValue: percent,
          ),
        if (!compact && detail.isNotEmpty) ...[
          const SizedBox(height: 6),
          HelpText(detail),
        ],
      ],
    );
  }
}
