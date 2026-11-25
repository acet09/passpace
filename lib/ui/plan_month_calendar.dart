import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import 'design.dart';

class PlanMonthCalendar extends StatefulWidget {
  final SavedPlan plan;
  final DateTime selected, today;
  final ValueChanged<DateTime> onSelect;
  final Color? Function(StudyTask)? subjectColor;
  final bool showMonthSummary;
  const PlanMonthCalendar({
    super.key,
    required this.plan,
    required this.selected,
    required this.today,
    required this.onSelect,
    this.subjectColor,
    this.showMonthSummary = true,
  });

  static DateTime dateInPlan(SavedPlan plan, DateTime date) =>
      date.isBefore(plan.start)
      ? plan.start
      : date.isAfter(plan.end)
      ? plan.end
      : date;

  @override
  State<PlanMonthCalendar> createState() => _PlanMonthCalendarState();
}

class _PlanMonthCalendarState extends State<PlanMonthCalendar> {
  final horizontal = ScrollController();
  bool reveal = true;
  double previousWidth = -1;
  double previousCellWidth = -1;
  @override
  void didUpdateWidget(PlanMonthCalendar old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected || old.plan != widget.plan) {
      reveal = true;
    }
  }

  @override
  void dispose() {
    horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final selected = PlanMonthCalendar.dateInPlan(plan, widget.selected);
    final subjectColor = widget.subjectColor;
    final first = DateTime(selected.year, selected.month);
    final days = DateTime(first.year, first.month + 1, 0).day;
    final leading = first.weekday - 1;
    final cells = ((leading + days + 6) ~/ 7) * 7;
    final monthTasks = plan.byDay.entries
        .where(
          (e) => e.key.startsWith(
            '${first.year}-${first.month.toString().padLeft(2, '0')}-',
          ),
        )
        .toList();
    final minutes = monthTasks
        .expand((e) => e.value)
        .fold(0, (n, t) => n + t.minutes);
    void move(int delta) {
      final month = DateTime(first.year, first.month + delta);
      final last = DateTime(month.year, month.month + 1, 0).day;
      widget.onSelect(
        PlanMonthCalendar.dateInPlan(
          plan,
          DateTime(month.year, month.month, math.min(selected.day, last)),
        ),
      );
    }

    final previous = IconButton(
      tooltip: '이전 달',
      onPressed: DateTime(first.year, first.month, 0).isBefore(plan.start)
          ? null
          : () => move(-1),
      icon: const Icon(Icons.chevron_left_rounded),
    );
    final next = IconButton(
      tooltip: '다음 달',
      onPressed: DateTime(first.year, first.month + 1).isAfter(plan.end)
          ? null
          : () => move(1),
      icon: const Icon(Icons.chevron_right_rounded),
    );
    final title = Tooltip(
      message: '다른 날짜로 이동',
      child: TextButton(
        onPressed: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: selected,
            firstDate: plan.start,
            lastDate: plan.end,
            helpText: '학습 날짜로 이동',
          );
          if (mounted && picked != null) widget.onSelect(picked);
        },
        child: Text(
          '${first.year}년 ${first.month}월',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            previous,
            Expanded(child: title),
            next,
          ],
        ),
        const SizedBox(height: 8),
        if (widget.showMonthSummary)
          Text(
            '${monthTasks.length}일 배정 · 계획 ${durationLabel(minutes)}',
            style: const TextStyle(color: muted, fontSize: 13, height: 1.5),
          ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, box) {
            final scaler = MediaQuery.textScalerOf(context);
            final width = math
                .max(box.maxWidth, 7 * math.max(48.0, scaler.scale(14) * 2 + 8))
                .toDouble();
            final cellWidth = width / 7;
            final cellHeight = math.max(52.0, scaler.scale(14) * 1.4 + 17);
            if (previousWidth != box.maxWidth ||
                previousCellWidth != cellWidth) {
              previousWidth = box.maxWidth;
              previousCellWidth = cellWidth;
              reveal = true;
            }
            if (reveal) {
              reveal = false;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || !horizontal.hasClients) return;
                final left = (selected.weekday - 1) * cellWidth,
                    right = left + cellWidth;
                final position = horizontal.position;
                final offset = left < position.pixels
                    ? left
                    : right > position.pixels + box.maxWidth
                    ? right - box.maxWidth
                    : position.pixels;
                horizontal.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
              });
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  key: const ValueKey('calendar-horizontal-scroll'),
                  controller: horizontal,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            for (final name in weekdays)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  child: Text(
                                    name,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        GridView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          primary: false,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7,
                                mainAxisExtent: cellHeight,
                              ),
                          itemCount: cells,
                          itemBuilder: (context, index) {
                            final number = index - leading + 1;
                            if (number < 1 || number > days) {
                              return const SizedBox.shrink();
                            }
                            final date = DateTime(
                              first.year,
                              first.month,
                              number,
                            );
                            final enabled =
                                !date.isBefore(plan.start) &&
                                !date.isAfter(plan.end);
                            final on = date == selected,
                                isToday = date == widget.today;
                            final filled =
                                on && subjectColor == null && !isToday;
                            final radius = BorderRadius.circular(12);
                            final tasks = plan.on(date);
                            final colors = {
                              if (enabled && subjectColor != null)
                                for (final task in tasks)
                                  (task.exam, task.subject):
                                      subjectColor(task) ?? blue,
                            };
                            final total = tasks.fold(
                              0,
                              (n, t) => n + t.minutes,
                            );
                            void select() => widget.onSelect(date);
                            return Semantics(
                              key: ValueKey('calendar-day-${isoDay(date)}'),
                              button: true,
                              enabled: enabled,
                              selected: on,
                              onTap: enabled ? select : null,
                              label:
                                  '${isoDay(date)}, ${weekdays[date.weekday - 1]}요일${isToday ? ', 오늘' : ''}, ${tasks.isEmpty ? '계획된 학습 없음' : '계획 ${durationLabel(total)}'}${enabled ? '' : ', 계획 기간 밖'}',
                              child: ExcludeSemantics(
                                child: Material(
                                  color: filled
                                      ? blue
                                      : on
                                      ? pale
                                      : Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: radius,
                                    side: isToday
                                        ? const BorderSide(color: blue)
                                        : BorderSide.none,
                                  ),
                                  child: InkWell(
                                    onTap: enabled ? select : null,
                                    borderRadius: radius,
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '$number',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: on || isToday
                                                  ? FontWeight.w800
                                                  : FontWeight.w600,
                                              color: filled
                                                  ? Colors.white
                                                  : on
                                                  ? blue
                                                  : enabled
                                                  ? (isToday ? blue : ink)
                                                  : muted.withValues(
                                                      alpha: .55,
                                                    ),
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          if (subjectColor == null)
                                            DecoratedBox(
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: tasks.isEmpty || !enabled
                                                    ? Colors.transparent
                                                    : (filled
                                                          ? Colors.white
                                                          : blue),
                                              ),
                                              child: const SizedBox.square(
                                                dimension: 4,
                                              ),
                                            )
                                          else
                                            SizedBox(
                                              height: 6,
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                spacing: 3,
                                                children: [
                                                  for (final color
                                                      in colors.values.take(3))
                                                    DecoratedBox(
                                                      decoration: BoxDecoration(
                                                        color: color,
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child:
                                                          const SizedBox.square(
                                                            dimension: 6,
                                                          ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                if (width > box.maxWidth)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      '달력을 좌우로 밀어 모든 요일을 확인하세요.',
                      style: TextStyle(color: muted, fontSize: 12, height: 1.5),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
