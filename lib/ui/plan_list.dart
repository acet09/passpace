import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/models.dart';
import 'design.dart';
import 'schedule_editor.dart';

/// 계획을 저장할 때 묻는다: 바로 사용(true) · 목록에만 추가(false) · 취소(null).
Future<bool?> askPlanSave(BuildContext context, PassApi api) =>
    showDialog<bool>(
      context: context,
      builder: (c) {
        Widget dialog() {
          final blocked = api.timerBlocksPlanChanges;
          return AlertDialog(
            scrollable: true,
            title: const Text('이 계획을 저장할까요?'),
            content: Text(
              blocked
                  ? '타이머 기록이 정리되기 전에는 바로 사용할 수 없어요. '
                        '새 계획은 지금 목록에 추가할 수 있어요.\n\n'
                        '$planTimerBlockedMessage'
                  : '저장한 계획은 지우기 전까지 계획 목록에 남아요.\n\n'
                        '바로 사용하면 홈·달력·타이머가 이 계획을 따르고, '
                        '지금 쓰던 계획은 목록에 보관됩니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('목록에만 추가'),
              ),
              FilledButton(
                onPressed: blocked ? null : () => Navigator.pop(c, true),
                child: const Text('바로 사용'),
              ),
            ],
          );
        }

        final timer = api.planTimer;
        return timer == null
            ? dialog()
            : ListenableBuilder(listenable: timer, builder: (_, _) => dialog());
      },
    );

enum _PlanAction { activate, delete }

/// 저장한 계획을 열고, 사용할 계획을 바꾸거나 삭제한다.
class PlanListScreen extends StatefulWidget {
  final PassApi api;

  /// 사용 중인 계획이 바뀌거나 계획을 지웠을 때 (홈·학습계획 새로고침용).
  final VoidCallback? onChanged;
  const PlanListScreen(this.api, {super.key, this.onChanged});
  @override
  State<PlanListScreen> createState() => _PlanListScreenState();
}

class _PlanListScreenState extends State<PlanListScreen> {
  late Future<List<PlanSummary>> plans = widget.api.plans();
  int? busy;
  String? error;

  Future<void> reload() async {
    setState(() {
      plans = widget.api.plans();
    });
    try {
      await plans;
    } catch (_) {
      // 목록 영역이 오류와 다시 시도 버튼을 보여 준다.
    }
  }

  Future<void> _run(PlanSummary plan, Future<void> Function() work) async {
    if (busy != null) return;
    setState(() {
      busy = plan.id;
      error = null;
    });
    try {
      await work();
      widget.onChanged?.call();
      if (mounted) await reload();
    } catch (e) {
      if (mounted) setState(() => error = friendly(e));
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  Future<void> use(PlanSummary plan) => _run(plan, () async {
    await widget.api.usePlan(plan.id);
    if (mounted) toast(context, '이 계획을 사용해요. 쓰던 계획은 목록에 보관했어요.');
  });

  Future<void> remove(PlanSummary plan) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('이 계획을 삭제할까요?'),
        content: Text(
          '${plan.name}\n\n날짜별 할 일까지 함께 지워지고 되돌릴 수 없어요.'
          '${plan.active ? '\n지금 사용 중인 계획이라, 지우면 사용 중인 계획이 없어집니다.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(c).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await _run(plan, () async {
      await widget.api.deletePlan(plan.id);
      if (mounted) toast(context, '계획을 삭제했어요.');
    });
  }

  void openSchedule(PlanSummary plan) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PlanScheduleScreen(
          widget.api,
          plan,
          onChanged: () {
            if (!mounted) return;
            widget.onChanged?.call();
            reload();
          },
        ),
      ),
    );
  }

  Widget _tile(PlanSummary plan) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        hint: '계획 일정 보기',
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          onTap: busy == plan.id ? null : () => openSchedule(plan),
          title: Text(
            plan.name,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: plan.active ? 17 : 15,
              height: 1.35,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: HelpText(
              '${isoDay(plan.start)} ~ ${isoDay(plan.end)}\n'
              '${plan.days}일 배정 · ${durationLabel(plan.totalMinutes)}',
            ),
          ),
          trailing: PopupMenuButton<_PlanAction>(
            tooltip: '${plan.name} 더보기',
            enabled: busy == null,
            icon: const Icon(Icons.more_horiz_rounded),
            onSelected: (action) => switch (action) {
              _PlanAction.activate => use(plan),
              _PlanAction.delete => remove(plan),
            },
            itemBuilder: (context) => [
              if (!plan.active)
                const PopupMenuItem(
                  value: _PlanAction.activate,
                  child: Text('이 계획 사용'),
                ),
              PopupMenuItem(
                value: _PlanAction.delete,
                child: Text(
                  '삭제',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ),
        ),
      ),
      if (busy == plan.id)
        const LinearProgressIndicator(semanticsLabel: '처리하는 중'),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('저장한 계획')),
    body: SafeArea(
      child: FutureBuilder<List<PlanSummary>>(
        future: plans,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data ?? const <PlanSummary>[];
          final active = list.where((plan) => plan.active);
          final archived = list.where((plan) => !plan.active).toList();
          return ScrollBody(
            refresh: reload,
            children: [
              if (error != null) AlertText(error!),
              if (snap.hasError)
                EmptyPanel(
                  Icons.cloud_off_outlined,
                  '계획 목록을 불러오지 못했어요',
                  friendly(snap.error!),
                  action: '다시 시도',
                  onTap: reload,
                )
              else if (list.isEmpty)
                const EmptyPanel(
                  Icons.calendar_month_outlined,
                  '아직 저장한 계획이 없어요',
                  '학습계획 만들기나 학습 상담에서 계획을 만들어 저장해 보세요.',
                )
              else ...[
                if (active.isNotEmpty) ...[
                  const Heading('사용 중인 계획'),
                  for (final plan in active)
                    Material(
                      key: ValueKey('active-plan-card-${plan.id}'),
                      color: pale,
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: _tile(plan),
                    ),
                ] else
                  const HelpText('사용 중인 계획이 없어요. 더보기에서 사용할 계획을 고를 수 있어요.'),
                if (archived.isNotEmpty) ...[
                  const Heading('보관한 계획'),
                  for (final (index, plan) in archived.indexed) ...[
                    if (index > 0) const Divider(height: 1),
                    _tile(plan),
                  ],
                ],
              ],
            ],
          );
        },
      ),
    ),
  );
}

/// 목록의 계획 한 건: 날짜별 할 일.
class _PlanScheduleScreen extends StatefulWidget {
  final PassApi api;
  final PlanSummary summary;
  final VoidCallback onChanged;
  const _PlanScheduleScreen(this.api, this.summary, {required this.onChanged});
  @override
  State<_PlanScheduleScreen> createState() => _PlanScheduleScreenState();
}

class _PlanScheduleScreenState extends State<_PlanScheduleScreen> {
  late Future<SavedPlan> plan = widget.api.plan(widget.summary.id);

  Future<void> edit(SavedPlan plan, {StudyTask? task}) async {
    final result = await showScheduleEditor(
      context,
      widget.api,
      plan,
      task: task,
    );
    if (result == null || !mounted) return;
    final refreshed = widget.api.plan(widget.summary.id);
    setState(() {
      this.plan = refreshed;
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('계획 일정')),
    body: SafeArea(
      child: FutureBuilder<SavedPlan>(
        future: plan,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return ScrollBody(
              children: [
                EmptyPanel(
                  Icons.cloud_off_outlined,
                  '일정을 불러오지 못했어요',
                  friendly(snap.error!),
                  action: '다시 시도',
                  onTap: () => setState(() {
                    plan = widget.api.plan(widget.summary.id);
                  }),
                ),
              ],
            );
          }
          final p = snap.data!;
          final keys = p.byDay.keys.toList()..sort();
          return WidthLimit(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              itemCount: keys.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        HelpText(
                          '${isoDay(p.start)} – ${isoDay(p.end)} · '
                          '공부하는 날 ${keys.length}일 · 총 ${durationLabel(p.totalMinutes)}',
                        ),
                        if (p.canEditSchedule)
                          TextButton.icon(
                            onPressed: () => edit(p),
                            icon: const Icon(
                              Icons.date_range_outlined,
                              size: 18,
                            ),
                            label: const Text('계획 기간 수정'),
                          )
                        else if (p.byDay.isNotEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: HelpText(scheduleServerMessage),
                          ),
                      ],
                    ),
                  );
                }
                final date = DateTime.parse(keys[i - 1]);
                final tasks = p.on(date);
                return Padding(
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
                                '${shortDay(date)} (${weekdays[date.weekday - 1]})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Text(
                              durationLabel(
                                tasks.fold(0, (n, t) => n + t.minutes),
                              ),
                              style: const TextStyle(
                                color: blue,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        for (final t in tasks)
                          Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: HelpText(
                                    '${t.exam.isEmpty ? '' : '${t.exam} · '}${t.subject} · ${t.minutes}분',
                                  ),
                                ),
                              ),
                              if (canEditTask(p, t))
                                Tooltip(
                                  message: '${t.subject} 날짜·배정시간 수정',
                                  child: TextButton(
                                    onPressed: () => edit(p, task: t),
                                    child: const Text('수정'),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    ),
  );
}
