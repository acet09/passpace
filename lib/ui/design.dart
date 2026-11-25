import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/models.dart';

const ink = Color(0xff192840);
const muted = Color(0xff52617a);
const blue = Color(0xff3155c7);
const pale = Color(0xffedf2ff);
const paper = Color(0xfff7f9fc);
const line = Color(0xffe7e5e1);
const acid = Color(0xffc4dcff);
const green = Color(0xff136c53);
const amber = Color(0xff865114);

ThemeData paceTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    colorScheme: ColorScheme.fromSeed(seedColor: blue).copyWith(
      primary: blue,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: ink,
      outline: const Color(0xff8190a6),
      error: const Color(0xffa12a36),
    ),
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return base.copyWith(
    scaffoldBackgroundColor: Colors.white,
    visualDensity: VisualDensity.standard,
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      scrolledUnderElevation: 0,
      titleSpacing: 20,
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        color: ink,
        letterSpacing: -.5,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: muted,
      ),
    ),
    dividerTheme: const DividerThemeData(color: line, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink,
      shape: shape,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 54),
        shape: shape,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        foregroundColor: ink,
        side: const BorderSide(color: Color(0xff8190a6)),
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: const BorderSide(color: Color(0xff8190a6)),
      selectedColor: pale,
      labelStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      errorMaxLines: 4,
      helperMaxLines: 4,
      labelStyle: const TextStyle(color: muted, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xff8190a6)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xff8190a6)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: blue, width: 1.8),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: pale,
      height: 76,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? blue : muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? blue : muted,
          size: 23,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
  );
}

class Brand extends StatelessWidget {
  final bool light;
  final bool useLauncherIcon;
  const Brand({super.key, this.light = false, this.useLauncherIcon = false});
  @override
  Widget build(BuildContext context) => Semantics(
    label: '패스페이스',
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (useLauncherIcon)
            Image.asset('assets/passpace_launcher.png', width: 28, height: 28)
          else
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: light ? Colors.white : blue,
                borderRadius: BorderRadius.circular(9),
              ),
              child: CustomPaint(
                painter: MarkPainter(light ? blue : Colors.white),
              ),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'PASS PACE',
                style: TextStyle(
                  color: light ? Colors.white : ink,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.9,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class MarkPainter extends CustomPainter {
  final Color color;
  MarkPainter(this.color);
  @override
  void paint(Canvas c, Size s) {
    c.scale(s.width / 30, s.height / 30);
    final p = Paint()..color = color;
    c.drawPath(
      Path()
        ..moveTo(6, 21)
        ..lineTo(13.2, 8)
        ..lineTo(17.5, 8)
        ..lineTo(10.3, 21)
        ..close(),
      p,
    );
    c.drawPath(
      Path()
        ..moveTo(12.5, 21)
        ..lineTo(19.7, 8)
        ..lineTo(24, 8)
        ..lineTo(16.8, 21)
        ..close(),
      p,
    );
  }

  @override
  bool shouldRepaint(MarkPainter old) => old.color != color;
}

class _Tracks extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final center = Offset(s.width + 8, s.height * .38);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: .13);
    for (int i = 0; i < 5; i++) {
      final r = 50 + i * 15.0;
      c.drawCircle(center, r, p);
      if (i == 2) {
        c.drawArc(
          Rect.fromCircle(center: center, radius: r),
          math.pi * .85,
          math.pi * .25,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..color = acid,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Tracks old) => false;
}

class PaceBanner extends StatelessWidget {
  final String label, headline, detail;
  const PaceBanner({
    super.key,
    required this.label,
    required this.headline,
    required this.detail,
  });
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(24),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xff354fbb), Color(0xff5274f2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _Tracks())),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xffe7edff),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  headline,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 29,
                    height: 1.3,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: Color(0xffe7edff),
                      height: 1.5,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class Pane extends StatelessWidget {
  final Widget child;
  final double padding;
  final Color color;
  const Pane({
    super.key,
    required this.child,
    this.padding = 16,
    this.color = Colors.white,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: color == Colors.white ? line : Colors.transparent,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: EdgeInsets.all(padding), child: child),
    ),
  );
}

class WidthLimit extends StatelessWidget {
  final Widget child;
  const WidthLimit({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: child,
    ),
  );
}

class ScrollBody extends StatelessWidget {
  final List<Widget> children;
  final Future<void> Function()? refresh;
  final ScrollController? controller;
  const ScrollBody({
    super.key,
    required this.children,
    this.refresh,
    this.controller,
  });
  @override
  Widget build(BuildContext context) {
    final body = SingleChildScrollView(
      controller: controller,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
    return WidthLimit(
      child: refresh == null
          ? body
          : RefreshIndicator(onRefresh: refresh!, child: body),
    );
  }
}

class HorizontalChoices extends StatefulWidget {
  final int selectedIndex;
  final List<Widget> children;
  const HorizontalChoices({
    super.key,
    required this.selectedIndex,
    required this.children,
  });
  @override
  State<HorizontalChoices> createState() => _HorizontalChoicesState();
}

class _HorizontalChoicesState extends State<HorizontalChoices> {
  final controller = ScrollController();
  double previousWidth = -1;
  bool reveal = true;
  @override
  void didUpdateWidget(HorizontalChoices old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex) reveal = true;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final width = math.max(52.0, box.maxWidth / widget.children.length);
      if (previousWidth != box.maxWidth) {
        previousWidth = box.maxWidth;
        reveal = true;
      }
      if (reveal) {
        reveal = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !controller.hasClients) return;
          final left = width * widget.selectedIndex;
          final right = left + width;
          final position = controller.position;
          final offset = left < position.pixels
              ? left
              : right > position.pixels + box.maxWidth
              ? right - box.maxWidth
              : position.pixels;
          controller.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
        });
      }
      return SingleChildScrollView(
        controller: controller,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final child in widget.children)
              SizedBox(width: width, child: child),
          ],
        ),
      );
    },
  );
}

class Heading extends StatelessWidget {
  final String text;
  const Heading(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -.5,
        ),
      ),
    ),
  );
}

class PageTitle extends StatelessWidget {
  final String title;
  final String? eyebrow, description;

  const PageTitle(this.title, {super.key, this.eyebrow, this.description});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (eyebrow != null) ...[
        Text(
          eyebrow!,
          style: const TextStyle(
            color: blue,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
      ],
      Semantics(
        header: true,
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            height: 1.3,
            letterSpacing: -.7,
          ),
        ),
      ),
      if (description != null) ...[
        const SizedBox(height: 8),
        HelpText(description!),
      ],
    ],
  );
}

class SectionRow extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onTap;
  const SectionRow(this.title, {super.key, this.action, this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -.5,
            ),
          ),
        ),
        if (action != null && onTap == null)
          Text(action!, style: const TextStyle(fontSize: 12, color: muted)),
        if (action != null && onTap != null)
          TextButton(
            onPressed: onTap,
            child: Text(action!, style: const TextStyle(fontSize: 13)),
          ),
      ],
    ),
  );
}

class FieldGap extends SizedBox {
  const FieldGap({super.key}) : super(height: 12);
}

class HelpText extends StatelessWidget {
  final String text;
  const HelpText(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(color: muted, fontSize: 14, height: 1.5),
  );
}

class StatusTag extends StatelessWidget {
  final String label;
  final Color color, background;
  const StatusTag(
    this.label, {
    super.key,
    this.color = blue,
    this.background = pale,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
    ),
  );
}

class ExamIcon extends StatelessWidget {
  final String name;
  final double size;
  const ExamIcon(this.name, {super.key, this.size = 42});
  @override
  Widget build(BuildContext context) {
    final sql = name.toUpperCase().contains('SQL');
    final color = sql ? blue : const Color(0xff526780);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(size * .29),
      ),
      child: Icon(
        sql ? Icons.storage_rounded : Icons.menu_book_rounded,
        color: color,
        size: size * .47,
      ),
    );
  }
}

class AlertText extends StatelessWidget {
  final String text;
  const AlertText(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xfffff0e8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: amber, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: amber, fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    ),
  );
}

class EmptyPanel extends StatelessWidget {
  final IconData icon;
  final String title, body;
  final String? action;
  final VoidCallback? onTap;
  const EmptyPanel(
    this.icon,
    this.title,
    this.body, {
    super.key,
    this.action,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => Pane(
    padding: 24,
    child: Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: pale,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Icon(icon, color: blue, size: 25),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 7),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, fontSize: 13, height: 1.6),
        ),
        if (action != null) ...[
          const SizedBox(height: 18),
          PrimaryAction(action!, onTap),
        ],
      ],
    ),
  );
}

class PrimaryAction extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  const PrimaryAction(this.label, this.onTap, {super.key, this.busy = false});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: busy ? null : onTap,
      child: busy
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: '처리 중',
                color: blue,
              ),
            )
          : Text(label, textAlign: TextAlign.center),
    ),
  );
}

class StickyActions extends StatelessWidget {
  final String label;
  final VoidCallback? onTap, onBack;
  final bool busy;
  final String? error, summary;
  const StickyActions(
    this.label,
    this.onTap, {
    super.key,
    this.onBack,
    this.busy = false,
    this.error,
    this.summary,
  });
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final available =
        (media.size.height -
                media.viewInsets.bottom -
                media.padding.vertical -
                kToolbarHeight)
            .clamp(160.0, double.infinity);
    Widget message(Widget child, double height) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height),
      child: SingleChildScrollView(primary: false, child: child),
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: line)),
      ),
      child: SafeArea(
        top: false,
        child: WidthLimit(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null)
                  message(
                    AlertText(error!),
                    (available * .22).clamp(48.0, 128.0),
                  ),
                if (summary != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: message(
                      HelpText(summary!),
                      (available * .15).clamp(28.0, 80.0),
                    ),
                  ),
                LayoutBuilder(
                  builder: (context, b) {
                    final back = onBack == null
                        ? null
                        : OutlinedButton(
                            onPressed: busy ? null : onBack,
                            child: const Text('이전'),
                          );
                    final primary = PrimaryAction(label, onTap, busy: busy);
                    if (back != null &&
                        (b.maxWidth < 260 || media.textScaler.scale(16) > 21)) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [back, const SizedBox(height: 8), primary],
                      );
                    }
                    return Row(
                      children: [
                        if (back != null) ...[back, const SizedBox(width: 10)],
                        Expanded(child: primary),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StepHeader extends StatelessWidget {
  final int current;
  final List<String> labels;
  const StepHeader({super.key, required this.current, required this.labels});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: List.generate(
          labels.length,
          (i) => Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 6),
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: i <= current ? blue : line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        '${current + 1} / ${labels.length}  ·  ${labels[current]}',
        style: const TextStyle(
          color: blue,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    ],
  );
}

class Entrance extends StatelessWidget {
  final Widget child;
  const Entrance({super.key, required this.child});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    builder: (_, v, child) => Opacity(
      opacity: v,
      child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: child),
    ),
    child: child,
  );
}

class LoadingPanel extends StatelessWidget {
  const LoadingPanel({super.key});
  @override
  Widget build(BuildContext context) => ScrollBody(
    children: [
      const SizedBox(height: 8),
      const LinearProgressIndicator(
        minHeight: 2,
        semanticsLabel: '학습 정보를 불러오는 중',
      ),
      const SizedBox(height: 20),
      for (final h in [130.0, 84.0, 84.0])
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            height: h,
            decoration: BoxDecoration(
              color: line.withValues(alpha: .6),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
    ],
  );
}

class LoadBox<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(T) content;
  const LoadBox({super.key, required this.load, required this.content});
  @override
  State<LoadBox<T>> createState() => _LoadBoxState<T>();
}

class _LoadBoxState<T> extends State<LoadBox<T>> {
  late Future<T> value = widget.load();
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: value,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) {
        return const LoadingPanel();
      }
      if (snap.hasError) {
        return ScrollBody(
          children: [
            EmptyPanel(
              Icons.cloud_off_outlined,
              '불러오지 못했어요',
              friendly(snap.error!),
              action: '다시 시도',
              onTap: () {
                final next = widget.load();
                setState(() {
                  value = next;
                });
              },
            ),
          ],
        );
      }
      return widget.content(snap.data as T);
    },
  );
}

Future<DateTime?> selectDate(
  BuildContext context, {
  required DateTime first,
  required DateTime last,
  DateTime? current,
}) {
  final d = current ?? first;
  return showDatePicker(
    context: context,
    firstDate: first,
    lastDate: last,
    initialDate: d.isBefore(first)
        ? first
        : d.isAfter(last)
        ? last
        : d,
    helpText: '목표에 맞는 날짜를 선택하세요',
  );
}

class DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  const DateField(this.label, this.value, this.onTap, {super.key});
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Icon(Icons.calendar_today_outlined, size: 18, color: blue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: muted, fontSize: 12)),
                const SizedBox(height: 3),
                Text(
                  value == null ? '날짜 선택' : isoDay(value!),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.keyboard_arrow_down_rounded, color: muted),
        ],
      ),
    ),
  );
}

void toast(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));
