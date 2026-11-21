import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/study_models.dart';
import 'design.dart';

const _plotInset = 5.0;
double _plotWidth(double width) => math.max(1.0, width - _plotInset * 2);

class StudyChart extends StatefulWidget {
  final StudyStats stats;
  const StudyChart(this.stats, {super.key});
  @override
  State<StudyChart> createState() => _StudyChartState();
}

class _StudyChartState extends State<StudyChart> {
  bool bars = true;
  late int selected = widget.stats.days.length - 1;
  late int dailyEnd = widget.stats.days.length;
  @override
  void didUpdateWidget(StudyChart old) {
    super.didUpdateWidget(old);
    if (!identical(old.stats, widget.stats)) {
      selected = widget.stats.days.length - 1;
      dailyEnd = widget.stats.days.length;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    final days = stats.days;
    final day = days[selected];
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('기록한 실제 공부시간', style: TextStyle(color: muted)),
              const SizedBox(height: 6),
              Text(
                durationLabel(stats.totalMinutes),
                key: const ValueKey('study-total'),
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: blue,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('꺾은선'),
                    selected: !bars,
                    onSelected: (_) => setState(() => bars = false),
                  ),
                  ChoiceChip(
                    label: const Text('막대'),
                    selected: bars,
                    onSelected: (_) => setState(() => bars = true),
                  ),
                ],
              ),
              const SizedBox(height: 18),
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
                    height: 170,
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
                                  '일별 실제 공부시간 ${bars ? '막대' : '꺾은선'} 그래프. 아래 날짜 이동 또는 일별 공부시간에서 확인할 수 있어요.',
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
                                    height: 170,
                                    width: double.infinity,
                                    child: CustomPaint(
                                      key: const ValueKey('study-plot'),
                                      painter: _StudyPainter(
                                        days,
                                        ceiling,
                                        selected,
                                        bars,
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
                            durationLabel(day.minutes),
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
              if (stats.totalMinutes == 0)
                const HelpText('이 기간에 기록한 공부시간이 없어요.'),
            ],
          ),
        ),
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
                                child: const ColoredBox(color: blue),
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

class _StudyPainter extends CustomPainter {
  final List<StudyDay> days;
  final int ceiling, selected;
  final bool bars;
  _StudyPainter(this.days, this.ceiling, this.selected, this.bars);

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
      inset + (days.length == 1 ? width / 2 : width * i / (days.length - 1)),
      inset + height * (1 - days[i].minutes / ceiling),
    );
    final path = Path();
    final stroke = Paint()
      ..color = blue
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < days.length; i++) {
      final p = point(i);
      if (bars) {
        final barWidth = math.min(16.0, width / days.length * .65);
        canvas.drawRect(
          Rect.fromLTRB(
            p.dx - barWidth / 2,
            p.dy,
            p.dx + barWidth / 2,
            inset + height,
          ),
          Paint()..color = blue,
        );
      } else {
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
    }
    if (!bars) canvas.drawPath(path, stroke);
    final p = point(selected);
    canvas.drawLine(
      Offset(p.dx, inset),
      Offset(p.dx, inset + height),
      Paint()
        ..color = muted
        ..strokeWidth = 1,
    );
    canvas.drawCircle(p, 5, Paint()..color = Colors.white);
    canvas.drawCircle(p, 3.5, Paint()..color = blue);
  }

  @override
  bool shouldRepaint(_StudyPainter old) =>
      !identical(old.days, days) ||
      old.selected != selected ||
      old.bars != bars;
}
