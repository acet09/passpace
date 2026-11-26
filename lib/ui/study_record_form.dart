import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/models.dart';
import '../data/session.dart';
import '../data/study_models.dart';
import 'design.dart';
import 'study_task_picker.dart';
import 'subject_color_picker.dart';

class StudyRecordForm extends StatefulWidget {
  final Session session;
  final void Function(DateTime date, int minutes) onUncertain;
  final VoidCallback onForbidden;
  final StudyRecord? record;
  final StudySubjectColor? colorForSubject;
  const StudyRecordForm(
    this.session, {
    super.key,
    required this.onUncertain,
    required this.onForbidden,
    this.record,
    this.colorForSubject,
  });

  @override
  State<StudyRecordForm> createState() => _StudyRecordFormState();
}

class _StudyRecordFormState extends State<StudyRecordForm> {
  final form = GlobalKey<FormState>();
  final minutes = TextEditingController();
  late final PassApi account;
  DateTime date = dayInSeoul();
  bool busy = false, uncertain = false, blocked = false;
  String? error;
  StudyTaskChoice? selectedTask;
  bool taskChanged = false;
  bool get editing => widget.record != null;

  @override
  void initState() {
    super.initState();
    account = widget.session.account!;
    final record = widget.record;
    if (record != null) {
      date = record.date;
      minutes.text = '${record.minutes}';
    }
    widget.session.addListener(_accountChanged);
  }

  void _accountChanged() {
    if (!identical(account, widget.session.account) && mounted) {
      setState(() {
        blocked = true;
        minutes.clear();
      });
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_accountChanged);
    minutes.dispose();
    super.dispose();
  }

  Future<void> chooseDate() async {
    final next = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(1000),
      lastDate: dayInSeoul(),
      helpText: '공부한 날짜',
    );
    if (mounted && next != null && !blocked) setState(() => date = next);
  }

  void forbidden() {
    widget.onForbidden();
    if (mounted) setState(() => blocked = true);
  }

  Future<void> chooseTask() async {
    if (busy || blocked || uncertain) return;
    FocusScope.of(context).unfocus();
    final result = await Navigator.push<StudyTaskSelection>(
      context,
      MaterialPageRoute(
        builder: (_) => StudyTaskPicker(
          widget.session,
          date: date,
          selectedId: taskChanged ? selectedTask?.id : widget.record?.taskId,
          onForbidden: forbidden,
          colorForSubject: widget.colorForSubject,
        ),
      ),
    );
    if (mounted &&
        !blocked &&
        identical(account, widget.session.account) &&
        result != null) {
      setState(() {
        selectedTask = result.task;
        taskChanged = widget.record?.taskId != selectedTask?.id;
      });
    }
  }

  String get taskLabel {
    if (taskChanged || widget.record == null) {
      return selectedTask?.name ?? '과목 연결 없음';
    }
    final original = widget.record!;
    return original.taskId == null
        ? '과목 연결 없음'
        : original.subjectName?.trim().isNotEmpty == true
        ? original.subjectName!
        : '연결된 과목 이름 없음';
  }

  Future<void> save() async {
    if (busy || uncertain || blocked || !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final value = int.parse(minutes.text);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final original = widget.record;
      final record = original == null
          ? await account.saveStudySession(date, value, task: selectedTask)
          : await account.updateStudySession(
              original,
              date,
              value,
              changeTask: taskChanged,
              task: selectedTask,
            );
      if (mounted && identical(account, widget.session.account) && !blocked) {
        Navigator.pop(context, record);
      }
    } on StudySaveUncertain catch (e) {
      if (mounted && identical(account, widget.session.account)) {
        widget.onUncertain(date, value);
        setState(() {
          uncertain = true;
          error = e.message;
        });
      }
    } catch (e) {
      if (mounted && identical(account, widget.session.account)) {
        if (e is ApiError && (e.status == 401 || e.status == 403)) {
          widget.onForbidden();
          setState(() => blocked = true);
        } else {
          setState(() => error = friendly(e));
        }
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: Text(editing ? '공부시간 수정' : '공부시간 추가')),
      body: SafeArea(
        child: blocked
            ? ScrollBody(
                children: [
                  const AlertText(
                    '로그인 상태가 바뀌었거나 기록을 저장할 권한이 없어요. 다시 로그인해 주세요.',
                  ),
                  PrimaryAction('기록으로 돌아가기', () => Navigator.pop(context)),
                ],
              )
            : ScrollBody(
                children: [
                  Text(
                    editing ? '공부한 날짜와 시간을 수정해요' : '실제로 공부한 시간을 남겨요',
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const HelpText('계획에 배정된 시간과 별도로 기록돼요.'),
                  if (widget.record case final original?) ...[
                    const SizedBox(height: 10),
                    HelpText(
                      '수정 전: ${isoDay(original.date)} · ${durationLabel(original.minutes)}',
                    ),
                    if (original.subjectName != null)
                      Text(original.subjectName!),
                  ],
                  const SizedBox(height: 24),
                  Form(
                    key: form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton(
                          onPressed: busy || uncertain ? null : chooseDate,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_outlined,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('공부한 날짜'),
                                    Text(isoDay(date)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        OutlinedButton(
                          key: const ValueKey('study-task-picker'),
                          onPressed: busy || uncertain ? null : chooseTask,
                          child: Row(
                            children: [
                              const Icon(Icons.link_outlined, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('과목 연결 · 선택'),
                                    Text(taskLabel),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const ValueKey('study-minutes'),
                          controller: minutes,
                          enabled: !busy && !uncertain,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: '실제 공부시간',
                            suffixText: '분',
                            helperText: '1~1,440분 · 같은 날 합계도 최대 1,440분',
                          ),
                          validator: (raw) {
                            final value = int.tryParse(raw ?? '');
                            return !RegExp(r'^[0-9]{1,4}$')
                                        .hasMatch(raw ?? '') ||
                                    value == null ||
                                    value < 1 ||
                                    value > 1440
                                ? '공부한 시간을 1~1,440분 사이로 입력해 주세요.'
                                : null;
                          },
                          onFieldSubmitted: (_) => save(),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final n in [30, 60, 90])
                              ActionChip(
                                label: Text('$n분'),
                                onPressed: busy || uncertain
                                    ? null
                                    : () => setState(() => minutes.text = '$n'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (error != null) ...[
                    AlertText(error!),
                    const SizedBox(height: 16),
                  ],
                  if (uncertain)
                    PrimaryAction('기록 목록 확인', () => Navigator.pop(context))
                  else
                    PrimaryAction(
                      editing ? '수정 내용 저장' : '공부시간 저장',
                      save,
                      busy: busy,
                    ),
                  const SizedBox(height: 12),
                  if (!uncertain) const HelpText('저장한 기록을 기준으로 개인 학습통계가 갱신돼요.'),
                ],
              ),
      ),
    ),
  );
}
