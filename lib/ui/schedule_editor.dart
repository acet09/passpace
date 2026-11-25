import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/api.dart';
import '../data/models.dart';
import 'design.dart';

enum ScheduleEditResult { saved, reload }

const scheduleServerMessage = '일정을 수정하려면 1122jhg 서버에 연결해 주세요.';

bool canEditTask(SavedPlan plan, StudyTask task) =>
    plan.id != null && task.id != null && !task.date.isBefore(dayInSeoul());

Future<ScheduleEditResult?> showScheduleEditor(
  BuildContext context,
  PassApi api,
  SavedPlan plan, {
  StudyTask? task,
  bool moveOnly = false,
}) async {
  final today = dayInSeoul();
  if (!plan.canEditSchedule ||
      task != null && !canEditTask(plan, task) ||
      moveOnly && task?.date != today) {
    return null;
  }
  final first = today.isAfter(plan.start) ? today : plan.start;
  if (moveOnly && !plan.end.isAfter(first)) {
    toast(context, '계획 기간 안에 옮길 수 있는 날짜가 없어요.');
    return null;
  }
  final result = await showDialog<ScheduleEditResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ScheduleEditor(api, plan, task, moveOnly),
  );
  if (context.mounted && result == ScheduleEditResult.saved) {
    toast(
      context,
      moveOnly
          ? '학습 날짜를 옮겼어요.'
          : task != null
          ? '학습 일정을 수정했어요.'
          : '계획 기간을 수정했어요.',
    );
  }
  return result;
}

class _ScheduleEditor extends StatefulWidget {
  final PassApi api;
  final SavedPlan plan;
  final StudyTask? task;
  final bool moveOnly;
  const _ScheduleEditor(this.api, this.plan, this.task, this.moveOnly);

  @override
  State<_ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<_ScheduleEditor> {
  late DateTime start = widget.task?.date ?? widget.plan.start;
  late DateTime end = widget.plan.end;
  late final minutes = TextEditingController(
    text: widget.task?.minutes.toString(),
  );
  bool busy = false, reload = false;
  String? error;

  @override
  void dispose() {
    minutes.dispose();
    super.dispose();
  }

  Future<void> selectDate(bool endDate) async {
    final today = dayInSeoul();
    final task = widget.task;
    final earliest = widget.moveOnly ? plusDays(today, 1) : today;
    final first = task != null && widget.plan.start.isAfter(earliest)
        ? widget.plan.start
        : earliest;
    final last = task != null ? widget.plan.end : plusDays(today, 540);
    if (last.isBefore(first)) return;
    final value = endDate ? end : start;
    final chosen = await showDatePicker(
      context: context,
      initialDate: value.isBefore(first)
          ? first
          : value.isAfter(last)
          ? last
          : value,
      firstDate: first,
      lastDate: last,
    );
    if (!mounted || chosen == null) return;
    setState(() {
      if (endDate) {
        end = chosen;
      } else {
        start = chosen;
      }
      error = null;
    });
  }

  Future<void> save() async {
    final task = widget.task, plan = widget.plan;
    final time = widget.moveOnly ? task?.minutes : int.tryParse(minutes.text);
    if (task == null && end.isBefore(start)) {
      setState(() => error = '종료일은 시작일과 같거나 이후여야 해요.');
      return;
    }
    if (task != null && (time == null || time < 1 || time > 960)) {
      setState(() => error = '배정 시간은 1~960분으로 입력해 주세요.');
      return;
    }
    if (task == null && start == plan.start && end == plan.end ||
        task != null && start == task.date && time == task.minutes) {
      setState(
        () => error = widget.moveOnly ? '옮길 날짜를 선택해 주세요.' : '변경할 내용을 입력해 주세요.',
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (task == null) {
        await widget.api.changePlanPeriod(plan.id!, plan.version, start, end);
      } else {
        await widget.api.changePlanTask(
          plan.id!,
          task.id!,
          plan.version,
          date: start == task.date ? null : start,
          minutes: time == task.minutes ? null : time,
        );
      }
      if (mounted) Navigator.pop(context, ScheduleEditResult.saved);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = friendly(e);
          reload = e is ApiError && e.status == 409;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget dateField(String label, DateTime date, {required bool endDate}) =>
      OutlinedButton.icon(
        key: ValueKey(
          widget.moveOnly
              ? 'schedule-move-date'
              : endDate
              ? 'schedule-end-date'
              : 'schedule-start-date',
        ),
        onPressed: busy || reload ? null : () => selectDate(endDate),
        icon: const Icon(Icons.calendar_today_outlined, size: 18),
        label: Text(
          widget.moveOnly
              ? date == widget.task?.date
                    ? '옮길 날짜 선택'
                    : isoDay(date)
              : '$label · ${isoDay(date)}',
        ),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      );

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(
          widget.moveOnly
              ? '학습 날짜 옮기기'
              : task != null
              ? '학습 일정 수정'
              : '계획 기간 수정',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (task != null) ...[
                Text(
                  task.subject,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                HelpText(
                  '현재 ${isoDay(task.date)} · ${durationLabel(task.minutes)}',
                ),
              ] else
                const HelpText('기존 학습 항목은 그대로 유지돼요.'),
              const SizedBox(height: 14),
              dateField(task == null ? '시작일' : '학습 날짜', start, endDate: false),
              if (task == null) dateField('종료일', end, endDate: true),
              if (task != null && !widget.moveOnly) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('schedule-minutes'),
                  controller: minutes,
                  enabled: !busy && !reload,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: const InputDecoration(
                    labelText: '배정 시간',
                    suffixText: '분',
                  ),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 12),
                AlertText(error!),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          if (reload)
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, ScheduleEditResult.reload),
              child: const Text('최신 일정 불러오기'),
            )
          else
            FilledButton(
              onPressed: busy || widget.moveOnly && start == task?.date
                  ? null
                  : save,
              child: Text(
                busy
                    ? '저장 중'
                    : widget.moveOnly
                    ? '옮기기'
                    : '저장',
              ),
            ),
        ],
      ),
    );
  }
}
