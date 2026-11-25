import 'dart:async';

import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/models.dart';
import '../data/session.dart';
import '../data/study_timer.dart';
import '../data/subject_colors.dart';
import 'auth.dart';
import 'chat.dart';
import 'design.dart';
import 'planner.dart';
import 'plan_list.dart';
import 'plan_month_calendar.dart';
import 'replan.dart';
import 'schedule_editor.dart';
import 'study_records.dart';
import 'subject_color_picker.dart';
import 'today_study_progress.dart';
import 'whole_plan_editor.dart';

class Dashboard extends StatefulWidget {
  final Session session;
  const Dashboard(this.session, {super.key});
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  int tab = 0;
  late Future<SavedPlan?> saved;
  late Future<GoalData> target;

  /// 계획이 많이 밀렸을 때 서버가 주는 재편성 추천 (없거나 읽지 못하면 null).
  late Future<ReplanAdvice?> advice;
  bool adviceHidden = false;
  late final fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 1,
  );
  final chatKey = GlobalKey<ChatScreenState>();
  final planKey = GlobalKey<_PlanPageState>();
  final recordsKey = GlobalKey<StudyRecordsScreenState>();
  final studyTimer = ValueNotifier<StudyTimer?>(null);
  int studyRecordsRevision = 0;
  bool openingPlannedTimer = false;
  DateTime today = dayInSeoul();
  Timer? dayBoundary;
  late PassApi planAccount;
  SubjectColorPreferences? _colorPreferences;
  Map<String, String> _subjectColors = const {};
  late Future<bool> _colorsReady;
  bool _editingSubjectColor = false;
  PassApi get api => widget.session.account!;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    planAccount = api;
    _loadSubjectColors();
    _load();
    scheduleDayBoundary();
  }

  void _load() {
    saved = api.saved();
    target = api.goal();
    // 추천은 부가 기능이라 읽지 못해도 홈을 막지 않는다.
    advice = api.replan().then<ReplanAdvice?>(
      (value) => value,
      onError: (Object _) => null,
    );
    adviceHidden = false;
  }

  void _loadSubjectColors() {
    final session = widget.session;
    final preferences = SubjectColorPreferences(
      session.drafts,
      session.origin,
      session.user!.id,
    );
    if (_colorPreferences?.key == preferences.key) return;
    _colorPreferences = preferences;
    _subjectColors = const {};
    _colorsReady = _readSubjectColors(preferences);
  }

  Future<bool> _readSubjectColors(SubjectColorPreferences preferences) async {
    try {
      final restored = await preferences.read();
      if (mounted && identical(preferences, _colorPreferences)) {
        setState(() => _subjectColors = restored);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _editSubjectColor(StudyTask task, Color automatic) async {
    if (_editingSubjectColor || widget.session.accountActionsBlocked) return;
    final preferences = _colorPreferences!;
    final account = api;
    final subjectKey = SubjectColorPreferences.subjectKey(task);
    bool current() =>
        identical(preferences, _colorPreferences) &&
        identical(account, widget.session.account) &&
        !widget.session.accountActionsBlocked;

    _editingSubjectColor = true;
    try {
      if (!await _colorsReady) {
        if (!mounted || !current()) return;
        _colorsReady = _readSubjectColors(preferences);
        if (!await _colorsReady) {
          if (mounted && current()) toast(context, '과목 색상을 불러오지 못했어요.');
          return;
        }
      }
      if (!mounted || !current()) return;
      final selected = SubjectColorChoice.fromName(_subjectColors[subjectKey]);
      final choice = await showSubjectColorPicker(
        context,
        subject: task.subject,
        selected: selected,
        automatic: automatic,
      );
      if (choice == null || choice == selected || !mounted || !current()) {
        return;
      }
      final updated = {..._subjectColors};
      if (choice == SubjectColorChoice.standard) {
        updated.remove(subjectKey);
      } else {
        updated[subjectKey] = choice.name;
      }
      await preferences.save(updated);
      if (mounted && current()) setState(() => _subjectColors = updated);
    } catch (_) {
      if (mounted && current()) toast(context, '과목 색상을 저장하지 못했어요.');
    } finally {
      _editingSubjectColor = false;
    }
  }

  Future<void> openReplan(ReplanAdvice value) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ReplanScreen(api, value)),
    );
    if (ok != true || !mounted) return;
    await refresh();
    if (mounted) toast(context, '일정을 다시 짰어요. 쓰던 계획은 계획 목록에 보관했어요.');
  }

  Future<void> laterReplan() async {
    setState(() => adviceHidden = true);
    try {
      await api.dismissReplan();
      if (mounted) toast(context, '알겠어요. 7일 동안 다시 묻지 않을게요.');
    } catch (e) {
      if (!mounted) return;
      setState(() => adviceHidden = false);
      toast(context, friendly(e));
    }
  }

  @override
  void didUpdateWidget(Dashboard old) {
    super.didUpdateWidget(old);
    if (!identical(planAccount, api)) {
      planAccount = api;
      _loadSubjectColors();
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    fade.dispose();
    studyTimer.dispose();
    dayBoundary?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        widget.session.account != null) {
      refreshDay();
    }
  }

  void refreshDay() {
    setState(() {
      today = dayInSeoul();
      _load();
    });
    scheduleDayBoundary();
  }

  void scheduleDayBoundary() {
    dayBoundary?.cancel();
    final next = DateTime.utc(
      today.year,
      today.month,
      today.day + 1,
    ).subtract(const Duration(hours: 9));
    dayBoundary = Timer(next.difference(DateTime.now().toUtc()), () {
      if (mounted && widget.session.account != null) refreshDay();
    });
  }

  void selectTab(int i) {
    if (i == tab) return;
    setState(() => tab = i);
    if (!MediaQuery.disableAnimationsOf(context)) fade.forward(from: 0);
  }

  Future<void> openPlannedTimer(SavedPlan plan, StudyTask task) async {
    final records = recordsKey.currentState;
    if (openingPlannedTimer || records == null) return;
    setState(() => openingPlannedTimer = true);
    final source = saved;
    final account = api;
    bool isCurrent() =>
        mounted &&
        tab == 0 &&
        identical(saved, source) &&
        identical(widget.session.account, account);
    try {
      if (await records.selectPlannedTask(plan, task, isCurrent: isCurrent) &&
          isCurrent()) {
        records.showTimer();
        selectTab(2);
      }
    } catch (e) {
      if (mounted && isCurrent()) toast(context, friendly(e));
    } finally {
      if (mounted) setState(() => openingPlannedTimer = false);
    }
  }

  Future<void> editSchedule(
    SavedPlan plan, {
    StudyTask? task,
    bool moveOnly = false,
  }) async {
    final account = api;
    final result = await showScheduleEditor(
      context,
      account,
      plan,
      task: task,
      moveOnly: moveOnly,
    );
    if (result != null &&
        mounted &&
        identical(widget.session.account, account)) {
      await refresh();
    }
  }

  Future<void> editWholePlan(SavedPlan plan) async {
    final account = api;
    final id = plan.id;
    if (id == null) return;
    final edited = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => WholePlanEditor(account, id)),
    );
    if (edited == true &&
        mounted &&
        identical(widget.session.account, account)) {
      await refresh();
      if (mounted && identical(widget.session.account, account)) {
        toast(context, '전체 학습계획을 수정했어요.');
      }
    }
  }

  void openLearningPlan({DateTime? day}) {
    if (day != null) planKey.currentState?.showCalendarOn(day);
    selectTab(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && tab == 1) planKey.currentState?.showOverview();
    });
  }

  Future<void> refresh() async {
    setState(_load);
    try {
      await Future.wait([saved.then<void>((_) {}), target.then<void>((_) {})]);
    } catch (_) {
      // The affected section provides its own retry action.
    }
  }

  Future<void> create() async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final account = api;
    final ok = await Navigator.push<PlanSaveResult>(
      context,
      MaterialPageRoute(
        builder: (_) => PlannerScreen(
          account,
          draftRepository: widget.session.planDraft,
          onDefaultsChanged: (updatedGoal) {
            if (!mounted || !identical(widget.session.account, account)) return;
            setState(() {
              target = updatedGoal;
            });
          },
        ),
      ),
    );
    if (mounted && ok != null) {
      selectTab(1);
      await refresh();
      if (mounted) {
        final message = ok.activated
            ? '학습계획을 저장하고 적용했어요.'
            : '계획 목록에 저장했어요. 저장한 계획에서 사용할 수 있어요.';
        toast(
          context,
          ok.draftCleared ? message : '$message 기기의 초안을 정리하지 못했어요.',
        );
      }
    }
  }

  void ask(String message) {
    selectTab(3);
    chatKey.currentState?.prepareQuestion(message);
  }

  static const names = ['홈', '학습계획', '기록', '학습 상담', '내 정보'];
  static const navigation = [
    (
      tab: 1,
      item: NavigationDestination(
        icon: Icon(Icons.calendar_today_outlined),
        selectedIcon: Icon(Icons.calendar_month_rounded),
        label: '학습계획',
      ),
    ),
    (
      tab: 2,
      item: NavigationDestination(
        icon: Icon(Icons.history_outlined),
        selectedIcon: Icon(Icons.history_rounded),
        label: '기록',
      ),
    ),
    (
      tab: 0,
      item: NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home_rounded),
        label: '홈',
      ),
    ),
    (
      tab: 3,
      item: NavigationDestination(
        icon: Icon(Icons.chat_bubble_outline_rounded),
        selectedIcon: Icon(Icons.chat_bubble_rounded),
        label: '상담',
      ),
    ),
    (
      tab: 4,
      item: NavigationDestination(
        icon: Icon(Icons.person_outline_rounded),
        selectedIcon: Icon(Icons.person_rounded),
        label: '내 정보',
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: tab == 0 ? const Brand(useLauncherIcon: true) : Text(names[tab]),
      actions: [
        if (tab == 1) ...[
          IconButton(
            tooltip: '저장한 계획 목록',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PlanListScreen(api, onChanged: refresh),
              ),
            ),
            icon: const Icon(Icons.list_alt_rounded, size: 22),
          ),
          if (MediaQuery.sizeOf(context).width >= 360 &&
              MediaQuery.textScalerOf(context).scale(14) <= 20)
            Tooltip(
              message: '새 계획 만들기',
              child: TextButton.icon(
                onPressed: create,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('새 계획'),
              ),
            )
          else
            IconButton(
              tooltip: '새 계획 만들기',
              onPressed: create,
              icon: const Icon(Icons.add_rounded),
            ),
          FutureBuilder<SavedPlan?>(
            future: saved,
            builder: (context, snapshot) {
              final plan = snapshot.data;
              if (snapshot.hasError || plan == null || !plan.canEditSchedule) {
                return const SizedBox.shrink();
              }
              return PopupMenuButton<_PlanEditAction>(
                tooltip: '계획 수정',
                enabled: snapshot.connectionState == ConnectionState.done,
                icon: const Icon(Icons.edit_outlined, color: blue),
                onSelected: (action) => switch (action) {
                  _PlanEditAction.whole => editWholePlan(plan),
                  _PlanEditAction.period => editSchedule(plan),
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _PlanEditAction.whole,
                    child: Text('전체 계획 수정'),
                  ),
                  PopupMenuItem(
                    value: _PlanEditAction.period,
                    child: Text('계획 기간 수정'),
                  ),
                ],
              );
            },
          ),
        ],
        if (tab == 3)
          IconButton(
            tooltip: '새 대화',
            onPressed: () => chatKey.currentState?.newChat(),
            icon: const Icon(Icons.edit_square, size: 21),
          ),
        const SizedBox(width: 6),
      ],
    ),
    body: SafeArea(
      child: FadeTransition(
        opacity: fade,
        child: FutureBuilder<SavedPlan?>(
          future: saved,
          builder: (context, snapshot) => _tabs(snapshot),
        ),
      ),
    ),
    bottomNavigationBar: DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: line)),
      ),
      child: NavigationBar(
        height: MediaQuery.textScalerOf(context).scale(12) > 16 ? 104 : 76,
        selectedIndex: navigation.indexWhere((entry) => entry.tab == tab),
        onDestinationSelected: (index) {
          final i = navigation[index].tab;
          if (i == 1 && i == tab) planKey.currentState?.showOverview();
          if (i == 2) recordsKey.currentState?.showTimer();
          selectTab(i);
        },
        destinations: [for (final entry in navigation) entry.item],
      ),
    ),
  );
  Widget _plans(
    AsyncSnapshot<SavedPlan?> snap,
    Color? Function(StudyTask) colorForSubject,
    Map<StudyTask, TaskProgress>? todayProgress,
    Widget? progressStatus,
  ) => _PlanPage(
    key: planKey,
    plan: snap.data,
    loading: snap.connectionState != ConnectionState.done,
    error: snap.error,
    refresh: refresh,
    onCreate: create,
    onAsk: ask,
    onEditTask: (plan, task) => editSchedule(plan, task: task),
    colorForSubject: colorForSubject,
    todayProgress: todayProgress,
    progressStatus: progressStatus,
  );

  Widget _error(Object error) => ScrollBody(
    refresh: refresh,
    children: [
      EmptyPanel(
        Icons.cloud_off_outlined,
        '계획을 불러오지 못했어요',
        friendly(error),
        action: '다시 시도',
        onTap: refresh,
      ),
    ],
  );
  Widget _tabs(AsyncSnapshot<SavedPlan?> snapshot) {
    final plan = snapshot.connectionState == ConnectionState.done
        ? snapshot.data
        : null;
    final automaticColors = automaticSubjectColors(
      plan?.byDay.values
              .expand((day) => day)
              .map(SubjectColorPreferences.subjectKey) ??
          const [],
      _colorPreferences!.key,
    );
    Color? colorForKey(String key) =>
        SubjectColorChoice.fromName(_subjectColors[key]).color ??
        automaticColors[key];
    final hasSubjectColors =
        automaticColors.isNotEmpty || _subjectColors.isNotEmpty;
    final tasksById = {
      if (plan != null)
        for (final day in plan.byDay.values)
          for (final task in day) ?task.id: task,
    };

    final records = StudyRecordsScreen(
      widget.session,
      key: recordsKey,
      active: tab == 2,
      onOpenTimer: () => selectTab(2),
      onTimerBound: (timer) => studyTimer.value = timer,
      onRecordsChanged: () => setState(() => studyRecordsRevision++),
      colorForRecord: hasSubjectColors
          ? (record) {
              if (record.planId != null && record.planId != plan?.id) {
                return null;
              }
              final task = tasksById[record.taskId];
              final name = record.subjectName?.trim();
              if (task == null ||
                  name != null &&
                      name.isNotEmpty &&
                      name != task.subject.trim()) {
                return null;
              }
              return colorForKey(SubjectColorPreferences.subjectKey(task));
            }
          : null,
      colorForSubject: (task) {
        final name = task.subjectName;
        if (name == null || name.trim().isEmpty) return null;
        final key = SubjectColorPreferences.keyForNames(
          task.certificationName,
          name,
        );
        return colorForKey(key);
      },
    );
    final chat = ChatScreen(api, key: chatKey, onPlanSaved: refresh);
    final profile = ProfileScreen(
      widget.session,
      prepareWithdrawal: () async =>
          await recordsKey.currentState?.prepareForWithdrawal() ?? false,
    );
    final plannedMinutes = (plan?.on(today) ?? const <StudyTask>[]).fold(
      0,
      (sum, task) => sum + task.minutes,
    );

    Widget pages(
      Map<StudyTask, TaskProgress>? studied,
      Widget? summary,
      Widget? status,
    ) => IndexedStack(
      index: tab,
      children: [
        _home(snapshot, automaticColors, studied, summary, status),
        _plans(
          snapshot,
          (task) => colorForKey(SubjectColorPreferences.subjectKey(task)),
          studied,
          status,
        ),
        records,
        chat,
        profile,
      ],
    );
    return ValueListenableBuilder(
      valueListenable: studyTimer,
      builder: (context, timer, _) => TodayStudyProgress(
        api: api,
        plan: plan?.id != null && plannedMinutes > 0 ? plan : null,
        day: today,
        plannedMinutes: plannedMinutes,
        refreshSignal: (saved, studyRecordsRevision),
        timer: timer,
        builder: pages,
      ),
    );
  }

  Widget _home(
    AsyncSnapshot<SavedPlan?> snap,
    Map<String, Color> automaticColors,
    Map<StudyTask, TaskProgress>? studied,
    Widget? summary,
    Widget? progressStatus,
  ) => FutureBuilder<GoalData>(
    future: target,
    builder: (context, goalSnap) {
      if (snap.connectionState != ConnectionState.done) {
        return const LoadingPanel();
      }
      if (snap.hasError) return _error(snap.error!);
      final plan = snap.data;
      final tasks = plan?.on(today) ?? [];
      final plannedMinutes = tasks.fold<int>(
        0,
        (sum, task) => sum + task.minutes,
      );

      Widget taskList() {
        if (plan == null) return const SizedBox.shrink();
        if (tasks.isEmpty) {
          return const EmptyPanel(
            Icons.event_note_outlined,
            '계획된 학습 없음',
            '월간 일정에서 다른 날짜의 과목을 볼 수 있어요.',
          );
        }

        // Preserve an open measurement. Otherwise offer the first item with time left.
        final clock = studyTimer.value;
        final current = clock?.task;
        final currentId =
            current != null &&
                current.planId == plan.id &&
                current.scheduledDate == today &&
                (clock!.phase == StudyTimerPhase.running ||
                    clock.elapsed > Duration.zero)
            ? current.id
            : null;
        final resumable = tasks
            .where(
              (task) =>
                  currentId != null &&
                  (task.id == currentId || studied?[task]?.taskId == currentId),
            )
            .firstOrNull;
        final next =
            resumable ??
            tasks.where((task) {
              final time = studied?[task]?.time;
              return time == null || time < Duration(minutes: task.minutes);
            }).firstOrNull;
        final multipleExams = tasks.map((t) => t.exam).toSet().length > 1;
        Widget tile(StudyTask task) {
          final key = SubjectColorPreferences.subjectKey(task);
          final automatic = automaticColors[key]!;
          return TaskTile(
            task,
            onTap: openingPlannedTimer
                ? null
                : () => openPlannedTimer(plan, task),
            onDetails: () => showTaskDetails(context, task, onAsk: ask),
            onColor: () => _editSubjectColor(task, automatic),
            subjectColor: SubjectColorChoice.fromName(_subjectColors[key]),
            automaticColor: automatic,
            onMove: plan.id != null && task.id != null
                ? () => editSchedule(plan, task: task, moveOnly: true)
                : null,
            progress: studied?[task],
            showProgress: plan.id != null,
            showExam: multipleExams,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            summary ?? TodayProgressSummary(plannedMinutes: plannedMinutes),
            if (progressStatus != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: progressStatus,
              ),
            const SizedBox(height: 32),
            Semantics(
              header: true,
              child: const Text(
                '오늘 할 학습',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            if (next != null) tile(next),
            for (final task in tasks)
              if (task != next) tile(task),
          ],
        );
      }

      return ScrollBody(
        key: const PageStorageKey('home-scroll'),
        refresh: refresh,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              Text(
                '${shortDay(today)} ${weekdays[today.weekday - 1]}요일',
                style: const TextStyle(
                  color: muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (goalSnap.data?.examDate case final DateTime examDate)
                _HomeGoal(
                  name: goalSnap.data!.examLabel,
                  examDate: examDate,
                  today: today,
                  onTap: openLearningPlan,
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (plan == null)
            EmptyPanel(
              Icons.auto_stories_outlined,
              '합격을 향한 첫 계획',
              '준비하는 시험과 공부할 시간을 정하면 오늘 할 학습이 여기에 표시돼요.',
              action: '학습계획 만들기',
              onTap: openLearningPlan,
            )
          else ...[
            taskList(),
            const SizedBox(height: 20),
            _HomeMonthCalendar(
              plan: plan,
              today: today,
              onOpenSchedule: (day) => openLearningPlan(day: day),
              subjectColor: (task) {
                final key = SubjectColorPreferences.subjectKey(task);
                return SubjectColorChoice.fromName(_subjectColors[key]).color ??
                    automaticColors[key];
              },
            ),
          ],
          const SizedBox(height: 8),
          if (goalSnap.hasError)
            TextButton.icon(
              onPressed: refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('목표 다시 불러오기'),
            )
          else if (goalSnap.hasData &&
              goalSnap.data?.examDate == null &&
              plan != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: create,
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text('새 계획에서 목표 정하기'),
              ),
            ),
          if (plan != null && !adviceHidden)
            FutureBuilder<ReplanAdvice?>(
              future: advice,
              builder: (context, found) => found.data == null
                  ? const SizedBox.shrink()
                  : ReplanCard(
                      found.data!,
                      onOpen: () => openReplan(found.data!),
                      onLater: laterReplan,
                    ),
            ),
        ],
      );
    },
  );
}

class _HomeGoal extends StatelessWidget {
  final String name;
  final DateTime examDate, today;
  final VoidCallback onTap;
  const _HomeGoal({
    required this.name,
    required this.examDate,
    required this.today,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final delta = examDate.difference(today).inDays;
    final label = delta == 0
        ? 'D-DAY'
        : delta > 0
        ? 'D-$delta'
        : 'D+${-delta}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Wrap(
            runAlignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xffefe9e2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xff675747),
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              if (delta < 0) const HelpText('목표일 지남'),
            ],
          ),
        ),
      ),
    );
  }
}

class WeekStrip extends StatelessWidget {
  final DateTime selected, today;
  final SavedPlan? plan;
  final ValueChanged<DateTime> change;
  const WeekStrip({
    super.key,
    required this.selected,
    required this.today,
    required this.plan,
    required this.change,
  });
  @override
  Widget build(BuildContext context) {
    final mon = plusDays(selected, 1 - selected.weekday);
    final period = mon.month == plusDays(mon, 6).month
        ? '${mon.year}년 ${mon.month}월'
        : '${shortDay(mon)} – ${shortDay(plusDays(mon, 6))}';
    final previous = IconButton(
      tooltip: '이전 주',
      onPressed: () => change(plusDays(selected, -7)),
      icon: const Icon(Icons.chevron_left_rounded, size: 21),
    );
    final next = IconButton(
      tooltip: '다음 주',
      onPressed: () => change(plusDays(selected, 7)),
      icon: const Icon(Icons.chevron_right_rounded, size: 21),
    );
    final now = TextButton(
      onPressed: () => change(today),
      child: const Text('오늘', style: TextStyle(fontSize: 13)),
    );
    final title = Text(
      period,
      textAlign: TextAlign.center,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
    );
    return Column(
      children: [
        if (MediaQuery.textScalerOf(context).scale(14) > 20)
          Column(
            children: [
              title,
              Row(
                children: [previous, const Spacer(), now, const Spacer(), next],
              ),
            ],
          )
        else
          Row(
            children: [
              previous,
              Expanded(child: title),
              now,
              next,
            ],
          ),
        const SizedBox(height: 8),
        HorizontalChoices(
          key: ValueKey(isoDay(mon)),
          selectedIndex: selected.weekday - 1,
          children: List.generate(7, (i) {
            final d = plusDays(mon, i),
                on = d == selected,
                has = plan?.on(d).isNotEmpty ?? false,
                isToday = d == today;
            return Semantics(
              key: ValueKey('week-day-${isoDay(d)}'),
              button: true,
              selected: on,
              onTap: () => change(d),
              label:
                  '${shortDay(d)} ${weekdays[i]}요일${isToday ? ', 오늘' : ''}${has ? ', 계획 있음' : ''}',
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Material(
                    color: on ? blue : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => change(d),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          children: [
                            Text(
                              weekdays[i],
                              style: TextStyle(
                                fontSize: 12,
                                color: on ? Colors.white : muted,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${d.day}',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: on
                                    ? Colors.white
                                    : isToday
                                    ? blue
                                    : ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: has
                                    ? (on ? Colors.white : blue)
                                    : Colors.transparent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

enum _TaskAction { move, details, color }

class _HomeMonthCalendar extends StatefulWidget {
  final SavedPlan plan;
  final DateTime today;
  final Color? Function(StudyTask) subjectColor;
  final ValueChanged<DateTime> onOpenSchedule;

  const _HomeMonthCalendar({
    required this.plan,
    required this.today,
    required this.subjectColor,
    required this.onOpenSchedule,
  });

  @override
  State<_HomeMonthCalendar> createState() => _HomeMonthCalendarState();
}

class _HomeMonthCalendarState extends State<_HomeMonthCalendar> {
  late DateTime selected = widget.today;
  final expansion = ExpansibleController();

  @override
  void didUpdateWidget(_HomeMonthCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plan.id != widget.plan.id || selected == oldWidget.today) {
      selected = widget.today;
    }
  }

  @override
  void dispose() {
    expansion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final date = PlanMonthCalendar.dateInPlan(plan, selected);
    final tasks = plan.on(date);
    final compact =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(14) > 20;
    const scheduleKey = ValueKey('home-open-schedule');
    void openSchedule() => widget.onOpenSchedule(date);
    return ExpansionTile(
      key: const PageStorageKey('home-month-calendar-toggle'),
      controller: expansion,
      initiallyExpanded: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      shape: const Border(top: BorderSide(color: line)),
      collapsedShape: const Border(top: BorderSide(color: line)),
      title: const Text('월간 일정', style: TextStyle(fontWeight: FontWeight.w700)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (compact)
            IconButton(
              key: scheduleKey,
              tooltip: '전체 일정',
              onPressed: openSchedule,
              icon: const Icon(Icons.event_note_outlined, color: blue),
            )
          else
            TextButton(
              key: scheduleKey,
              onPressed: openSchedule,
              child: const Text('전체 일정'),
            ),
          ListenableBuilder(
            listenable: expansion,
            builder: (context, child) => AnimatedRotation(
              turns: expansion.isExpanded ? .5 : 0,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              child: child,
            ),
            child: const Icon(Icons.expand_more, size: 20),
          ),
        ],
      ),
      children: [
        PlanMonthCalendar(
          key: const PageStorageKey('home-month-calendar'),
          plan: plan,
          selected: date,
          today: widget.today,
          onSelect: (date) => setState(() => selected = date),
          subjectColor: widget.subjectColor,
          showMonthSummary: false,
        ),
        if (selected != widget.today) ...[
          const SizedBox(height: 12),
          const Divider(),
          Column(
            key: const ValueKey('home-month-selected-day'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Heading('${shortDay(date)} 학습'),
              if (tasks.isEmpty) const HelpText('계획된 학습 없음'),
              for (final task in tasks)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SubjectColorDot(widget.subjectColor(task) ?? blue),
                      const SizedBox(width: 8),
                      Expanded(flex: 3, child: Text(task.subject)),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: Text(
                          durationLabel(task.minutes),
                          textAlign: TextAlign.end,
                          style: const TextStyle(color: muted),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class TaskTile extends StatelessWidget {
  final StudyTask task;
  final VoidCallback? onTap, onDetails, onMove, onColor;
  final SubjectColorChoice subjectColor;
  final Color? automaticColor;
  final TaskProgress? progress;
  final bool showProgress;
  final bool showExam;
  const TaskTile(
    this.task, {
    super.key,
    this.onTap,
    this.onDetails,
    this.onMove,
    this.onColor,
    this.subjectColor = SubjectColorChoice.standard,
    this.automaticColor,
    this.progress,
    this.showProgress = false,
    this.showExam = false,
  });

  Widget? actions() {
    if (onMove != null || onColor != null) {
      return PopupMenuButton<_TaskAction>(
        key: ValueKey('planned-task-actions-${task.id}'),
        tooltip: '${task.subject} 메뉴',
        onSelected: (action) => switch (action) {
          _TaskAction.move => onMove?.call(),
          _TaskAction.details => onDetails?.call(),
          _TaskAction.color => onColor?.call(),
        },
        itemBuilder: (_) => [
          if (onMove != null)
            const PopupMenuItem(
              value: _TaskAction.move,
              child: Text('다른 날짜로 옮기기'),
            ),
          if (onDetails != null)
            const PopupMenuItem(
              value: _TaskAction.details,
              child: Text('상세 보기'),
            ),
          if (onColor != null)
            const PopupMenuItem(value: _TaskAction.color, child: Text('색상 변경')),
        ],
      );
    }
    if (onDetails == null) return null;
    return IconButton(
      tooltip: '${task.subject} 상세 보기',
      onPressed: onDetails,
      icon: const Icon(Icons.info_outline_rounded, color: muted),
    );
  }

  @override
  Widget build(BuildContext context) {
    final menu = actions();
    final showBar = showProgress && task.minutes > 0;
    final color = subjectColor.color ?? automaticColor;
    final subject = Text(
      task.subject,
      style: const TextStyle(
        fontSize: 17,
        height: 1.35,
        fontWeight: FontWeight.w700,
        letterSpacing: -.3,
      ),
    );
    return Material(
      color: Colors.transparent,
      child: Semantics(
        hint: onTap == null ? null : '타이머 열기',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          highlightColor: (color ?? blue).withValues(alpha: .09),
          splashColor: (color ?? blue).withValues(alpha: .14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                if (color != null) ...[
                  SubjectColorDot(
                    color,
                    size: 12,
                    label: '과목 색상 ${subjectColor.labelFor(color)}',
                    markerKey: ValueKey('today-task-color-${task.id}'),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: showBar
                      ? StudyProgressBar(
                          barKey: progress != null || task.id != null
                              ? ValueKey(
                                  'today-task-progress-${progress?.taskId ?? task.id}',
                                )
                              : ObjectKey(task),
                          compact: true,
                          label: '${task.subject} 진행률',
                          studied: progress?.time,
                          plannedMinutes: task.minutes,
                          detail: '',
                          trackColor: color == null
                              ? line
                              : subjectColorTrack(color),
                          fillColor: color,
                          header: (percent) => Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    subject,
                                    if (showExam) HelpText(task.exam),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                percent,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            subject,
                            HelpText(
                              '${task.exam} · 배정 ${durationLabel(task.minutes)}',
                            ),
                          ],
                        ),
                ),
                ?menu,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showTaskDetails(
  BuildContext context,
  StudyTask t, {
  required ValueChanged<String> onAsk,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (c) => SafeArea(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: ExamIcon(t.exam, size: 50),
            ),
            const SizedBox(height: 15),
            Text(t.exam, style: const TextStyle(color: muted, fontSize: 13)),
            const SizedBox(height: 5),
            Text(
              t.subject,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -.8,
              ),
            ),
            const SizedBox(height: 18),
            Pane(
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text(shortDay(t.date)),
                  Text(
                    '계획 ${durationLabel(t.minutes)}',
                    style: const TextStyle(
                      color: blue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            PrimaryAction('이 과목 공부 방법 상담', () {
              Navigator.pop(c);
              onAsk(
                '${t.exam}의 ${t.subject} 과목을 ${t.minutes}분 동안 어떻게 공부하면 좋을까요?',
              );
            }),
          ],
        ),
      ),
    ),
  ),
);

enum _PlanEditAction { whole, period }

class _PlanPage extends StatefulWidget {
  final SavedPlan? plan;
  final bool loading;
  final Object? error;
  final Future<void> Function() refresh;
  final VoidCallback onCreate;
  final ValueChanged<String> onAsk;
  final void Function(SavedPlan, StudyTask) onEditTask;
  final Color? Function(StudyTask) colorForSubject;
  final Map<StudyTask, TaskProgress>? todayProgress;
  final Widget? progressStatus;
  const _PlanPage({
    super.key,
    required this.plan,
    required this.loading,
    required this.error,
    required this.refresh,
    required this.onCreate,
    required this.onAsk,
    required this.onEditTask,
    required this.colorForSubject,
    required this.todayProgress,
    required this.progressStatus,
  });
  @override
  State<_PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<_PlanPage> {
  bool calendarList = false;
  DateTime selected = dayInSeoul();
  final scroll = ScrollController();
  void showCalendarOn(DateTime day) {
    if (!calendarList && selected == day) return;
    setState(() {
      selected = day;
      calendarList = false;
    });
  }

  void showOverview() {
    if (!scroll.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      scroll.jumpTo(0);
      return;
    }
    scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.plan;
    if (widget.error != null || p == null) {
      return ScrollBody(
        key: const PageStorageKey('plan-scroll'),
        controller: scroll,
        refresh: widget.refresh,
        children: [
          if (widget.loading)
            const Pane(
              child: Column(
                children: [
                  LinearProgressIndicator(semanticsLabel: '계획을 불러오는 중'),
                  SizedBox(height: 16),
                  HelpText('저장된 계획을 불러오고 있어요.'),
                ],
              ),
            )
          else if (widget.error != null)
            EmptyPanel(
              Icons.cloud_off_outlined,
              '계획을 불러오지 못했어요',
              friendly(widget.error!),
              action: '다시 시도',
              onTap: widget.refresh,
            )
          else
            EmptyPanel(
              Icons.calendar_month_outlined,
              '아직 저장한 계획이 없어요',
              '공부할 요일과 시간을 고르고 미리보기에서 일정을 확인하세요.',
              action: '학습계획 만들기',
              onTap: widget.onCreate,
            ),
        ],
      );
    }
    final today = dayInSeoul();
    final keys = p.byDay.keys.toList()..sort();
    final calendarDay = PlanMonthCalendar.dateInPlan(p, selected);
    final visible = calendarList
        ? keys
        : [if (p.on(calendarDay).isNotEmpty) isoDay(calendarDay)];
    final status = today.isBefore(p.start)
        ? '시작 예정'
        : today.isAfter(p.end)
        ? '학습 기간 종료'
        : '학습 기간 중';
    final dayLabel = p.start.year == today.year && p.end.year == today.year
        ? shortDay
        : isoDay;
    return WidthLimit(
      child: RefreshIndicator(
        onRefresh: widget.refresh,
        child: ListView.builder(
          key: const PageStorageKey('plan-scroll'),
          controller: scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          itemCount: visible.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageTitle(
                    p.name.trim().isNotEmpty ? p.name : '나의 학습계획',
                    eyebrow: '저장된 학습계획',
                    description:
                        '${dayLabel(p.start)} – ${dayLabel(p.end)} · $status',
                  ),
                  if (!p.canEditSchedule && p.byDay.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: HelpText(scheduleServerMessage),
                    ),
                  const SizedBox(height: 16),
                  if (!calendarList) const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          calendarList ? '날짜별 학습' : '월간 일정',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Tooltip(
                        message: calendarList ? '달력으로 보기' : '목록으로 보기',
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() => calendarList = !calendarList),
                          icon: Icon(
                            calendarList
                                ? Icons.calendar_month_outlined
                                : Icons.view_list_outlined,
                            size: 20,
                          ),
                          label: Text(calendarList ? '달력으로' : '목록으로'),
                        ),
                      ),
                    ],
                  ),
                  if (!calendarList) ...[
                    const SizedBox(height: 8),
                    KeyedSubtree(
                      key: const PageStorageKey('plan-calendar-position'),
                      child: PlanMonthCalendar(
                        key: const ValueKey('plan-month-calendar'),
                        plan: p,
                        selected: calendarDay,
                        today: today,
                        onSelect: (date) => setState(() => selected = date),
                        subjectColor: widget.colorForSubject,
                        showMonthSummary: false,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Divider(),
                    const SizedBox(height: 10),
                    const Heading('날짜별 학습'),
                  ],
                  if (visible.contains(isoDay(today)) &&
                      widget.progressStatus != null)
                    widget.progressStatus!,
                  if (visible.isEmpty)
                    EmptyPanel(
                      Icons.calendar_today_outlined,
                      '계획된 학습 없음',
                      calendarList
                          ? '계획에 배정된 학습이 없어요.'
                          : '${shortDay(calendarDay)}에 배정된 학습이 없어요.',
                    ),
                ],
              );
            }
            final d = DateTime.parse(visible[i - 1]),
                tasks = p.byDay[visible[i - 1]]!,
                on = d == today;
            final minutes = tasks.fold<int>(
              0,
              (sum, task) => sum + task.minutes,
            );
            final dayText = calendarList
                ? '${d.day}일 ${weekdays[d.weekday - 1]}요일'
                : shortDay(d);
            final dayTile = ExpansionTile(
              tilePadding: EdgeInsets.zero,
              key: PageStorageKey(
                'day-${p.version}-$calendarList-${visible[i - 1]}',
              ),
              shape: const Border(),
              collapsedShape: const Border(),
              initiallyExpanded: on || !calendarList,
              title: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(
                    on ? '오늘 · $dayText' : dayText,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: on ? blue : ink,
                    ),
                  ),
                  if (calendarList)
                    Text(
                      '${tasks.length}개 항목 · ${durationLabel(minutes)}',
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
                ],
              ),
              subtitle: calendarList
                  ? null
                  : Text(
                      '${tasks.length}개 항목 · ${durationLabel(minutes)}',
                      style: const TextStyle(fontSize: 12, color: muted),
                    ),
              children: tasks.map((t) {
                final color = widget.colorForSubject(t);
                final progress = on ? (widget.todayProgress?[t]) : null;
                final allocated = durationLabel(t.minutes);
                return ListTile(
                  contentPadding: const EdgeInsetsDirectional.only(start: 10),
                  title: Row(
                    children: [
                      if (color != null) ...[
                        SubjectColorDot(
                          color,
                          markerKey: t.id == null
                              ? ObjectKey(t)
                              : ValueKey('plan-task-color-${t.id}'),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          t.subject,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 5, bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.exam,
                          style: const TextStyle(fontSize: 12, color: muted),
                        ),
                        const SizedBox(height: 6),
                        if (on)
                          StudyProgressBar(
                            barKey: progress != null || t.id != null
                                ? ValueKey(
                                    'plan-task-progress-${progress?.taskId ?? t.id}',
                                  )
                                : ObjectKey(t),
                            label: '${t.subject} 진행률',
                            detail: progress == null
                                ? '계획 $allocated'
                                : '공부 ${durationLabel(progress.time.inMinutes)} · 배정 $allocated',
                            studied: progress?.time,
                            plannedMinutes: t.minutes,
                            compact: true,
                            fillColor: color,
                            trackColor: color == null
                                ? line
                                : subjectColorTrack(color),
                          )
                        else
                          Text(
                            '계획 $allocated',
                            style: const TextStyle(
                              color: blue,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  onTap: () => showTaskDetails(context, t, onAsk: widget.onAsk),
                  trailing: canEditTask(p, t)
                      ? Tooltip(
                          message: '${t.subject} 날짜·배정시간 수정',
                          child: TextButton(
                            onPressed: widget.loading
                                ? null
                                : () => widget.onEditTask(p, t),
                            child: const Text('수정'),
                          ),
                        )
                      : null,
                );
              }).toList(),
            );
            if (!calendarList) {
              return DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: line)),
                ),
                child: dayTile,
              );
            }
            final firstOfMonth =
                i == 1 ||
                visible[i - 2].substring(0, 7) !=
                    visible[i - 1].substring(0, 7);
            if (!firstOfMonth) return dayTile;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: i == 1 ? 8 : 20, bottom: 4),
                  child: Semantics(
                    header: true,
                    child: Text(
                      '${d.year}년 ${d.month}월',
                      style: const TextStyle(
                        color: muted,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                dayTile,
              ],
            );
          },
        ),
      ),
    );
  }
}
