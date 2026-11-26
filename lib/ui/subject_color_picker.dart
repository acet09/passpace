import 'dart:math';

import 'package:flutter/material.dart';

import '../data/study_models.dart';
import 'design.dart';

typedef StudySubjectColor = Color? Function(StudyTaskChoice task);

class SubjectColorDot extends StatelessWidget {
  final Color color;
  final Key? markerKey;
  final String? label;

  final double size;
  const SubjectColorDot(
    this.color, {
    super.key,
    this.markerKey,
    this.label,
    this.size = 9,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        key: markerKey,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    ),
  );
}

enum SubjectColorChoice {
  standard(null, null),
  blue('파랑', Color(0xff3972dc)),
  teal('청록', Color(0xff17846f)),
  purple('보라', Color(0xff8868d5)),
  orange('주황', Color(0xffc66a2c)),
  rose('분홍', Color(0xffc2577e)),
  grey('회색', Color(0xff708299));

  final String? label;
  final Color? color;
  const SubjectColorChoice(this.label, this.color);

  static SubjectColorChoice fromName(String? value) =>
      values.where((choice) => choice.name == value).firstOrNull ?? standard;

  String labelFor(Color automatic) {
    if (label case final name?) return name;
    for (final choice in values) {
      if (choice.color == automatic) return choice.label!;
    }
    final hsl = HSLColor.fromColor(automatic);
    if (hsl.saturation < .15) return '회색 계열';
    final hueName = switch (hsl.hue) {
      < 15 || >= 345 => '빨강',
      < 45 => '주황',
      < 70 => '노랑',
      < 155 => '초록',
      < 195 => '청록',
      < 250 => '파랑',
      < 300 => '보라',
      _ => '분홍',
    };
    return '${hsl.lightness >= .5 ? '연한' : '진한'} $hueName';
  }
}

Color subjectColorTrack(Color color) =>
    Color.alphaBlend(color.withValues(alpha: .12), paper);

Map<String, Color> automaticSubjectColors(
  Iterable<String> subjectKeys,
  String accountKey,
) {
  final subjects = subjectKeys.toSet().toList()..sort();
  // Use a stable seed so reordering dates or reopening the app keeps the
  // same colors. Allocate slots independently of manual overrides.
  final seed = accountKey.codeUnits.fold(0, (hash, code) {
    return (hash * 31 + code) & 0x7fffffff;
  });
  final random = Random(seed);
  final palette = [
    for (final choice in SubjectColorChoice.values) ?choice.color,
  ]..shuffle(random);
  final used = palette.map((color) => color.toARGB32()).toSet();

  while (palette.length < subjects.length) {
    final color = HSLColor.fromAHSL(
      1,
      random.nextDouble() * 360,
      .55 + random.nextDouble() * .25,
      .42 + random.nextDouble() * .18,
    ).toColor();
    final luminance = color.computeLuminance();
    final trackLuminance = subjectColorTrack(color).computeLuminance();
    if (luminance >= .17 &&
        (trackLuminance + .05) / (luminance + .05) >= 3 &&
        used.add(color.toARGB32())) {
      palette.add(color);
    }
  }
  return {
    for (var index = 0; index < subjects.length; index++)
      subjects[index]: palette[index],
  };
}

Future<SubjectColorChoice?> showSubjectColorPicker(
  BuildContext context, {
  required String subject,
  required SubjectColorChoice selected,
  required Color automatic,
}) {
  final currentColor = selected.color ?? automatic;
  final automaticIsNamed = SubjectColorChoice.values.any(
    (choice) => choice.color == automatic,
  );
  final choices = SubjectColorChoice.values.where(
    (choice) => choice.color != null || !automaticIsNamed,
  );
  return showModalBottomSheet<SubjectColorChoice>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageTitle('과목 색상'),
            const SizedBox(height: 4),
            HelpText(subject),
            const SizedBox(height: 8),
            for (final choice in choices)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Icon(
                  Icons.circle,
                  size: 18,
                  color: choice.color ?? automatic,
                ),
                title: Text(choice.labelFor(automatic)),
                selected: (choice.color ?? automatic) == currentColor,
                trailing: (choice.color ?? automatic) == currentColor
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(
                  sheetContext,
                  choice.color == automatic
                      ? SubjectColorChoice.standard
                      : choice,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
