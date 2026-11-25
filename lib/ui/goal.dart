import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/api.dart';
import '../data/models.dart';
import 'design.dart';

class GoalScreen extends StatelessWidget {
  final PassApi api;
  const GoalScreen(this.api, {super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('기본값 수정')),
    body: SafeArea(
      child: LoadBox<GoalData>(
        load: api.goal,
        content: (d) => _GoalForm(api, d),
      ),
    ),
  );
}

class _GoalForm extends StatefulWidget {
  final PassApi api;
  final GoalData data;
  const _GoalForm(this.api, this.data);
  @override
  State<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<_GoalForm> {
  late int? round = widget.data.roundId;
  late DateTime? date = widget.data.date;
  late final values = Map<String, int>.of(widget.data.familiarity);
  late final minutes = TextEditingController(
    text: widget.data.minutes?.toString() ?? '',
  );
  String? error;
  bool busy = false;
  @override
  void dispose() {
    minutes.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    final txt = minutes.text.trim(), n = int.tryParse(minutes.text.trim());
    if (txt.isNotEmpty && (n == null || n < 10 || n > 720)) {
      setState(() => error = '하루 가용 시간은 10~720분으로 입력해 주세요.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.updateGoal({
        'examRoundId': round,
        'targetExamDate': round != null || date == null ? null : isoDay(date!),
        'dailyMinutes': n,
        'familiarity': Map.of(values),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseDate() async {
    if (busy) return;
    final now = dayInSeoul(),
        first = date != null && date!.isBefore(now) ? date! : now,
        last = DateTime(now.year + 15, 12, 31);
    final d = await selectDate(
      context,
      first: first,
      last: date != null && date!.isAfter(last) ? date! : last,
      current: date,
    );
    if (mounted && d != null) setState(() => date = d);
  }

  @override
  Widget build(BuildContext context) {
    final opts = {
      for (final r in widget.data.rounds)
        r['examRoundId'] as int: r['label'] as String,
    };
    if (round != null) opts.putIfAbsent(round!, () => '저장된 회차 #$round');
    return PopScope(
      canPop: !busy,
      child: Column(
        children: [
          Expanded(
            child: ScrollBody(
              children: [
                const HelpText('새 계획에 사용할 시험일과 공부 시간을 저장해요.'),
                const Heading('목표 시험'),
                DropdownButtonFormField<int>(
                  initialValue: round ?? 0,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '시험 회차'),
                  items: [
                    const DropdownMenuItem(
                      value: 0,
                      child: Text('회차 미지정 · 날짜 직접 선택'),
                    ),
                    ...opts.entries.map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() => round = v == 0 ? null : v),
                ),
                if (round == null) ...[
                  const FieldGap(),
                  DateField('목표 시험일', date, chooseDate),
                  if (date != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() => date = null),
                        child: const Text('날짜 지우기'),
                      ),
                    ),
                ],
                const Heading('하루 최대 학습 시간'),
                TextField(
                  controller: minutes,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: const InputDecoration(
                    labelText: '공부할 수 있는 시간',
                    suffixText: '분',
                    helperText: '10~720분 · 선택 입력',
                  ),
                ),
                if (widget.data.subjects.isNotEmpty) ...[
                  const Heading('과목별 사전 이해도'),
                  const HelpText('현재 느끼는 정도를 선택해 주세요.'),
                  const SizedBox(height: 13),
                ],
                for (final s in widget.data.subjects)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Pane(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s['subjectName'],
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: List.generate(3, (i) {
                              final id = s['subjectId'].toString();
                              return ChoiceChip(
                                label: Text(levels[i]),
                                selected: values[id] == i + 1,
                                onSelected: busy
                                    ? null
                                    : (on) => setState(() {
                                        if (on) {
                                          values[id] = i + 1;
                                        } else {
                                          values.remove(id);
                                        }
                                      }),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          StickyActions('기본값 저장', save, busy: busy, error: error),
        ],
      ),
    );
  }
}
