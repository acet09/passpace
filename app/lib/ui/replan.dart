import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/models.dart';
import 'design.dart';

/// 홈에 뜨는 재편성 추천: 계획이 많이 밀렸을 때 남은 일정을 다시 짜 보라고 알린다.
class ReplanCard extends StatelessWidget {
  final ReplanAdvice advice;
  final VoidCallback? onOpen, onLater;
  const ReplanCard(this.advice, {super.key, this.onOpen, this.onLater});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Semantics(
      container: true,
      label: '일정 재편성 추천',
      child: Pane(
        color: const Color(0xfffff6e8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.update_rounded, size: 19, color: amber),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '계획이 밀렸어요. 일정을 다시 짤까요?',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '어제까지 계획한 ${durationLabel(advice.dueMinutes)} 중 '
              '${durationLabel(advice.doneMinutes)}을 기록했어요. '
              '밀린 ${durationLabel(advice.behindMinutes)}은 전체 계획의 ${advice.percent}%예요.',
              style: const TextStyle(fontSize: 13, height: 1.55),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: onOpen,
                  child: const Text('다시 짠 일정 보기'),
                ),
                TextButton(onPressed: onLater, child: const Text('나중에')),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// 다시 짠 일정을 확인하고 받아들인다. 받아들이면 true 로 닫힌다.
class ReplanScreen extends StatefulWidget {
  final PassApi api;
  final ReplanAdvice advice;
  const ReplanScreen(this.api, this.advice, {super.key});
  @override
  State<ReplanScreen> createState() => _ReplanScreenState();
}

class _ReplanScreenState extends State<ReplanScreen> {
  bool busy = false;
  String? error;

  Future<void> accept() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.acceptReplan();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.advice, plan = a.proposal;
    final days = [...plan.days]
      ..sort((x, y) => (x['date'] as String).compareTo(y['date'] as String));
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('일정 재편성')),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: WidthLimit(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    itemCount: days.length + 1,
                    itemBuilder: (context, i) {
                      if (i == 0) return _summary(a, plan, days);
                      final day = days[i - 1];
                      final date = DateTime.parse(day['date'] as String);
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
                              for (final t in rows(day['allocations']))
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: HelpText(
                                    '${t['certificationName'] ?? ''} · ${t['subjectName']} · ${t['minutes']}분',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              StickyActions('이 일정으로 바꾸기', accept, busy: busy, error: error),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summary(ReplanAdvice a, Preview plan, List<Json> days) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        '남은 공부를 오늘부터 다시 나눴어요',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -.8,
          height: 1.35,
        ),
      ),
      const SizedBox(height: 8),
      HelpText(
        '${a.planName}\n'
        '어제까지 계획 ${durationLabel(a.dueMinutes)} 중 ${durationLabel(a.doneMinutes)} 기록 · '
        '밀린 시간 ${durationLabel(a.behindMinutes)} (전체의 ${a.percent}%)',
      ),
      const SizedBox(height: 14),
      Pane(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const HelpText('다시 배정할 공부량'),
            const SizedBox(height: 6),
            Text(
              durationLabel(plan.requiredMinutes),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 8),
            HelpText(
              days.isEmpty
                  ? '배정된 날짜가 없어요.'
                  : '${shortDay(DateTime.parse(days.first['date'] as String))} – '
                        '${shortDay(DateTime.parse(days.last['date'] as String))} · 공부하는 날 ${days.length}일',
            ),
          ],
        ),
      ),
      if (plan.missingMinutes > 0)
        AlertText(
          '원래 끝내려던 날까지 ${durationLabel(plan.missingMinutes)}은 넣지 못했어요. '
          '받아들인 뒤 하루 시간을 늘려 새 계획을 만들거나, 끝낼 날짜를 늦춰 주세요.',
        ),
      const SizedBox(height: 8),
      const HelpText(
        '받아들이면 이 일정이 사용 중인 계획이 되고, 지금 쓰던 계획은 계획 목록에 보관됩니다. '
        '공부하던 요일과 하루 시간은 그대로 두고, 할 일에 연결해 기록한 시간만큼은 뺐어요.',
      ),
      const Heading('다시 짠 일정'),
    ],
  );
}
