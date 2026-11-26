import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/plan_comparison.dart';
import 'design.dart';

class PlanComparisonSummary extends StatelessWidget {
  final PlanComparison comparison;
  const PlanComparisonSummary(this.comparison, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = comparison;
    return Pane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            c.previous == null ? '첫 학습계획' : '현재 계획과 변경 비교',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          const SizedBox(height: 9),
          if (c.previous == null)
            HelpText('저장하면 총 ${durationLabel(c.afterMinutes)}의 일정이 시작돼요.')
          else ...[
            LayoutBuilder(
              builder: (context, b) {
                final values = [
                  _Total('현재 배정 시간', c.beforeMinutes),
                  _Total('새 배정 시간', c.afterMinutes, emphasized: true),
                ];
                if (b.maxWidth < 250 ||
                    MediaQuery.textScalerOf(context).scale(14) > 20) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      values[0],
                      const SizedBox(height: 12),
                      values[1],
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: values[0]),
                    const SizedBox(width: 10),
                    Expanded(child: values[1]),
                  ],
                );
              },
            ),
            const SizedBox(height: 9),
            const HelpText('각 계획의 전체 배정 기간 기준'),
            const SizedBox(height: 13),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                StatusTag('추가 ${c.added}'),
                StatusTag(
                  '제외 ${c.removed}',
                  color: amber,
                  background: const Color(0xfffff1df),
                ),
                StatusTag('시간 변경 ${c.adjusted}'),
              ],
            ),
            const SizedBox(height: 10),
            if (c.changes.isEmpty)
              const HelpText('날짜·시험·과목별 배정 시간이 같아요.')
            else
              OutlinedButton.icon(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(builder: (_) => _ComparisonDetails(c)),
                ),
                icon: const Icon(Icons.compare_arrows_rounded, size: 20),
                label: Text('변경 상세 ${c.changes.length}건 보기'),
              ),
          ],
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  final String label;
  final int value;
  final bool emphasized;
  const _Total(this.label, this.value, {this.emphasized = false});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: emphasized ? pale : paper,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: emphasized ? const Color(0xffb7c8f4) : line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: emphasized ? blue : muted, fontSize: 13),
        ),
        const SizedBox(height: 7),
        Text(
          durationLabel(value),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 21,
            color: emphasized ? blue : ink,
          ),
        ),
      ],
    ),
  );
}

class _ComparisonDetails extends StatelessWidget {
  final PlanComparison comparison;
  const _ComparisonDetails(this.comparison);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('계획 변경 상세')),
    body: SafeArea(
      child: WidthLimit(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          itemCount: comparison.changes.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PlanComparisonSummaryHeader(comparison),
                    const SizedBox(height: 10),
                    const HelpText('배정 내용이 달라지는 항목을 날짜순으로 표시해요.'),
                  ],
                ),
              );
            }
            final change = comparison.changes[i - 1];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Pane(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            change.key.date,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        StatusTag(
                          change.label,
                          color: change.after == 0 ? amber : blue,
                          background: change.after == 0
                              ? const Color(0xfffff1df)
                              : pale,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    HelpText(change.key.exam),
                    Text(
                      change.key.subject,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      children: [
                        Text(
                          '현재 ${durationLabel(change.before)}',
                          style: const TextStyle(fontSize: 14, color: muted),
                        ),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 17,
                          color: muted,
                        ),
                        Text(
                          '새 계획 ${durationLabel(change.after)}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: blue,
                            fontWeight: FontWeight.w700,
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
      ),
    ),
  );
}

class PlanComparisonSummaryHeader extends StatelessWidget {
  final PlanComparison comparison;
  const PlanComparisonSummaryHeader(this.comparison, {super.key});
  @override
  Widget build(BuildContext context) => Text(
    '추가 ${comparison.added} · 제외 ${comparison.removed} · 시간 변경 ${comparison.adjusted}',
    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
  );
}
