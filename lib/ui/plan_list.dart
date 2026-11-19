import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/models.dart';
import 'design.dart';

/// 계획을 저장할 때 묻는다: 바로 사용(true) · 목록에만 추가(false) · 취소(null).
Future<bool?> askPlanSave(BuildContext context) => showDialog<bool>(
  context: context,
  builder: (c) => AlertDialog(
    title: const Text('이 계획을 저장할까요?'),
    content: const Text(
      '저장한 계획은 지우기 전까지 계획 목록에 남아요.\n\n'
      '바로 사용하면 홈·달력·타이머가 이 계획을 따르고, 지금 쓰던 계획은 목록에 보관됩니다.',
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(c), child: const Text('취소')),
      TextButton(
        onPressed: () => Navigator.pop(c, false),
        child: const Text('목록에만 추가'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(c, true),
        child: const Text('바로 사용'),
      ),
    ],
  ),
);

/// 저장한 학습계획 목록: 사용할 계획을 고르고, 일정을 보고, 지운다.
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

  Widget _tile(PlanSummary plan) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Pane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          plan.active
              ? const StatusTag('사용 중')
              : const StatusTag(
                  '보관',
                  color: muted,
                  background: Color(0xfff1f3f5),
                ),
          const SizedBox(height: 10),
          Text(
            plan.name,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          HelpText(
            '${isoDay(plan.start)} – ${isoDay(plan.end)}\n'
            '공부하는 날 ${plan.days}일 · 총 ${durationLabel(plan.totalMinutes)}',
          ),
          const SizedBox(height: 8),
          if (busy == plan.id)
            const LinearProgressIndicator(semanticsLabel: '처리하는 중')
          else
            Wrap(
              spacing: 8,
              children: [
                if (!plan.active)
                  FilledButton.tonal(
                    onPressed: busy != null ? null : () => use(plan),
                    child: const Text('이 계획 사용'),
                  ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _PlanScheduleScreen(widget.api, plan),
                    ),
                  ),
                  child: const Text('일정 보기'),
                ),
                TextButton(
                  onPressed: busy != null ? null : () => remove(plan),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: const Text('삭제'),
                ),
              ],
            ),
        ],
      ),
    ),
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
          return ScrollBody(
            refresh: reload,
            children: [
              const HelpText(
                '저장한 계획은 지우기 전까지 여기에 남아요. '
                '홈·달력·타이머는 사용 중인 계획 하나를 따릅니다.',
              ),
              const SizedBox(height: 14),
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
                if (!list.any((p) => p.active))
                  const AlertText(
                    '사용 중인 계획이 없어요. 아래에서 [이 계획 사용]을 눌러 하나를 골라 주세요.',
                  ),
                for (final plan in list) _tile(plan),
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
  const _PlanScheduleScreen(this.api, this.summary);
  @override
  State<_PlanScheduleScreen> createState() => _PlanScheduleScreenState();
}

class _PlanScheduleScreenState extends State<_PlanScheduleScreen> {
  late Future<SavedPlan> plan = widget.api.plan(widget.summary.id);

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
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: HelpText(
                              '${t.exam.isEmpty ? '' : '${t.exam} · '}${t.subject} · ${t.minutes}분',
                            ),
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
