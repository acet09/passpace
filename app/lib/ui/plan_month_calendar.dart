import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import 'design.dart';

class PlanMonthCalendar extends StatefulWidget {
  final SavedPlan plan;
  final DateTime selected, today;
  final ValueChanged<DateTime> onSelect;
  const PlanMonthCalendar({
    super.key,
    required this.plan,
    required this.selected,
    required this.today,
    required this.onSelect,
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
    final now = TextButton(
      onPressed:
          widget.today.isBefore(plan.start) || widget.today.isAfter(plan.end)
          ? null
          : () => widget.onSelect(widget.today),
      child: const Text('오늘'),
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
        LayoutBuilder(
          builder: (context, box) =>
              box.maxWidth < 360 ||
                  MediaQuery.textScalerOf(context).scale(14) > 20
              ? Column(
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
              : Row(
                  children: [
                    previous,
                    Expanded(child: title),
                    now,
                    next,
                  ],
                ),
        ),
        const SizedBox(height: 8),
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
            final cellHeight = math.max(
              70.0,
              scaler.scale(14) * 1.4 + scaler.scale(10) * 1.4 + 20,
            );
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
                            final tasks = plan.on(date);
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
                                  color: on
                                      ? blue
                                      : tasks.isNotEmpty && enabled
                                      ? pale
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    onTap: enabled ? select : null,
                                    borderRadius: BorderRadius.circular(12),
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
                                              color: on
                                                  ? Colors.white
                                                  : enabled
                                                  ? ink
                                                  : muted.withValues(
                                                      alpha: .55,
                                                    ),
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            !enabled
                                                ? '—'
                                                : tasks.isNotEmpty
                                                ? '배정'
                                                : isToday
                                                ? '오늘'
                                                : '—',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: on
                                                  ? Colors.white
                                                  : enabled
                                                  ? muted
                                                  : muted.withValues(
                                                      alpha: .55,
                                                    ),
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
