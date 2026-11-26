import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/api.dart';
import '../data/models.dart';
import '../data/plan_draft.dart';
import '../data/plan_comparison.dart';
import 'plan_comparison.dart';
import 'plan_list.dart';
import '../data/certification_info.dart';
import 'cert_info.dart';
import 'design.dart';

class PlannerScreen extends StatelessWidget {
  final PassApi api;
  final PlanDraftRepository draftRepository;
  const PlannerScreen(this.api, {super.key, required this.draftRepository});
  Future<_PlannerSetup> _load() async {
    String? goalError, draftError;
    Future<GoalData?> readGoal() async {
      try {
        return await api.goal();
      } catch (_) {
        goalError = '저장한 목표를 불러오지 못했어요. 직접 입력하거나 다시 불러올 수 있어요.';
        return null;
      }
    }

    Future<PlannerDraft?> readDraft() async {
      try {
        return await draftRepository.read();
      } catch (_) {
        draftError = '기기에 저장한 초안을 읽지 못했어요.';
        return null;
      }
    }

    final results = await Future.wait<Object?>([
      api.catalog(),
      readGoal(),
      readDraft(),
    ]);
    return _PlannerSetup(
      results[0] as Catalog,
      results[1] as GoalData?,
      results[2] as PlannerDraft?,
      goalError,
      draftError,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('학습계획 만들기')),
    body: SafeArea(
      child: LoadBox<_PlannerSetup>(
        load: _load,
        content: (c) => _PlanForm(api, c, draftRepository),
      ),
    ),
  );
}

class _PlannerSetup {
  final Catalog catalog;
  final GoalData? goal;
  final PlannerDraft? draft;
  final String? goalError, draftError;
  const _PlannerSetup(
    this.catalog,
    this.goal,
    this.draft,
    this.goalError,
    this.draftError,
  );
}

class PlanSaveResult {
  final bool draftCleared;
  const PlanSaveResult(this.draftCleared);
}

class _PlanForm extends StatefulWidget {
  final PassApi api;
  final _PlannerSetup setup;
  final PlanDraftRepository repository;
  Catalog get catalog => setup.catalog;
  const _PlanForm(this.api, this.setup, this.repository);
  @override
  State<_PlanForm> createState() => _PlanFormState();
}

class _PlanFormState extends State<_PlanForm> with WidgetsBindingObserver {
  final today = dayInSeoul();
  late final endLimit = plusDays(today, 540);
  final days = {1, 2, 3, 4, 5, 6, 7};
  late final minutes = TextEditingController(
    text:
        (widget.setup.goal?.minutes ?? widget.catalog.minutes)?.toString() ??
        '',
  );
  late final drafts = {
    for (final e in widget.catalog.exams)
      e.key: ExamDraft(
        today,
        _usable(e.suggested),
        familiarity: widget.setup.goal == null
            ? {}
            : savedFamiliarity(e, widget.setup.goal!),
      ),
  };
  final scroll = ScrollController();
  int step = 0;
  bool busy = false;
  String? error;
  late GoalData? profile = widget.setup.goal;
  late PlannerDraft? pendingDraft = widget.setup.draft;
  late String? draftProblem = widget.setup.draftError;
  late String? profileNote = widget.setup.goalError;
  String? storageError, restoreNote;
  bool _tracking = false, _dirty = false, _completed = false, _leaving = false;
  int _revision = 0, _savedRevision = 0;
  Timer? _saveTimer;
  @override
  void initState() {
    super.initState();
    _tracking = pendingDraft == null && draftProblem == null;
    if (widget.setup.goal?.minutes != null ||
        drafts.values.any((d) => d.familiarity.isNotEmpty)) {
      restoreNote = '저장한 목표 값을 미리 채웠어요.';
    }
    minutes.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
  }

  void _changed() {
    if (!_tracking || _completed || _leaving) return;
    setState(() {
      _dirty = true;
      _revision++;
    });
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), () {
      _flush();
    });
  }

  void _edit(VoidCallback action) {
    setState(action);
    _changed();
  }

  PlannerDraft _snapshot() => PlannerDraft(
    minutes: minutes.text,
    weekdays: Set.of(days),
    exams: Map.of(drafts),
    step: step,
    updatedAt: DateTime.now().toUtc(),
  );
  Future<bool> _flush() async {
    _saveTimer?.cancel();
    if (!_dirty || _completed || !_tracking) return true;
    final revision = _revision, snapshot = _snapshot();
    try {
      await widget.repository.save(snapshot);
      if (mounted && !_completed) {
        setState(() {
          if (revision >= _savedRevision) {
            _savedRevision = revision;
            storageError = null;
          }
        });
      }
      return true;
    } catch (_) {
      if (mounted && !_completed) {
        setState(
          () => storageError = '기기에 초안을 저장하지 못했어요. 화면을 닫기 전에 다시 저장해 주세요.',
        );
      }
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _flush();
    }
  }

  Future<void> _back() async {
    if (busy || _leaving) return;
    if (pendingDraft != null || draftProblem != null) {
      Navigator.pop(context);
      return;
    }
    if (step > 0) {
      move(step - 1);
      return;
    }
    setState(() => _leaving = true);
    final saved = await _flush();
    if (!mounted) return;
    if (!saved) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('초안을 저장하지 못했어요'),
          content: const Text('계속 작성하거나, 저장 없이 화면을 닫을 수 있어요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('계속 작성'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('저장 없이 닫기'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (leave != true) {
        setState(() => _leaving = false);
        return;
      }
    }
    Navigator.pop(context);
  }

  Future<void> _startFresh() async {
    try {
      await widget.repository.clear();
    } catch (_) {
      storageError = '기기 저장소에 접근하지 못했어요. 초안 자동 저장을 다시 확인해 주세요.';
    }
    if (!mounted) return;
    setState(() {
      pendingDraft = null;
      draftProblem = null;
      _tracking = true;
    });
  }

  void _resume() {
    final draft = pendingDraft!;
    final notes = <String>[];
    _tracking = false;
    minutes.text = draft.minutes;
    days
      ..clear()
      ..addAll(draft.weekdays);
    for (final exam in widget.catalog.exams) {
      final old = draft.exams[exam.key];
      if (old == null) continue;
      final subjects = exam.subjects.map((s) => s['name'] as String).toSet();
      final start = old.start.isBefore(today) ? today : old.start;
      if (start != old.start) notes.add('지난 학습 시작일을 오늘로 옮겼어요.');
      if (old.familiarity.keys.any((s) => !subjects.contains(s))) {
        notes.add('변경된 과목 목록에 맞춰 이해도를 확인해 주세요.');
      }
      drafts[exam.key] = ExamDraft(
        start,
        old.end,
        selected: old.selected,
        familiarity: {
          for (final e in old.familiarity.entries)
            if (subjects.contains(e.key) && e.value >= 1 && e.value <= 3)
              e.key: e.value,
        },
      );
    }
    if (draft.exams.entries.any(
      (e) => e.value.selected && !drafts.containsKey(e.key),
    )) {
      notes.add('현재 제공되지 않는 시험을 제외했어요. 준비할 시험을 확인해 주세요.');
    }
    setState(() {
      step = draft.step;
      pendingDraft = null;
      _tracking = true;
      restoreNote = ['기기에 저장한 초안을 복원했어요.', ...notes.toSet()].join(' ');
    });
    _changed();
  }

  Future<void> _reloadProfile() async {
    try {
      final goal = await widget.api.goal();
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('저장한 값을 불러올까요?'),
          content: const Text('하루 가용 시간과 과목 ID가 일치하는 이해도를 입력란에 적용해요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('불러오기'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      _tracking = false;
      if (goal.minutes != null) minutes.text = goal.minutes.toString();
      for (final exam in widget.catalog.exams) {
        drafts[exam.key]!.familiarity.addAll(savedFamiliarity(exam, goal));
      }
      setState(() {
        profile = goal;
        profileNote = null;
        restoreNote = '저장한 목표를 불러왔어요.';
        _tracking = true;
      });
      _changed();
    } catch (_) {
      if (mounted) {
        setState(() => profileNote = '기존 값을 불러오지 못했어요. 입력한 내용은 보관하고 있어요.');
      }
    }
  }

  Future<bool> _committed() async {
    _completed = true;
    _saveTimer?.cancel();
    try {
      await widget.repository.clear();
      return true;
    } catch (_) {
      return false;
    }
  }

  List<CatalogExam> get selected =>
      widget.catalog.exams.where((e) => drafts[e.key]!.selected).toList();
  DateTime? _usable(DateTime? d) =>
      d != null && d.isAfter(today) && !d.isAfter(endLimit) ? d : null;
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    minutes.removeListener(_changed);
    if (_dirty && !_completed && !_leaving && _tracking) {
      unawaited(widget.repository.save(_snapshot()).catchError((Object _) {}));
    }
    minutes.dispose();
    scroll.dispose();
    super.dispose();
  }

  int validatedMinutes() {
    final n = int.tryParse(minutes.text.trim());
    if (n == null || n < 30 || n > 960) {
      throw const ApiError('하루 공부할 시간은 30~960분으로 입력해 주세요.');
    }
    if (days.isEmpty) throw const ApiError('공부할 요일을 하나 이상 선택해 주세요.');
    return n;
  }

  void validateExams() {
    if (selected.isEmpty) throw const ApiError('준비할 시험을 하나 이상 선택해 주세요.');
    if (selected.length > 12) {
      throw const ApiError('시험은 최대 12개까지 함께 준비할 수 있어요.');
    }
    for (final e in selected) {
      final g = drafts[e.key]!;
      if (g.end == null || !g.start.isBefore(g.end!)) {
        throw ApiError('${e.name}의 목표일을 학습 시작일 다음 날 이후로 선택해 주세요.');
      }
      if (!g.end!.isAfter(today) || g.end!.isAfter(endLimit)) {
        throw ApiError('${e.name}의 목표 시험일을 내일부터 540일 이내로 다시 선택해 주세요.');
      }
    }
  }

  Json payload() {
    final n = validatedMinutes();
    validateExams();
    final goals = <Json>[];
    for (final exam in selected) {
      final g = drafts[exam.key]!, subjects = <Json>[];
      for (final s in exam.subjects) {
        final name = s['name'] as String,
            level = g.familiarity[name],
            hours = s['baseHours'] as num?;
        if (level == null) throw ApiError('$name 과목의 이해도를 선택해 주세요.');
        if (hours == null || hours <= 0) {
          throw ApiError('$name 과목의 기준시간이 아직 준비되지 않았어요.');
        }
        subjects.add({
          'name': name,
          'baseHours': hours,
          'familiarity': level,
          'progressPercent': 0,
          'actualMinutes': 0,
        });
      }
      goals.add({
        'key': exam.key,
        'certificationName': exam.name,
        'startDate': isoDay(g.start),
        'examDate': isoDay(g.end!),
        'subjects': subjects,
      });
    }
    return {
      'dailyMinutes': n,
      'studyWeekdays': days.toList()..sort(),
      'goals': goals,
    };
  }

  void move(int value) {
    FocusScope.of(context).unfocus();
    _edit(() {
      step = value;
      error = null;
    });
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  Future<void> next() async {
    if (busy) return;
    try {
      if (step == 0) {
        validatedMinutes();
        move(1);
        return;
      }
      if (step == 1) {
        validateExams();
        move(2);
        return;
      }
      final form = payload();
      FocusScope.of(context).unfocus();
      setState(() {
        busy = true;
        error = null;
      });
      await _flush();
      final results = await Future.wait<Object?>([
        widget.api.preview(form),
        widget.api.saved(),
      ]);
      if (!mounted) return;
      final saved = await Navigator.push<PlanSaveResult>(
        context,
        MaterialPageRoute(
          builder: (_) => _PreviewScreen(
            widget.api,
            form,
            results[0] as Preview,
            results[1] as SavedPlan?,
            _committed,
          ),
        ),
      );
      if (saved != null && mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) setState(() => error = friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> date(ExamDraft g, bool start) async {
    final d = await selectDate(
      context,
      first: start ? today : plusDays(g.start, 1),
      last: start ? plusDays(endLimit, -1) : endLimit,
      current: start ? g.start : g.end,
    );
    if (d != null && mounted) {
      _edit(() {
        if (start) {
          g.start = d;
          if (g.end != null && !d.isBefore(g.end!)) g.end = null;
        } else {
          g.end = d;
        }
      });
    }
  }

  Widget timeStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 22),
      const Text(
        '학습할 시간을 정해요',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
          height: 1.3,
        ),
      ),
      const SizedBox(height: 10),
      const HelpText('선택한 요일에 공부할 수 있는 최대 시간을 정해 주세요.'),
      const SizedBox(height: 22),
      TextField(
        controller: minutes,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(3),
        ],
        decoration: const InputDecoration(
          labelText: '하루 최대 학습 시간',
          suffixText: '분',
          helperText: '30분부터 16시간까지 입력할 수 있어요.',
        ),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        children: [
          for (final n in [60, 90, 120, 180])
            ChoiceChip(
              label: Text(durationLabel(n)),
              selected: minutes.text == n.toString(),
              onSelected: (_) => setState(() => minutes.text = n.toString()),
            ),
        ],
      ),
      const Heading('공부할 요일'),
      Wrap(
        spacing: 7,
        children: List.generate(
          7,
          (i) => FilterChip(
            label: Text(weekdays[i]),
            showCheckmark: false,
            selected: days.contains(i + 1),
            onSelected: (v) => _edit(() {
              if (v) {
                days.add(i + 1);
              } else {
                days.remove(i + 1);
              }
            }),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Pane(
        color: pale,
        child: Row(
          children: [
            const Icon(Icons.calendar_month_outlined, color: blue, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '일주일에 ${days.length}일 공부해요.',
                style: const TextStyle(
                  color: blue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
  Widget examStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Heading('준비할 시험'),
      const HelpText('여러 자격증을 함께 선택할 수 있어요.\n시험별 학습 시작일과 목표일을 정해 주세요.'),
      const SizedBox(height: 16),
      for (final exam in widget.catalog.exams)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Pane(
            padding: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ExamIcon(exam.name),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          exam.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: exam.temporary
                            ? const Text(
                                '임시 과목 목록',
                                style: TextStyle(fontSize: 12),
                              )
                            : null,
                        value: drafts[exam.key]!.selected,
                        onChanged: (v) =>
                            _edit(() => drafts[exam.key]!.selected = v == true),
                      ),
                    ),
                    // [11-26] 자격증 정보 요약 시트
                    if (certIdFromKey(exam.key) != null)
                      IconButton(
                        tooltip: '${exam.name} 정보',
                        onPressed: () => showCertInfoSheet(
                          context,
                          widget.api,
                          certIdFromKey(exam.key)!,
                        ),
                        icon: const Icon(Icons.info_outline_rounded, size: 20),
                      ),
                  ],
                ),
                if (drafts[exam.key]!.selected) ...[
                  const SizedBox(height: 13),
                  DateField(
                    '학습 시작일',
                    drafts[exam.key]!.start,
                    () => date(drafts[exam.key]!, true),
                  ),
                  const FieldGap(),
                  DateField(
                    '목표 시험일',
                    drafts[exam.key]!.end,
                    () => date(drafts[exam.key]!, false),
                  ),
                  if (_usable(profile?.examDate) != null)
                    TextButton.icon(
                      onPressed: () {
                        final value = profile!.examDate!;
                        if (!drafts[exam.key]!.start.isBefore(value)) {
                          setState(
                            () => error = '저장한 목표일보다 이른 학습 시작일을 선택해 주세요.',
                          );
                          return;
                        }
                        _edit(() => drafts[exam.key]!.end = value);
                      },
                      icon: const Icon(Icons.flag_outlined, size: 16),
                      label: Text(
                        '저장한 목표일 사용 · ${shortDay(profile!.examDate!)}',
                      ),
                    ),
                  if ((exam.scheduleNote ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: HelpText(exam.scheduleNote!),
                    ),
                ],
              ],
            ),
          ),
        ),
      if (widget.catalog.exams.isEmpty)
        const EmptyPanel(
          Icons.search_off_rounded,
          '선택할 수 있는 시험이 없어요',
          '시험 정보를 준비한 뒤 다시 확인해 주세요.',
        ),
    ],
  );
  Widget familiarityStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Heading('나에게 맞는 학습량'),
      const HelpText('과목마다 현재 이해도를 골라 주세요.'),
      const SizedBox(height: 18),
      for (final exam in selected)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Pane(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ExamIcon(exam.name, size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        exam.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                for (final s in exam.subjects) ...[
                  const SizedBox(height: 21),
                  Text(
                    s['name'],
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: List.generate(
                      3,
                      (i) => ChoiceChip(
                        label: Text(levels[i]),
                        selected:
                            drafts[exam.key]!.familiarity[s['name']] == i + 1,
                        onSelected: (_) => _edit(
                          () =>
                              drafts[exam.key]!.familiarity[s['name']] = i + 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
    ],
  );
  Widget _draftChoice() {
    final date = pendingDraft?.updatedAt.toUtc().add(const Duration(hours: 9));
    return ScrollBody(
      children: [
        const SizedBox(height: 20),
        EmptyPanel(
          Icons.edit_note_rounded,
          pendingDraft == null ? '초안을 확인해 주세요' : '이어서 작성할 계획이 있어요',
          pendingDraft == null
              ? draftProblem!
              : '${shortDay(date!)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} 저장 · ${pendingDraft!.step + 1}단계',
          action: pendingDraft == null ? '다시 읽기' : '이어서 작성',
          onTap: pendingDraft == null
              ? () async {
                  try {
                    final value = await widget.repository.read();
                    if (mounted) {
                      setState(() {
                        pendingDraft = value;
                        draftProblem = null;
                        _tracking = value == null;
                      });
                    }
                  } catch (_) {
                    if (mounted) toast(context, '초안을 읽지 못했어요.');
                  }
                }
              : _resume,
        ),
        const FieldGap(),
        OutlinedButton(onPressed: _startFresh, child: const Text('새로 작성')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _back();
    },
    child: pendingDraft != null || draftProblem != null
        ? _draftChoice()
        : AbsorbPointer(
            absorbing: busy || _leaving,
            child: Column(
              children: [
                Expanded(
                  child: ScrollBody(
                    controller: scroll,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.edit_note_rounded,
                            size: 17,
                            color: muted,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              _dirty
                                  ? _savedRevision < _revision
                                        ? '초안 저장 중…'
                                        : '이 기기에 초안 저장됨'
                                  : '입력하면 이 기기에 초안이 자동 저장돼요.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      StepHeader(
                        current: step,
                        labels: const ['시간과 요일', '목표 시험', '과목 이해도'],
                      ),
                      if (restoreNote != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: HelpText(restoreNote!),
                        ),
                      if (profileNote != null) AlertText(profileNote!),
                      if (storageError != null) ...[
                        AlertText(storageError!),
                        TextButton(
                          onPressed: _flush,
                          child: const Text('초안 저장 다시 시도'),
                        ),
                      ],
                      if (step == 0)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: busy ? null : _reloadProfile,
                            icon: const Icon(Icons.download_rounded, size: 17),
                            label: const Text('기존 값 불러오기'),
                          ),
                        ),
                      Entrance(
                        key: ValueKey(step),
                        child: step == 0
                            ? timeStep()
                            : step == 1
                            ? examStep()
                            : familiarityStep(),
                      ),
                    ],
                  ),
                ),
                StickyActions(
                  step == 2 ? '계획 미리보기' : '다음',
                  widget.catalog.exams.isEmpty ? null : next,
                  onBack: step == 0 ? null : () => move(step - 1),
                  busy: busy || _leaving,
                  error: error,
                  summary: step == 2
                      ? '${selected.length}개 시험 · 주 ${days.length}일 · 하루 ${minutes.text}분'
                      : null,
                ),
              ],
            ),
          ),
  );
}

class _PreviewScreen extends StatefulWidget {
  final PassApi api;
  final Json form;
  final Preview result;
  final SavedPlan? previous;
  final Future<bool> Function() onCommitted;
  const _PreviewScreen(
    this.api,
    this.form,
    this.result,
    this.previous,
    this.onCommitted,
  );
  @override
  State<_PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<_PreviewScreen> {
  int week = 0;
  bool busy = false;
  String? error;
  late SavedPlan? previous = widget.previous;
  late PlanComparison comparison = PlanComparison(previous, widget.result);
  Future<void> save() async {
    if (busy) return;
    final activate = await askPlanSave(context);
    if (!mounted || activate == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      // 바로 사용할 때만, 비교해 보여 준 "쓰던 계획"이 그사이 바뀌지 않았는지 확인한다.
      if (activate) {
        final latest = await widget.api.saved();
        if (!mounted) return;
        if (!PlanComparison.samePlan(previous, latest)) {
          setState(() {
            previous = latest;
            comparison = PlanComparison(latest, widget.result);
            error = '사용 중인 계획이 바뀌었어요. 최신 변경 내용을 확인한 뒤 다시 저장해 주세요.';
          });
          return;
        }
      }
      await widget.api.save(widget.form, activate: activate);
      final cleared = await widget.onCommitted();
      if (mounted) Navigator.pop(context, PlanSaveResult(cleared));
    } catch (e) {
      if (mounted) setState(() => error = friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result, slice = r.weekAt(week);
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('계획 미리보기')),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ScrollBody(
                  children: [
                    StatusTag(
                      r.feasible ? '목표일까지 배정 가능' : '시간 조정이 필요해요',
                      color: r.feasible ? green : amber,
                      background: r.feasible
                          ? const Color(0xffe6f5ed)
                          : const Color(0xfffff1df),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      r.feasible ? '배정 시간을 확인해 보세요' : '목표에 맞게 시간을 조정해 보세요',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    HelpText(
                      r.feasible
                          ? '과목별 이해도와 가용 시간으로 계산한 일정이에요.'
                          : '목표일까지 ${durationLabel(r.missingMinutes)}이 부족해요. 입력을 수정해 다시 계산할 수 있어요.',
                    ),
                    const SizedBox(height: 17),
                    Pane(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const HelpText('예상 필요 학습시간'),
                          const SizedBox(height: 7),
                          Text(
                            durationLabel(r.requiredMinutes),
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                            ),
                          ),
                          if (!r.feasible && r.minimumDailyMinutes != null) ...[
                            const SizedBox(height: 10),
                            HelpText(
                              '서버가 계산한 하루 최소 시간 · ${durationLabel(r.minimumDailyMinutes!)}',
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    PlanComparisonSummary(comparison),
                    for (final goal in r.goals)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Pane(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                goal['certificationName'] as String,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              HelpText(
                                '${goal['startDate']} – ${goal['examDate']}',
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '배정 ${durationLabel(goal['scheduledMinutes'] as int)}',
                                style: const TextStyle(
                                  color: blue,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const Heading('주간 배정'),
                    if (slice.isEmpty)
                      const HelpText('배정된 날짜가 없어요.')
                    else ...[
                      Row(
                        children: [
                          IconButton(
                            tooltip: '이전 7일',
                            onPressed: week > 0
                                ? () => setState(() => week--)
                                : null,
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          Expanded(
                            child: Text(
                              '${shortDay(DateTime.parse(slice.first['date']))} – ${shortDay(DateTime.parse(slice.last['date']))}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '다음 7일',
                            onPressed: week + 1 < r.calendarWeeks
                                ? () => setState(() => week++)
                                : null,
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ],
                      ),
                      WeekLoad(slice),
                      const SizedBox(height: 12),
                      for (final day in slice)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Pane(
                            padding: 15,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${shortDay(DateTime.parse(day['date']))} (${weekdays[DateTime.parse(day['date']).weekday - 1]})',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      durationLabel(
                                        day['allocatedMinutes'] as int,
                                      ),
                                      style: const TextStyle(
                                        color: blue,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                if (rows(day['allocations']).isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 8),
                                    child: HelpText('배정된 학습 없음'),
                                  ),
                                for (final a in rows(day['allocations']))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: HelpText(
                                      '${a['certificationName'] ?? ''} · ${a['subjectName']} · ${a['minutes']}분',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                    TextButton.icon(
                      onPressed: busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: const Text('입력 수정'),
                    ),
                  ],
                ),
              ),
              StickyActions('이 계획 저장', save, busy: busy, error: error),
            ],
          ),
        ),
      ),
    );
  }
}

class WeekLoad extends StatelessWidget {
  final List<Json> days;
  const WeekLoad(this.days, {super.key});
  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const Pane(child: HelpText('계획된 학습 없음'));
    final max = days
        .map((d) => d['allocatedMinutes'] as int)
        .fold(1, (n, v) => v > n ? v : n);
    return Pane(
      padding: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HelpText('날짜별 계획 시간 · 분'),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, b) {
              final minWidth =
                  (MediaQuery.textScalerOf(context).scale(12) * 1.8 + 12).clamp(
                    34.0,
                    84.0,
                  );
              final width = (b.maxWidth / days.length).clamp(
                minWidth,
                double.infinity,
              );
              final scrolls = width * days.length > b.maxWidth + 1;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: days.map((d) {
                        final n = d['allocatedMinutes'] as int,
                            date = DateTime.parse(d['date']);
                        return SizedBox(
                          width: width,
                          child: Semantics(
                            label: '${shortDay(date)} 계획 $n분',
                            child: ExcludeSemantics(
                              child: Column(
                                children: [
                                  Text(
                                    '$n',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: muted,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  SizedBox(
                                    height: 76,
                                    child: Align(
                                      alignment: Alignment.bottomCenter,
                                      child: FractionallySizedBox(
                                        heightFactor: n / max,
                                        widthFactor: .42,
                                        child: Container(
                                          decoration: const BoxDecoration(
                                            color: blue,
                                            borderRadius: BorderRadius.vertical(
                                              top: Radius.circular(5),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 9),
                                  Text(
                                    '${date.day}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    weekdays[date.weekday - 1],
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  if (scrolls) ...[
                    const SizedBox(height: 12),
                    const HelpText('좌우로 밀어 7일의 배정을 확인하세요.'),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
