import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/study_models.dart';
import 'design.dart';
import 'subject_color_picker.dart';

typedef StudySubjectSlice = ({String name, int minutes, Color? color});
typedef _LegendEntry = ({String name, Color color});

_LegendEntry _legendEntry(StudySubjectSlice subject) =>
    (name: subject.name, color: subject.color ?? muted);

const _plotInset = 5.0;
const _plotHeight = 150.0;
double _plotWidth(double width) => math.max(1.0, width - _plotInset * 2);

class StudyChart extends StatefulWidget {
  final StudyStats stats;
  final Widget? breakdown;
  final Map<DateTime, List<StudySubjectSlice>>? subjectsByDay;
  const StudyChart(this.stats, {super.key, this.breakdown, this.subjectsByDay});
  @override
  State<StudyChart> createState() => _StudyChartState();
}

class _StudyChartState extends State<StudyChart> {
  bool bars = true;
  _LegendEntry? _subjectFilter;
  late int selected = widget.stats.days.length - 1;
  late int dailyEnd = widget.stats.days.length;
  @override
  void didUpdateWidget(StudyChart old) {
    super.didUpdateWidget(old);
    if (!identical(old.stats, widget.stats)) {
      _subjectFilter = null;
      selected = widget.stats.days.length - 1;
      dailyEnd = widget.stats.days.length;
    }
  }

  List<StudySubjectSlice>? _verifiedSubjects(StudyDay day) {
    final subjects = widget.subjectsByDay?[day.date];
    if (subjects == null) return null;
    final minutes = subjects.fold(0, (sum, subject) => sum + subject.minutes);
    return minutes == day.minutes ? subjects : null;
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    final days = stats.days;
    final day = days[selected];
    final segments = days.map(_verifiedSubjects).toList(growable: false);
    final legend = {
      if (bars)
        for (final subjects in segments.nonNulls)
          for (final subject in subjects) _legendEntry(subject),
    };
    final filter = legend.contains(_subjectFilter) ? _subjectFilter : null;
    final chartSegments = filter == null
        ? segments
        : [
            for (final subjects in segments)
              subjects
                  ?.where((subject) => _legendEntry(subject) == filter)
                  .toList(),
          ];
    final chartMinutes = <int?>[
      for (final (index, date) in days.indexed)
        if (filter == null || date.minutes == 0)
          date.minutes
        else
          chartSegments[index]?.fold<int>(
            0,
            (sum, subject) => sum + subject.minutes,
          ),
    ];
    final selectedSubjects = chartSegments[selected];
    final selectedMinutes = chartMinutes[selected];
    final peak = days.fold(0, (n, d) => math.max(n, d.minutes));
    final ceiling = math.max(60, (peak / 60).ceil() * 60);
    final range =
        stats.start.year == stats.end.year &&
            stats.start.month == stats.end.month
        ? '${stats.start.year}년 ${stats.start.month}월'
        : '${stats.start.year}년 ${stats.start.month}월 ~ ${stats.end.year}년 ${stats.end.month}월';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Pane(
          color: pale,
          padding: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '총 공부 시간',
                style: TextStyle(color: muted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                durationLabel(stats.totalMinutes),
                key: const ValueKey('study-total'),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: ink,
                  letterSpacing: -.7,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Pane(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  const Text(
                    '공부시간 추이',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('꺾은선'),
                        selected: !bars,
                        onSelected: (_) => setState(() {
                          bars = false;
                          _subjectFilter = null;
                        }),
                      ),
                      ChoiceChip(
                        label: const Text('막대'),
                        selected: bars,
                        onSelected: (_) => setState(() => bars = true),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(range, style: const TextStyle(fontWeight: FontWeight.w700)),
              const Text(
                '가로: 일 · 세로: 분',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: _plotHeight,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$ceiling',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                        Text(
                          '${ceiling ~/ 2}',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                        const Text(
                          '0',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final count = days.length == 1
                            ? 1
                            : math.min(
                                days.length,
                                math.max(
                                  2,
                                  (box.maxWidth /
                                          MediaQuery.textScalerOf(context)
                                              .scale(46))
                                      .floor(),
                                ),
                              );
                        final ticks = [
                          for (var i = 0; i < count; i++)
                            count == 1
                                ? 0
                                : (i * (days.length - 1) / (count - 1)).round(),
                        ];
                        return Column(
                          children: [
                            Semantics(
                              label:
                                  '${filter?.name ?? '전체 과목'} 일별 실제 공부시간 ${bars ? '막대' : '꺾은선'} 그래프. 아래에서 날짜를 이동할 수 있어요.',
                              child: ExcludeSemantics(
                                child: GestureDetector(
                                  onTapDown: (event) {
                                    final index =
                                        (((event.localPosition.dx -
                                                        _plotInset) /
                                                    _plotWidth(box.maxWidth)) *
                                                (days.length - 1))
                                            .round()
                                            .clamp(0, days.length - 1);
                                    setState(() => selected = index);
                                  },
                                  child: SizedBox(
                                    height: _plotHeight,
                                    width: double.infinity,
                                    child: CustomPaint(
                                      key: const ValueKey('study-plot'),
                                      painter: _StudyPainter(
                                        chartMinutes,
                                        ceiling,
                                        selected,
                                        bars,
                                        chartSegments,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                for (final index in ticks)
                                  Text(
                                    '${days[index].date.day}',
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
              if (legend.isNotEmpty) ...[
                const SizedBox(height: 12),
                _SubjectLegend(
                  legend,
                  selected: filter,
                  onSelect: (entry) => setState(() {
                    _subjectFilter = filter == entry ? null : entry;
                  }),
                ),
              ],
              const SizedBox(height: 16),
              const Divider(),
              Row(
                children: [
                  IconButton(
                    tooltip: '이전 날짜',
                    onPressed: selected > 0
                        ? () => setState(() => selected--)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Column(
                        children: [
                          Text(
                            isoDay(day.date),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: muted, fontSize: 13),
                          ),
                          Text(
                            selectedMinutes == null
                                ? '—'
                                : durationLabel(selectedMinutes),
                            key: const ValueKey('study-selected-day'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '다음 날짜',
                    onPressed: selected < days.length - 1
                        ? () => setState(() => selected++)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              if (selectedSubjects != null && selectedSubjects.isNotEmpty)
                _SelectedSubjects(selectedSubjects)
              else if (selectedSubjects == null &&
                  day.minutes > 0 &&
                  widget.subjectsByDay != null)
                const HelpText('이 날짜의 과목별 시간을 확인할 수 없어요. 새로고침해 주세요.'),
              if (stats.totalMinutes == 0)
                const HelpText('이 기간에 기록한 공부시간이 없어요.'),
            ],
          ),
        ),
        if (widget.breakdown case final breakdown?) ...[
          const SizedBox(height: 20),
          breakdown,
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(
              child: Text(
                '일별 공부시간',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: '이전 7일',
              onPressed: dailyEnd > 7
                  ? () => setState(() => dailyEnd -= 7)
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: '다음 7일',
              onPressed: dailyEnd < days.length
                  ? () => setState(
                      () => dailyEnd = math.min(days.length, dailyEnd + 7),
                    )
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Text(
          '${isoDay(days[math.max(0, dailyEnd - 7)].date)} ~ ${isoDay(days[dailyEnd - 1].date)}',
          style: const TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 8),
        for (var i = dailyEnd - 1; i >= math.max(0, dailyEnd - 7); i--)
          Semantics(
            selected: selected == i,
            button: true,
            child: InkWell(
              key: ValueKey('study-day-${isoDay(days[i].date)}'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => selected = i),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  color: selected == i ? pale : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${days[i].date.month}.${days[i].date.day} (${const ['월', '화', '수', '목', '금', '토', '일'][days[i].date.weekday - 1]})',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: Text(
                            durationLabel(days[i].minutes),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: ExcludeSemantics(
                        child: SizedBox(
                          height: 5,
                          child: ColoredBox(
                            color: line,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                heightFactor: 1,
                                widthFactor: peak == 0
                                    ? 0
                                    : days[i].minutes / peak,
                                child: switch (segments[i]) {
                                  final subjects? => Row(
                                    key: ValueKey(
                                      'study-day-segments-${isoDay(days[i].date)}',
                                    ),
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (final (index, subject)
                                          in subjects.indexed)
                                        Expanded(
                                          flex: subject.minutes,
                                          child: ColoredBox(
                                            color: subject.color ?? muted,
                                            child: index == 0
                                                ? null
                                                : const DecoratedBox(
                                                    decoration: BoxDecoration(
                                                      border: Border(
                                                        left: BorderSide(
                                                          color: Colors.white,
                                                          width: .75,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  null => const ColoredBox(color: muted),
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SubjectLegend extends StatelessWidget {
  final Set<_LegendEntry> entries;
  final _LegendEntry? selected;
  final ValueChanged<_LegendEntry> onSelect;
  const _SubjectLegend(
    this.entries, {
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('study-chart-legend'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        header: true,
        child: const Text(
          '과목 범례',
          style: TextStyle(
            fontSize: 12,
            color: muted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final entry in entries)
            FilterChip(
              selected: selected == entry,
              onSelected: (_) => onSelect(entry),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SubjectColorDot(entry.color),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      entry.name,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ],
  );
}

class _SelectedSubjects extends StatelessWidget {
  final List<StudySubjectSlice> subjects;
  const _SelectedSubjects(this.subjects);

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Column(
      key: const ValueKey('study-selected-subjects'),
      children: [
        for (final subject in subjects)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SubjectColorDot(subject.color ?? muted),
                const SizedBox(width: 8),
                Expanded(flex: 3, child: Text(subject.name)),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Text(
                    durationLabel(subject.minutes),
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _StudyPainter extends CustomPainter {
  final List<int?> minutes;
  final int ceiling, selected;
  final bool bars;
  final List<List<StudySubjectSlice>?> segments;
  _StudyPainter(
    this.minutes,
    this.ceiling,
    this.selected,
    this.bars,
    this.segments,
  );

  @override
  void paint(Canvas canvas, Size size) {
    const inset = _plotInset;
    final width = _plotWidth(size.width);
    final height = size.height - inset * 2;
    final grid = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (final ratio in [0.0, .5, 1.0]) {
      final y = inset + height * ratio;
      canvas.drawLine(Offset(inset, y), Offset(size.width - inset, y), grid);
    }
    Offset point(int i) => Offset(
      inset +
          (minutes.length == 1 ? width / 2 : width * i / (minutes.length - 1)),
      inset + height * (1 - (minutes[i] ?? 0) / ceiling),
    );
    final path = Path();
    final stroke = Paint()
      ..color = blue
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final selectedPoint = point(selected);
    final bottom = inset + height;
    canvas.drawLine(
      Offset(selectedPoint.dx, inset),
      Offset(selectedPoint.dx, bottom),
      Paint()
        ..color = muted
        ..strokeWidth = 1,
    );
    final barWidth = math.min(16.0, width / minutes.length * .65);
    final fill = Paint();
    final divider = Paint()
      ..color = Colors.white
      ..strokeWidth = .75;
    for (var i = 0; i < minutes.length; i++) {
      final p = point(i);
      if (bars) {
        if ((minutes[i] ?? 0) == 0) continue;
        final center = p.dx.clamp(barWidth / 2, size.width - barWidth / 2);
        final bar = Rect.fromLTRB(
          center - barWidth / 2,
          p.dy,
          center + barWidth / 2,
          bottom,
        );
        canvas.save();
        canvas.clipRRect(
          RRect.fromRectAndCorners(
            bar,
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(4),
          ),
        );
        if (segments[i] case final subjects?) {
          var offset = bottom;
          for (final subject in subjects) {
            final top = offset - height * subject.minutes / ceiling;
            canvas.drawRect(
              Rect.fromLTRB(bar.left, top, bar.right, offset),
              fill..color = subject.color ?? muted,
            );
            if (offset != bottom) {
              canvas.drawLine(
                Offset(bar.left, offset),
                Offset(bar.right, offset),
                divider,
              );
            }
            offset = top;
          }
        } else {
          canvas.drawRect(bar, fill..color = muted);
        }
        canvas.restore();
      } else {
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
    }
    if (!bars) {
      canvas.drawPath(path, stroke);
      canvas.drawCircle(selectedPoint, 5, fill..color = Colors.white);
      canvas.drawCircle(selectedPoint, 3.5, fill..color = blue);
    }
  }

  @override
  bool shouldRepaint(_StudyPainter old) =>
      !identical(old.minutes, minutes) ||
      !identical(old.segments, segments) ||
      old.selected != selected ||
      old.bars != bars;
}
