import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import 'design.dart';

Future<DateTimeRange?> pickStudyRange(
  BuildContext context, {
  required DateTimeRange initial,
  required DateTime today,
}) => showModalBottomSheet<DateTimeRange>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: Colors.white,
  constraints: const BoxConstraints(maxWidth: 520),
  builder: (context) =>
      _StudyRangePicker(initial: initial, today: DateUtils.dateOnly(today)),
);

class _StudyRangePicker extends StatefulWidget {
  final DateTimeRange initial;
  final DateTime today;
  const _StudyRangePicker({required this.initial, required this.today});

  @override
  State<_StudyRangePicker> createState() => _StudyRangePickerState();
}

class _StudyRangePickerState extends State<_StudyRangePicker> {
  static const maxDays = 366;
  static const yearColumns = 3;
  final first = DateTime(1000);
  late DateTime start = _bounded(widget.initial.start);
  late DateTime? end = _bounded(widget.initial.end);
  late DateTime month = DateTime(end!.year, end!.month);
  ScrollController? years;
  bool choosingYear = false;
  bool tooLong = false;

  @override
  void dispose() {
    years?.dispose();
    super.dispose();
  }

  double get yearHeight =>
      math.max(48, MediaQuery.textScalerOf(context).scale(14) * 1.4 + 12);

  void toggleYear() {
    if (!choosingYear) {
      final row = (widget.today.year - month.year) ~/ yearColumns;
      years?.dispose();
      years = ScrollController(
        initialScrollOffset: math.max(0, row - 1) * yearHeight,
      );
    }
    setState(() => choosingYear = !choosingYear);
  }

  DateTime _bounded(DateTime date) {
    final day = DateUtils.dateOnly(date);
    if (day.isBefore(first)) return first;
    if (day.isAfter(widget.today)) return widget.today;
    return day;
  }

  int _daysThrough(DateTime day) =>
      DateTime.utc(
        day.year,
        day.month,
        day.day,
      ).difference(DateTime.utc(start.year, start.month, start.day)).inDays +
      1;

  void select(DateTime day) => setState(() {
    tooLong = false;
    if (end != null || day.isBefore(start)) {
      start = day;
      end = null;
    } else if (_daysThrough(day) > maxDays) {
      tooLong = true;
    } else {
      end = day;
    }
  });

  Widget calendar() {
    final length = DateUtils.getDaysInMonth(month.year, month.month);
    final leading = month.weekday - DateTime.monday;
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '이전 달',
              onPressed: choosingYear || !month.isAfter(first)
                  ? null
                  : () => setState(
                      () => month = DateTime(month.year, month.month - 1),
                    ),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Tooltip(
                message: choosingYear ? '월간 달력 보기' : '연도 선택',
                child: TextButton.icon(
                  onPressed: toggleYear,
                  iconAlignment: IconAlignment.end,
                  icon: Icon(
                    choosingYear ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                  ),
                  label: Text(
                    '${month.year}년 ${month.month}월',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '다음 달',
              onPressed:
                  choosingYear ||
                      DateTime(
                        month.year,
                        month.month + 1,
                      ).isAfter(widget.today)
                  ? null
                  : () => setState(
                      () => month = DateTime(month.year, month.month + 1),
                    ),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        if (choosingYear)
          SizedBox(
            height: 252,
            child: GridView.builder(
              key: const ValueKey('study-range-year-picker'),
              controller: years,
              itemCount: widget.today.year - first.year + 1,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: yearColumns,
                mainAxisExtent: yearHeight,
              ),
              itemBuilder: (context, index) {
                final year = widget.today.year - index;
                return Semantics(
                  selected: year == month.year,
                  child: TextButton(
                    onPressed: () => setState(() {
                      final day = _bounded(DateTime(year, month.month));
                      month = DateTime(day.year, day.month);
                      choosingYear = false;
                    }),
                    child: Text(
                      MaterialLocalizations.of(context)
                          .formatYear(DateTime(year)),
                    ),
                  ),
                );
              },
            ),
          )
        else ...[
          Row(
            children: [
              for (final weekday in weekdays)
                Expanded(
                  child: Text(
                    weekday,
                    style: const TextStyle(color: muted, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
          GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 6),
            shrinkWrap: true,
            itemCount: leading + length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: math.max(
                48,
                MediaQuery.textScalerOf(context).scale(14) * 1.45 + 9,
              ),
            ),
            itemBuilder: (context, i) {
              final number = i - leading + 1;
              return number < 1
                  ? const SizedBox.shrink()
                  : _dayCell(DateTime(month.year, month.month, number));
            },
          ),
        ],
      ],
    );
  }

  Widget _dayCell(DateTime day) {
    final enabled = !day.isAfter(widget.today);
    final endpoint = day == start || day == end;
    final inside = end != null && day.isAfter(start) && day.isBefore(end!);
    final today = day == widget.today;
    final label = [
      isoDay(day),
      if (today) '오늘',
      if (day == start) '시작일',
      if (day == end) '종료일',
    ].join(', ');
    return Semantics(
      key: ValueKey('study-range-day-${isoDay(day)}'),
      label: label,
      button: true,
      enabled: enabled,
      selected: endpoint || inside,
      onTap: enabled ? () => select(day) : null,
      child: ExcludeSemantics(
        child: Material(
          color: endpoint
              ? blue
              : inside
              ? pale
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(endpoint ? 12 : 0),
            side: today && !endpoint
                ? const BorderSide(color: blue)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: enabled ? () => select(day) : null,
            child: Center(
              child: Text(
                '${day.day}',
                style: TextStyle(
                  color: endpoint
                      ? Colors.white
                      : enabled
                      ? ink
                      : muted.withValues(alpha: .5),
                  fontWeight: endpoint ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = end;
    final count = last == null ? 0 : _daysThrough(last);
    String dateLabel(DateTime day) => isoDay(day).replaceAll('-', '.');
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .86,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '조회 기간 선택',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const HelpText('시작일과 종료일을 차례로 선택하세요. 최대 366일'),
                      ],
                    ),
                  ),
                  calendar(),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${dateLabel(start)} ~',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (last != null) ...[
                        Text(
                          dateLabel(last),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        HelpText('$count일'),
                      ] else if (tooLong)
                        Text(
                          '최대 366일 이내의 종료일을 골라 주세요.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        )
                      else
                        const HelpText('종료일 선택'),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('취소'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: last == null || count > maxDays
                          ? null
                          : () => Navigator.pop(
                              context,
                              DateTimeRange(start: start, end: last),
                            ),
                      child: const Text('조회'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
