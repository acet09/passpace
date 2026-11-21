import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/models.dart';
import '../data/session.dart';
import 'auth.dart';
import 'chat.dart';
import 'design.dart';
import 'goal.dart';
import 'planner.dart';
import 'plan_goal_section.dart';
import 'plan_list.dart';
import 'plan_month_calendar.dart';
import 'replan.dart';
import 'study_records.dart';
import 'view_switch.dart';

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
  bool homeMonth = false;
  bool settingsSaved = false;
  bool goalExpanded = true;
  DateTime today = dayInSeoul();
  late DateTime selected = today;
  late PassApi planAccount;
  PassApi get api => widget.session.account!;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    planAccount = api;
    _load();
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
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    fade.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        widget.session.account != null) {
      setState(() {
        final now = dayInSeoul();
        if (selected == today) selected = now;
        today = now;
        _load();
      });
    }
  }

  void selectTab(int i) {
    if (i == tab) return;
    setState(() => tab = i);
    if (!MediaQuery.disableAnimationsOf(context)) fade.forward(from: 0);
  }

  void openLearningPlan() {
    selectTab(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) planKey.currentState?.showOverview();
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

  Future<void> goal() async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => GoalScreen(api)),
    );
    if (mounted && ok == true) {
      await refresh();
      if (!mounted) return;
      setState(() {
        settingsSaved = true;
        goalExpanded = true;
      });
      openLearningPlan();
    }
  }

  Future<void> create() async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    final ok = await Navigator.push<PlanSaveResult>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PlannerScreen(api, draftRepository: widget.session.planDraft),
      ),
    );
    if (mounted && ok != null) {
      setState(() => settingsSaved = false);
      selectTab(1);
      await refresh();
      if (mounted) {
        toast(
          context,
          ok.draftCleared
              ? '학습계획을 저장했어요.'
              : '학습계획을 저장했어요. 기기의 초안을 정리하지 못해 다시 확인이 필요해요.',
        );
      }
    }
  }

  void ask(String message) {
    selectTab(3);
    chatKey.currentState?.prepareQuestion(message);
  }

  static const names = ['홈', '학습계획', '기록', '학습 상담', '내 정보'];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: tab == 0 ? const Brand() : Text(names[tab]),
      actions: [
        if (tab == 0)
          IconButton(
            tooltip: '학습계획 관리',
            onPressed: openLearningPlan,
            icon: const Icon(Icons.flag_outlined, size: 22),
          ),
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
          IconButton(
            tooltip: '목표와 기본 설정',
            onPressed: goal,
            icon: const Icon(Icons.tune_rounded, size: 22),
          ),
          IconButton(
            tooltip: '새 학습계획',
            onPressed: create,
            icon: const Icon(Icons.add_rounded, size: 25),
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
        child: IndexedStack(
          index: tab,
          children: [
            _home(),
            _plans(),
            StudyRecordsScreen(
              widget.session,
              key: recordsKey,
              active: tab == 2,
              onOpenTimer: () => selectTab(2),
            ),
            ChatScreen(api, key: chatKey, onPlanSaved: refresh),
            ProfileScreen(widget.session, openLearningPlan),
          ],
        ),
      ),
    ),
    bottomNavigationBar: DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: line)),
      ),
      child: NavigationBar(
        height: MediaQuery.textScalerOf(context).scale(12) > 16 ? 104 : 76,
        selectedIndex: tab,
        onDestinationSelected: (i) {
          if (i == 1 && i == tab) planKey.currentState?.showOverview();
          if (i == 2) recordsKey.currentState?.showTimer();
          selectTab(i);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '홈',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: '학습계획',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: '기록',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: '상담',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: '내 정보',
          ),
        ],
      ),
    ),
  );
  Widget _plans() => FutureBuilder<GoalData>(
    future: target,
    builder: (context, goalSnap) => FutureBuilder<SavedPlan?>(
      future: saved,
      builder: (context, snap) => _PlanPage(
        key: planKey,
        plan: snap.data,
        loading: snap.connectionState != ConnectionState.done,
        error: snap.error,
        overview: PlanGoalSection(
          goal: goalSnap,
          hasPlan: snap.data != null,
          settingsSaved: settingsSaved,
          expanded: goalExpanded,
          toggle: () => setState(() => goalExpanded = !goalExpanded),
          edit: goal,
          create: create,
          retry: refresh,
        ),
        refresh: refresh,
        onAsk: ask,
      ),
    ),
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
  Widget _home() => FutureBuilder<GoalData>(
    future: target,
    builder: (context, goalSnap) => FutureBuilder<SavedPlan?>(
      future: saved,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const LoadingPanel();
        }
        if (snap.hasError) return _error(snap.error!);
        final plan = snap.data;
        final homeDay = homeMonth && plan != null
            ? PlanMonthCalendar.dateInPlan(plan, selected)
            : selected;
        final tasks = plan?.on(homeDay) ?? [];
        return ScrollBody(
          key: const PageStorageKey('home-scroll'),
          refresh: refresh,
          children: [
            const SizedBox(height: 3),
            Text(
              '${shortDay(today)} ${weekdays[today.weekday - 1]}요일',
              style: const TextStyle(
                color: muted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '${widget.session.user!.name}님의 학습',
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 18),
            if (plan == null)
              EmptyPanel(
                Icons.auto_stories_outlined,
                '합격을 향한 첫 계획',
                '준비할 자격증과 공부할 시간을 알려주세요.\n오늘부터 할 일을 함께 정리해 드릴게요.',
                action: '학습계획 만들기',
                onTap: openLearningPlan,
              )
            else
              DailySummary(date: homeDay, today: today, tasks: tasks),
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
            if (plan != null)
              SectionRow(
                homeDay == today ? '오늘 할 학습' : '${shortDay(homeDay)} 학습',
                action: tasks.isNotEmpty ? '${tasks.length}개 항목' : null,
              ),
            if (plan != null)
              Entrance(
                key: ValueKey(isoDay(homeDay)),
                child: Column(
                  children: [
                    if (tasks.isEmpty)
                      const EmptyPanel(
                        Icons.event_note_outlined,
                        '계획된 학습 없음',
                        '공부할 날짜를 선택해 주세요.\n계획을 조정하고 싶다면 새 계획을 만들 수 있어요.',
                      ),
                    ...tasks.map(
                      (t) => TaskTile(
                        t,
                        onTap: () => showTaskDetails(context, t, onAsk: ask),
                      ),
                    ),
                  ],
                ),
              ),
            Builder(
              builder: (context) {
                if (goalSnap.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    height: 96,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                if (goalSnap.hasError) {
                  return Pane(
                    padding: 12,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.flag_outlined, color: blue),
                      title: const Text('목표 정보를 확인해 주세요'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: openLearningPlan,
                    ),
                  );
                }
                return GoalCard(goalSnap.data!, today, openLearningPlan);
              },
            ),
            if (plan != null) ...[
              Text(
                homeMonth ? '월간 학습' : '이번 주 학습',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              ViewSwitch(
                selected: homeMonth ? 1 : 0,
                options: [
                  ViewSwitchOption(
                    '주간',
                    const ValueKey('home-calendar-week'),
                    () => setState(() => homeMonth = false),
                  ),
                  ViewSwitchOption(
                    '월간',
                    const ValueKey('home-calendar-expand'),
                    () => setState(() => homeMonth = true),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (homeMonth)
                PlanMonthCalendar(
                  key: const ValueKey('home-month-calendar'),
                  plan: plan,
                  selected: homeDay,
                  today: today,
                  onSelect: (d) => setState(() => selected = d),
                )
              else
                WeekStrip(
                  selected: homeDay,
                  today: today,
                  plan: plan,
                  change: (d) => setState(() => selected = d),
                ),
            ],
            const SizedBox(height: 18),
            Pane(
              padding: 0,
              child: InkWell(
                onTap: () => selectTab(3),
                child: Padding(
                  padding: const EdgeInsets.all(17),
                  child: Row(
                    children: [
                      const ExamIcon('상담', size: 40),
                      const SizedBox(width: 13),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '공부 방법이 막막할 때',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 3),
                            HelpText('자격증 준비를 상담해 보세요.'),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 19,
                        color: muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class GoalCard extends StatelessWidget {
  final GoalData data;
  final DateTime today;
  final VoidCallback edit;
  const GoalCard(this.data, this.today, this.edit, {super.key});
  @override
  Widget build(BuildContext context) {
    final date = data.examDate, delta = date?.difference(today).inDays;
    final label = delta == null
        ? '목표 설정'
        : delta == 0
        ? 'D-DAY'
        : delta > 0
        ? 'D-$delta'
        : 'D+${-delta}';
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: edit,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.flag_outlined, size: 21, color: muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        date == null ? '어떤 시험을 준비하나요?' : data.examLabel,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (date != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          '${isoDay(date)} · ${delta! < 0 ? '목표일 지남' : '목표 시험일'}',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusTag(label),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: muted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DailySummary extends StatelessWidget {
  final DateTime date, today;
  final List<StudyTask> tasks;
  const DailySummary({
    super.key,
    required this.date,
    required this.today,
    required this.tasks,
  });
  @override
  Widget build(BuildContext context) {
    final total = tasks.fold(0, (n, t) => n + t.minutes),
        exams = tasks.map((t) => t.exam).toSet().length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: blue,
        borderRadius: BorderRadius.circular(18),
      ),
      child: LayoutBuilder(
        builder: (context, b) {
          final summary = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                date == today ? '오늘의 계획 시간' : '${shortDay(date)} 계획 시간',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                durationLabel(total),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.7,
                ),
              ),
            ],
          );
          final count = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${tasks.length}개 학습 항목',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$exams개 시험',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          );
          if (b.maxWidth < 270 ||
              MediaQuery.textScalerOf(context).scale(14) > 20) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [summary, const SizedBox(height: 12), count],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: summary),
              const SizedBox(width: 16),
              count,
            ],
          );
        },
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
    return Pane(
      padding: 10,
      child: Column(
        children: [
          if (MediaQuery.textScalerOf(context).scale(14) > 20)
            Column(
              children: [
                title,
                Row(
                  children: [
                    previous,
                    const Spacer(),
                    now,
                    const Spacer(),
                    next,
                  ],
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
          const SizedBox(height: 6),
          HorizontalChoices(
            key: ValueKey(isoDay(mon)),
            selectedIndex: selected.weekday - 1,
            children: List.generate(7, (i) {
              final d = plusDays(mon, i),
                  on = d == selected,
                  has = plan?.on(d).isNotEmpty ?? false,
                  isToday = d == today;
              return Semantics(
                button: true,
                selected: on,
                onTap: () => change(d),
                label: '${shortDay(d)} ${weekdays[i]}요일${has ? ', 계획 있음' : ''}',
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Material(
                      color: on ? blue : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
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
      ),
    );
  }
}

class TaskTile extends StatelessWidget {
  final StudyTask task;
  final VoidCallback? onTap;
  const TaskTile(this.task, {super.key, this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Pane(
      padding: 0,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, b) {
              final stacked =
                  b.maxWidth < 280 ||
                  MediaQuery.textScalerOf(context).scale(14) > 20;
              final time = Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: pale,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  durationLabel(task.minutes),
                  style: const TextStyle(
                    color: blue,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExamIcon(task.exam, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.exam,
                          style: const TextStyle(
                            color: muted,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          task.subject,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                        ),
                        if (stacked) ...[const SizedBox(height: 10), time],
                      ],
                    ),
                  ),
                  if (!stacked) ...[const SizedBox(width: 12), time],
                  if (onTap != null) ...[
                    const SizedBox(width: 5),
                    const Padding(
                      padding: EdgeInsets.only(top: 9),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 19,
                        color: muted,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

Future<void> showTaskDetails(
  BuildContext context,
  StudyTask t, {
  required ValueChanged<String> onAsk,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  backgroundColor: paper,
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

class _PlanPage extends StatefulWidget {
  final SavedPlan? plan;
  final Widget overview;
  final bool loading;
  final Object? error;
  final Future<void> Function() refresh;
  final ValueChanged<String> onAsk;
  const _PlanPage({
    super.key,
    required this.plan,
    required this.overview,
    required this.loading,
    required this.error,
    required this.refresh,
    required this.onAsk,
  });
  @override
  State<_PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<_PlanPage> {
  int view = 1;
  bool calendarList = false;
  DateTime selected = dayInSeoul();
  final scroll = ScrollController();
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
          widget.overview,
          const Heading('저장된 학습계획'),
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
            const EmptyPanel(
              Icons.calendar_month_outlined,
              '아직 저장한 계획이 없어요',
              '위에서 목표와 기본 설정을 확인하고\n계획을 미리 본 뒤 저장해 보세요.',
            ),
        ],
      );
    }
    final today = dayInSeoul();
    final keys = p.byDay.keys.toList()..sort();
    final calendarDay = PlanMonthCalendar.dateInPlan(p, selected);
    final exams = p.exams;
    final start = plusDays(selected, 1 - selected.weekday),
        last = plusDays(start, 6);
    final visible = view == 0
        ? keys.where((s) {
            final d = DateTime.parse(s);
            return !d.isBefore(start) && !d.isAfter(last);
          }).toList()
        : calendarList
        ? keys
        : p.on(calendarDay).isEmpty
        ? <String>[]
        : [isoDay(calendarDay)];
    final status = today.isBefore(p.start)
        ? '시작 예정'
        : today.isAfter(p.end)
        ? '학습 기간 종료'
        : '학습 기간 중';
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
                  widget.overview,
                  const Heading('저장된 학습계획'),
                  Pane(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            StatusTag(status),
                            Text(
                              '버전 ${p.version}',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          exams.isEmpty
                              ? '나의 학습계획'
                              : exams.length == 1
                              ? exams.single
                              : '${exams.first} 외 ${exams.length - 1}개 시험',
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        HelpText('${isoDay(p.start)} – ${isoDay(p.end)}'),
                        const SizedBox(height: 19),
                        LayoutBuilder(
                          builder: (context, b) {
                            final values = [
                              _Metric('준비하는 시험', '${exams.length}개'),
                              _Metric('계획한 학습일', '${keys.length}일'),
                              _Metric('총 계획 시간', durationLabel(p.totalMinutes)),
                            ];
                            if (b.maxWidth < 280 ||
                                MediaQuery.textScalerOf(context).scale(14) >
                                    20) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (int i = 0; i < values.length; i++) ...[
                                    if (i > 0) const SizedBox(height: 14),
                                    values[i],
                                  ],
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final value in values)
                                  Expanded(child: value),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 0, label: Text('이번 주')),
                      ButtonSegment(value: 1, label: Text('전체 일정')),
                    ],
                    selected: {view},
                    onSelectionChanged: (v) => setState(() => view = v.single),
                  ),
                  if (view == 0) ...[
                    const SizedBox(height: 13),
                    WeekStrip(
                      selected: selected,
                      today: today,
                      plan: p,
                      change: (d) => setState(() => selected = d),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            calendarList ? '날짜별 전체 목록' : '월간 일정',
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
                            label: Text(calendarList ? '달력' : '목록'),
                          ),
                        ),
                      ],
                    ),
                    if (!calendarList) ...[
                      const SizedBox(height: 8),
                      PlanMonthCalendar(
                        key: const ValueKey('plan-month-calendar'),
                        plan: p,
                        selected: calendarDay,
                        today: today,
                        onSelect: (date) => setState(() => selected = date),
                      ),
                    ],
                  ],
                  Heading(
                    view == 1 && !calendarList
                        ? '${shortDay(calendarDay)} 학습'
                        : '날짜별 학습',
                  ),
                  if (visible.isEmpty)
                    EmptyPanel(
                      view == 1 && !calendarList
                          ? Icons.calendar_today_outlined
                          : Icons.event_available_outlined,
                      view == 1 && !calendarList
                          ? '계획된 학습 없음'
                          : '이 주에는 배정된 학습이 없어요',
                      view == 1 && !calendarList
                          ? '이 날짜에 배정된 학습이 없어요.'
                          : '다른 주를 선택하거나 전체 일정을 확인해 주세요.',
                    ),
                ],
              );
            }
            final d = DateTime.parse(visible[i - 1]),
                tasks = p.byDay[visible[i - 1]]!,
                on = d == today;
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Pane(
                padding: 2,
                child: ExpansionTile(
                  key: PageStorageKey(
                    'day-${p.version}-${view == 1 && !calendarList ? 'calendar' : 'list'}-${visible[i - 1]}',
                  ),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  initiallyExpanded: view == 0 || !calendarList || on,
                  title: Text(
                    on ? '오늘 · ${shortDay(d)}' : shortDay(d),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: on ? blue : ink,
                    ),
                  ),
                  subtitle: Text(
                    '${tasks.length}개 항목 · ${durationLabel(tasks.fold(0, (n, t) => n + t.minutes))}',
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                  children: tasks
                      .map(
                        (t) => ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18,
                          ),
                          title: Text(
                            t.subject,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 5, bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.exam,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: muted,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '계획 ${durationLabel(t.minutes)}',
                                  style: const TextStyle(
                                    color: blue,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          onTap: () =>
                              showTaskDetails(context, t, onAsk: widget.onAsk),
                        ),
                      )
                      .toList(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label, value;
  const _Metric(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: muted, fontSize: 12)),
      const SizedBox(height: 6),
      Text(
        value,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: -.5,
        ),
      ),
    ],
  );
}
