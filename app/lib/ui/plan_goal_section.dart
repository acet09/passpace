import 'package:flutter/material.dart';

import '../data/models.dart';
import 'design.dart';

class PlanGoalSection extends StatelessWidget {
  final AsyncSnapshot<GoalData> goal;
  final bool hasPlan, settingsSaved, expanded;
  final VoidCallback edit, create, retry, toggle;
  const PlanGoalSection({
    super.key,
    required this.goal,
    required this.hasPlan,
    required this.settingsSaved,
    required this.expanded,
    required this.toggle,
    required this.edit,
    required this.create,
    required this.retry,
  });

  @override
  Widget build(BuildContext context) {
    final data = goal.data;
    final loading =
        goal.connectionState != ConnectionState.done && !goal.hasData;
    return Pane(
      child: AnimatedSize(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: expanded ? '목표와 기본 설정 접기' : '목표와 기본 설정 펼치기',
                    child: Semantics(
                      expanded: expanded,
                      child: TextButton(
                        onPressed: toggle,
                        style: TextButton.styleFrom(
                          foregroundColor: ink,
                          padding: EdgeInsets.zero,
                          alignment: Alignment.centerLeft,
                        ),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '목표와 기본 설정',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              expanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              size: 22,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (expanded && !loading && !goal.hasError)
                  TextButton(onPressed: edit, child: const Text('설정 수정')),
              ],
            ),
            if (expanded) ...[
              if (loading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(semanticsLabel: '기본 설정을 불러오는 중'),
                const SizedBox(height: 12),
              ] else if (goal.hasError) ...[
                const SizedBox(height: 8),
                const Text(
                  '기본 설정을 불러오지 못했어요',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const HelpText('다시 불러오거나 계획에서 직접 입력할 수 있어요.'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: retry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('기본 설정 다시 불러오기'),
                  ),
                ),
              ] else if (data != null) ...[
                const SizedBox(height: 8),
                Text(
                  data.examDate == null ? '목표 시험일을 정해 보세요' : data.examLabel,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    StatusTag(
                      data.examDate == null
                          ? '시험일 미설정'
                          : '목표 ${isoDay(data.examDate!)}',
                      color: muted,
                      background: paper,
                    ),
                    StatusTag(
                      data.minutes == null
                          ? '공부 시간 미설정'
                          : '하루 최대 ${durationLabel(data.minutes!)}',
                      color: muted,
                      background: paper,
                    ),
                    if (data.familiarity.isNotEmpty)
                      StatusTag(
                        '이해도 ${data.familiarity.length}과목',
                        color: muted,
                        background: paper,
                      ),
                  ],
                ),
              ],
              if (settingsSaved) ...[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '목표를 저장했어요',
                        style: TextStyle(
                          color: green,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      HelpText(
                        hasPlan
                            ? '새 미리보기를 확인하고 저장하면 변경한 설정을 일정에 반영할 수 있어요.'
                            : '저장한 시간과 이해도를 불러와 계획을 이어서 작성하세요.',
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                HelpText(
                  hasPlan
                      ? '설정을 바꾼 뒤에는 새 미리보기를 확인해 주세요.'
                      : '기본 설정은 계획 작성에 불러올 수 있고, 시험별 날짜는 작성 중 확인할 수 있어요.',
                ),
              ],
              const SizedBox(height: 16),
              PrimaryAction(
                settingsSaved
                    ? '이 설정으로 계획 만들기'
                    : hasPlan
                    ? '새 계획 미리보기'
                    : '학습계획 만들기',
                create,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
