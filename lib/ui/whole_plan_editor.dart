import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/api.dart';
import '../data/models.dart';
import '../data/whole_plan.dart';
import 'design.dart';

class WholePlanEditor extends StatefulWidget {
  final PassApi api;
  final int planId;
  const WholePlanEditor(this.api, this.planId, {super.key});

  @override
  State<WholePlanEditor> createState() => _WholePlanEditorState();
}

class _WholePlanEditorState extends State<WholePlanEditor> {
  int revision = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('전체 계획 수정')),
    body: SafeArea(
      child: LoadBox<WholePlanInput>(
        key: ValueKey(revision),
        load: () => widget.api.wholePlan(widget.planId),
        content: (data) => _EditForm(
          widget.api,
          data,
          onReload: () => setState(() => revision++),
        ),
      ),
    ),
  );
}

class _EditForm extends StatefulWidget {
  final PassApi api;
  final WholePlanInput data;
  final VoidCallback onReload;
  const _EditForm(this.api, this.data, {required this.onReload});

  @override
  State<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends State<_EditForm> {
  static const steps = ['시간과 요일', '계획 기간', '과목별 배정 시간'];
  final scroll = ScrollController();
  late DateTime start = widget.data.start, end = widget.data.end;
  late final days = widget.data.weekdayMinutes.keys.toSet();
  late final caps = {
    for (var day = 1; day <= 7; day++)
      day: TextEditingController(
        text: widget.data.weekdayMinutes[day]?.toString() ?? '',
      ),
  };
  late final subjects = {
    for (final subject in widget.data.subjects)
      subject.key: TextEditingController(text: '${subject.minutes}'),
  };
  int step = 0;
  bool busy = false, stale = false;
  String? error;

  @override
  void dispose() {
    scroll.dispose();
    for (final controller in [...caps.values, ...subjects.values]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> pickDate({required bool startDate}) async {
    final today = widget.data.today;
    final selected = await selectDate(
      context,
      first: today,
      last: plusDays(today, 540),
      current: startDate ? start : end,
    );
    if (!mounted || selected == null) return;
    setState(() {
      if (startDate) {
        start = selected;
      } else {
        end = selected;
      }
      error = null;
    });
  }

  void validatePeriod() {
    if (end.isBefore(start)) {
      throw const ApiError('종료일은 시작일과 같거나 이후여야 해요.');
    }
  }

  Map<String, int> weekdayLimits() {
    if (days.isEmpty) throw const ApiError('공부할 요일을 선택해 주세요.');
    final weekdayMinutes = <String, int>{};
    for (final day in days.toList()..sort()) {
      final minutes = int.tryParse(caps[day]!.text);
      if (minutes == null || minutes < 1 || minutes > 960) {
        throw ApiError('${weekdays[day - 1]}요일 최대 시간은 1~960분으로 입력해 주세요.');
      }
      weekdayMinutes['$day'] = minutes;
    }
    return weekdayMinutes;
  }

  Json request() {
    final budgets = <Json>[];
    for (final subject in widget.data.subjects) {
      final minutes = int.tryParse(subjects[subject.key]!.text);
      if (minutes == null || minutes < 0 || minutes > 519360) {
        throw ApiError('${subject.name}의 배정 시간을 확인해 주세요.');
      }
      budgets.add({'key': subject.key, 'minutes': minutes});
    }
    return {
      'expectedPlanVersion': widget.data.version,
      'startDate': isoDay(start),
      'endDate': isoDay(end),
      'weekdayMinutes': weekdayLimits(),
      'subjects': budgets,
    };
  }

  void move(int value) {
    FocusScope.of(context).unfocus();
    setState(() {
      step = value;
      if (!stale) error = null;
    });
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  Future<void> next() async {
    if (busy || stale) return;
    try {
      if (step == 0) {
        weekdayLimits();
        move(1);
        return;
      }
      validatePeriod();
      if (step == 1) {
        move(2);
        return;
      }
      final edit = request();
      FocusScope.of(context).unfocus();
      setState(() {
        busy = true;
        error = null;
      });
      final result = await widget.api.previewWholePlan(widget.data.id, edit);
      if (!mounted) return;
      if (!result.changed) {
        setState(() => error = '변경할 내용을 입력해 주세요.');
        return;
      }
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              _ReviewChanges(widget.api, widget.data.id, edit, result),
        ),
      );
      if (!mounted) return;
      if (saved == true) {
        Navigator.pop(context, true);
      } else if (saved == false) {
        setState(() {
          stale = true;
          error = '저장 전 최신 일정을 다시 불러와 주세요.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          stale = e is ApiError && e.status == 409;
          error = friendly(e);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget minuteField(
    TextEditingController controller,
    String label,
    int digits,
  ) => TextField(
    controller: controller,
    enabled: !busy,
    keyboardType: TextInputType.number,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(digits),
    ],
    decoration: InputDecoration(labelText: label, suffixText: '분'),
  );

  Widget timeStep() => Pane(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HelpText('공부할 요일과 요일별 최대 시간을 정해 주세요.'),
        const FieldGap(),
        Wrap(
          spacing: 7,
          children: [
            for (var day = 1; day <= 7; day++)
              FilterChip(
                label: Text(weekdays[day - 1]),
                showCheckmark: false,
                selected: days.contains(day),
                onSelected: (enabled) => setState(() {
                  if (enabled) {
                    days.add(day);
                  } else {
                    days.remove(day);
                  }
                  error = null;
                }),
              ),
          ],
        ),
        if (days.isNotEmpty) ...[
          const FieldGap(),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 10.0;
              final twoColumns =
                  constraints.maxWidth >= 270 &&
                  MediaQuery.textScalerOf(context).scale(14) <= 19;
              final width = twoColumns
                  ? (constraints.maxWidth - gap) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final day in days.toList()..sort())
                    SizedBox(
                      key: ValueKey(day),
                      width: width,
                      child: minuteField(
                        caps[day]!,
                        '${weekdays[day - 1]}요일 최대 시간',
                        3,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    ),
  );

  Widget periodStep() => Pane(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (isStart, label, date) in [
          (true, '시작일', start),
          (false, '종료일', end),
        ]) ...[
          if (!isStart) const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => pickDate(startDate: isStart),
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text('$label · ${isoDay(date)}'),
          ),
        ],
        const SizedBox(height: 8),
        const HelpText('지난 일정과 직접 옮긴 일정, 공부기록이 있는 항목은 유지돼요.'),
      ],
    ),
  );

  Widget subjectStep() {
    final byExam = <String, List<WholePlanSubject>>{};
    for (final subject in widget.data.subjects) {
      (byExam[subject.exam] ??= []).add(subject);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HelpText('앞으로 배정할 시간을 입력해 주세요. 0분인 과목은 새로 배정하지 않아요.'),
        if (byExam.isEmpty) const HelpText('수정할 과목이 없어요.'),
        for (final exam in byExam.entries) ...[
          const FieldGap(),
          Pane(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (exam.key.isNotEmpty) ...[
                  Text(
                    exam.key,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const FieldGap(),
                ],
                for (final (index, subject) in exam.value.indexed) ...[
                  if (index > 0) const FieldGap(),
                  minuteField(subjects[subject.key]!, subject.name, 6),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && step == 0,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && !busy && step > 0) move(step - 1);
    },
    child: Column(
      children: [
        Expanded(
          child: AbsorbPointer(
            absorbing: busy,
            child: ScrollBody(
              controller: scroll,
              children: [
                StepHeader(current: step, labels: steps),
                const FieldGap(),
                HelpText(widget.data.name),
                const FieldGap(),
                Entrance(
                  key: ValueKey(step),
                  child: switch (step) {
                    0 => timeStep(),
                    1 => periodStep(),
                    _ => subjectStep(),
                  },
                ),
                if (stale)
                  TextButton(
                    onPressed: widget.onReload,
                    child: const Text('최신 일정 다시 불러오기'),
                  ),
              ],
            ),
          ),
        ),
        StickyActions(
          step == steps.length - 1 ? '변경안 미리보기' : '다음',
          stale ? null : next,
          onBack: step == 0 ? null : () => move(step - 1),
          error: error,
          busy: busy,
        ),
      ],
    ),
  );
}

class _ReviewChanges extends StatefulWidget {
  final PassApi api;
  final int planId;
  final Json edit;
  final WholePlanPreview result;
  const _ReviewChanges(this.api, this.planId, this.edit, this.result);

  @override
  State<_ReviewChanges> createState() => _ReviewChangesState();
}

class _ReviewChangesState extends State<_ReviewChanges> {
  bool busy = false, stale = false;
  String? error;

  Future<void> save() async {
    if (busy || stale) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.applyWholePlan(
        widget.planId,
        widget.edit,
        widget.result.approval,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          stale = e is ApiError && e.status == 409;
          error = friendly(e);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final removed = <String, List<WholePlanAllocation>>{};
    final added = <String, List<WholePlanAllocation>>{};
    for (final row in result.removed) {
      (removed[isoDay(row.date)] ??= []).add(row);
    }
    for (final row in result.added) {
      (added[isoDay(row.date)] ??= []).add(row);
    }
    final dates = {...removed.keys, ...added.keys}.toList()..sort();
    final caps = object(widget.edit['weekdayMinutes']).entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('전체 계획 변경 확인')),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: WidthLimit(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    itemCount: dates.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const PageTitle('저장할 변경안'),
                            const SizedBox(height: 12),
                            HelpText(
                              '${widget.edit['startDate']} ~ ${widget.edit['endDate']}',
                            ),
                            HelpText(
                              caps
                                  .map(
                                    (day) =>
                                        '${weekdays[int.parse(day.key) - 1]} ${day.value}분',
                                  )
                                  .join(' · '),
                            ),
                            HelpText(
                              '기존 일정 ${result.protectedTasks}개 보존 · ${result.removed.length}개 제외 · ${result.added.length}개 추가',
                            ),
                            const SizedBox(height: 16),
                            if (dates.isEmpty)
                              const HelpText('계획 기간이나 요일별 최대 시간이 바뀌어요.'),
                          ],
                        );
                      }
                      final date = dates[index - 1];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Heading(shortDay(DateTime.parse(date))),
                          for (final row
                              in removed[date] ?? const <WholePlanAllocation>[])
                            allocation(row, '변경 전'),
                          for (final row
                              in added[date] ?? const <WholePlanAllocation>[])
                            allocation(row, '변경 후'),
                        ],
                      );
                    },
                  ),
                ),
              ),
              StickyActions(
                stale ? '최신 일정 확인으로 돌아가기' : '이 계획에 저장',
                stale ? () => Navigator.pop(context, false) : save,
                busy: busy,
                error: error,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget allocation(WholePlanAllocation row, String tag) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      '$tag · ${row.exam.isEmpty ? '' : '${row.exam} · '}${row.subject} · ${durationLabel(row.minutes)}',
    ),
  );
}
