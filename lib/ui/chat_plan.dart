import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/api.dart';
import '../data/chat_plan.dart';
import '../data/models.dart';
import '../data/plan_draft.dart';
import 'design.dart';

const _strong = TextStyle(fontWeight: FontWeight.w700, fontSize: 14);

/// 상담 답변 아래에 열리는 자동 학습계획 카드: 시간·요일·기간·이해도 → 계산 → 저장.
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
  final resultKey = GlobalKey();
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

  String get _actionLabel => setup.dailyTotal(inputs) == null
      ? (setup.splits(inputs)
            ? '자격증별 하루 시간을 입력해 주세요'
            : '하루 공부 가능시간을 먼저 선택해 주세요')
      : inputs.weekdays.isEmpty
      ? '공부할 요일을 하나 이상 선택해 주세요'
      : !setup.familiarityChosen(inputs)
      ? '과목별 이해도를 선택해 주세요'
      : setup.result != null
      ? '변경된 입력으로 다시 계산'
      : '학습계획 자동 생성';

  bool get _ready =>
      setup.dailyTotal(inputs) != null &&
      inputs.weekdays.isNotEmpty &&
      setup.familiarityChosen(inputs);

  Future<void> _calculate() async {
    if (setup.busy || !_ready) return;
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
      _showResult();
    } catch (e) {
      setup.error = friendly(e);
    } finally {
      setup.busy = false;
      _refresh();
    }
  }

  // 계산 결과는 버튼 아래에 생기므로 화면 안으로 올려 보여 준다.
  void _showResult() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = resultKey.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _save() async {
    final request = setup.request;
    if (request == null || setup.saving || setup.saved) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('이 계획을 학습계획에 넣을까요?'),
        content: const Text(
          '웹과 앱에서 같은 일정을 확인할 수 있어요. 기존에 저장한 계획이 있다면 이 계획으로 교체됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('저장하기'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      setup.saving = true;
      setup.saveNote = null;
    });
    try {
      final data = await widget.api.save(request);
      final days = data['days'];
      setup
        ..saved = true
        ..saveNote =
            '학습계획에 넣었어요${days is int ? ' ($days일치)' : ''}. 이전 계획은 이 계획으로 바뀝니다.';
      widget.onSaved?.call();
    } catch (e) {
      setup.saveNote = '저장 실패: ${friendly(e)}';
    } finally {
      setup.saving = false;
      _refresh();
    }
  }

  Widget _section(String title, String help, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: _strong),
        const SizedBox(height: 5),
        _Note(help),
        const SizedBox(height: 10),
        ...children,
      ],
    ),
  );

  // 자격증이 둘 이상이면 하루 시간을 자격증별로 따로 정할 수 있다.
  Widget _splitSwitch() => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: const Text('자격증별로 시간 나누기', style: TextStyle(fontSize: 14)),
    value: inputs.split,
    onChanged: (v) => inputs.update(() => inputs.split = v),
  );

  Widget _timeEach() {
    final total = setup.dailyTotal(inputs);
    return _section(
      '① 자격증별 하루 공부시간 (필수)',
      '자격증마다 하루에 쓸 최대 시간을 정합니다. 그 시간을 넘겨 배정하지 않아요.'
          '${setup.splitFromQuestion ? ' 질문에 적은 시간을 먼저 넣어 두었어요.' : ''}',
      [
        _splitSwitch(),
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
    );
  }

  Widget _time() => _section(
    '① 하루 총 공부 가능시간 (필수)',
    '함께 준비하는 자격증이 이 시간을 나눠 씁니다.'
        '${setup.minutesFromQuestion == null ? '' : ' 질문에 적은 ${durationLabel(setup.minutesFromQuestion!)}을 먼저 넣어 두었어요.'}',
    [
      if (setup.exams.length >= 2) _splitSwitch(),
      Wrap(
        spacing: 8,
        children: [
          for (final n in [60, 90, 120, 150, 180, 240])
            ChoiceChip(
              label: Text(durationLabel(n)),
              selected: inputs.minutes == n,
              onSelected: (_) => inputs.update(() => inputs.minutes = n),
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
  );

  Widget _weekdays() {
    bool same(List<int> days) =>
        inputs.weekdays.length == days.length &&
        inputs.weekdays.containsAll(days);
    void set(Iterable<int> days) => inputs.update(
      () => inputs.weekdays
        ..clear()
        ..addAll(days),
    );
    return _section('② 공부할 요일 (기본: 매일)', '선택한 요일에만 공부가 배정됩니다.', [
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
              onSelected: (_) => set(days),
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
    ]);
  }

  Widget _period() => _section(
    '③ 공부 기간 (자유롭게 변경 가능)',
    '시작일부터 끝낼 날짜 전날까지 계획을 짭니다. 끝낼 날짜는 시험일이 아니어도 됩니다.'
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
  );

  Widget _familiarity() => _section('④ 과목별 이해도', '과목마다 현재 이해도를 골라 주세요.', [
    for (final exam in setup.exams) ...[
      Row(
        children: [
          ExamIcon(exam.name, size: 30),
          const SizedBox(width: 9),
          Expanded(child: Text(exam.name, style: _strong)),
        ],
      ),
      const SizedBox(height: 6),
      if (exam.reviewBased)
        _Note(
          '내 전공 구분: ${exam.majorLabel ?? '미설정'} · '
          '${exam.majorNote ?? '크롤링한 합격 후기 ${exam.reviewCount ?? 0}건의 평균 학습시간으로 계산합니다.'}',
        )
      else if (exam.majorFallback)
        const _Note('전공별 표본 부족: 집단 평균이 아닌 임시 추정시간을 사용합니다.'),
      for (final s in exam.subjects) ...[
        const SizedBox(height: 14),
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
              selected: inputs.goals[exam.key]!.familiarity[s['name']] == i + 1,
              onSelected: (_) => inputs.update(
                () => inputs.goals[exam.key]!.familiarity[s['name'] as String] =
                    i + 1,
              ),
            ),
          ),
        ),
      ],
      const SizedBox(height: 16),
    ],
  ]);

  String _baseHours(CatalogExam exam, Json subject) {
    final hours = subject['baseHours'] as num?;
    if (hours == null || hours <= 0) return '';
    return ' · ${exam.reviewBased ? '후기 평균' : '잠정'} ${hours.toStringAsFixed(1)}시간';
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Pane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.event_note_rounded, size: 18, color: blue),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  '자동 학습계획',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: blue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const _Note(
            '시간·요일·기간·이해도를 고르면 이 대화 안에서 계획을 계산합니다. '
            '처음 채워진 끝낼 날짜는 2026년 공고의 월/일을 옮긴 임시 값(공식 시험일 아님)이니 원하는 날짜로 바꿔 주세요.',
          ),
          setup.splits(inputs) ? _timeEach() : _time(),
          _weekdays(),
          _period(),
          _familiarity(),
          PrimaryAction(
            _actionLabel,
            _ready ? _calculate : null,
            busy: setup.busy,
          ),
          if (setup.error != null) AlertText(setup.error!),
          if (setup.result case final r?)
            _PlanResult(
              r,
              setup,
              key: resultKey,
              request: setup.request!,
              onSave: setup.saved ? null : _save,
            ),
        ],
      ),
    ),
  );
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
              plan.additionalDailyMinutes > 0
                  ? '현재 일정은 학습시간이 부족합니다. 하루 합계로 최소 ${plan.minimumDailyMinutes}분이 필요합니다.'
                  : '현재 입력으로는 ${durationLabel(plan.missingMinutes)}을 배정하지 못했어요. 하루 시간을 늘리거나 끝낼 날짜를 조정해 주세요.',
              // 자격증별 시간을 정했을 때 서버가 알려 주는 자격증별 최소 시간.
              ...plan.notices.where((n) => n.contains('최소 하루')),
            ].join('\n'),
          ),
        const SizedBox(height: 10),
        const _Note(
          '하루 공부 가능시간은 상한입니다. 선택한 요일에 45분 이상 블록으로 분산하며 마지막 잔여시간은 짧을 수 있습니다. '
          '기출·복습 시간은 아직 추가 산정하지 않았습니다. 시험일은 가상 목표일일 수 있습니다.',
        ),
      ],
    );
  }
}
