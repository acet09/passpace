import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/api.dart';
import '../data/chat_plan.dart';
import '../data/models.dart';
import '../data/plan_draft.dart';
import 'design.dart';
import 'plan_list.dart';

const _strong = TextStyle(fontWeight: FontWeight.w700, fontSize: 14);

/// 상담 답변 아래에 열리는 자동 학습계획 카드.
/// 시간 → 요일 → 기간 → 자격증별 이해도를 한 번에 하나씩 묻고, 답한 것은 한 줄로 접어 둔다.
/// 질문에서 이미 읽은 것은 묻지 않고 접힌 줄로 보여 주며, 눌러서 고칠 수 있다.
class ChatPlanCard extends StatefulWidget {
  final PassApi api;
  final ChatPlanSetup setup;
  final ChatPlanInputs inputs;
  final int? Function() conversation;
  final VoidCallback? onSaved;
  const ChatPlanCard(
    this.api,
    this.setup,
    this.inputs, {
    super.key,
    required this.conversation,
    this.onSaved,
  });
  @override
  State<ChatPlanCard> createState() => _ChatPlanCardState();
}

class _ChatPlanCardState extends State<ChatPlanCard> {
  final today = dayInSeoul();
  late final limit = plusDays(today, 540);
  late final custom = TextEditingController(
    text: widget.inputs.minutes?.toString() ?? '',
  );
  late final each = {
    for (final e in widget.setup.exams)
      e.key: TextEditingController(
        text: widget.inputs.examMinutes[e.key]?.toString() ?? '',
      ),
  };
  final resultKey = GlobalKey(), stepKey = GlobalKey();
  ChatPlanSetup get setup => widget.setup;
  ChatPlanInputs get inputs => widget.inputs;

  @override
  void initState() {
    super.initState();
    inputs.addListener(_sync);
  }

  @override
  void dispose() {
    inputs.removeListener(_sync);
    custom.dispose();
    for (final c in each.values) {
      c.dispose();
    }
    super.dispose();
  }

  // 다른 카드나 시간 버튼에서 바뀐 값을 이 카드의 직접 입력란에도 맞춘다.
  void _sync() {
    if (!mounted) return;
    final n = inputs.minutes;
    if (n != null && int.tryParse(custom.text.trim()) != n) {
      custom.text = n.toString();
    }
    for (final e in each.entries) {
      final own = inputs.examMinutes[e.key];
      if (own != null && int.tryParse(e.value.text.trim()) != own) {
        e.value.text = own.toString();
      }
    }
    setState(() {});
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  // 화면 안으로 올려 보여 준다 (새로 열린 질문, 계산 결과).
  void _show(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = key.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: .15,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  /// 이 단계의 답을 마치고 다음 질문을 연다.
  void _next(String step) {
    if (!setup.answered(step, inputs)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      setup.confirmed.add(step);
      setup.editing = null;
    });
    _show(setup.current(inputs) == null ? resultKey : stepKey);
  }

  void _edit(String step) {
    setState(() => setup.editing = step);
    _show(stepKey);
  }

  Future<void> _pick(ExamDraft g, bool start) async {
    final earliest = start ? today : plusDays(g.start, 1);
    final tomorrow = plusDays(today, 1);
    final d = await selectDate(
      context,
      first: start
          ? (g.start.isBefore(today) ? g.start : today)
          : (earliest.isBefore(tomorrow) ? tomorrow : earliest),
      last: start ? plusDays(limit, -1) : limit,
      current: start ? g.start : g.end,
    );
    if (d == null) return;
    inputs.update(() {
      if (start) {
        g.start = d;
        if (g.end != null && !d.isBefore(g.end!)) g.end = null;
      } else {
        g.end = d;
      }
    });
  }

  Future<void> _calculate() async {
    if (setup.busy || setup.current(inputs) != null) return;
    FocusScope.of(context).unfocus();
    final Json request;
    try {
      final id = widget.conversation();
      if (id == null) throw const ApiError('대화가 바뀌었어요. 질문을 다시 보내 주세요.');
      request = setup.buildRequest(inputs);
      setState(() {
        setup.busy = true;
        setup.error = null;
      });
      final result = await widget.api.previewChat(request, id);
      setup
        ..request = request
        ..result = result
        ..saved = false
        ..saveNote = null;
      _show(resultKey);
    } catch (e) {
      setup.error = friendly(e);
    } finally {
      setup.busy = false;
      _refresh();
    }
  }

  Future<void> _save() async {
    final request = setup.request;
    if (request == null || setup.saving || setup.saved) return;
    final activate = await askPlanSave(context, widget.api);
    if (activate == null || !mounted) return;
    setState(() {
      setup.saving = true;
      setup.saveNote = null;
    });
    try {
      final data = await widget.api.save(request, activate: activate);
      final days = data['days'];
      final count = days is int ? ' ($days일치)' : '';
      setup
        ..saved = true
        ..saveNote = activate
            ? '학습계획에 넣고 바로 사용해요$count. 쓰던 계획은 계획 목록에 보관했어요.'
            : '계획 목록에 추가했어요$count. 학습계획 화면의 계획 목록에서 사용할 수 있어요.';
      widget.onSaved?.call();
    } catch (e) {
      final message = '저장 실패: ${friendly(e)}';
      setup.saveNote = message;
      if (mounted) toast(context, message);
    } finally {
      setup.saving = false;
      _refresh();
    }
  }

  // ---------------------------------------------------------------------------
  // 질문 하나: 물음, 도움말, 고르는 곳, [다음]
  // ---------------------------------------------------------------------------

  Widget _question(
    String step,
    String title,
    String help,
    List<Widget> children, {
    required String waiting,
  }) {
    final ready = setup.answered(step, inputs);
    return Padding(
      key: stepKey,
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 5),
          _Note(help),
          const SizedBox(height: 12),
          ...children,
          const SizedBox(height: 14),
          PrimaryAction(ready ? '다음' : waiting, ready ? () => _next(step) : null),
        ],
      ),
    );
  }

  // 답을 마친 단계: 한 줄 요약. 누르면 그 질문을 다시 연다.
  Widget _answer(String step, String label, String value, {bool asked = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Material(
          color: pale,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: setup.busy ? null : () => _edit(step),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, size: 18, color: blue),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$label${asked ? ' · 질문에서 읽음' : ''}',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          value,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '수정',
                      style: TextStyle(
                        color: blue,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  // ---------------------------------------------------------------------------
  // ① 시간
  // ---------------------------------------------------------------------------

  // 자격증이 둘 이상이면 자격증별로, 그리고 언제든 요일별로 시간을 다르게 정할 수 있다.
  List<Widget> _timeModes() => [
    if (setup.exams.length >= 2 && !inputs.byWeekday)
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('자격증별로 시간 나누기', style: TextStyle(fontSize: 14)),
        value: inputs.split,
        onChanged: (v) => inputs.update(() => inputs.split = v),
      ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('요일마다 시간 다르게', style: TextStyle(fontSize: 14)),
      value: inputs.byWeekday,
      onChanged: (v) => inputs.update(() {
        inputs.byWeekday = v;
        if (!v) return;
        inputs.split = false;
        // 처음 켤 때는 지금 고른 요일에 지금 고른 하루 시간을 넣어 둔다.
        if (inputs.dayMinutes.isEmpty && validDailyMinutes(inputs.minutes)) {
          inputs.setDayMinutes({
            for (final day in inputs.weekdays) day: inputs.minutes!,
          });
        }
      }),
    ),
  ];

  Widget _timeByWeekday() => _question(
    ChatPlanSetup.stepTime,
    '요일마다 얼마나 공부할 수 있나요?',
    '요일별로 그날 쓸 수 있는 최대 시간을 골라 주세요. 쉬는 날에는 배정하지 않아요.'
        '${setup.dayMinutesFromQuestion ? ' 질문에 적은 시간을 먼저 넣어 두었어요.' : ''}',
    [
      ..._timeModes(),
      for (var day = 1; day <= 7; day++)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                child: Text('${weekdays[day - 1]}요일', style: _strong),
              ),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('day-$day-${inputs.dayMinutes[day] ?? 0}'),
                  initialValue: inputs.dayMinutes[day] ?? 0,
                  isExpanded: true,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: '${weekdays[day - 1]}요일 공부시간',
                  ),
                  items: [
                    for (final n in {
                      0,
                      30,
                      60,
                      90,
                      120,
                      150,
                      180,
                      240,
                      300,
                      360,
                      480,
                      inputs.dayMinutes[day] ?? 0,
                    }.toList()..sort())
                      DropdownMenuItem(
                        value: n,
                        child: Text(n == 0 ? '쉬는 날' : durationLabel(n)),
                      ),
                  ],
                  onChanged: (n) => inputs.update(() {
                    final minutes = {...inputs.dayMinutes};
                    if (n == null || n == 0) {
                      minutes.remove(day);
                    } else {
                      minutes[day] = n;
                    }
                    inputs.setDayMinutes(minutes);
                  }),
                ),
              ),
            ],
          ),
        ),
    ],
    waiting: '공부할 요일의 시간을 하나 이상 골라 주세요',
  );

  Widget _timeEach() {
    final total = setup.dailyTotal(inputs);
    return _question(
      ChatPlanSetup.stepTime,
      '자격증마다 하루에 얼마나 공부할까요?',
      '자격증마다 하루에 쓸 최대 시간을 정합니다. 그 시간을 넘겨 배정하지 않아요.'
          '${setup.splitFromQuestion ? ' 질문에 적은 시간을 먼저 넣어 두었어요.' : ''}',
      [
        ..._timeModes(),
        for (final exam in setup.exams) ...[
          const SizedBox(height: 6),
          Text(exam.name, style: _strong),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final n in [30, 60, 90, 120, 180])
                ChoiceChip(
                  label: Text(durationLabel(n)),
                  selected: inputs.examMinutes[exam.key] == n,
                  onSelected: (_) =>
                      inputs.update(() => inputs.examMinutes[exam.key] = n),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: each[exam.key],
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            decoration: InputDecoration(
              labelText: '${exam.name} 하루 시간 직접 입력',
              suffixText: '분',
            ),
            onChanged: (v) => inputs.update(() {
              final n = int.tryParse(v.trim());
              if (validDailyMinutes(n)) {
                inputs.examMinutes[exam.key] = n!;
              } else {
                inputs.examMinutes.remove(exam.key);
              }
            }),
          ),
          const SizedBox(height: 8),
        ],
        _Note(
          total == null
              ? '각 30분 이상, 합계 16시간 이하로 정해 주세요.'
              : '하루 합계 ${durationLabel(total)}',
        ),
      ],
      waiting: '자격증별 하루 시간을 입력해 주세요',
    );
  }

  Widget _time() => _question(
    ChatPlanSetup.stepTime,
    '하루에 얼마나 공부할 수 있나요?',
    '함께 준비하는 자격증이 이 시간을 나눠 씁니다. 시간을 누르면 다음 질문으로 넘어가요.'
        '${setup.minutesFromQuestion == null ? '' : ' 질문에 적은 ${durationLabel(setup.minutesFromQuestion!)}을 먼저 넣어 두었어요.'}',
    [
      ..._timeModes(),
      Wrap(
        spacing: 8,
        children: [
          for (final n in [60, 90, 120, 150, 180, 240])
            ChoiceChip(
              label: Text(durationLabel(n)),
              selected: inputs.minutes == n,
              onSelected: (_) {
                inputs.update(() => inputs.minutes = n);
                _next(ChatPlanSetup.stepTime);
              },
            ),
        ],
      ),
      const SizedBox(height: 10),
      TextField(
        controller: custom,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(3),
        ],
        decoration: const InputDecoration(
          labelText: '그 외 시간은 직접 입력',
          hintText: '예: 75',
          suffixText: '분',
          helperText: '30~960분',
        ),
        onChanged: (v) => inputs.update(() {
          final n = int.tryParse(v.trim());
          inputs.minutes = validDailyMinutes(n) ? n : null;
        }),
      ),
    ],
    waiting: '하루 공부 가능시간을 먼저 선택해 주세요',
  );

  String get _timeAnswer {
    if (inputs.byWeekday) {
      return [
        for (final day in inputs.dayMinutes.keys.toList()..sort())
          '${weekdays[day - 1]} ${durationLabel(inputs.dayMinutes[day]!)}',
      ].join(' · ');
    }
    if (setup.splits(inputs)) {
      return '${[for (final e in setup.exams) '${e.name} ${durationLabel(inputs.examMinutes[e.key]!)}'].join(' · ')}'
          ' (합계 ${durationLabel(setup.dailyTotal(inputs)!)})';
    }
    return '하루 ${durationLabel(inputs.minutes!)}';
  }

  // ---------------------------------------------------------------------------
  // ② 요일
  // ---------------------------------------------------------------------------

  Widget _weekdays() {
    bool same(List<int> days) =>
        inputs.weekdays.length == days.length &&
        inputs.weekdays.containsAll(days);
    final asked = setup.weekdaysFromQuestion;
    return _question(
      ChatPlanSetup.stepDays,
      '어느 요일에 공부할 수 있나요?',
      '선택한 요일에만 공부가 배정됩니다. 안 되는 요일은 빼 주세요.'
          '${asked == null ? '' : ' 질문에 적은 요일(${weekdayNames(asked)})을 먼저 넣어 두었어요.'}',
      [
        Wrap(
          spacing: 8,
          children: [
            for (final (title, days) in [
              ('매일', [1, 2, 3, 4, 5, 6, 7]),
              ('월~금', [1, 2, 3, 4, 5]),
              ('토·일', [6, 7]),
            ])
              ChoiceChip(
                label: Text(title),
                selected: same(days),
                onSelected: (_) {
                  inputs.update(
                    () => inputs.weekdays
                      ..clear()
                      ..addAll(days),
                  );
                  _next(ChatPlanSetup.stepDays);
                },
              ),
          ],
        ),
        Wrap(
          spacing: 7,
          children: List.generate(
            7,
            (i) => FilterChip(
              label: Text(weekdays[i]),
              showCheckmark: false,
              selected: inputs.weekdays.contains(i + 1),
              onSelected: (v) => inputs.update(
                () => v
                    ? inputs.weekdays.add(i + 1)
                    : inputs.weekdays.remove(i + 1),
              ),
            ),
          ),
        ),
      ],
      waiting: '공부할 요일을 하나 이상 선택해 주세요',
    );
  }

  String get _daysAnswer =>
      inputs.weekdays.length == 7 ? '매일' : weekdayNames(inputs.weekdays);

  // ---------------------------------------------------------------------------
  // ③ 기간
  // ---------------------------------------------------------------------------

  Widget _period() => _question(
    ChatPlanSetup.stepPeriod,
    '언제부터 언제까지 공부할까요?',
    '시작일부터 끝낼 날짜 전날까지 계획을 짭니다. 끝낼 날짜는 시험일이 아니어도 됩니다. '
        '처음 채워진 끝낼 날짜는 2026년 공고의 월/일을 옮긴 임시 값(공식 시험일 아님)이에요.'
        '${setup.datesFromQuestion ? ' 질문에 적은 날짜를 먼저 넣어 두었어요.' : ''}',
    [
      for (final exam in setup.exams) ...[
        DateField(
          '${exam.name} 공부 시작일',
          inputs.goals[exam.key]!.start,
          () => _pick(inputs.goals[exam.key]!, true),
        ),
        const SizedBox(height: 8),
        DateField(
          '${exam.name} 끝낼 날짜',
          inputs.goals[exam.key]!.end,
          () => _pick(inputs.goals[exam.key]!, false),
        ),
        const SizedBox(height: 12),
      ],
      if (setup.budgetHours != null)
        _Note(
          '총 ${setup.budgetHours}시간은 전체 학습 예산이고, 하루 가능시간과 다릅니다. '
          '현재는 필수 예상학습량부터 배정합니다. 남는 시간은 기출·복습에 활용할 수 있어요.',
        ),
    ],
    waiting: '끝낼 날짜를 선택해 주세요',
  );

  String get _periodAnswer => [
    for (final exam in setup.exams)
      '${setup.exams.length == 1 ? '' : '${exam.name} '}'
          '${isoDay(inputs.goals[exam.key]!.start)} ~ ${isoDay(inputs.goals[exam.key]!.end!)}',
  ].join('\n');

  // ---------------------------------------------------------------------------
  // ④ 이해도 (자격증마다 한 번씩)
  // ---------------------------------------------------------------------------

  Widget _familiarity(CatalogExam exam) {
    final step = ChatPlanSetup.stepLevel(exam);
    final goal = inputs.goals[exam.key]!;
    return _question(
      step,
      '${exam.name}, 과목별로 얼마나 알고 있나요?',
      exam.reviewBased
          ? '내 전공 구분: ${exam.majorLabel ?? '미설정'} · '
                '${exam.majorNote ?? '크롤링한 합격 후기 ${exam.reviewCount ?? 0}건의 평균 학습시간으로 계산합니다.'}'
          : exam.majorFallback
          ? '전공별 표본 부족: 집단 평균이 아닌 임시 추정시간을 사용합니다. 과목마다 현재 이해도를 골라 주세요.'
          : '과목마다 현재 이해도를 골라 주세요. 낯설수록 시간을 더 배정합니다.',
      [
        for (final s in exam.subjects) ...[
          Text(
            '${s['name']}${_baseHours(exam, s)}',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: List.generate(
              3,
              (i) => ChoiceChip(
                label: Text(levels[i]),
                selected: goal.familiarity[s['name']] == i + 1,
                onSelected: (_) {
                  final first = !setup.answered(step, inputs);
                  inputs.update(
                    () => goal.familiarity[s['name'] as String] = i + 1,
                  );
                  // 마지막 과목까지 처음 고른 순간 다음 질문으로 넘어간다.
                  if (first) _next(step);
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (exam.subjects.isEmpty) const _Note('이 시험은 고를 과목이 없어요.'),
      ],
      waiting: '과목별 이해도를 선택해 주세요',
    );
  }

  String _levelAnswer(CatalogExam exam) => exam.subjects.isEmpty
      ? '과목 없음'
      : [
          for (final s in exam.subjects)
            '${s['name']} ${levels[inputs.goals[exam.key]!.familiarity[s['name']]! - 1]}',
        ].join(' · ');

  String _baseHours(CatalogExam exam, Json subject) {
    final hours = subject['baseHours'] as num?;
    if (hours == null || hours <= 0) return '';
    return ' · ${exam.reviewBased ? '후기 평균' : '잠정'} ${hours.toStringAsFixed(1)}시간';
  }

  Widget _stepBody(String step) {
    if (step == ChatPlanSetup.stepTime) {
      return inputs.byWeekday
          ? _timeByWeekday()
          : setup.splits(inputs)
          ? _timeEach()
          : _time();
    }
    if (step == ChatPlanSetup.stepDays) return _weekdays();
    if (step == ChatPlanSetup.stepPeriod) return _period();
    return _familiarity(
      setup.exams.firstWhere((e) => ChatPlanSetup.stepLevel(e) == step),
    );
  }

  Widget _stepAnswer(String step) {
    if (step == ChatPlanSetup.stepTime) {
      return _answer(
        step,
        inputs.byWeekday ? '요일별 공부시간' : '하루 공부시간',
        _timeAnswer,
        asked:
            setup.minutesFromQuestion != null ||
            setup.splitFromQuestion ||
            setup.dayMinutesFromQuestion,
      );
    }
    if (step == ChatPlanSetup.stepDays) {
      return _answer(
        step,
        '공부할 요일',
        _daysAnswer,
        asked: setup.weekdaysFromQuestion != null,
      );
    }
    if (step == ChatPlanSetup.stepPeriod) {
      return _answer(
        step,
        '공부 기간',
        _periodAnswer,
        asked: setup.datesFromQuestion,
      );
    }
    final exam = setup.exams.firstWhere(
      (e) => ChatPlanSetup.stepLevel(e) == step,
    );
    return _answer(step, '${exam.name} 이해도', _levelAnswer(exam));
  }

  @override
  Widget build(BuildContext context) {
    final steps = setup.steps(inputs), current = setup.current(inputs);
    final done = steps
        .where((s) => s != current && setup.confirmed.contains(s))
        .length;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Pane(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.event_note_rounded, size: 18, color: blue),
                const SizedBox(width: 7),
                const Expanded(
                  child: Text(
                    '자동 학습계획',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: blue,
                    ),
                  ),
                ),
                Text(
                  current == null
                      ? '질문 ${steps.length}개 완료'
                      : '질문 ${done + 1} / ${steps.length}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
            for (final step in steps)
              if (step == current)
                _stepBody(step)
              else if (setup.confirmed.contains(step) &&
                  setup.answered(step, inputs))
                _stepAnswer(step),
            if (current == null) ...[
              const SizedBox(height: 16),
              PrimaryAction(
                setup.result != null ? '변경된 입력으로 다시 계산' : '학습계획 자동 생성',
                _calculate,
                busy: setup.busy,
              ),
            ],
            if (setup.error != null) AlertText(setup.error!),
            if (setup.result case final r?)
              _PlanResult(
                r,
                setup,
                key: resultKey,
                request: setup.request!,
                onSave: setup.saved ? null : _save,
              )
            else
              SizedBox(key: resultKey),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(color: muted, fontSize: 13, height: 1.5),
  );
}

class _PlanResult extends StatelessWidget {
  final ChatPlanReply reply;
  final ChatPlanSetup setup;
  final Json request;
  final VoidCallback? onSave;
  const _PlanResult(
    this.reply,
    this.setup, {
    super.key,
    required this.request,
    required this.onSave,
  });

  static String _hours(num minutes) => (minutes / 60).toStringAsFixed(1);

  Widget _day(Json day) {
    final date = DateTime.parse(day['date'] as String);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${shortDay(date)} (${weekdays[date.weekday - 1]}) · '
            '${day['allocatedMinutes']}/${day['availableMinutes']}분',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          for (final a in rows(day['allocations']))
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: _Note(
                '- ${a['certificationName'] ?? ''} / ${a['subjectName']}: ${a['minutes']}분',
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = reply.plan, days = plan.days;
    final picked = (request['studyWeekdays'] as List)
        .map((d) => weekdays[(d as int) - 1])
        .join('·');
    final byWeekday = request.containsKey('weekdayMinutes');
    final budget = setup.budgetHours;
    final spare = budget == null ? 0 : budget * 60 - plan.requiredMinutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 14),
        SelectableText(
          reply.answer,
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
        const SizedBox(height: 8),
        _Note('선택 학습 요일: $picked · 선택하지 않은 요일에는 공부를 배정하지 않습니다.'),
        if (budget != null) ...[
          const SizedBox(height: 6),
          _Note(
            spare >= 0
                ? '전체 $budget시간 중 기본 학습 추정 ${_hours(plan.requiredMinutes)}시간을 배정했습니다. '
                      '남은 ${_hours(spare)}시간은 복습 예산이며 아직 날짜별 계획에는 배정하지 않았습니다.'
                : '전체 $budget시간 예산보다 추정 학습량이 ${_hours(-spare)}시간 많습니다. 시험일까지 추가 시간이 필요합니다.',
          ),
        ],
        const SizedBox(height: 16),
        Text('날짜별 계획 (${days.length}일)', style: _strong),
        if (days.isEmpty) const _Note('배정된 날짜가 없어요.'),
        for (final day in days.take(7)) _day(day),
        if (days.length > 7)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            title: Text(
              '나머지 일정 ${days.length - 7}일 펼치기',
              style: const TextStyle(fontSize: 13),
            ),
            children: [for (final day in days.skip(7)) _day(day)],
          ),
        const SizedBox(height: 14),
        PrimaryAction(
          setup.saved ? '학습계획에 넣기 완료' : '이 계획을 학습계획에 넣기',
          onSave,
          busy: setup.saving,
        ),
        if (setup.saveNote != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(liveRegion: true, child: _Note(setup.saveNote!)),
          ),
        if (plan.additionalDailyMinutes > 0 || plan.missingMinutes > 0)
          AlertText(
            [
              plan.additionalDailyMinutes > 0 && byWeekday
                  ? '현재 일정은 학습시간이 부족합니다. 공부하는 날마다 약 ${plan.additionalDailyMinutes}분씩 더 필요해요.'
                  : plan.additionalDailyMinutes > 0
                  ? '현재 일정은 학습시간이 부족합니다. 하루 합계로 최소 ${plan.minimumDailyMinutes}분이 필요합니다.'
                  : '현재 입력으로는 ${durationLabel(plan.missingMinutes)}을 배정하지 못했어요. 하루 시간을 늘리거나 끝낼 날짜를 조정해 주세요.',
              // 자격증별 시간을 정했을 때 서버가 알려 주는 자격증별 최소 시간.
              ...plan.notices.where((n) => n.contains('최소 하루')),
            ].join('\n'),
          ),
        const SizedBox(height: 10),
        const _Note(
          '하루 공부 가능시간은 상한입니다. 선택한 요일에 50분 이상 블록으로 분산하며 마지막 잔여시간은 짧을 수 있습니다. '
          '기출·복습 시간은 아직 추가 산정하지 않았습니다. 시험일은 가상 목표일일 수 있습니다.',
        ),
      ],
    );
  }
}
